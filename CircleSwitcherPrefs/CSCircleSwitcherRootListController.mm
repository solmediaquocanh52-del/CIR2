#import "CSCircleSwitcherRootListController.h"
#import "CSCircleSwitcherPreviewHeader.h"
#import "CSCircleSwitcherEasterEgg.h"
#import <spawn.h>
#import <unistd.h>

extern char **environ;

static UIColor *CSHexToUIColor(NSString *hexStr) {
    if (!hexStr || hexStr.length == 0) return [UIColor colorWithRed:0.0 green:0.90 blue:1.0 alpha:1.0];
    NSString *clean = [[hexStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    if ([clean hasPrefix:@"#"]) clean = [clean substringFromIndex:1];
    if (clean.length != 6) return [UIColor colorWithRed:0.0 green:0.90 blue:1.0 alpha:1.0];
    unsigned int val = 0;
    [[NSScanner scannerWithString:clean] scanHexInt:&val];
    return [UIColor colorWithRed:((val & 0xFF0000) >> 16) / 255.0
                           green:((val & 0x00FF00) >> 8) / 255.0
                            blue:(val & 0x0000FF) / 255.0
                           alpha:1.0];
}

static NSString *CSUIColorToHex(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 1;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat w = 1.0;
        [color getWhite:&w alpha:&a];
        r = g = b = w;
    }
    int ri = (int)lround(MAX(0.0, MIN(1.0, r)) * 255.0);
    int gi = (int)lround(MAX(0.0, MIN(1.0, g)) * 255.0);
    int bi = (int)lround(MAX(0.0, MIN(1.0, b)) * 255.0);
    return [NSString stringWithFormat:@"#%02X%02X%02X", ri, gi, bi];
}

static UIColor *CSColorFromHueDegrees(CGFloat hueDeg) {
    CGFloat h = fmod(hueDeg, 360.0) / 360.0;
    if (h < 0) h += 1.0f;
    return [UIColor colorWithHue:h saturation:0.88 brightness:1.0 alpha:1.0];
}

@interface CSCircleSwitcherRootListController () <CSCircleSwitcherPreviewHeaderDelegate, UIColorPickerViewControllerDelegate>
@property (nonatomic, strong) CSCircleSwitcherPreviewHeader *stickyPreviewHeader;
@property (nonatomic, strong) NSLayoutConstraint *previewHeightConstraint;
@property (nonatomic, copy) NSString *activeColorPickerKey;
@end

@implementation CSCircleSwitcherRootListController

- (BOOL)isEnglishLanguage {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.vn.circleswitcher"];
    [defaults synchronize];
    return ([defaults integerForKey:@"language"] == 1);
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSString *plistName = [self isEnglishLanguage] ? @"Root_EN" : @"Root";
        _specifiers = [self loadSpecifiersFromPlistName:plistName target:self];
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    UIImage *heartImg = [UIImage imageNamed:@"heart" inBundle:bundle compatibleWithTraitCollection:nil];
    UIBarButtonItem *shareBtn = [[UIBarButtonItem alloc] initWithImage:heartImg
                                                                 style:UIBarButtonItemStylePlain
                                                                target:self
                                                                action:@selector(shareTweak)];
    self.navigationItem.rightBarButtonItem = shareBtn;

    // Sticky Floating 3D Live Preview pinned at top of Safe Area
    self.stickyPreviewHeader = [[CSCircleSwitcherPreviewHeader alloc] initWithFrame:CGRectMake(12, 0, self.view.bounds.size.width - 24, 212)];
    self.stickyPreviewHeader.translatesAutoresizingMaskIntoConstraints = NO;
    self.stickyPreviewHeader.delegate = self;
    [self.view addSubview:self.stickyPreviewHeader];

    self.previewHeightConstraint = [self.stickyPreviewHeader.heightAnchor constraintEqualToConstant:212.0];
    [NSLayoutConstraint activateConstraints:@[
        [self.stickyPreviewHeader.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8.0],
        [self.stickyPreviewHeader.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12.0],
        [self.stickyPreviewHeader.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12.0],
        self.previewHeightConstraint
    ]];

    [self updateTableInsetForStickyPreview:NO];

    UIButton *secretBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    secretBtn.frame = CGRectMake(0, 0, self.view.bounds.size.width, 32);
    [secretBtn setTitle:@"CircleSwitcher 2.0.0" forState:UIControlStateNormal];
    secretBtn.titleLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium];
    secretBtn.alpha = 0.45;
    [secretBtn addTarget:self action:@selector(openEasterEgg) forControlEvents:UIControlEventTouchUpInside];
    self.table.tableHeaderView = secretBtn;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleLiveSliderUpdate:)
                                                 name:@"CSPrefsSliderLiveChanged"
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)updateTableInsetForStickyPreview:(BOOL)animated {
    CGFloat previewH = self.stickyPreviewHeader.isCollapsed ? 38.0 : 212.0;
    CGFloat targetTopInset = previewH + 16.0;

    void (^applyBlock)(void) = ^{
        self.previewHeightConstraint.constant = previewH;
        UIEdgeInsets insets = self.table.contentInset;
        insets.top = targetTopInset;
        self.table.contentInset = insets;
        self.table.scrollIndicatorInsets = insets;
        [self.view layoutIfNeeded];
    };

    if (animated) {
        [UIView animateWithDuration:0.28 delay:0 usingSpringWithDamping:0.84 initialSpringVelocity:0.4 options:(UIViewAnimationOptions)0 animations:applyBlock completion:nil];
    } else {
        applyBlock();
    }
}

