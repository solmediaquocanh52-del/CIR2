#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>

// ============================================================================
// CircleSwitcher v2.3.1 — Max-FPS Anti-Freeze 360° Carousel & Liquid Glass Engine
// Supports iOS 14.0 - 16.3.1+ (Rootless & Rootful)
// ============================================================================

@interface SBAppSwitcherPageView : UIView
@property (nonatomic, strong) UIView *view;
@property (nonatomic, assign) CGFloat cornerRadius;
- (void)_updateCornerRadius;
@end

@interface SBFluidSwitcherItemContainerHeaderView : UIView
@end

@interface SBFluidSwitcherItemContainer : UIView
@property (nonatomic, strong) SBAppSwitcherPageView *pageView;
@property (nonatomic, assign) CGFloat contentPageViewScale;
- (void)_cs_applyClassicTransform;
- (void)_cs_resetToNativeFullscreen;
@end

@interface SBFluidSwitcherViewController : UIViewController
@property (nonatomic, copy) NSArray *appLayouts;
@property (nonatomic, strong) NSDictionary *visibleItemContainers;
- (void)_cs_handlePrefsOrStateChanged;
- (void)_cs_setSwitcherActive:(BOOL)active;
- (void)_cs_dismissSwitcherToHome;
- (void)_cs_activateAppLayout:(id)appLayout bundleID:(NSString *)bundleID;
- (void)_cs_killAppLayout:(id)appLayout bundleID:(NSString *)bundleID;
@end

// ============================================================================
// Preferences State
// ============================================================================

static NSString * const kCSDomain = @"com.vn.circleswitcher";
static NSString * const kCSReloadNotification = @"com.vn.circleswitcher/ReloadPrefs";

static BOOL kEnabled = YES;
static NSInteger kLayoutMode = 0; // 0: Cylinder Cards, 1: Cylinder Orbs, 2: Orbital Orbs, 3: Radial Ring, 4-9: Classic
static BOOL kInfiniteScroll = YES;
static BOOL kCircleMorph = NO;
static CGFloat kCircleRadius = 34.0;
static CGFloat kWheelCurvature = 1.05;
static CGFloat kCardScale = 0.86;
static CGFloat kOrbSize = 0.72;
static CGFloat kCardSpacing = 1.05;

static NSInteger kTitlePosition = 1; // 0: Top, 1: Center (Dim), 2: Bottom, 3: Hidden
static CGFloat kCenterDimAlpha = 0.45;
static BOOL kShowCloseButton = YES;

static BOOL kLiquidGlass = YES;
static CGFloat kGlowIntensity = 0.65;
static NSInteger kGlowColorIndex = 0;
static NSString *kGlowColorHex = @"#00E5FF";
static CGFloat kGlassRefract = 0.65;
static CGFloat kGlassSpecular = 0.85;
static CGFloat kGlassDispersion = 0.40;

static BOOL kHologramBaseEnabled = YES;
static BOOL kBaseSyncColor = YES;
static NSString *kBaseColorHex = @"#00E5FF";
static CGFloat kBaseIntensity = 0.75;
static CGFloat kBaseScale = 1.0;
static BOOL kBackdropEnabled = YES;

static BOOL kMotionBlurOn = YES;
static CGFloat kMotionBlurIntensity = 7.5;
static BOOL kFadeIcons = YES;
static BOOL kScaleIcons = YES;
static BOOL kRollIcons = NO;
static BOOL kHapticFeedback = YES;

// Switcher State Guards
static BOOL gSwitcherActive = NO;
static BOOL gIsUpdatingSwitcherState = NO;
static BOOL gIsKillingSingleApp = NO;
static BOOL gIsLaunchingApp = NO;
static __weak SBFluidSwitcherViewController *gPrimarySwitcherVC = nil;
static __weak UIView *kLastCenteredContainer = nil;
static UIImpactFeedbackGenerator *kHapticGenerator = nil;

static const void *kCSCarouselStageKey = &kCSCarouselStageKey;

// ============================================================================
// Color & Asset Helpers
// ============================================================================

static UIColor *CSColorFromHex(NSString *hexStr, CGFloat alpha) {
    if (!hexStr || ![hexStr isKindOfClass:[NSString class]] || hexStr.length == 0) {
        return [UIColor colorWithRed:0.0 green:0.90 blue:1.0 alpha:alpha];
    }
    NSString *clean = [[hexStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    if ([clean hasPrefix:@"#"]) clean = [clean substringFromIndex:1];
    if ([clean hasPrefix:@"0X"]) clean = [clean substringFromIndex:2];
    if (clean.length != 6) {
        return [UIColor colorWithRed:0.0 green:0.90 blue:1.0 alpha:alpha];
    }
    unsigned int rgbVal = 0;
    [[NSScanner scannerWithString:clean] scanHexInt:&rgbVal];
    CGFloat r = ((rgbVal & 0xFF0000) >> 16) / 255.0;
    CGFloat g = ((rgbVal & 0x00FF00) >> 8) / 255.0;
    CGFloat b = (rgbVal & 0x0000FF) / 255.0;
    return [UIColor colorWithRed:r green:g blue:b alpha:alpha];
}

static UIColor *CSActiveGlowColor(CGFloat alpha) {
    if (kGlowColorHex && kGlowColorHex.length >= 6 && (kGlowColorIndex == 5 || ![kGlowColorHex isEqualToString:@"#00E5FF"])) {
        return CSColorFromHex(kGlowColorHex, alpha);
    }
    switch (kGlowColorIndex) {
        case 1:  return [UIColor colorWithRed:0.15 green:0.55 blue:1.00 alpha:alpha];
        case 2:  return [UIColor colorWithRed:0.68 green:0.35 blue:1.00 alpha:alpha];
        case 3:  return [UIColor colorWithRed:0.15 green:0.90 blue:0.65 alpha:alpha];
        case 4:  return [UIColor colorWithWhite:1.00 alpha:alpha];
        case 0:
        default: return [UIColor colorWithRed:0.00 green:0.90 blue:1.00 alpha:alpha];
    }
}

static UIColor *CSActiveBaseColor(CGFloat alpha) {
    if (kBaseSyncColor) return CSActiveGlowColor(alpha);
    return CSColorFromHex(kBaseColorHex, alpha);
}

static NSBundle *CSPrefsBundle(void) {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<NSString *> *paths = @[
            @"/var/jb/Library/PreferenceBundles/CircleSwitcherPrefs.bundle",
            @"/Library/PreferenceBundles/CircleSwitcherPrefs.bundle"
        ];
        for (NSString *p in paths) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:p]) {
                bundle = [NSBundle bundleWithPath:p];
                break;
            }
        }
    });
    return bundle;
}

static UIImage *CSLoadAsset(NSString *name, BOOL asTemplate) {
    static NSMutableDictionary<NSString *, UIImage *> *assetCache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        assetCache = [NSMutableDictionary dictionary];
    });
    NSString *cacheKey = [NSString stringWithFormat:@"%@_%d", name, asTemplate ? 1 : 0];
    UIImage *cached = assetCache[cacheKey];
    if (cached) return cached;

    NSBundle *b = CSPrefsBundle();
    UIImage *img = b ? [UIImage imageNamed:name inBundle:b compatibleWithTraitCollection:nil] : nil;
    if (!img) {
        NSArray<NSString *> *paths = @[
            [NSString stringWithFormat:@"/var/jb/Library/PreferenceBundles/CircleSwitcherPrefs.bundle/%@@3x.png", name],
            [NSString stringWithFormat:@"/var/jb/Library/PreferenceBundles/CircleSwitcherPrefs.bundle/%@@2x.png", name],
            [NSString stringWithFormat:@"/Library/PreferenceBundles/CircleSwitcherPrefs.bundle/%@@3x.png", name],
            [NSString stringWithFormat:@"/Library/PreferenceBundles/CircleSwitcherPrefs.bundle/%@@2x.png", name]
        ];
        for (NSString *p in paths) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:p]) {
                img = [UIImage imageWithContentsOfFile:p];
                if (img) break;
            }
        }
    }
    if (img && asTemplate) {
        img = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    if (img) {
        assetCache[cacheKey] = img;
    }
    return img;
}

static BOOL CSUsesInfiniteCarouselOverlay(void) {
    return kEnabled && (kLayoutMode == 0 || kLayoutMode == 1 || kLayoutMode == 2 || kLayoutMode == 3);
}

// ============================================================================
// Safe App Metadata Helpers (Zero drawViewHierarchyInRect -> Zero Deadlock)
// ============================================================================

static NSString *CSBundleIDFromAppLayout(id appLayout) {
    if (!appLayout) return nil;
    @try {
        SEL itemRoleSel = NSSelectorFromString(@"itemForLayoutRole:");
        id displayItem = nil;
        if ([appLayout respondsToSelector:itemRoleSel]) {
            displayItem = ((id (*)(id, SEL, NSInteger))objc_msgSend)(appLayout, itemRoleSel, 1);
        }
        if (!displayItem && [appLayout respondsToSelector:NSSelectorFromString(@"allItems")]) {
            NSArray *items = ((id (*)(id, SEL))objc_msgSend)(appLayout, NSSelectorFromString(@"allItems"));
            displayItem = items.firstObject;
        }
        if (displayItem && [displayItem respondsToSelector:NSSelectorFromString(@"bundleIdentifier")]) {
            return ((id (*)(id, SEL))objc_msgSend)(displayItem, NSSelectorFromString(@"bundleIdentifier"));
        }
    } @catch (NSException *e) {}
    return nil;
}

static NSString *CSAppDisplayNameForBundleID(NSString *bundleID) {
    if (!bundleID || bundleID.length == 0) return @"App";
    @try {
        Class appCtrlCls = NSClassFromString(@"SBApplicationController");
        if (appCtrlCls && [appCtrlCls respondsToSelector:NSSelectorFromString(@"sharedInstance")]) {
            id ctrl = ((id (*)(id, SEL))objc_msgSend)(appCtrlCls, NSSelectorFromString(@"sharedInstance"));
            SEL appForBid = NSSelectorFromString(@"applicationWithBundleIdentifier:");
            if (ctrl && [ctrl respondsToSelector:appForBid]) {
                id app = ((id (*)(id, SEL, id))objc_msgSend)(ctrl, appForBid, bundleID);
                if (app && [app respondsToSelector:NSSelectorFromString(@"displayName")]) {
                    NSString *name = ((id (*)(id, SEL))objc_msgSend)(app, NSSelectorFromString(@"displayName"));
                    if (name.length > 0) return name;
                }
            }
        }
    } @catch (NSException *e) {}
    NSArray<NSString *> *parts = [bundleID componentsSeparatedByString:@"."];
    return parts.lastObject.length > 0 ? [parts.lastObject capitalizedString] : bundleID;
}

static UIImage *CSAppIconForBundleID(NSString *bundleID) {
    if (!bundleID || bundleID.length == 0) return nil;
    static NSMutableDictionary<NSString *, UIImage *> *iconCache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        iconCache = [NSMutableDictionary dictionary];
    });
    UIImage *cached = iconCache[bundleID];
    if (cached) return cached;

    @try {
        SEL iconSel = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
        if ([UIImage respondsToSelector:iconSel]) {
            CGFloat scale = [UIScreen mainScreen].scale;
            UIImage *img = ((UIImage * (*)(id, SEL, NSString *, int, CGFloat))objc_msgSend)([UIImage class], iconSel, bundleID, 2, scale);
            if (img) {
                iconCache[bundleID] = img;
                return img;
            }
        }
    } @catch (NSException *e) {}
    return nil;
}

// ============================================================================
// Preferences Loader
// ============================================================================

static NSDictionary *CSReadPreferencesDictionary(void) {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kCSDomain];
    NSDictionary *dict = [defaults dictionaryRepresentation];
    if (dict && dict[@"enabled"] != nil) return dict;

    NSArray<NSString *> *paths = @[
        @"/var/jb/var/mobile/Library/Preferences/com.vn.circleswitcher.plist",
        @"/var/mobile/Library/Preferences/com.vn.circleswitcher.plist"
    ];
    for (NSString *p in paths) {
        NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:p];
        if (plist) return plist;
    }
    return nil;
}

static void CSLoadPreferences(void) {
    NSDictionary *prefs = CSReadPreferencesDictionary();
    kEnabled             = prefs[@"enabled"]             ? [prefs[@"enabled"] boolValue]             : YES;
    kLayoutMode          = prefs[@"layoutMode"]          ? [prefs[@"layoutMode"] integerValue]       : 0;
    kInfiniteScroll      = prefs[@"infiniteScroll"]      ? [prefs[@"infiniteScroll"] boolValue]      : YES;
    kCircleMorph         = prefs[@"circleMorph"]         ? [prefs[@"circleMorph"] boolValue]         : NO;
    kCircleRadius        = prefs[@"circleRadius"]        ? [prefs[@"circleRadius"] doubleValue]      : 34.0;
    kWheelCurvature      = prefs[@"wheelCurvature"]      ? [prefs[@"wheelCurvature"] doubleValue]    : 1.05;
    kCardScale           = prefs[@"cardScale"]           ? [prefs[@"cardScale"] doubleValue]         : 0.86;
    kOrbSize             = prefs[@"orbSize"]             ? [prefs[@"orbSize"] doubleValue]           : 0.72;
    kCardSpacing         = prefs[@"cardSpacing"]         ? [prefs[@"cardSpacing"] doubleValue]       : 1.05;

    kTitlePosition       = prefs[@"titlePosition"]       ? [prefs[@"titlePosition"] integerValue]    : 1;
    kCenterDimAlpha      = prefs[@"centerDimAlpha"]      ? [prefs[@"centerDimAlpha"] doubleValue]    : 0.45;
    kShowCloseButton     = prefs[@"showCloseButton"]     ? [prefs[@"showCloseButton"] boolValue]     : YES;

    kLiquidGlass         = prefs[@"liquidGlass"]         ? [prefs[@"liquidGlass"] boolValue]         : YES;
    kGlowIntensity       = prefs[@"glowIntensity"]       ? [prefs[@"glowIntensity"] doubleValue]     : 0.65;
    kGlowColorIndex      = prefs[@"glowColorIndex"]      ? [prefs[@"glowColorIndex"] integerValue]   : 0;
    kGlowColorHex        = prefs[@"glowColorHex"]        ? [prefs[@"glowColorHex"] description]      : @"#00E5FF";
    kGlassRefract        = prefs[@"glassRefract"]        ? [prefs[@"glassRefract"] doubleValue]      : 0.65;
    kGlassSpecular       = prefs[@"glassSpecular"]       ? [prefs[@"glassSpecular"] doubleValue]     : 0.85;
    kGlassDispersion     = prefs[@"glassDispersion"]     ? [prefs[@"glassDispersion"] doubleValue]   : 0.40;

    kHologramBaseEnabled = prefs[@"hologramBaseEnabled"] ? [prefs[@"hologramBaseEnabled"] boolValue] : YES;
    kBaseSyncColor       = prefs[@"baseSyncColor"]       ? [prefs[@"baseSyncColor"] boolValue]       : YES;
    kBaseColorHex        = prefs[@"baseColorHex"]        ? [prefs[@"baseColorHex"] description]      : @"#00E5FF";
    kBaseIntensity       = prefs[@"baseIntensity"]       ? [prefs[@"baseIntensity"] doubleValue]     : 0.75;
    kBaseScale           = prefs[@"baseScale"]           ? [prefs[@"baseScale"] doubleValue]         : 1.0;
    kBackdropEnabled     = prefs[@"backdropEnabled"]     ? [prefs[@"backdropEnabled"] boolValue]     : YES;

    kMotionBlurOn        = prefs[@"motionBlurOn"]        ? [prefs[@"motionBlurOn"] boolValue]        : YES;
    kMotionBlurIntensity = prefs[@"motionBlurIntensity"] ? [prefs[@"motionBlurIntensity"] doubleValue]: 7.5;
    kFadeIcons           = prefs[@"fadeIcons"]           ? [prefs[@"fadeIcons"] boolValue]           : YES;
    kScaleIcons          = prefs[@"scaleIcons"]          ? [prefs[@"scaleIcons"] boolValue]          : YES;
    kRollIcons           = prefs[@"rollIcons"]           ? [prefs[@"rollIcons"] boolValue]           : NO;
    kHapticFeedback      = prefs[@"hapticFeedback"]      ? [prefs[@"hapticFeedback"] boolValue]      : YES;
}

static void CSReloadCallback(CFNotificationCenterRef center,
                             void *observer,
                             CFStringRef name,
                             const void *object,
                             CFDictionaryRef userInfo) {
    CSLoadPreferences();
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gPrimarySwitcherVC) {
            [gPrimarySwitcherVC _cs_handlePrefsOrStateChanged];
        }
    });
}

// ============================================================================
// Edge-to-Edge Vector + Optical Liquid Glass Item View (Zero Black Crescents)
// ============================================================================

@interface CSInfiniteCarouselItem : UIView
@property (nonatomic, strong) id appLayout;
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, strong) UIImageView *ambientIconBG;
@property (nonatomic, strong) UIVisualEffectView *frostedGlassView;
@property (nonatomic, strong) CAGradientLayer *liquidBodyGradient;
@property (nonatomic, strong) CAGradientLayer *specularSheenLayer;
@property (nonatomic, strong) CAShapeLayer *innerBevelLayer;
@property (nonatomic, strong) UIView *dimOverlay;
@property (nonatomic, strong) UIImageView *circularGlassRimOverlay;
@property (nonatomic, strong) UIImageView *iconImageView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *outerHaloView;
@property (nonatomic, assign) double lastTheta;
- (void)updateOpticalGlassWithColor:(UIColor *)glowCol cornerRadius:(CGFloat)cornerR isCircular:(BOOL)isCircular frontWeight:(double)frontWeight theta:(double)theta;
@end

@implementation CSInfiniteCarouselItem

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.06 green:0.10 blue:0.17 alpha:0.78];
        self.layer.masksToBounds = YES;
        self.clipsToBounds = YES;

        // Soft icon color bleed filling entire glass body
        self.ambientIconBG = [[UIImageView alloc] initWithFrame:self.bounds];
        self.ambientIconBG.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.ambientIconBG.contentMode = UIViewContentModeScaleAspectFill;
        self.ambientIconBG.alpha = 0.42;
        [self addSubview:self.ambientIconBG];

        // Hardware-accelerated frosted glass filling 100% of bounds
        UIBlurEffectStyle blurStyle = UIBlurEffectStyleDark;
        if (@available(iOS 13.0, *)) {
            blurStyle = UIBlurEffectStyleSystemUltraThinMaterialDark;
        }
        self.frostedGlassView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:blurStyle]];
        self.frostedGlassView.frame = self.bounds;
        self.frostedGlassView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:self.frostedGlassView];

        // Full-bleed optical refraction & tint gradient (fills 100% edge-to-edge)
        self.liquidBodyGradient = [CAGradientLayer layer];
        self.liquidBodyGradient.frame = self.bounds;
        self.liquidBodyGradient.startPoint = CGPointMake(0.0, 0.0);
        self.liquidBodyGradient.endPoint = CGPointMake(1.0, 1.0);
        [self.layer addSublayer:self.liquidBodyGradient];

        // Dynamic studio specular highlight + chromatic dispersion sheen
        self.specularSheenLayer = [CAGradientLayer layer];
        self.specularSheenLayer.frame = self.bounds;
        self.specularSheenLayer.startPoint = CGPointMake(0.0, 0.0);
        self.specularSheenLayer.endPoint = CGPointMake(1.0, 1.0);
        [self.layer addSublayer:self.specularSheenLayer];

        // Dim overlay for center title legibility
        self.dimOverlay = [[UIView alloc] initWithFrame:self.bounds];
        self.dimOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.dimOverlay.backgroundColor = [UIColor blackColor];
        self.dimOverlay.alpha = 0.0;
        [self addSubview:self.dimOverlay];

        // Circular glass rim overlay (ONLY used for circular orbs, NEVER stretched on rectangles!)
        self.circularGlassRimOverlay = [[UIImageView alloc] initWithFrame:self.bounds];
        self.circularGlassRimOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.circularGlassRimOverlay.contentMode = UIViewContentModeScaleToFill;
        self.circularGlassRimOverlay.alpha = 0.0;
        [self addSubview:self.circularGlassRimOverlay];

        // Crisp inner glass bevel stroke matching exact rounded-rect or circle path
        self.innerBevelLayer = [CAShapeLayer layer];
        self.innerBevelLayer.fillColor = [UIColor clearColor].CGColor;
        self.innerBevelLayer.lineWidth = 1.25;
        [self.layer addSublayer:self.innerBevelLayer];

        self.iconImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 68, 68)];
        self.iconImageView.contentMode = UIViewContentModeScaleAspectFill;
        self.iconImageView.layer.cornerRadius = 16.0;
        self.iconImageView.layer.masksToBounds = YES;
        [self addSubview:self.iconImageView];

        self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        self.titleLabel.font = [UIFont systemFontOfSize:15.5 weight:UIFontWeightBold];
        self.titleLabel.textColor = [UIColor whiteColor];
        self.titleLabel.textAlignment = NSTextAlignmentCenter;
        self.titleLabel.numberOfLines = 1;
        self.titleLabel.adjustsFontSizeToFitWidth = YES;
        self.titleLabel.minimumScaleFactor = 0.72;
        self.titleLabel.layer.shadowColor = [UIColor blackColor].CGColor;
        self.titleLabel.layer.shadowOpacity = 0.85;
        self.titleLabel.layer.shadowRadius = 3.5;
        self.titleLabel.layer.shadowOffset = CGSizeMake(0, 1.5);
        [self addSubview:self.titleLabel];
    }
    return self;
}