- (void)previewHeaderDidToggleCollapse:(BOOL)collapsed {
    [self updateTableInsetForStickyPreview:YES];
}

- (void)handleLiveSliderUpdate:(NSNotification *)note {
    [self.stickyPreviewHeader reloadPreviewFromPreferences];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];

    NSString *key = [specifier propertyForKey:@"key"];
    if (key) {
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.vn.circleswitcher"];
        [defaults setObject:value forKey:key];
        [defaults synchronize];

        if ([key isEqualToString:@"language"]) {
            _specifiers = nil;
            [self reloadSpecifiers];
        } else if ([key isEqualToString:@"motionBlurOn"] && [value boolValue]) {
            [self.stickyPreviewHeader triggerMotionBlurDemo];
        }
    }

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.vn.circleswitcher/ReloadPrefs"),
        NULL,
        NULL,
        YES
    );

    [self.stickyPreviewHeader reloadPreviewFromPreferences];
}

// ============================================================================
// Full 16-Million RGB Color Pickers (Rim Glow & Hologram Base Ring)
// ============================================================================

- (void)openGlowColorPicker:(id)sender {
    [self presentColorPickerForKey:@"glowColorHex" defaultHex:@"#00E5FF"];
}

- (void)openBaseColorPicker:(id)sender {
    [self presentColorPickerForKey:@"baseColorHex" defaultHex:@"#00E5FF"];
}

- (void)presentColorPickerForKey:(NSString *)prefKey defaultHex:(NSString *)defaultHex {
    self.activeColorPickerKey = prefKey;

    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.vn.circleswitcher"];
    [defaults synchronize];
    NSString *currentHex = [defaults stringForKey:prefKey] ?: defaultHex;

    if (@available(iOS 14.0, *)) {
        UIColorPickerViewController *picker = [[UIColorPickerViewController alloc] init];
        picker.delegate = self;
        picker.supportsAlpha = NO;
        picker.selectedColor = CSHexToUIColor(currentHex);
        picker.title = [self isEnglishLanguage] ? @"Select Full RGB Color" : @"Chọn Màu Full RGB";
        [self presentViewController:picker animated:YES completion:nil];
    }
}

- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)viewController {
    [self saveSelectedColor:viewController.selectedColor];
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController {
    [self saveSelectedColor:viewController.selectedColor];
    [self reloadSpecifiers];
}

- (void)saveSelectedColor:(UIColor *)color {
    if (!self.activeColorPickerKey || !color) return;
    NSString *hex = CSUIColorToHex(color);

    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.vn.circleswitcher"];
    [defaults setObject:hex forKey:self.activeColorPickerKey];
    if ([self.activeColorPickerKey isEqualToString:@"glowColorHex"]) {
        [defaults setObject:@5 forKey:@"glowColorIndex"];
    } else if ([self.activeColorPickerKey isEqualToString:@"baseColorHex"]) {
        [defaults setObject:@NO forKey:@"baseSyncColor"];
    }
    [defaults synchronize];

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.vn.circleswitcher/ReloadPrefs"),
        NULL,
        NULL,
        YES
    );

    [self.stickyPreviewHeader reloadPreviewFromPreferences];
}

// ============================================================================
// One-Tap Layout & Presets.json Integration
// ============================================================================

- (void)applyBatchPreferences:(NSDictionary *)values {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.vn.circleswitcher"];
    for (NSString *k in values) {
        [defaults setObject:values[k] forKey:k];
    }
    [defaults synchronize];

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.vn.circleswitcher/ReloadPrefs"),
        NULL,
        NULL,
        YES
    );

    [self reloadSpecifiers];
    [self.stickyPreviewHeader reloadPreviewFromPreferences];
    [self.stickyPreviewHeader triggerMotionBlurDemo];
}

- (void)applyCylinderCardsPreset:(id)sender {
    [self applyBatchPreferences:@{
        @"enabled": @YES,
        @"layoutMode": @0,
        @"infiniteScroll": @YES,
        @"circleMorph": @NO,
        @"circleRadius": @32.0,
        @"wheelCurvature": @1.05,
        @"cardScale": @0.86,
        @"cardSpacing": @1.08,
        @"titlePosition": @1,
        @"centerDimAlpha": @0.45,
        @"showCloseButton": @YES,
        @"liquidGlass": @YES,
        @"glowIntensity": @0.72,
        @"glowColorIndex": @5,
        @"glowColorHex": @"#00E5FF",
        @"hologramBaseEnabled": @YES,
        @"baseSyncColor": @YES,
        @"baseIntensity": @0.80,
        @"baseScale": @1.00,
        @"backdropEnabled": @YES,
        @"motionBlurOn": @YES
    }];
}

- (void)applyCylinderOrbsPreset:(id)sender {
    [self applyBatchPreferences:@{
        @"enabled": @YES,
        @"layoutMode": @1,
        @"infiniteScroll": @YES,
        @"circleMorph": @YES,
        @"wheelCurvature": @1.05,
        @"orbSize": @0.78,
        @"cardSpacing": @1.05,
        @"titlePosition": @1,
        @"centerDimAlpha": @0.40,
        @"showCloseButton": @YES,
        @"liquidGlass": @YES,
        @"glowIntensity": @0.78,
        @"glowColorIndex": @5,
        @"glowColorHex": @"#00E5FF",
        @"hologramBaseEnabled": @YES,
        @"baseSyncColor": @YES,
        @"baseIntensity": @0.82,
        @"baseScale": @1.00,
        @"backdropEnabled": @YES,
        @"motionBlurOn": @YES
    }];
}

- (void)applyOrbitalPreviewPreset:(id)sender {
    [self applyBatchPreferences:@{
        @"enabled": @YES,
        @"layoutMode": @2,
        @"infiniteScroll": @YES,
        @"circleMorph": @YES,
        @"cardScale": @0.88,
        @"orbSize": @0.70,
        @"cardSpacing": @1.02,
        @"titlePosition": @0,
        @"showCloseButton": @YES,
        @"liquidGlass": @YES,
        @"glowIntensity": @0.75,
        @"glowColorIndex": @5,
        @"glowColorHex": @"#1E90FF",
        @"hologramBaseEnabled": @NO,
        @"backdropEnabled": @YES,
        @"motionBlurOn": @YES
    }];
}