- (void)updateOpticalGlassWithColor:(UIColor *)glowCol
                       cornerRadius:(CGFloat)cornerR
                         isCircular:(BOOL)isCircular
                        frontWeight:(double)frontWeight
                              theta:(double)theta {
    CGRect b = self.bounds;
    self.liquidBodyGradient.frame = b;
    self.specularSheenLayer.frame = b;
    self.innerBevelLayer.frame = b;

    if (!kLiquidGlass || kGlowIntensity <= 0.01) {
        self.layer.borderWidth = 0.0;
        self.liquidBodyGradient.opacity = 0.0;
        self.specularSheenLayer.opacity = 0.0;
        self.innerBevelLayer.opacity = 0.0;
        self.circularGlassRimOverlay.alpha = 0.0;
        return;
    }

    // Outer glowing rim flush with the card/orb edge
    CGFloat rimAlpha = MIN(0.98, (0.48 + kGlowIntensity * 0.50) * (0.65 + 0.35 * frontWeight));
    self.layer.borderWidth = 1.6 + kGlowIntensity * 1.1;
    self.layer.borderColor = [glowCol colorWithAlphaComponent:rimAlpha].CGColor;

    // Full-bleed edge-to-edge Liquid Glass body tint (controlled by glassRefract + glowIntensity)
    CGFloat bodyTopAlpha = MIN(0.45, (0.10 + kGlassRefract * 0.24) * MAX(0.35, kGlowIntensity));
    CGFloat bodyMidAlpha = MIN(0.22, (0.04 + kGlassRefract * 0.12) * MAX(0.35, kGlowIntensity));
    CGFloat bodyBotAlpha = MIN(0.40, (0.08 + kGlassRefract * 0.22) * MAX(0.35, kGlowIntensity));
    self.liquidBodyGradient.opacity = 1.0;
    self.liquidBodyGradient.colors = @[
        (id)[glowCol colorWithAlphaComponent:bodyTopAlpha].CGColor,
        (id)[glowCol colorWithAlphaComponent:bodyMidAlpha].CGColor,
        (id)[glowCol colorWithAlphaComponent:bodyBotAlpha].CGColor
    ];
    self.liquidBodyGradient.locations = @[@0.0, @0.5, @1.0];

    // Dynamic specular highlight + chromatic dispersion that shifts smoothly with swipe angle theta
    CGFloat specAlpha = MIN(0.55, (0.14 + (kGlassSpecular / 1.5) * 0.32) * (0.6 + 0.4 * frontWeight));
    CGFloat dispMix = MIN(0.35, kGlassDispersion * 0.30);
    UIColor *warmDispersion = [UIColor colorWithRed:1.0 green:0.88 blue:0.96 alpha:specAlpha * (0.55 + dispMix)];
    UIColor *coolDispersion = [UIColor colorWithRed:0.82 green:0.97 blue:1.0 alpha:specAlpha * (0.55 + dispMix)];

    double shift = sin(theta * 1.35) * 0.28;
    self.specularSheenLayer.opacity = 1.0;
    self.specularSheenLayer.startPoint = CGPointMake(MAX(0.0, 0.15 + shift), 0.0);
    self.specularSheenLayer.endPoint = CGPointMake(MIN(1.0, 0.85 + shift), 1.0);
    self.specularSheenLayer.colors = @[
        (id)[[UIColor whiteColor] colorWithAlphaComponent:specAlpha].CGColor,
        (id)coolDispersion.CGColor,
        (id)[UIColor clearColor].CGColor,
        (id)warmDispersion.CGColor
    ];
    self.specularSheenLayer.locations = @[@0.0, @0.24, @0.58, @1.0];

    // Inner specular glass bevel path matching exact card/orb geometry (zero crescent artifacts!)
    CGRect insetRect = CGRectInset(b, 1.2, 1.2);
    CGFloat innerR = MAX(0.0, cornerR - 1.2);
    UIBezierPath *bevelPath = isCircular
        ? [UIBezierPath bezierPathWithOvalInRect:insetRect]
        : [UIBezierPath bezierPathWithRoundedRect:insetRect cornerRadius:innerR];
    self.innerBevelLayer.path = bevelPath.CGPath;
    self.innerBevelLayer.opacity = 1.0;
    self.innerBevelLayer.strokeColor = [[UIColor whiteColor] colorWithAlphaComponent:MIN(0.65, 0.22 + (kGlassSpecular / 1.5) * 0.36)].CGColor;

    // Only apply circular glass_rim texture on circular modes (1, 2, 3), NEVER stretch on rectangles!
    if (isCircular && self.circularGlassRimOverlay.image) {
        self.circularGlassRimOverlay.alpha = MIN(0.85, 0.25 + kGlowIntensity * 0.45);
    } else {
        self.circularGlassRimOverlay.alpha = 0.0;
    }
}

@end

// ============================================================================
// Max-FPS Anti-Freeze 360° Infinite Carousel Stage View
// ============================================================================

@interface CSInfiniteCarouselStageView : UIView <UIGestureRecognizerDelegate>
@property (nonatomic, weak) SBFluidSwitcherViewController *ownerVC;
@property (nonatomic, strong) UIVisualEffectView *stageWallpaperBlur;
@property (nonatomic, strong) UIView *darkStageTint;
@property (nonatomic, strong) UIImageView *ambientBackdropView;
@property (nonatomic, strong) UIView *hologramBaseView;
@property (nonatomic, strong) UIImageView *baseOuterHalo;
@property (nonatomic, strong) UIImageView *baseInnerHalo;
@property (nonatomic, strong) UIImageView *baseCoreDisc;
@property (nonatomic, strong) UIView *carouselContentLayer;
@property (nonatomic, strong) UIVisualEffectView *entranceBlurVeil;
@property (nonatomic, strong) UIView *topHeaderPill;
@property (nonatomic, strong) UIImageView *topHeaderIcon;
@property (nonatomic, strong) UILabel *topHeaderLabel;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) NSMutableArray<CSInfiniteCarouselItem *> *items;
@property (nonatomic, assign) double spinAngle;
@property (nonatomic, assign) double angularVelocity;
@property (nonatomic, assign) double snapTargetAngle;
@property (nonatomic, assign) BOOL isSnapping;
@property (nonatomic, assign) NSInteger frontItemIndex;
@property (nonatomic, assign) NSInteger lastHapticIndex;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) CFTimeInterval lastTickTime;
@property (nonatomic, assign) BOOL panLockedVertical;
@property (nonatomic, assign) BOOL panLockedHorizontal;
@property (nonatomic, assign) CGFloat verticalDragOffset;
@property (nonatomic, assign) BOOL isLayingOutCarousel;
@property (nonatomic, assign) CGSize lastLayoutSize;
- (NSInteger)reloadAppsFromSwitcher;
- (void)layoutCarousel3D;
- (void)triggerSafeEntranceMotionBlur;
- (void)stopPhysics;
@end

@implementation CSInfiniteCarouselStageView

- (instancetype)initWithFrame:(CGRect)frame owner:(SBFluidSwitcherViewController *)owner {
    self = [super initWithFrame:frame];
    if (self) {
        self.ownerVC = owner;
        self.backgroundColor = [UIColor clearColor];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.items = [NSMutableArray array];
        self.frontItemIndex = 0;
        self.lastHapticIndex = -1;
        self.lastLayoutSize = CGSizeZero;

        // Full-screen wallpaper blur so underlying home/switcher never bleeds through
        UIBlurEffectStyle stageBlur = UIBlurEffectStyleDark;
        if (@available(iOS 13.0, *)) {
            stageBlur = UIBlurEffectStyleSystemUltraThinMaterialDark;
        }
        self.stageWallpaperBlur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:stageBlur]];
        self.stageWallpaperBlur.frame = self.bounds;
        self.stageWallpaperBlur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.stageWallpaperBlur.userInteractionEnabled = NO;
        [self addSubview:self.stageWallpaperBlur];

        self.darkStageTint = [[UIView alloc] initWithFrame:self.bounds];
        self.darkStageTint.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.darkStageTint.backgroundColor = [UIColor colorWithRed:0.01 green:0.03 blue:0.07 alpha:0.68];
        self.darkStageTint.userInteractionEnabled = NO;
        [self addSubview:self.darkStageTint];

        self.ambientBackdropView = [[UIImageView alloc] initWithFrame:self.bounds];
        self.ambientBackdropView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.ambientBackdropView.image = CSLoadAsset(@"ambient_backdrop", YES);
        self.ambientBackdropView.contentMode = UIViewContentModeScaleAspectFill;
        self.ambientBackdropView.userInteractionEnabled = NO;
        [self addSubview:self.ambientBackdropView];

        // Multi-ring 3D Hologram Projection Base
        self.hologramBaseView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 320)];
        self.hologramBaseView.userInteractionEnabled = NO;
        [self addSubview:self.hologramBaseView];

        UIImage *haloImg = CSLoadAsset(@"orb_halo", YES);
        self.baseOuterHalo = [[UIImageView alloc] initWithFrame:self.hologramBaseView.bounds];
        self.baseOuterHalo.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.baseOuterHalo.image = haloImg;
        [self.hologramBaseView addSubview:self.baseOuterHalo];

        self.baseInnerHalo = [[UIImageView alloc] initWithFrame:CGRectInset(self.hologramBaseView.bounds, 44, 44)];
        self.baseInnerHalo.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.baseInnerHalo.image = haloImg;
        [self.hologramBaseView addSubview:self.baseInnerHalo];

        self.baseCoreDisc = [[UIImageView alloc] initWithFrame:CGRectInset(self.hologramBaseView.bounds, 88, 88)];
        self.baseCoreDisc.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.baseCoreDisc.image = haloImg;
        [self.hologramBaseView addSubview:self.baseCoreDisc];

        self.carouselContentLayer = [[UIView alloc] initWithFrame:self.bounds];
        self.carouselContentLayer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.carouselContentLayer.backgroundColor = [UIColor clearColor];
        [self addSubview:self.carouselContentLayer];

        // Hardware-safe blur veil for smooth entrance motion blur
        self.entranceBlurVeil = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
        self.entranceBlurVeil.frame = self.bounds;
        self.entranceBlurVeil.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.entranceBlurVeil.userInteractionEnabled = NO;
        self.entranceBlurVeil.alpha = 0.0;
        self.entranceBlurVeil.layer.zPosition = 850.0;
        [self addSubview:self.entranceBlurVeil];

        self.topHeaderPill = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 192, 42)];
        self.topHeaderPill.backgroundColor = [UIColor colorWithWhite:0.10 alpha:0.84];
        self.topHeaderPill.layer.cornerRadius = 21.0;
        self.topHeaderPill.layer.borderWidth = 1.0;
        self.topHeaderPill.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.24].CGColor;
        self.topHeaderPill.userInteractionEnabled = NO;
        self.topHeaderPill.layer.zPosition = 900.0;
        [self addSubview:self.topHeaderPill];

        self.topHeaderIcon = [[UIImageView alloc] initWithFrame:CGRectMake(8, 7, 28, 28)];
        self.topHeaderIcon.layer.cornerRadius = 7.0;
        self.topHeaderIcon.layer.masksToBounds = YES;
        [self.topHeaderPill addSubview:self.topHeaderIcon];

        self.topHeaderLabel = [[UILabel alloc] initWithFrame:CGRectMake(42, 6, 140, 30)];
        self.topHeaderLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightBold];
        self.topHeaderLabel.textColor = [UIColor whiteColor];
        self.topHeaderLabel.textAlignment = NSTextAlignmentLeft;
        [self.topHeaderPill addSubview:self.topHeaderLabel];

        self.closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.closeButton.frame = CGRectMake(0, 0, 44, 44);
        self.closeButton.backgroundColor = [UIColor colorWithWhite:0.14 alpha:0.86];
        self.closeButton.layer.cornerRadius = 22.0;
        self.closeButton.layer.borderWidth = 1.25;
        self.closeButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
        [self.closeButton setTitle:@"✕" forState:UIControlStateNormal];
        [self.closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.closeButton.titleLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightBold];
        self.closeButton.layer.zPosition = 960.0;
        [self.closeButton addTarget:self action:@selector(handleCloseFrontApp:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.closeButton];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        pan.delegate = self;
        [self addGestureRecognizer:pan];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        tap.delegate = self;
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)dealloc {
    [self stopPhysics];
}

// Always let Home Bar (bottom 44pt) & Status Bar (top 48pt) pass straight through to iOS!
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || self.alpha < 0.05 || !self.userInteractionEnabled) {
        return nil;
    }
    CGFloat h = self.bounds.size.height;
    if (point.y > (h - 44.0) || point.y < 48.0) {
        return nil;
    }
    return [super hitTest:point withEvent:event];
}

- (void)stopPhysics {
    if (self.displayLink) {
        [self.displayLink invalidate];
        self.displayLink = nil;
    }
    self.angularVelocity = 0.0;
    self.isSnapping = NO;
}

- (void)startPhysicsIfNeeded {
    if (!self.displayLink) {
        self.lastTickTime = CACurrentMediaTime();
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(physicsTick:)];
        self.displayLink.preferredFramesPerSecond = 120;
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

- (double)slotAngleForCount:(NSInteger)count {
    if (count <= 1) return 2.0 * M_PI;
    // Ensure generous minimum angular separation so neighboring cards/orbs never collide
    double minSafeStep = (kLayoutMode == 2) ? 0.88 : 0.78;
    double naturalStep = (2.0 * M_PI) / (double)MIN(count, 8);
    return MAX(minSafeStep, naturalStep);
}

- (void)triggerSafeEntranceMotionBlur {
    if (!kMotionBlurOn) return;

    self.carouselContentLayer.transform = CGAffineTransformMakeScale(1.12, 1.12);
    self.carouselContentLayer.alpha = 0.0;
    self.entranceBlurVeil.alpha = MIN(0.72, MAX(0.18, kMotionBlurIntensity / 18.0));

    [UIView animateWithDuration:0.24 delay:0 usingSpringWithDamping:0.88 initialSpringVelocity:0.3 options:(UIViewAnimationOptions)UIViewAnimationOptionAllowUserInteraction animations:^{
        self.carouselContentLayer.transform = CGAffineTransformIdentity;
        self.carouselContentLayer.alpha = 1.0;
        self.entranceBlurVeil.alpha = 0.0;
    } completion:nil];
}

- (NSInteger)reloadAppsFromSwitcher {
    SBFluidSwitcherViewController *vc = self.ownerVC;
    if (!vc) return 0;

    NSArray *layouts = nil;
    @try {
        if ([vc respondsToSelector:@selector(appLayouts)]) {
            layouts = vc.appLayouts;
        }
        if ((!layouts || layouts.count == 0) && [vc respondsToSelector:NSSelectorFromString(@"dataSource")]) {
            id ds = ((id (*)(id, SEL))objc_msgSend)(vc, NSSelectorFromString(@"dataSource"));
            SEL dsSel = NSSelectorFromString(@"appLayoutsForSwitcherContentController:");
            if (ds && [ds respondsToSelector:dsSel]) {
                layouts = ((id (*)(id, SEL, id))objc_msgSend)(ds, dsSel, vc);
            }
        }
        if (!layouts || layouts.count == 0) {
            for (NSString *clsName in @[@"SBMainSwitcherControllerCoordinator", @"SBMainSwitcherViewController"]) {
                Class cls = NSClassFromString(clsName);
                if (!cls || ![cls respondsToSelector:NSSelectorFromString(@"sharedInstance")]) continue;
                id inst = ((id (*)(id, SEL))objc_msgSend)(cls, NSSelectorFromString(@"sharedInstance"));
                if (!inst) continue;
                id recent = nil;
                if ([inst respondsToSelector:NSSelectorFromString(@"recentAppLayouts")]) {
                    recent = ((id (*)(id, SEL))objc_msgSend)(inst, NSSelectorFromString(@"recentAppLayouts"));
                }
                if (recent && [recent respondsToSelector:NSSelectorFromString(@"recents")]) {
                    layouts = ((id (*)(id, SEL))objc_msgSend)(recent, NSSelectorFromString(@"recents"));
                    if (layouts.count > 0) break;
                }
            }
        }
    } @catch (NSException *e) {}

    for (CSInfiniteCarouselItem *item in self.items) {
        [item.outerHaloView removeFromSuperview];
        [item removeFromSuperview];
    }
    [self.items removeAllObjects];

    if (![layouts isKindOfClass:[NSArray class]] || layouts.count == 0) {
        self.topHeaderPill.hidden = YES;
        self.closeButton.hidden = YES;
        return 0;
    }

    UIImage *haloImg = CSLoadAsset(@"orb_halo", YES);
    UIImage *rimImg  = CSLoadAsset(@"glass_rim", NO);

    NSInteger maxApps = MIN((NSInteger)layouts.count, 24);
    for (NSInteger idx = 0; idx < maxApps; idx++) {
        id layout = layouts[idx];
        NSString *bid = CSBundleIDFromAppLayout(layout);
        if (!bid || bid.length == 0) continue;

        CSInfiniteCarouselItem *item = [[CSInfiniteCarouselItem alloc] initWithFrame:CGRectMake(0, 0, 180, 320)];
        item.appLayout = layout;
        item.bundleID = bid;
        item.displayName = CSAppDisplayNameForBundleID(bid);
        item.titleLabel.text = item.displayName;

        UIImage *appIcon = CSAppIconForBundleID(bid);
        item.iconImageView.image = appIcon;
        item.ambientIconBG.image = appIcon;
        item.circularGlassRimOverlay.image = rimImg;

        UIImageView *halo = [[UIImageView alloc] initWithFrame:CGRectZero];
        halo.image = haloImg;
        halo.userInteractionEnabled = NO;
        [self.carouselContentLayer addSubview:halo];
        item.outerHaloView = halo;

        [self.carouselContentLayer addSubview:item];
        [self.items addObject:item];
    }

    self.spinAngle = 0.0;
    self.angularVelocity = 0.0;
    self.isSnapping = NO;
    self.verticalDragOffset = 0.0;
    self.frontItemIndex = 0;
    self.lastHapticIndex = 0;

    [self layoutCarousel3D];
    return (NSInteger)self.items.count;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!CGSizeEqualToSize(self.bounds.size, self.lastLayoutSize) && !self.hidden) {
        self.lastLayoutSize = self.bounds.size;
        [self layoutCarousel3D];
    }
}