- (void)openGlassPresetsMenu:(id)sender {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *jsonPath = [bundle pathForResource:@"Presets" ofType:@"json"];
    NSData *data = jsonPath ? [NSData dataWithContentsOfFile:jsonPath] : nil;
    NSDictionary *parsed = data ? [NSJSONSerialization JSONObjectWithData:data options:(NSJSONReadingOptions)0 error:nil] : nil;
    NSArray *presets = parsed[@"presets"];

    BOOL isEN = [self isEnglishLanguage];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:(isEN ? @"Liquid Glass Presets" : @"Bộ Preset Kính Lỏng")
                                                                   message:(isEN ? @"Choose a curated optical glass style:" : @"Chọn nhanh phong cách kính & ánh sáng:")
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    if (presets && presets.count > 0) {
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.vn.circleswitcher"];
        [defaults synchronize];
        NSInteger currentMode = [defaults integerForKey:@"layoutMode"];

        for (NSDictionary *item in presets) {
            NSString *name = item[@"name"] ?: @"Preset";
            NSDictionary *vals = item[@"values"] ?: @{};
            [sheet addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                CGFloat hue = vals[@"glowHue"] ? [vals[@"glowHue"] floatValue] : 200.0f;
                NSString *hex = CSUIColorToHex(CSColorFromHueDegrees(hue));
                CGFloat glowAmt = vals[@"glowAmt"] ? ([vals[@"glowAmt"] floatValue] / 100.0f) : 0.65f;
                CGFloat refract = vals[@"glassRefract"] ? ([vals[@"glassRefract"] floatValue] / 100.0f) : 0.65f;
                CGFloat spec    = vals[@"glassSpecular"] ? ([vals[@"glassSpecular"] floatValue] / 100.0f) : 0.85f;
                CGFloat disp    = vals[@"glassDispersion"] ? ([vals[@"glassDispersion"] floatValue] / 100.0f) : 0.40f;
                BOOL ringGlow   = vals[@"ringGlow"] ? [vals[@"ringGlow"] boolValue] : YES;

                NSMutableDictionary *batch = [@{
                    @"enabled": @YES,
                    @"liquidGlass": @YES,
                    @"glowColorIndex": @5,
                    @"glowColorHex": hex,
                    @"glowIntensity": @(glowAmt),
                    @"glassRefract": @(refract),
                    @"glassSpecular": @(spec),
                    @"glassDispersion": @(disp),
                    @"baseSyncColor": @YES
                } mutableCopy];

                if (currentMode != 2) {
                    batch[@"hologramBaseEnabled"] = @(ringGlow);
                }

                [self applyBatchPreferences:batch];
            }]];
        }
    }

    [sheet addAction:[UIAlertAction actionWithTitle:(isEN ? @"Cancel" : @"Hủy") style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width * 0.5, self.view.bounds.size.height * 0.5, 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

// ============================================================================
// Actions: Respring, Share, Easter Egg
// ============================================================================

- (void)respring:(id)sender {
    BOOL isEN = [self isEnglishLanguage];
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:(isEN ? @"Respring SpringBoard?" : @"Khởi động lại SpringBoard?")
                                                                     message:(isEN ? @"Apply all changes smoothly to your App Switcher." : @"Áp dụng đồng bộ toàn bộ hiệu ứng mới ra màn hình Đa nhiệm.")
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:(isEN ? @"Cancel" : @"Hủy") style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Respring" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        pid_t pid;
        const char *rootlessKill = "/var/jb/usr/bin/killall";
        const char *rootfulKill  = "/usr/bin/killall";
        const char *binPath = (access(rootlessKill, X_OK) == 0) ? rootlessKill : rootfulKill;
        const char *args[] = {"killall", "-9", "SpringBoard", NULL};
        posix_spawn(&pid, binPath, NULL, NULL, (char * const *)args, environ);
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)shareTweak {
    NSString *text = @"Loving #CircleSwitcher 2.0.0 — 3D Hologram Cylinder, Orbital Orbs & Liquid Glass Switcher for iOS!";
    UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:@[text] applicationActivities:nil];
    vc.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)openEasterEgg {
    CSCircleSwitcherEasterEggController *ee = [[CSCircleSwitcherEasterEggController alloc] init];
    [self.navigationController pushViewController:ee animated:YES];
}

@end