- (void)layoutCarousel3D {
    if (self.isLayingOutCarousel) return;
    self.isLayingOutCarousel = YES;

    // Disable CoreAnimation 0.25s implicit animations so physics ticks are silky smooth!
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    if (w < 10 || h < 10) {
        [CATransaction commit];
        self.isLayingOutCarousel = NO;
        return;
    }

    UIColor *glowCol = CSActiveGlowColor(1.0);
    UIColor *baseCol = CSActiveBaseColor(1.0);

    self.ambientBackdropView.hidden = !kBackdropEnabled;
    self.ambientBackdropView.tintColor = [glowCol colorWithAlphaComponent:0.20 * MAX(0.25, kGlowIntensity)];

    BOOL showBase = kHologramBaseEnabled && (kLayoutMode == 0 || kLayoutMode == 1 || kLayoutMode == 2);
    self.hologramBaseView.hidden = !showBase;
    if (showBase) {
        CGFloat ringDim = MIN(w, h) * 0.86 * kBaseScale;
        self.hologramBaseView.layer.transform = CATransform3DIdentity;
        self.hologramBaseView.bounds = CGRectMake(0, 0, ringDim, ringDim);
        self.hologramBaseView.center = CGPointMake(w * 0.5, h * 0.72);

        self.baseOuterHalo.tintColor = baseCol;
        self.baseInnerHalo.tintColor = baseCol;
        self.baseCoreDisc.tintColor  = baseCol;
        self.baseOuterHalo.alpha = 0.92;
        self.baseInnerHalo.alpha = 0.78;
        self.baseCoreDisc.alpha  = 0.55;
        self.hologramBaseView.alpha = MIN(1.0, kBaseIntensity * 1.15);

        CATransform3D baseTx = CATransform3DIdentity;
        baseTx.m34 = -1.0 / 520.0;
        baseTx = CATransform3DRotate(baseTx, 1.24, 1.0, 0.0, 0.0);
        self.hologramBaseView.layer.transform = baseTx;
        self.hologramBaseView.layer.shadowColor = baseCol.CGColor;
        self.hologramBaseView.layer.shadowOpacity = (float)(kBaseIntensity * 0.85);
        self.hologramBaseView.layer.shadowRadius = 24.0;
        self.hologramBaseView.layer.shadowOffset = CGSizeMake(0, -6);
    }

    NSInteger count = (NSInteger)self.items.count;
    if (count == 0) {
        self.topHeaderPill.hidden = YES;
        self.closeButton.hidden = YES;
        [CATransaction commit];
        self.isLayingOutCarousel = NO;
        return;
    }

    double slotAngle = [self slotAngleForCount:count];
    double totalSpan = (double)count * slotAngle;

    NSInteger bestIdx = 0;
    double bestCos = -999.0;
    CGFloat frontItemHeight = 320.0;

    for (NSInteger i = 0; i < count; i++) {
        CSInfiniteCarouselItem *item = self.items[i];

        double raw = ((double)i * slotAngle) + self.spinAngle;
        double theta = raw;
        if (kInfiniteScroll && count > 1) {
            theta = fmod(raw + totalSpan * 0.5, totalSpan);
            if (theta < 0.0) theta += totalSpan;
            theta -= totalSpan * 0.5;
        }
        item.lastTheta = theta;

        if (fabs(theta) > M_PI * 0.96) {
            item.hidden = YES;
            item.outerHaloView.hidden = YES;
            continue;
        }
        item.hidden = NO;

        double cosT = cos(theta);
        double sinT = sin(theta);
        double frontWeight = (cosT + 1.0) * 0.5;

        if (cosT > bestCos) {
            bestCos = cosT;
            bestIdx = i;
        }

        BOOL isCircular = (kLayoutMode == 1 || kLayoutMode == 2 || kLayoutMode == 3);
        CGFloat itemW = 192.0 * kCardScale;
        CGFloat itemH = 338.0 * kCardScale;

        if (kLayoutMode == 1) {
            CGFloat sz = 182.0 * kOrbSize;
            itemW = sz;
            itemH = sz;
        } else if (kLayoutMode == 2) {
            // Sharp focus curve so ONLY the centered orb expands big while side orbs stay compact & non-overlapping
            double focus = MAX(0.0, cosT);
            double focusSmooth = pow(focus, 4.2);
            CGFloat bigOrb = 216.0 * kCardScale;
            CGFloat smallOrb = 96.0 * kOrbSize;
            CGFloat sz = smallOrb + (bigOrb - smallOrb) * focusSmooth;
            itemW = sz;
            itemH = sz;
        } else if (kLayoutMode == 3) {
            CGFloat sz = 114.0 * kOrbSize;
            itemW = sz;
            itemH = sz;
        }

        if (i == bestIdx) {
            frontItemHeight = itemH;
        }

        CGFloat posX = w * 0.5;
        CGFloat posY = h * 0.48;
        CGFloat transZ = 0.0;
        CGFloat angleY = 0.0;
        CGFloat depthScale = 1.0;

        if (kLayoutMode == 0 || kLayoutMode == 1) {
            CGFloat cylR = MAX(itemW * 0.96, w * 0.45) * kCardSpacing;
            posX = (w * 0.5) + cylR * sinT;
            posY = (h * 0.47) - (1.0 - cosT) * 22.0;
            transZ = (cosT - 1.0) * 195.0 * kWheelCurvature;
            angleY = -theta * 0.78 * kWheelCurvature;
            depthScale = kScaleIcons ? (0.64 + 0.36 * frontWeight) : (0.90 + 0.10 * frontWeight);
        } else if (kLayoutMode == 2) {
            CGFloat orbitR = MAX(172.0, w * 0.48) * kCardSpacing;
            posX = (w * 0.5) + orbitR * sinT;
            posY = (h * 0.48) + (1.0 - cosT) * 16.0;
            transZ = (cosT - 1.0) * 155.0 * kWheelCurvature;
            angleY = -sinT * 0.48 * kWheelCurvature;
            depthScale = kScaleIcons ? (0.76 + 0.24 * frontWeight) : (0.92 + 0.08 * frontWeight);
        } else {
            CGFloat ringR = MIN(w, h) * 0.35 * kCardSpacing;
            posX = (w * 0.5) + ringR * sinT;
            posY = (h * 0.49) - ringR * cosT * 0.85;
            transZ = (cosT - 1.0) * 60.0;
            angleY = 0.0;
            depthScale = kScaleIcons ? (0.74 + 0.26 * frontWeight) : (0.92 + 0.08 * frontWeight);
        }

        CGFloat killYOffset = (i == self.frontItemIndex) ? self.verticalDragOffset : 0.0;
        posY += killYOffset;

        item.layer.transform = CATransform3DIdentity;
        item.bounds = CGRectMake(0, 0, itemW, itemH);
        item.center = CGPointMake(posX, posY);

        CGFloat cornerR = isCircular ? (itemW * 0.5) : MIN(itemW * 0.45, MAX(18.0, kCircleRadius));
        item.layer.cornerRadius = cornerR;
        if (@available(iOS 13.0, *)) {
            item.layer.cornerCurve = isCircular ? kCACornerCurveCircular : kCACornerCurveContinuous;
        }

        item.layer.zPosition = cosT * 320.0;
        CGFloat killAlpha = (killYOffset < -10.0) ? MAX(0.15, 1.0 + (killYOffset / 240.0)) : 1.0;
        CGFloat baseAlpha = kFadeIcons ? MAX(0.36, 0.40 + 0.60 * frontWeight) : MAX(0.84, 0.86 + 0.14 * frontWeight);
        item.alpha = baseAlpha * killAlpha;

        // Edge-to-edge optical glass & rim update
        [item updateOpticalGlassWithColor:glowCol
                             cornerRadius:cornerR
                               isCircular:isCircular
                              frontWeight:frontWeight
                                    theta:theta];

        if (item.outerHaloView.image && kLiquidGlass && kGlowIntensity > 0.01 && isCircular) {
            item.outerHaloView.hidden = NO;
            CGFloat haloDim = itemW * depthScale * 1.28;
            item.outerHaloView.bounds = CGRectMake(0, 0, haloDim, haloDim);
            item.outerHaloView.center = CGPointMake(posX, posY);
            item.outerHaloView.tintColor = glowCol;
            item.outerHaloView.alpha = kGlowIntensity * MAX(0.22, frontWeight) * killAlpha;
            item.outerHaloView.layer.zPosition = item.layer.zPosition - 1.5;
        } else {
            item.outerHaloView.hidden = YES;
        }

        CGFloat iconSide = isCircular ? (itemW * 0.42) : (itemW * 0.36);
        item.iconImageView.bounds = CGRectMake(0, 0, iconSide, iconSide);
        item.iconImageView.layer.cornerRadius = iconSide * 0.23;

        if (kTitlePosition == 1) {
            item.dimOverlay.alpha = kCenterDimAlpha;
            item.iconImageView.center = CGPointMake(itemW * 0.5, itemH * 0.44);
            item.titleLabel.bounds = CGRectMake(0, 0, itemW * 0.86, 24.0);
            item.titleLabel.center = CGPointMake(itemW * 0.5, itemH * 0.44 + iconSide * 0.5 + 16.0);
            item.iconImageView.alpha = 1.0;
            item.titleLabel.alpha = 1.0;
        } else if (kTitlePosition == 2) {
            item.dimOverlay.alpha = 0.16;
            item.iconImageView.center = CGPointMake(itemW * 0.5, itemH * 0.52);
            item.titleLabel.bounds = CGRectMake(0, 0, itemW * 0.86, 22.0);
            item.titleLabel.center = CGPointMake(itemW * 0.5, itemH * 0.84);
            item.iconImageView.alpha = 1.0;
            item.titleLabel.alpha = 1.0;
        } else {
            item.dimOverlay.alpha = 0.0;
            item.iconImageView.center = CGPointMake(itemW * 0.5, itemH * 0.50);
            item.iconImageView.alpha = 1.0;
            item.titleLabel.alpha = 0.0;
        }

        CATransform3D tx = CATransform3DIdentity;
        tx.m34 = -1.0 / (880.0 / MAX(0.35, kWheelCurvature));
        tx = CATransform3DTranslate(tx, 0.0, 0.0, transZ);
        if (fabs(angleY) > 0.0001) {
            tx = CATransform3DRotate(tx, angleY, 0.0, 1.0, 0.0);
        }
        if (kRollIcons && fabs(sinT) > 0.001) {
            tx = CATransform3DRotate(tx, sinT * 0.26, 0.0, 0.0, 1.0);
        }
        tx = CATransform3DScale(tx, depthScale, depthScale, 1.0);
        item.layer.transform = tx;
    }

    self.frontItemIndex = bestIdx;

    if (kHapticFeedback && bestIdx != self.lastHapticIndex) {
        self.lastHapticIndex = bestIdx;
        if (!kHapticGenerator) {
            kHapticGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        }
        [kHapticGenerator impactOccurred];
    }

    CSInfiniteCarouselItem *frontItem = self.items[bestIdx];
    if (kTitlePosition == 0 && frontItem) {
        self.topHeaderPill.hidden = NO;
        self.topHeaderIcon.image = frontItem.iconImageView.image;
        self.topHeaderLabel.text = frontItem.displayName;
        CGFloat centerStageY = (kLayoutMode == 0 || kLayoutMode == 1) ? (h * 0.47) : (h * 0.48);
        CGFloat pillY = MAX(72.0, centerStageY - (frontItemHeight * 0.5) - 32.0);
        self.topHeaderPill.center = CGPointMake(w * 0.5, pillY);
    } else {
        self.topHeaderPill.hidden = YES;
    }

    self.closeButton.hidden = !kShowCloseButton;
    if (kShowCloseButton) {
        CGFloat closeY = (kLayoutMode == 0) ? (h * 0.72) : (h * 0.71);
        self.closeButton.center = CGPointMake(w * 0.5, closeY);
    }

    [CATransaction commit];
    self.isLayingOutCarousel = NO;
}

- (void)physicsTick:(CADisplayLink *)link {
    CFTimeInterval now = CACurrentMediaTime();
    double dt = MIN(0.033, MAX(0.004, now - self.lastTickTime));
    self.lastTickTime = now;

    NSInteger count = (NSInteger)self.items.count;
    if (count == 0 || self.hidden) {
        [self stopPhysics];
        return;
    }

    if (self.isSnapping) {
        double diff = self.snapTargetAngle - self.spinAngle;
        self.spinAngle += diff * MIN(1.0, dt * 15.0);
        if (fabs(diff) < 0.0012) {
            self.spinAngle = self.snapTargetAngle;
            self.isSnapping = NO;
            [self stopPhysics];
        }
        [self layoutCarousel3D];
        return;
    }

    if (fabs(self.angularVelocity) > 0.035) {
        self.spinAngle += self.angularVelocity * dt;
        self.angularVelocity *= pow(0.055, dt);
        [self layoutCarousel3D];
    } else {
        self.angularVelocity = 0.0;
        double step = [self slotAngleForCount:count];
        self.snapTargetAngle = round(self.spinAngle / step) * step;
        self.isSnapping = YES;
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self];
    CGPoint velocity = [pan velocityInView:self];

    if (pan.state == UIGestureRecognizerStateBegan) {
        [self stopPhysics];
        self.panLockedHorizontal = NO;
        self.panLockedVertical = NO;
        self.verticalDragOffset = 0.0;
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        if (!self.panLockedHorizontal && !self.panLockedVertical) {
            if (fabs(translation.y) > fabs(translation.x) * 1.4 && translation.y < -14.0) {
                self.panLockedVertical = YES;
            } else if (fabs(translation.x) > 8.0) {
                self.panLockedHorizontal = YES;
            }
        }

        if (self.panLockedVertical) {
            self.verticalDragOffset = MIN(0.0, translation.y);
            [self layoutCarousel3D];
        } else {
            double deltaAngle = (double)translation.x / 185.0;
            self.spinAngle += deltaAngle;
            [pan setTranslation:CGPointZero inView:self];
            [self layoutCarousel3D];
        }
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        if (self.panLockedVertical) {
            if (self.verticalDragOffset < -95.0 || velocity.y < -650.0) {
                [self handleCloseFrontApp:nil];
            } else {
                self.verticalDragOffset = 0.0;
                [UIView animateWithDuration:0.25 animations:^{
                    [self layoutCarousel3D];
                }];
            }
            self.panLockedVertical = NO;
        } else {
            self.angularVelocity = MAX(-14.0, MIN(14.0, (double)velocity.x / 210.0));
            self.isSnapping = NO;
            [self startPhysicsIfNeeded];
            self.panLockedHorizontal = NO;
        }
    }
}

- (void)handleTap:(UITapGestureRecognizer *)tap {
    if (gIsLaunchingApp) return;
    CGPoint pt = [tap locationInView:self];

    if (!self.closeButton.hidden && CGRectContainsPoint(CGRectInset(self.closeButton.frame, -12, -12), pt)) {
        [self handleCloseFrontApp:self.closeButton];
        return;
    }

    NSArray<CSInfiniteCarouselItem *> *sorted = [self.items sortedArrayUsingComparator:^NSComparisonResult(CSInfiniteCarouselItem *a, CSInfiniteCarouselItem *b) {
        if (a.layer.zPosition > b.layer.zPosition) return NSOrderedAscending;
        if (a.layer.zPosition < b.layer.zPosition) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    CSInfiniteCarouselItem *hitItem = nil;
    for (CSInfiniteCarouselItem *item in sorted) {
        if (item.hidden || item.alpha < 0.1) continue;
        CALayer *pres = item.layer.presentationLayer ?: item.layer;
        CGRect frameInSelf = [self.carouselContentLayer convertRect:pres.frame toView:self];
        if (CGRectContainsPoint(frameInSelf, pt)) {
            hitItem = item;
            break;
        }
    }

    if (!hitItem) {
        [self.ownerVC _cs_dismissSwitcherToHome];
        return;
    }

    NSInteger idx = [self.items indexOfObject:hitItem];
    if (idx != NSNotFound && fabs(hitItem.lastTheta) > 0.42 && self.items.count > 1) {
        [self stopPhysics];
        double step = [self slotAngleForCount:self.items.count];
        double delta = -hitItem.lastTheta;
        self.snapTargetAngle = round((self.spinAngle + delta) / step) * step;
        self.isSnapping = YES;
        [self startPhysicsIfNeeded];
    } else {
        // Smoothly zoom the front card/orb into fullscreen before hiding the stage
        [self stopPhysics];
        gIsLaunchingApp = YES;
        id targetLayout = hitItem.appLayout;
        NSString *targetBundle = hitItem.bundleID;

        [self.carouselContentLayer bringSubviewToFront:hitItem];
        hitItem.layer.zPosition = 999.0;

        [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            for (CSInfiniteCarouselItem *other in self.items) {
                if (other != hitItem) {
                    other.alpha = 0.0;
                    other.outerHaloView.alpha = 0.0;
                }
            }
            self.hologramBaseView.alpha = 0.0;
            self.closeButton.alpha = 0.0;
            self.topHeaderPill.alpha = 0.0;
            hitItem.outerHaloView.alpha = 0.0;
            hitItem.dimOverlay.alpha = 0.0;
            hitItem.titleLabel.alpha = 0.0;
            hitItem.center = CGPointMake(self.bounds.size.width * 0.5, self.bounds.size.height * 0.5);
            hitItem.layer.cornerRadius = 38.0;
            hitItem.layer.transform = CATransform3DMakeScale(2.35, 2.35, 1.0);
        } completion:^(BOOL finished) {
            [self.ownerVC _cs_activateAppLayout:targetLayout bundleID:targetBundle];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                self.closeButton.alpha = 1.0;
                self.topHeaderPill.alpha = 1.0;
                gIsLaunchingApp = NO;
            });
        }];
    }
}

- (void)handleCloseFrontApp:(id)sender {
    if (self.items.count == 0) return;

    [self stopPhysics];

    // Pick the exact item standing directly above the (✕) button (smallest |theta|)
    CSInfiniteCarouselItem *target = nil;
    double smallestAngle = 999.0;
    for (CSInfiniteCarouselItem *candidate in self.items) {
        if (fabs(candidate.lastTheta) < smallestAngle) {
            smallestAngle = fabs(candidate.lastTheta);
            target = candidate;
        }
    }
    if (!target) return;

    id layoutToKill = target.appLayout;
    NSString *bidToKill = target.bundleID;
    NSInteger remainingAfterKill = (NSInteger)self.items.count - 1;

    if (kHapticFeedback) {
        if (!kHapticGenerator) {
            kHapticGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        }
        [kHapticGenerator impactOccurred];
    }

    // Guard prevents SpringBoard from dismissing the whole switcher when killing a single app!
    gIsKillingSingleApp = YES;
    gSwitcherActive = (remainingAfterKill > 0);

    [UIView animateWithDuration:0.20 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        target.center = CGPointMake(target.center.x, -target.bounds.size.height);
        target.alpha = 0.0;
        target.outerHaloView.alpha = 0.0;
    } completion:^(BOOL finished) {
        [target.outerHaloView removeFromSuperview];
        [target removeFromSuperview];
        [self.items removeObject:target];
        self.verticalDragOffset = 0.0;

        [self.ownerVC _cs_killAppLayout:layoutToKill bundleID:bidToKill];

        if (self.items.count == 0) {
            gIsKillingSingleApp = NO;
            [self.ownerVC _cs_dismissSwitcherToHome];
        } else {
            // Re-center the next app directly above (✕) and keep switcher open
            double step = [self slotAngleForCount:self.items.count];
            self.spinAngle = round(self.spinAngle / step) * step;
            [UIView animateWithDuration:0.24 delay:0 usingSpringWithDamping:0.84 initialSpringVelocity:0.3 options:UIViewAnimationOptionAllowUserInteraction animations:^{
                [self layoutCarousel3D];
            } completion:nil];

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                gIsKillingSingleApp = NO;
            });
        }
    }];
}

@end

// ============================================================================
// Hook SBFluidSwitcherItemContainerHeaderView
// ============================================================================

%hook SBFluidSwitcherItemContainerHeaderView

- (void)setAlpha:(CGFloat)alpha {
    if (kEnabled && gSwitcherActive) {
        if (CSUsesInfiniteCarouselOverlay() || kTitlePosition != 0) {
            %orig(0.0);
            return;
        }
    }
    %orig(alpha);
}

%end

// ============================================================================
// Hook SBAppSwitcherPageView — 100% Untouched Fullscreen Apps
// ============================================================================

%hook SBAppSwitcherPageView

- (void)layoutSubviews {
    %orig;

    if (!kEnabled || CSUsesInfiniteCarouselOverlay() || !gSwitcherActive) {
        if (self.layer.cornerRadius != 0.0 || self.layer.borderWidth != 0.0) {
            self.layer.cornerRadius = 0.0;
            self.layer.masksToBounds = NO;
            self.layer.borderWidth = 0.0;
            self.layer.shadowOpacity = 0.0;
            self.layer.mask = nil;
        }
        return;
    }

    SBFluidSwitcherItemContainer *parentContainer = nil;
    UIView *sup = self.superview;
    while (sup) {
        if ([sup isKindOfClass:%c(SBFluidSwitcherItemContainer)]) {
            parentContainer = (SBFluidSwitcherItemContainer *)sup;
            break;
        }
        sup = sup.superview;
    }

    BOOL inSwitcherCard = (parentContainer != nil);
    if (inSwitcherCard && [parentContainer respondsToSelector:@selector(contentPageViewScale)]) {
        if (parentContainer.contentPageViewScale >= 0.90) {
            inSwitcherCard = NO;
        }
    }

    if (!inSwitcherCard) {
        self.layer.cornerRadius = 0.0;
        self.layer.masksToBounds = NO;
        self.layer.borderWidth = 0.0;
        self.layer.shadowOpacity = 0.0;
        self.layer.mask = nil;
        return;
    }

    if (kCircleMorph) {
        CGFloat minSide = MIN(self.bounds.size.width, self.bounds.size.height);
        self.layer.cornerRadius = MIN(minSide * 0.5, kCircleRadius);
        self.layer.masksToBounds = YES;
        if (@available(iOS 13.0, *)) {
            self.layer.cornerCurve = kCACornerCurveContinuous;
        }
    } else {
        self.layer.cornerRadius = 0.0;
        self.layer.masksToBounds = NO;
    }

    if (kLiquidGlass && kGlowIntensity > 0.01) {
        self.layer.borderWidth = 2.0;
        self.layer.borderColor = CSActiveGlowColor(MIN(0.95, 0.40 + kGlowIntensity * 0.55)).CGColor;
    } else {
        self.layer.borderWidth = 0.0;
    }
}

- (void)_updateCornerRadius {
    %orig;
    if (!kEnabled || CSUsesInfiniteCarouselOverlay() || !gSwitcherActive) {
        if (self.layer.cornerRadius != 0.0 || self.layer.borderWidth != 0.0) {
            self.layer.cornerRadius = 0.0;
            self.layer.masksToBounds = NO;
            self.layer.borderWidth = 0.0;
            self.layer.mask = nil;
        }
    }
}

%end

// ============================================================================
// Hook SBFluidSwitcherItemContainer — Hides System Cards in 3D Modes, Transforms Classic Modes
// ============================================================================

%hook SBFluidSwitcherItemContainer

- (void)layoutSubviews {
    %orig;
    if (CSUsesInfiniteCarouselOverlay() && gSwitcherActive) {
        self.alpha = 0.0;
        self.hidden = YES;
        return;
    }
    if (self.hidden) {
        self.hidden = NO;
        self.alpha = 1.0;
    }
    [self _cs_applyClassicTransform];
}

- (void)setAlpha:(CGFloat)alpha {
    if (CSUsesInfiniteCarouselOverlay() && gSwitcherActive) {
        %orig(0.0);
        return;
    }
    %orig(alpha);
}

- (void)setCenter:(CGPoint)center {
    %orig;
    if (!CSUsesInfiniteCarouselOverlay()) {
        [self _cs_applyClassicTransform];
    }
}

- (void)setContentPageViewScale:(CGFloat)scale {
    %orig(scale);
    if (!CSUsesInfiniteCarouselOverlay()) {
        [self _cs_applyClassicTransform];
    }
}

%new
- (void)_cs_resetToNativeFullscreen {
    if (self.hidden) self.hidden = NO;
    if (self.alpha < 1.0) self.alpha = 1.0;
    UIView *targetView = ([self respondsToSelector:@selector(pageView)] && self.pageView) ? self.pageView : self.subviews.firstObject;
    if (targetView) {
        if (!CATransform3DIsIdentity(targetView.layer.transform)) {
            targetView.layer.transform = CATransform3DIdentity;
        }
        if (targetView.layer.cornerRadius != 0.0 || targetView.layer.borderWidth != 0.0) {
            targetView.layer.cornerRadius = 0.0;
            targetView.layer.masksToBounds = NO;
            targetView.layer.borderWidth = 0.0;
            targetView.layer.shadowOpacity = 0.0;
            targetView.layer.mask = nil;
        }
    }
    if (self.layer.zPosition != 0.0) self.layer.zPosition = 0.0;
    if (self.layer.shadowOpacity != 0.0) self.layer.shadowOpacity = 0.0;
}

%new
- (void)_cs_applyClassicTransform {
    if (!kEnabled || CSUsesInfiniteCarouselOverlay() || !gSwitcherActive) {
        [self _cs_resetToNativeFullscreen];
        return;
    }

    if ([self respondsToSelector:@selector(contentPageViewScale)] && self.contentPageViewScale >= 0.90) {
        [self _cs_resetToNativeFullscreen];
        return;
    }

    UIView *targetView = ([self respondsToSelector:@selector(pageView)] && self.pageView) ? self.pageView : self.subviews.firstObject;
    if (!targetView) return;

    UIWindow *win = self.window;
    CGFloat screenW = win ? win.bounds.size.width : [UIScreen mainScreen].bounds.size.width;
    if (screenW <= 0) screenW = 390.0;

    CGPoint centerInScreen = [self.superview convertPoint:self.center toView:win];
    CGFloat deltaX = centerInScreen.x - (screenW * 0.5);
    CGFloat t = (deltaX / (screenW * 0.54)) / MAX(0.45, kCardSpacing);
    CGFloat clampedT = MAX(-1.8, MIN(1.8, t));
    CGFloat absT = fabs(clampedT);

    if (kHapticFeedback && absT < 0.07 && kLastCenteredContainer != self) {
        kLastCenteredContainer = self;
        if (!kHapticGenerator) {
            kHapticGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        }
        [kHapticGenerator impactOccurred];
    }

    self.layer.zPosition = 500.0 - (absT * 260.0);

    CATransform3D transform = CATransform3DIdentity;
    transform.m34 = -1.0 / (900.0 / MAX(0.35, kWheelCurvature));

    CGFloat scale = kCardScale;
    CGFloat angleY = 0.0;
    CGFloat angleZ = 0.0;
    CGFloat transY = 0.0;
    CGFloat transZ = 0.0;

    switch (kLayoutMode) {
        case 4: {
            angleY = -clampedT * (M_PI / 5.2) * kWheelCurvature;
            angleZ = clampedT * (M_PI / 18.0) * kWheelCurvature;
            transY = (absT * absT) * 44.0 * kWheelCurvature;
            transZ = -absT * 95.0 * kWheelCurvature;
            scale  = kCardScale * MAX(0.72, 1.0 - absT * 0.14);
            break;
        }
        case 5: {
            angleY = -clampedT * (M_PI / 6.5) * kWheelCurvature;
            transZ = -absT * 60.0 * kWheelCurvature;
            scale  = kCardScale * MAX(0.78, 1.0 - absT * 0.09);
            break;
        }
        case 6: {
            angleY = -0.22 * kWheelCurvature;
            transZ = -absT * 110.0 * kWheelCurvature;
            transY = -absT * 14.0;
            scale  = kCardScale * MAX(0.74, 1.0 - absT * 0.11);
            break;
        }
        case 7: {
            CGFloat sign = (clampedT > 0) ? 1.0 : ((clampedT < 0) ? -1.0 : 0.0);
            CGFloat flowFactor = MIN(1.0, absT * 1.4);
            angleY = -sign * flowFactor * (M_PI / 3.4) * kWheelCurvature;
            transZ = -flowFactor * 120.0 * kWheelCurvature;
            scale  = kCardScale * (1.0 - flowFactor * 0.14);
            break;
        }
        case 8: {
            CGFloat sign = (clampedT > 0) ? 1.0 : ((clampedT < 0) ? -1.0 : 0.0);
            CGFloat flowFactor = MIN(1.0, absT * 1.4);
            angleY = sign * flowFactor * (M_PI / 3.4) * kWheelCurvature;
            transZ = -flowFactor * 120.0 * kWheelCurvature;
            scale  = kCardScale * (1.0 - flowFactor * 0.14);
            break;
        }
        case 9:
        default: {
            scale = kCardScale;
            break;
        }
    }

    transform = CATransform3DTranslate(transform, 0.0, transY, transZ);
    if (fabs(angleY) > 0.0001) {
        transform = CATransform3DRotate(transform, angleY, 0.0, 1.0, 0.0);
    }
    if (fabs(angleZ) > 0.0001) {
        transform = CATransform3DRotate(transform, angleZ, 0.0, 0.0, 1.0);
    }
    transform = CATransform3DScale(transform, scale, scale, 1.0);
    targetView.layer.transform = transform;

    if (kLiquidGlass && kGlowIntensity > 0.01) {
        self.layer.shadowColor = CSActiveGlowColor(1.0).CGColor;
        self.layer.shadowOpacity = (float)(kGlowIntensity * MAX(0.25, 1.0 - absT * 0.45));
        self.layer.shadowRadius = 18.0;
        self.layer.shadowOffset = CGSizeMake(0, 6);
    } else {
        self.layer.shadowOpacity = 0.0;
    }
}

%end

// ============================================================================
// Hook SBFluidSwitcherViewController — Immediate System Switcher Suppression
// ============================================================================

%hook SBFluidSwitcherViewController

- (void)viewDidLoad {
    %orig;
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    if (self.view.bounds.size.width >= screenW * 0.85 || !gPrimarySwitcherVC) {
        gPrimarySwitcherVC = self;
    }
}

- (void)layoutStateTransitionCoordinator:(id)coordinator transitionDidBeginWithTransitionContext:(id)context {
    %orig(coordinator, context);
    if (self != gPrimarySwitcherVC && gPrimarySwitcherVC != nil) return;

    @try {
        id toModeObj = [context valueForKeyPath:@"toLayoutState.unlockedEnvironmentMode"];
        if (toModeObj && [toModeObj respondsToSelector:@selector(integerValue)]) {
            NSInteger toMode = [toModeObj integerValue];
            if (toMode == 2) {
                gSwitcherActive = YES;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self _cs_setSwitcherActive:YES];
                });
            } else if (!gIsKillingSingleApp) {
                gSwitcherActive = NO;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self _cs_setSwitcherActive:NO];
                });
            }
        }
    } @catch (NSException *e) {}
}

- (void)layoutStateTransitionCoordinator:(id)coordinator transitionDidEndWithTransitionContext:(id)context {
    %orig(coordinator, context);
    if (self != gPrimarySwitcherVC && gPrimarySwitcherVC != nil) return;

    @try {
        id toModeObj = [context valueForKeyPath:@"toLayoutState.unlockedEnvironmentMode"];
        if (toModeObj && [toModeObj respondsToSelector:@selector(integerValue)]) {
            NSInteger toMode = [toModeObj integerValue];
            if (gIsKillingSingleApp) {
                CSInfiniteCarouselStageView *stage = objc_getAssociatedObject(self, kCSCarouselStageKey);
                if (stage && stage.items.count > 0) {
                    gSwitcherActive = YES;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self _cs_setSwitcherActive:YES];
                    });
                    return;
                }
            }
            BOOL open = (toMode == 2);
            gSwitcherActive = open;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self _cs_setSwitcherActive:open];
            });
        }
    } @catch (NSException *e) {}
}

%new
- (void)_cs_handlePrefsOrStateChanged {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _cs_setSwitcherActive:gSwitcherActive];
    });
}

%new
- (void)_cs_setSwitcherActive:(BOOL)active {
    if (gIsUpdatingSwitcherState) return;
    gIsUpdatingSwitcherState = YES;

    CSInfiniteCarouselStageView *stage = objc_getAssociatedObject(self, kCSCarouselStageKey);

    if (active && CSUsesInfiniteCarouselOverlay()) {
        if (!stage) {
            stage = [[CSInfiniteCarouselStageView alloc] initWithFrame:self.view.bounds owner:self];
            [self.view addSubview:stage];
            objc_setAssociatedObject(self, kCSCarouselStageKey, stage, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }

        stage.frame = self.view.bounds;
        NSInteger appCount = (gIsKillingSingleApp && stage.items.count > 0)
            ? (NSInteger)stage.items.count
            : [stage reloadAppsFromSwitcher];

        if (appCount > 0) {
            for (UIView *sub in self.view.subviews) {
                if (sub == stage) continue;
                sub.hidden = YES;
                sub.alpha = 0.0;
            }
            if (self.view.subviews.lastObject != stage) {
                [self.view bringSubviewToFront:stage];
            }
            BOOL wasHidden = stage.hidden;
            stage.hidden = NO;
            stage.alpha = 1.0;
            stage.userInteractionEnabled = YES;
            if (wasHidden && !gIsKillingSingleApp) {
                [stage triggerSafeEntranceMotionBlur];
            }
        } else {
            stage.hidden = YES;
            stage.userInteractionEnabled = NO;
            for (UIView *sub in self.view.subviews) {
                if (sub == stage) continue;
                sub.hidden = NO;
                sub.alpha = 1.0;
            }
        }
    } else {
        if (stage) {
            [stage stopPhysics];
            stage.hidden = YES;
            stage.alpha = 0.0;
            stage.userInteractionEnabled = NO;
        }
        for (UIView *sub in self.view.subviews) {
            if (sub == stage) continue;
            sub.hidden = NO;
            sub.alpha = 1.0;
            for (UIView *child in sub.subviews) {
                if ([child isKindOfClass:%c(SBFluidSwitcherItemContainer)]) {
                    if (!active) {
                        [(SBFluidSwitcherItemContainer *)child _cs_resetToNativeFullscreen];
                    } else {
                        [(SBFluidSwitcherItemContainer *)child _cs_applyClassicTransform];
                    }
                }
            }
        }
    }

    gIsUpdatingSwitcherState = NO;
}

%new
- (void)_cs_dismissSwitcherToHome {
    gSwitcherActive = NO;
    [self _cs_setSwitcherActive:NO];
    @try {
        Class sbUI = NSClassFromString(@"SBUIController");
        if (sbUI && [sbUI respondsToSelector:NSSelectorFromString(@"sharedInstance")]) {
            id ui = ((id (*)(id, SEL))objc_msgSend)(sbUI, NSSelectorFromString(@"sharedInstance"));
            SEL homeSel = NSSelectorFromString(@"handleHomeButtonSinglePressUp");
            if (ui && [ui respondsToSelector:homeSel]) {
                ((void (*)(id, SEL))objc_msgSend)(ui, homeSel);
                return;
            }
        }
        for (NSString *clsName in @[@"SBMainSwitcherControllerCoordinator", @"SBMainSwitcherViewController"]) {
            Class cls = NSClassFromString(clsName);
            if (!cls || ![cls respondsToSelector:NSSelectorFromString(@"sharedInstance")]) continue;
            id inst = ((id (*)(id, SEL))objc_msgSend)(cls, NSSelectorFromString(@"sharedInstance"));
            SEL toggleSel = NSSelectorFromString(@"toggleMainSwitcherNoninteractivelyWithSource:");
            if (inst && [inst respondsToSelector:toggleSel]) {
                ((void (*)(id, SEL, NSInteger))objc_msgSend)(inst, toggleSel, 0);
                return;
            }
        }
    } @catch (NSException *e) {}
}

%new
- (void)_cs_activateAppLayout:(id)appLayout bundleID:(NSString *)bundleID {
    gSwitcherActive = NO;
    [self _cs_setSwitcherActive:NO];

    if (bundleID.length > 0) {
        @try {
            UIApplication *sbApp = [UIApplication sharedApplication];
            SEL launchSel = NSSelectorFromString(@"launchApplicationWithIdentifier:suspended:");
            if ([sbApp respondsToSelector:launchSel]) {
                ((void (*)(id, SEL, id, BOOL))objc_msgSend)(sbApp, launchSel, bundleID, NO);
            }
        } @catch (NSException *e) {}
    }
}

%new
- (void)_cs_killAppLayout:(id)appLayout bundleID:(NSString *)bundleID {
    if (!appLayout) return;
    @try {
        for (NSString *clsName in @[@"SBMainSwitcherControllerCoordinator", @"SBMainSwitcherViewController"]) {
            Class cls = NSClassFromString(clsName);
            if (!cls || ![cls respondsToSelector:NSSelectorFromString(@"sharedInstance")]) continue;
            id inst = ((id (*)(id, SEL))objc_msgSend)(cls, NSSelectorFromString(@"sharedInstance"));
            if (!inst) continue;

            id recent = nil;
            if ([inst respondsToSelector:NSSelectorFromString(@"recentAppLayouts")]) {
                recent = ((id (*)(id, SEL))objc_msgSend)(inst, NSSelectorFromString(@"recentAppLayouts"));
            }
            SEL remSel = NSSelectorFromString(@"remove:");
            if (recent && [recent respondsToSelector:remSel]) {
                ((void (*)(id, SEL, id))objc_msgSend)(recent, remSel, appLayout);
                break;
            }
        }

        if (bundleID.length > 0) {
            Class fbSystemServiceCls = NSClassFromString(@"FBSSystemService");
            if (fbSystemServiceCls && [fbSystemServiceCls respondsToSelector:NSSelectorFromString(@"sharedService")]) {
                id svc = ((id (*)(id, SEL))objc_msgSend)(fbSystemServiceCls, NSSelectorFromString(@"sharedService"));
                SEL termSel = NSSelectorFromString(@"terminateApplication:forReason:andReport:withDescription:");
                if (svc && [svc respondsToSelector:termSel]) {
                    ((void (*)(id, SEL, id, NSInteger, BOOL, id))objc_msgSend)(svc, termSel, bundleID, 1, NO, @"CircleSwitcher Close");
                }
            }
        }
    } @catch (NSException *e) {}
}

%end

// ============================================================================
// Coordinator Backup Hooks (iOS 14-16.3.1+ Safe)
// ============================================================================

%hook SBMainSwitcherControllerCoordinator

- (void)layoutStateTransitionCoordinator:(id)coordinator transitionDidBeginWithTransitionContext:(id)context {
    %orig(coordinator, context);
    @try {
        id toModeObj = [context valueForKeyPath:@"toLayoutState.unlockedEnvironmentMode"];
        if (toModeObj && [toModeObj respondsToSelector:@selector(integerValue)]) {
            NSInteger toMode = [toModeObj integerValue];
            if (toMode == 2) {
                gSwitcherActive = YES;
                if (gPrimarySwitcherVC) [gPrimarySwitcherVC _cs_handlePrefsOrStateChanged];
            } else if (!gIsKillingSingleApp) {
                gSwitcherActive = NO;
                if (gPrimarySwitcherVC) [gPrimarySwitcherVC _cs_handlePrefsOrStateChanged];
            }
        }
    } @catch (NSException *e) {}
}

- (void)layoutStateTransitionCoordinator:(id)coordinator transitionDidEndWithTransitionContext:(id)context {
    %orig(coordinator, context);
    @try {
        id toModeObj = [context valueForKeyPath:@"toLayoutState.unlockedEnvironmentMode"];
        if (toModeObj && [toModeObj respondsToSelector:@selector(integerValue)]) {
            if (gIsKillingSingleApp) return;
            gSwitcherActive = ([toModeObj integerValue] == 2);
            if (gPrimarySwitcherVC) [gPrimarySwitcherVC _cs_handlePrefsOrStateChanged];
        }
    } @catch (NSException *e) {}
}

%end

%ctor {
    @autoreleasepool {
        CSLoadPreferences();
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            CSReloadCallback,
            (__bridge CFStringRef)kCSReloadNotification,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
    }
}
