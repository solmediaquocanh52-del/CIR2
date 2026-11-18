#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>

// ============================================================================
// CircleSwitcher v2.1.0 — True 360° Infinite Carousel Engine & Native Fullscreen Safety
// Supports iOS 14.0 - 16.3.1+ (Rootless & Rootful)
// Fixes:
//   1. 100% Native Fullscreen Apps (never clips Facebook/Settings/apps into ovals!)
//   2. True Infinite 360° Bi-Directional Carousel (Left & Right endless wrap-around)
//   3. True 1:1 Circular Orbs (zero vertical squashing, zero square glass_rim bleed)
//   4. Strict Switcher Visibility Guard (zero ambient_backdrop leak on Home Screen)
//   5. Clean Header Control (zero overlapping native app names / Bubble labels)
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
- (void)_cs_refreshSwitcherUI;
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
// 0: Vòng Trụ Thẻ 3D (Carousel Cards)
// 1: Icon Tròn Vòng Trụ 3D (Standing Cylindrical Orbs)
// 2: Khung Tròn & Vành Đai Icon (Orbital Preview & Orbs)
// 3: Bánh Xe Icon 360° (Radial Ring Wheel)
// 4..9: Classic Native Modes (Circle Wheel, 3D Cards, Card Deck, CoverFlow, Inverse CoverFlow, 2D Flat)
static NSInteger kLayoutMode = 0;
static BOOL kInfiniteScroll = YES;
static BOOL kCircleMorph = NO;
static CGFloat kCircleRadius = 34.0;
static CGFloat kWheelCurvature = 1.05;
static CGFloat kCardScale = 0.86;
static CGFloat kOrbSize = 0.76;
static CGFloat kCardSpacing = 1.05;

static NSInteger kTitlePosition = 1; // 0: Top, 1: Center (Dim), 2: Bottom, 3: Hidden
static CGFloat kCenterDimAlpha = 0.45;
static BOOL kShowCloseButton = YES;

static BOOL kLiquidGlass = YES;
static CGFloat kGlowIntensity = 0.65;
static NSInteger kGlowColorIndex = 0;
static NSString *kGlowColorHex = @"#00E5FF";

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

// Global Switcher Visibility State (Strictly synchronized with SpringBoard LayoutState)
static BOOL gIsInAppSwitcher = NO;
static __weak UIView *kLastCenteredContainer = nil;
static UIImpactFeedbackGenerator *kHapticGenerator = nil;

// Associated Object Keys
static const void *kCSCarouselStageKey = &kCSCarouselStageKey;
static const void *kCSClassicRimKey    = &kCSClassicRimKey;

// ============================================================================
// Color & Bundle Asset Helpers (Rootless /var/jb & Rootful)
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
    return img;
}

// ============================================================================
// SpringBoard App Metadata & Snapshot Extractors (iOS 14 - 16 Safe)
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
        Class proxyCls = NSClassFromString(@"LSApplicationProxy");
        if (proxyCls && [proxyCls respondsToSelector:NSSelectorFromString(@"applicationProxyForIdentifier:")]) {
            id proxy = ((id (*)(id, SEL, id))objc_msgSend)(proxyCls, NSSelectorFromString(@"applicationProxyForIdentifier:"), bundleID);
            if (proxy && [proxy respondsToSelector:NSSelectorFromString(@"localizedName")]) {
                NSString *name = ((id (*)(id, SEL))objc_msgSend)(proxy, NSSelectorFromString(@"localizedName"));
                if (name.length > 0) return name;
            }
        }
    } @catch (NSException *e) {}
    NSArray<NSString *> *parts = [bundleID componentsSeparatedByString:@"."];
    return parts.lastObject.length > 0 ? [parts.lastObject capitalizedString] : bundleID;
}

static UIImage *CSAppIconForBundleID(NSString *bundleID) {
    if (!bundleID || bundleID.length == 0) return nil;
    @try {
        SEL iconSel = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
        if ([UIImage respondsToSelector:iconSel]) {
            CGFloat scale = [UIScreen mainScreen].scale;
            UIImage *img = ((UIImage * (*)(id, SEL, NSString *, int, CGFloat))objc_msgSend)([UIImage class], iconSel, bundleID, 2, scale);
            if (img) return img;
        }
    } @catch (NSException *e) {}
    return nil;
}

static UIImage *CSCaptureSnapshotFromContainer(UIView *container) {
    if (!container || container.bounds.size.width < 10 || container.bounds.size.height < 10) return nil;
    UIView *src = container;
    if ([container respondsToSelector:@selector(pageView)]) {
        UIView *pv = ((id (*)(id, SEL))objc_msgSend)(container, @selector(pageView));
        if (pv && pv.bounds.size.width > 10 && pv.bounds.size.height > 10) {
            src = pv;
        }
    }
    @try {
        CGSize targetSize = CGSizeMake(src.bounds.size.width * 0.45, src.bounds.size.height * 0.45);
        UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
        fmt.scale = 1.0;
        fmt.opaque = YES;
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:targetSize format:fmt];
        UIImage *img = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            [src drawViewHierarchyInRect:CGRectMake(0, 0, targetSize.width, targetSize.height) afterScreenUpdates:NO];
        }];
        return img;
    } @catch (NSException *e) {
        return nil;
    }
}

static BOOL CSIsSpringBoardMainSwitcherVisible(void) {
    @try {
        NSArray<NSString *> *clsNames = @[@"SBMainSwitcherControllerCoordinator", @"SBMainSwitcherViewController"];
        for (NSString *clsName in clsNames) {
            Class cls = NSClassFromString(clsName);
            if (!cls) continue;
            SEL sharedSel = NSSelectorFromString(@"sharedInstance");
            if (![cls respondsToSelector:sharedSel]) continue;
            id inst = ((id (*)(id, SEL))objc_msgSend)(cls, sharedSel);
            if (!inst) continue;

            SEL visSel1 = NSSelectorFromString(@"isMainSwitcherVisible");
            if ([inst respondsToSelector:visSel1]) {
                BOOL v = ((BOOL (*)(id, SEL))objc_msgSend)(inst, visSel1);
                return v;
            }
            SEL visSel2 = NSSelectorFromString(@"isAnySwitcherVisible");
            if ([inst respondsToSelector:visSel2]) {
                BOOL v = ((BOOL (*)(id, SEL))objc_msgSend)(inst, visSel2);
                return v;
            }
        }
    } @catch (NSException *e) {}
    return gIsInAppSwitcher;
}

static BOOL CSUsesInfiniteCarouselOverlay(void) {
    return kEnabled && (kLayoutMode == 0 || kLayoutMode == 1 || kLayoutMode == 2 || kLayoutMode == 3);
}

// ============================================================================
// Preferences Loader
// ============================================================================

static NSDictionary *CSReadPreferencesDictionary(void) {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kCSDomain];
    [defaults synchronize];
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
    kOrbSize             = prefs[@"orbSize"]             ? [prefs[@"orbSize"] doubleValue]           : 0.76;
    kCardSpacing         = prefs[@"cardSpacing"]         ? [prefs[@"cardSpacing"] doubleValue]       : 1.05;

    kTitlePosition       = prefs[@"titlePosition"]       ? [prefs[@"titlePosition"] integerValue]    : 1;
    kCenterDimAlpha      = prefs[@"centerDimAlpha"]      ? [prefs[@"centerDimAlpha"] doubleValue]    : 0.45;
    kShowCloseButton     = prefs[@"showCloseButton"]     ? [prefs[@"showCloseButton"] boolValue]     : YES;

    kLiquidGlass         = prefs[@"liquidGlass"]         ? [prefs[@"liquidGlass"] boolValue]         : YES;
    kGlowIntensity       = prefs[@"glowIntensity"]       ? [prefs[@"glowIntensity"] doubleValue]     : 0.65;
    kGlowColorIndex      = prefs[@"glowColorIndex"]      ? [prefs[@"glowColorIndex"] integerValue]   : 0;
    kGlowColorHex        = prefs[@"glowColorHex"]        ? [prefs[@"glowColorHex"] description]      : @"#00E5FF";

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
        [[NSNotificationCenter defaultCenter] postNotificationName:@"CSInternalPreferencesDidUpdate" object:nil];
    });
}

// ============================================================================
// TRUE 360° INFINITE CAROUSEL ITEM VIEW (Zero Squashing, Single Crisp Rim)
// ============================================================================

@interface CSInfiniteCarouselItem : UIView
@property (nonatomic, strong) id appLayout;
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, strong) UIImageView *snapshotView;
@property (nonatomic, strong) UIView *dimOverlay;
@property (nonatomic, strong) UIImageView *glassRimOverlay;
@property (nonatomic, strong) UIImageView *iconImageView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *outerHaloView;
@property (nonatomic, assign) double lastTheta;
@end

@implementation CSInfiniteCarouselItem

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.09 green:0.12 blue:0.18 alpha:0.96];
        self.layer.masksToBounds = YES;
        self.clipsToBounds = YES;

        self.snapshotView = [[UIImageView alloc] initWithFrame:self.bounds];
        self.snapshotView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.snapshotView.contentMode = UIViewContentModeScaleAspectFill;
        self.snapshotView.clipsToBounds = YES;
        [self addSubview:self.snapshotView];

        self.dimOverlay = [[UIView alloc] initWithFrame:self.bounds];
        self.dimOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.dimOverlay.backgroundColor = [UIColor blackColor];
        self.dimOverlay.alpha = 0.0;
        [self addSubview:self.dimOverlay];

        self.glassRimOverlay = [[UIImageView alloc] initWithFrame:self.bounds];
        self.glassRimOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.glassRimOverlay.contentMode = UIViewContentModeScaleToFill;
        self.glassRimOverlay.alpha = 0.0;
        [self addSubview:self.glassRimOverlay];

        self.iconImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 62, 62)];
        self.iconImageView.contentMode = UIViewContentModeScaleAspectFill;
        self.iconImageView.layer.cornerRadius = 15.0;
        self.iconImageView.layer.masksToBounds = YES;
        self.iconImageView.layer.shadowColor = [UIColor blackColor].CGColor;
        self.iconImageView.layer.shadowOpacity = 0.45;
        self.iconImageView.layer.shadowRadius = 6.0;
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

@end

// ============================================================================
// TRUE 360° INFINITE CAROUSEL STAGE VIEW (Bi-Directional Infinite Physics!)
// ============================================================================

@interface CSInfiniteCarouselStageView : UIView <UIGestureRecognizerDelegate>
@property (nonatomic, weak) SBFluidSwitcherViewController *ownerVC;
@property (nonatomic, strong) UIView *darkStageTint;
@property (nonatomic, strong) UIImageView *ambientBackdropView;
@property (nonatomic, strong) UIView *hologramBaseView;
@property (nonatomic, strong) UIImageView *baseOuterHalo;
@property (nonatomic, strong) UIImageView *baseInnerHalo;
@property (nonatomic, strong) UIView *carouselContentLayer;
@property (nonatomic, strong) UIView *topHeaderPill;
@property (nonatomic, strong) UIImageView *topHeaderIcon;
@property (nonatomic, strong) UILabel *topHeaderLabel;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) NSMutableArray<CSInfiniteCarouselItem *> *items;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIImage *> *snapshotCache;
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
- (void)reloadAppsFromSwitcher;
- (void)layoutCarousel3D;
- (void)triggerEntranceMotionBlur;
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
        self.snapshotCache = [NSMutableDictionary dictionary];
        self.frontItemIndex = 0;
        self.lastHapticIndex = -1;

        // Subtle dark atmospheric veil (replaces harsh white wash)
        self.darkStageTint = [[UIView alloc] initWithFrame:self.bounds];
        self.darkStageTint.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.darkStageTint.backgroundColor = [UIColor colorWithRed:0.02 green:0.05 blue:0.10 alpha:0.42];
        self.darkStageTint.userInteractionEnabled = NO;
        [self addSubview:self.darkStageTint];

        // Ambient stage radial glow (subtle, never overexposed)
        self.ambientBackdropView = [[UIImageView alloc] initWithFrame:self.bounds];
        self.ambientBackdropView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.ambientBackdropView.image = CSLoadAsset(@"ambient_backdrop", YES);
        self.ambientBackdropView.contentMode = UIViewContentModeScaleAspectFill;
        self.ambientBackdropView.userInteractionEnabled = NO;
        [self addSubview:self.ambientBackdropView];

        // 3D Hologram Base Platform
        self.hologramBaseView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 320)];
        self.hologramBaseView.userInteractionEnabled = NO;
        [self addSubview:self.hologramBaseView];

        UIImage *haloImg = CSLoadAsset(@"orb_halo", YES);
        self.baseOuterHalo = [[UIImageView alloc] initWithFrame:self.hologramBaseView.bounds];
        self.baseOuterHalo.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.baseOuterHalo.image = haloImg;
        [self.hologramBaseView addSubview:self.baseOuterHalo];

        self.baseInnerHalo = [[UIImageView alloc] initWithFrame:CGRectInset(self.hologramBaseView.bounds, 48, 48)];
        self.baseInnerHalo.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.baseInnerHalo.image = haloImg;
        [self.hologramBaseView addSubview:self.baseInnerHalo];

        // 3D Carousel Cards/Orbs Container
        self.carouselContentLayer = [[UIView alloc] initWithFrame:self.bounds];
        self.carouselContentLayer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.carouselContentLayer.backgroundColor = [UIColor clearColor];
        [self addSubview:self.carouselContentLayer];

        // Top Floating App Title Pill (used when titlePosition == 0)
        self.topHeaderPill = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 180, 42)];
        self.topHeaderPill.backgroundColor = [UIColor colorWithWhite:0.10 alpha:0.78];
        self.topHeaderPill.layer.cornerRadius = 21.0;
        self.topHeaderPill.layer.borderWidth = 1.0;
        self.topHeaderPill.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.22].CGColor;
        self.topHeaderPill.userInteractionEnabled = NO;
        self.topHeaderPill.layer.zPosition = 900.0;
        [self addSubview:self.topHeaderPill];

        self.topHeaderIcon = [[UIImageView alloc] initWithFrame:CGRectMake(8, 7, 28, 28)];
        self.topHeaderIcon.layer.cornerRadius = 7.0;
        self.topHeaderIcon.layer.masksToBounds = YES;
        [self.topHeaderPill addSubview:self.topHeaderIcon];

        self.topHeaderLabel = [[UILabel alloc] initWithFrame:CGRectMake(42, 6, 128, 30)];
        self.topHeaderLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightBold];
        self.topHeaderLabel.textColor = [UIColor whiteColor];
        self.topHeaderLabel.textAlignment = NSTextAlignmentLeft;
        [self.topHeaderPill addSubview:self.topHeaderLabel];

        // Quick Close (✕) Button
        self.closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
        self.closeButton.frame = CGRectMake(0, 0, 44, 44);
        self.closeButton.backgroundColor = [UIColor colorWithWhite:0.14 alpha:0.84];
        self.closeButton.layer.cornerRadius = 22.0;
        self.closeButton.layer.borderWidth = 1.25;
        self.closeButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
        [self.closeButton setTitle:@"✕" forState:UIControlStateNormal];
        [self.closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.closeButton.titleLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightBold];
        self.closeButton.layer.zPosition = 960.0;
        [self.closeButton addTarget:self action:@selector(handleCloseFrontApp:) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.closeButton];

        // Gestures: Bi-directional Infinite Spin + Swipe-Up-To-Kill + Tap to Launch / Dismiss
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
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
}

- (double)slotAngleForCount:(NSInteger)count {
    if (count <= 1) return 2.0 * M_PI;
    if (count <= 7) return (2.0 * M_PI) / (double)count;
    // Cap visible cylinder density at 8 evenly spaced slots so 15+ open apps never crowd together,
    // while still wrapping seamlessly 360° infinitely around all N apps!
    return (2.0 * M_PI) / 8.0;
}

- (void)triggerEntranceMotionBlur {
    if (!kMotionBlurOn || kMotionBlurIntensity <= 0.1) return;
    @try {
        Class filterCls = NSClassFromString(@"CAFilter");
        SEL filterSel = NSSelectorFromString(@"filterWithType:");
        if (filterCls && [filterCls respondsToSelector:filterSel]) {
            id blurFilter = ((id (*)(id, SEL, id))objc_msgSend)(filterCls, filterSel, @"gaussianBlur");
            if (blurFilter) {
                [blurFilter setValue:@"csStageBlur" forKey:@"name"];
                [blurFilter setValue:@(kMotionBlurIntensity) forKey:@"inputRadius"];
                self.carouselContentLayer.layer.filters = @[blurFilter];

                CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"filters.csStageBlur.inputRadius"];
                anim.fromValue = @(kMotionBlurIntensity);
                anim.toValue = @(0.0);
                anim.duration = 0.28;
                anim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
                [self.carouselContentLayer.layer addAnimation:anim forKey:@"csStageBlurFade"];

                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.28 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    self.carouselContentLayer.layer.filters = nil;
                });
            }
        }
    } @catch (NSException *e) {}

    // Subtle zoom-in morph settle
    self.carouselContentLayer.transform = CGAffineTransformMakeScale(1.12, 1.12);
    self.carouselContentLayer.alpha = 0.0;
    [UIView animateWithDuration:0.26 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0.3 options:(UIViewAnimationOptions)UIViewAnimationOptionAllowUserInteraction animations:^{
        self.carouselContentLayer.transform = CGAffineTransformIdentity;
        self.carouselContentLayer.alpha = 1.0;
    } completion:nil];
}

- (void)reloadAppsFromSwitcher {
    SBFluidSwitcherViewController *vc = self.ownerVC;
    if (!vc) return;

    NSArray *layouts = nil;
    NSDictionary *visibleMap = nil;
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
            @try { layouts = [vc valueForKey:@"_appLayouts"]; } @catch (NSException *ex) {}
        }
        if (!layouts || layouts.count == 0) {
            for (NSString *clsName in @[@"SBMainSwitcherControllerCoordinator", @"SBMainSwitcherViewController"]) {
                Class cls = NSClassFromString(clsName);
                if (!cls || ![cls respondsToSelector:NSSelectorFromString(@"sharedInstance")]) continue;
                id inst = ((id (*)(id, SEL))objc_msgSend)(cls, NSSelectorFromString(@"sharedInstance"));
                if (!inst) continue;
                id recent = nil;
                @try { recent = [inst valueForKey:@"_recentAppLayouts"]; } @catch (NSException *ex) {}
                if (!recent && [inst respondsToSelector:NSSelectorFromString(@"recentAppLayouts")]) {
                    recent = ((id (*)(id, SEL))objc_msgSend)(inst, NSSelectorFromString(@"recentAppLayouts"));
                }
                if (recent && [recent respondsToSelector:NSSelectorFromString(@"recents")]) {
                    layouts = ((id (*)(id, SEL))objc_msgSend)(recent, NSSelectorFromString(@"recents"));
                    if (layouts.count > 0) break;
                }
            }
        }
        if ([vc respondsToSelector:@selector(visibleItemContainers)]) {
            visibleMap = vc.visibleItemContainers;
        }
        if (!visibleMap) {
            @try { visibleMap = [vc valueForKey:@"_visibleItemContainers"]; } @catch (NSException *ex) {}
        }
        if ((!layouts || layouts.count == 0) && [visibleMap isKindOfClass:[NSDictionary class]]) {
            layouts = [visibleMap allKeys];
        }
    } @catch (NSException *e) {}

    // Cache live snapshots from any currently visible native containers
    if ([visibleMap isKindOfClass:[NSDictionary class]]) {
        for (id keyLayout in visibleMap) {
            NSString *bid = CSBundleIDFromAppLayout(keyLayout);
            UIView *container = visibleMap[keyLayout];
            if (bid.length > 0 && [container isKindOfClass:[UIView class]]) {
                UIImage *snap = CSCaptureSnapshotFromContainer(container);
                if (snap) {
                    self.snapshotCache[bid] = snap;
                }
            }
        }
    }

    // Clear previous item views
    for (CSInfiniteCarouselItem *item in self.items) {
        [item.outerHaloView removeFromSuperview];
        [item removeFromSuperview];
    }
    [self.items removeAllObjects];

    if (![layouts isKindOfClass:[NSArray class]] || layouts.count == 0) {
        self.topHeaderPill.hidden = YES;
        self.closeButton.hidden = YES;
        return;
    }

    UIImage *haloImg = CSLoadAsset(@"orb_halo", YES);
    UIImage *rimImg  = CSLoadAsset(@"glass_rim", NO);
    UIImage *stretchedRim = rimImg ? [rimImg resizableImageWithCapInsets:UIEdgeInsetsMake(rimImg.size.height * 0.45, rimImg.size.width * 0.45, rimImg.size.height * 0.45, rimImg.size.width * 0.45) resizingMode:UIImageResizingModeStretch] : nil;

    for (id layout in layouts) {
        NSString *bid = CSBundleIDFromAppLayout(layout);
        if (!bid || bid.length == 0) continue;

        CSInfiniteCarouselItem *item = [[CSInfiniteCarouselItem alloc] initWithFrame:CGRectMake(0, 0, 180, 320)];
        item.appLayout = layout;
        item.bundleID = bid;
        item.displayName = CSAppDisplayNameForBundleID(bid);
        item.titleLabel.text = item.displayName;
        item.iconImageView.image = CSAppIconForBundleID(bid);

        UIImage *snap = self.snapshotCache[bid];
        if (snap) {
            item.snapshotView.image = snap;
        } else {
            item.snapshotView.image = nil;
        }

        BOOL isCircularMode = (kLayoutMode == 1 || kLayoutMode == 2 || kLayoutMode == 3);
        item.glassRimOverlay.image = isCircularMode ? rimImg : stretchedRim;

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
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self layoutCarousel3D];
}

- (void)layoutCarousel3D {
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    if (w < 10 || h < 10) return;

    UIColor *glowCol = CSActiveGlowColor(1.0);
    UIColor *baseCol = CSActiveBaseColor(1.0);

    // Subtle Atmospheric Backdrop
    self.ambientBackdropView.hidden = !kBackdropEnabled;
    self.ambientBackdropView.tintColor = [glowCol colorWithAlphaComponent:0.16 * MAX(0.25, kGlowIntensity)];

    // 3D Hologram Base Ring (Modes 0, 1, 2)
    BOOL showBase = kHologramBaseEnabled && (kLayoutMode == 0 || kLayoutMode == 1 || kLayoutMode == 2);
    self.hologramBaseView.hidden = !showBase;
    if (showBase) {
        CGFloat ringDim = MIN(w, h) * 0.84 * kBaseScale;
        self.hologramBaseView.layer.transform = CATransform3DIdentity;
        self.hologramBaseView.bounds = CGRectMake(0, 0, ringDim, ringDim);
        self.hologramBaseView.center = CGPointMake(w * 0.5, h * 0.72);

        self.baseOuterHalo.tintColor = baseCol;
        self.baseInnerHalo.tintColor = baseCol;
        self.hologramBaseView.alpha = MIN(1.0, kBaseIntensity * 1.1);

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
        return;
    }

    double slotAngle = [self slotAngleForCount:count];
    double totalSpan = (double)count * slotAngle;

    NSInteger bestIdx = 0;
    double bestCos = -999.0;

    for (NSInteger i = 0; i < count; i++) {
        CSInfiniteCarouselItem *item = self.items[i];

        // True bi-directional infinite wrap-around modulo totalSpan
        double raw = ((double)i * slotAngle) + self.spinAngle;
        double theta = raw;
        if (kInfiniteScroll && count > 1) {
            theta = fmod(raw + totalSpan * 0.5, totalSpan);
            if (theta < 0.0) theta += totalSpan;
            theta -= totalSpan * 0.5;
        }

        item.lastTheta = theta;

        // Hide items currently behind the invisible back half when N > 8
        BOOL visibleOnRing = (fabs(theta) <= M_PI * 0.96);
        if (!visibleOnRing) {
            item.hidden = YES;
            item.outerHaloView.hidden = YES;
            continue;
        }
        item.hidden = NO;

        double cosT = cos(theta);
        double sinT = sin(theta);
        double frontWeight = (cosT + 1.0) * 0.5; // 1.0 at dead front, 0.0 at back

        if (cosT > bestCos) {
            bestCos = cosT;
            bestIdx = i;
        }

        BOOL isCircular = (kLayoutMode == 1 || kLayoutMode == 2 || kLayoutMode == 3);
        CGFloat itemW = 196.0 * kCardScale;
        CGFloat itemH = 344.0 * kCardScale;

        if (kLayoutMode == 1) {
            // Mode 1: Standing 1:1 Circular Orbs on 3D Cylinder (NO vertical squashing!)
            CGFloat sz = 188.0 * kOrbSize;
            itemW = sz;
            itemH = sz;
        } else if (kLayoutMode == 2) {
            // Mode 2: Center Large Circular Window + Smaller Side Orbs (True 1:1!)
            double focus = MAX(0.0, cosT);
            double focusSmooth = pow(focus, 2.2);
            CGFloat bigOrb = 224.0 * kCardScale;
            CGFloat smallOrb = 112.0 * kOrbSize;
            CGFloat sz = smallOrb + (bigOrb - smallOrb) * focusSmooth;
            itemW = sz;
            itemH = sz;
        } else if (kLayoutMode == 3) {
            // Mode 3: Radial 360° Icon Ring Orbs (True 1:1!)
            CGFloat sz = 118.0 * kOrbSize;
            itemW = sz;
            itemH = sz;
        }

        CGFloat posX = w * 0.5;
        CGFloat posY = h * 0.48;
        CGFloat transZ = 0.0;
        CGFloat angleY = 0.0;
        CGFloat depthScale = 1.0;

        if (kLayoutMode == 0 || kLayoutMode == 1) {
            // 3D Hologram Cylinder (Cards OR Standing Circular Orbs)
            CGFloat cylR = (w * 0.42) * kCardSpacing;
            posX = (w * 0.5) + cylR * sinT;
            posY = (h * 0.47) - (1.0 - cosT) * 24.0;
            transZ = (cosT - 1.0) * 185.0 * kWheelCurvature;
            angleY = -theta * 0.78 * kWheelCurvature;
            depthScale = 0.62 + 0.38 * frontWeight;
        } else if (kLayoutMode == 2) {
            // Orbital Preview & Side Orbs
            CGFloat orbitR = (w * 0.44) * kCardSpacing;
            posX = (w * 0.5) + orbitR * sinT;
            posY = (h * 0.48) + (1.0 - cosT) * 18.0;
            transZ = (cosT - 1.0) * 145.0 * kWheelCurvature;
            angleY = -sinT * 0.52 * kWheelCurvature;
            depthScale = 0.72 + 0.28 * frontWeight;
        } else {
            // Mode 3: Radial 360° Icon Ring
            CGFloat ringR = MIN(w, h) * 0.34 * kCardSpacing;
            posX = (w * 0.5) + ringR * sinT;
            posY = (h * 0.49) - ringR * cosT * 0.85;
            transZ = (cosT - 1.0) * 60.0;
            angleY = 0.0;
            depthScale = 0.76 + 0.24 * frontWeight;
        }

        // Apply vertical drag-up-to-kill offset only on the frontmost card
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

        // Depth sorting & smooth back-side fade
        item.layer.zPosition = cosT * 320.0;
        CGFloat killAlpha = (killYOffset < -10.0) ? MAX(0.15, 1.0 + (killYOffset / 240.0)) : 1.0;
        item.alpha = MAX(0.32, 0.38 + 0.62 * frontWeight) * killAlpha;

        // Single Crisp Neon Rim + Liquid Glass Specular Overlay (Zero Double Border!)
        if (kLiquidGlass && kGlowIntensity > 0.01) {
            item.layer.borderWidth = 2.0;
            item.layer.borderColor = [glowCol colorWithAlphaComponent:MIN(0.95, 0.45 + kGlowIntensity * 0.50)].CGColor;
            item.glassRimOverlay.alpha = MIN(0.88, 0.30 + kGlowIntensity * 0.52);
        } else {
            item.layer.borderWidth = 0.0;
            item.glassRimOverlay.alpha = 0.0;
        }

        // Outer Circular Neon Halo (strictly circular 1:1, never square bleed!)
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

        // Inner App Icon & Title Positioning + Auto-Dimming when Centered
        CGFloat iconSide = isCircular ? (itemW * 0.42) : (itemW * 0.36);
        item.iconImageView.bounds = CGRectMake(0, 0, iconSide, iconSide);
        item.iconImageView.layer.cornerRadius = iconSide * 0.23;

        if (kTitlePosition == 1) {
            // Centered App Icon + Title with Card Dimming
            item.dimOverlay.alpha = (item.snapshotView.image ? kCenterDimAlpha : 0.20);
            item.iconImageView.center = CGPointMake(itemW * 0.5, itemH * 0.44);
            item.titleLabel.bounds = CGRectMake(0, 0, itemW * 0.86, 24.0);
            item.titleLabel.center = CGPointMake(itemW * 0.5, itemH * 0.44 + iconSide * 0.5 + 16.0);
            item.iconImageView.alpha = 1.0;
            item.titleLabel.alpha = 1.0;
        } else if (kTitlePosition == 2) {
            // Bottom inside card
            item.dimOverlay.alpha = 0.16;
            item.iconImageView.center = CGPointMake(itemW * 0.5, itemH * 0.70);
            item.titleLabel.bounds = CGRectMake(0, 0, itemW * 0.86, 22.0);
            item.titleLabel.center = CGPointMake(itemW * 0.5, itemH * 0.86);
            item.iconImageView.alpha = 1.0;
            item.titleLabel.alpha = 1.0;
        } else if (kTitlePosition == 0) {
            // Top Floating Pill (card stays bright; side orbs show icon cleanly)
            item.dimOverlay.alpha = (item.snapshotView.image ? 0.0 : 0.12);
            item.iconImageView.center = CGPointMake(itemW * 0.5, itemH * 0.50);
            item.iconImageView.alpha = (item.snapshotView.image && !(kLayoutMode == 2 && frontWeight < 0.65)) ? 0.0 : 1.0;
            item.titleLabel.alpha = 0.0;
        } else {
            // Hidden Title
            item.dimOverlay.alpha = 0.0;
            item.iconImageView.center = CGPointMake(itemW * 0.5, itemH * 0.50);
            item.iconImageView.alpha = item.snapshotView.image ? 0.0 : 1.0;
            item.titleLabel.alpha = 0.0;
        }

        CATransform3D tx = CATransform3DIdentity;
        tx.m34 = -1.0 / (880.0 / MAX(0.35, kWheelCurvature));
        tx = CATransform3DTranslate(tx, 0.0, 0.0, transZ);
        if (fabs(angleY) > 0.0001) {
            tx = CATransform3DRotate(tx, angleY, 0.0, 1.0, 0.0);
        }
        tx = CATransform3DScale(tx, depthScale, depthScale, 1.0);
        item.layer.transform = tx;
    }

    self.frontItemIndex = bestIdx;

    // Haptic tick when a new app rotates into front center
    if (kHapticFeedback && bestIdx != self.lastHapticIndex) {
        self.lastHapticIndex = bestIdx;
        if (!kHapticGenerator) {
            kHapticGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        }
        [kHapticGenerator impactOccurred];
    }

    // Update Top Floating Pill (only when titlePosition == 0)
    CSInfiniteCarouselItem *frontItem = self.items[bestIdx];
    if (kTitlePosition == 0 && frontItem) {
        self.topHeaderPill.hidden = NO;
        self.topHeaderIcon.image = frontItem.iconImageView.image;
        self.topHeaderLabel.text = frontItem.displayName;
        CGFloat pillY = (kLayoutMode == 0) ? (h * 0.16) : (h * 0.21);
        self.topHeaderPill.center = CGPointMake(w * 0.5, pillY);
    } else {
        self.topHeaderPill.hidden = YES;
    }

    // Update Quick Close (✕) Button below front item
    self.closeButton.hidden = !kShowCloseButton;
    if (kShowCloseButton) {
        CGFloat closeY = (kLayoutMode == 0) ? (h * 0.72) : (h * 0.71);
        self.closeButton.center = CGPointMake(w * 0.5, closeY);
    }
}

// ============================================================================
// Physics Tick: Smooth Infinite Momentum + Elastic Center Snap
// ============================================================================

- (void)physicsTick:(CADisplayLink *)link {
    CFTimeInterval now = CACurrentMediaTime();
    double dt = MIN(0.04, MAX(0.004, now - self.lastTickTime));
    self.lastTickTime = now;

    NSInteger count = (NSInteger)self.items.count;
    if (count == 0) {
        [self stopPhysics];
        return;
    }

    if (self.isSnapping) {
        double diff = self.snapTargetAngle - self.spinAngle;
        self.spinAngle += diff * MIN(1.0, dt * 14.0);
        if (fabs(diff) < 0.0015) {
            self.spinAngle = self.snapTargetAngle;
            self.isSnapping = NO;
            [self stopPhysics];
        }
        [self layoutCarousel3D];
        return;
    }

    if (fabs(self.angularVelocity) > 0.04) {
        self.spinAngle += self.angularVelocity * dt;
        // Smooth exponential deceleration
        self.angularVelocity *= pow(0.06, dt);
        [self layoutCarousel3D];
    } else {
        // Snap smoothly to nearest app slot
        self.angularVelocity = 0.0;
        double step = [self slotAngleForCount:count];
        self.snapTargetAngle = round(self.spinAngle / step) * step;
        self.isSnapping = YES;
    }
}

// ============================================================================
// Gestures: Bi-Directional Infinite Pan, Swipe-Up-To-Kill, Tap Launch/Dismiss
// ============================================================================

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
    CGPoint pt = [tap locationInView:self];

    // Check close button first
    if (!self.closeButton.hidden && CGRectContainsPoint(CGRectInset(self.closeButton.frame, -10, -10), pt)) {
        [self handleCloseFrontApp:self.closeButton];
        return;
    }

    // Hit-test items from frontmost zPosition backwards
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
        // Tapped empty space -> dismiss switcher cleanly to Home Screen
        [self.ownerVC _cs_dismissSwitcherToHome];
        return;
    }

    NSInteger idx = [self.items indexOfObject:hitItem];
    if (idx != NSNotFound && fabs(hitItem.lastTheta) > 0.42 && self.items.count > 1) {
        // Rotate tapped side app smoothly to front center
        [self stopPhysics];
        double step = [self slotAngleForCount:self.items.count];
        double delta = -hitItem.lastTheta;
        self.snapTargetAngle = round((self.spinAngle + delta) / step) * step;
        self.isSnapping = YES;
        [self startPhysicsIfNeeded];
    } else {
        // Launch front app into 100% native fullscreen!
        [self stopPhysics];
        [self.ownerVC _cs_activateAppLayout:hitItem.appLayout bundleID:hitItem.bundleID];
    }
}

- (void)handleCloseFrontApp:(id)sender {
    if (self.items.count == 0 || self.frontItemIndex < 0 || self.frontItemIndex >= (NSInteger)self.items.count) return;

    CSInfiniteCarouselItem *target = self.items[self.frontItemIndex];
    id layoutToKill = target.appLayout;
    NSString *bidToKill = target.bundleID;

    if (kHapticFeedback) {
        if (!kHapticGenerator) {
            kHapticGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        }
        [kHapticGenerator impactOccurred];
    }

    [UIView animateWithDuration:0.22 animations:^{
        target.center = CGPointMake(target.center.x, -target.bounds.size.height);
        target.alpha = 0.0;
        target.outerHaloView.alpha = 0.0;
    } completion:^(BOOL finished) {
        [target.outerHaloView removeFromSuperview];
        [target removeFromSuperview];
        [self.items removeObject:target];
        self.verticalDragOffset = 0.0;
        [self.ownerVC _cs_killAppLayout:layoutToKill bundleID:bidToKill];
        [UIView animateWithDuration:0.26 animations:^{
            [self layoutCarousel3D];
        }];
    }];
}

@end

// ============================================================================
// Hook SBFluidSwitcherItemContainerHeaderView — Fix Overlapping Native Headers
// ============================================================================

%hook SBFluidSwitcherItemContainerHeaderView

- (void)setAlpha:(CGFloat)alpha {
    if (kEnabled && gIsInAppSwitcher) {
        if (CSUsesInfiniteCarouselOverlay()) {
            %orig(0.0);
            return;
        }
        if (kTitlePosition != 0) {
            %orig(0.0);
            return;
        }
    }
    %orig(alpha);
}

%end

// ============================================================================
// Hook SBAppSwitcherPageView — Strict Native Fullscreen Restoration!
// Fixes Facebook / Settings Rounded Corner Cutout Bug Permanently!
// ============================================================================

%hook SBAppSwitcherPageView

- (void)layoutSubviews {
    %orig;

    // Modes 0..3 use the clean Infinite Carousel Overlay -> NEVER touch native pageView!
    if (!kEnabled || CSUsesInfiniteCarouselOverlay() || !gIsInAppSwitcher) {
        self.layer.cornerRadius = 0.0;
        self.layer.masksToBounds = NO;
        self.layer.borderWidth = 0.0;
        self.layer.shadowOpacity = 0.0;
        self.layer.mask = nil;
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
        if (parentContainer.contentPageViewScale >= 0.91) {
            inSwitcherCard = NO;
        }
    }

    if (!inSwitcherCard) {
        // 100% Native Fullscreen App: wipe every trace of rounding/border!
        self.layer.cornerRadius = 0.0;
        self.layer.masksToBounds = NO;
        self.layer.borderWidth = 0.0;
        self.layer.shadowOpacity = 0.0;
        self.layer.mask = nil;
        return;
    }

    // Classic Native Modes (4..9) ONLY while actively in Switcher
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
    if (!kEnabled || CSUsesInfiniteCarouselOverlay() || !gIsInAppSwitcher) {
        self.layer.cornerRadius = 0.0;
        self.layer.masksToBounds = NO;
        self.layer.borderWidth = 0.0;
        self.layer.mask = nil;
    }
}

%end

// ============================================================================
// Hook SBFluidSwitcherItemContainer — Clean Classic Modes (4..9) + Fullscreen Reset
// ============================================================================

%hook SBFluidSwitcherItemContainer

- (void)layoutSubviews {
    %orig;
    [self _cs_applyClassicTransform];
}

- (void)setCenter:(CGPoint)center {
    %orig;
    [self _cs_applyClassicTransform];
}

- (void)setContentPageViewScale:(CGFloat)scale {
    %orig(scale);
    [self _cs_applyClassicTransform];
}

%new
- (void)_cs_resetToNativeFullscreen {
    UIView *targetView = ([self respondsToSelector:@selector(pageView)] && self.pageView) ? self.pageView : self.subviews.firstObject;
    if (targetView) {
        targetView.layer.transform = CATransform3DIdentity;
        targetView.layer.cornerRadius = 0.0;
        targetView.layer.masksToBounds = NO;
        targetView.layer.borderWidth = 0.0;
        targetView.layer.shadowOpacity = 0.0;
        targetView.layer.mask = nil;
    }
    self.layer.zPosition = 0.0;
    self.layer.shadowOpacity = 0.0;
}

%new
- (void)_cs_applyClassicTransform {
    if (!kEnabled || CSUsesInfiniteCarouselOverlay() || !gIsInAppSwitcher) {
        [self _cs_resetToNativeFullscreen];
        return;
    }

    if ([self respondsToSelector:@selector(contentPageViewScale)] && self.contentPageViewScale >= 0.91) {
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
        case 4: { // Circle Wheel 3D
            angleY = -clampedT * (M_PI / 5.2) * kWheelCurvature;
            angleZ = clampedT * (M_PI / 18.0) * kWheelCurvature;
            transY = (absT * absT) * 44.0 * kWheelCurvature;
            transZ = -absT * 95.0 * kWheelCurvature;
            scale  = kCardScale * MAX(0.72, 1.0 - absT * 0.14);
            break;
        }
        case 5: { // 3D Cards
            angleY = -clampedT * (M_PI / 6.5) * kWheelCurvature;
            transZ = -absT * 60.0 * kWheelCurvature;
            scale  = kCardScale * MAX(0.78, 1.0 - absT * 0.09);
            break;
        }
        case 6: { // Card Deck
            angleY = -0.22 * kWheelCurvature;
            transZ = -absT * 110.0 * kWheelCurvature;
            transY = -absT * 14.0;
            scale  = kCardScale * MAX(0.74, 1.0 - absT * 0.11);
            break;
        }
        case 7: { // CoverFlow
            CGFloat sign = (clampedT > 0) ? 1.0 : ((clampedT < 0) ? -1.0 : 0.0);
            CGFloat flowFactor = MIN(1.0, absT * 1.4);
            angleY = -sign * flowFactor * (M_PI / 3.4) * kWheelCurvature;
            transZ = -flowFactor * 120.0 * kWheelCurvature;
            scale  = kCardScale * (1.0 - flowFactor * 0.14);
            break;
        }
        case 8: { // Inverse CoverFlow
            CGFloat sign = (clampedT > 0) ? 1.0 : ((clampedT < 0) ? -1.0 : 0.0);
            CGFloat flowFactor = MIN(1.0, absT * 1.4);
            angleY = sign * flowFactor * (M_PI / 3.4) * kWheelCurvature;
            transZ = -flowFactor * 120.0 * kWheelCurvature;
            scale  = kCardScale * (1.0 - flowFactor * 0.14);
            break;
        }
        case 9:
        default: { // 2D Flat
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
// Hook SBFluidSwitcherViewController — Strict Switcher Lifecycle & Overlay Host
// ============================================================================

%hook SBFluidSwitcherViewController

- (void)viewDidLoad {
    %orig;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_cs_refreshSwitcherUI)
                                                 name:@"CSInternalPreferencesDidUpdate"
                                               object:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig(animated);
    [self _cs_setSwitcherActive:NO];
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig(animated);
    [self _cs_setSwitcherActive:NO];
}

- (void)layoutStateTransitionCoordinator:(id)coordinator transitionDidBeginWithTransitionContext:(id)context {
    %orig(coordinator, context);
    @try {
        id toModeObj = [context valueForKeyPath:@"toLayoutState.unlockedEnvironmentMode"];
        if (toModeObj && [toModeObj respondsToSelector:@selector(integerValue)]) {
            NSInteger toMode = [toModeObj integerValue];
            [self _cs_setSwitcherActive:(toMode == 2)];
        }
    } @catch (NSException *e) {}
}

- (void)layoutStateTransitionCoordinator:(id)coordinator transitionDidEndWithTransitionContext:(id)context {
    %orig(coordinator, context);
    @try {
        id toModeObj = [context valueForKeyPath:@"toLayoutState.unlockedEnvironmentMode"];
        if (toModeObj && [toModeObj respondsToSelector:@selector(integerValue)]) {
            NSInteger toMode = [toModeObj integerValue];
            [self _cs_setSwitcherActive:(toMode == 2)];
        }
    } @catch (NSException *e) {}
}

- (void)viewDidLayoutSubviews {
    %orig;
    BOOL realVisible = CSIsSpringBoardMainSwitcherVisible();
    if (realVisible != gIsInAppSwitcher) {
        [self _cs_setSwitcherActive:realVisible];
    } else if (gIsInAppSwitcher) {
        CSInfiniteCarouselStageView *stage = objc_getAssociatedObject(self, kCSCarouselStageKey);
        if (stage && !stage.hidden) {
            stage.frame = self.view.bounds;
            [stage layoutCarousel3D];
        }
    }
}

%new
- (void)_cs_setSwitcherActive:(BOOL)active {
    BOOL wasActive = gIsInAppSwitcher;
    gIsInAppSwitcher = active;

    CSInfiniteCarouselStageView *stage = objc_getAssociatedObject(self, kCSCarouselStageKey);
    if (!stage && active && CSUsesInfiniteCarouselOverlay()) {
        stage = [[CSInfiniteCarouselStageView alloc] initWithFrame:self.view.bounds owner:self];
        [self.view addSubview:stage];
        objc_setAssociatedObject(self, kCSCarouselStageKey, stage, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (active && CSUsesInfiniteCarouselOverlay()) {
        // Capture fresh live snapshots BEFORE hiding native scrollView
        stage.frame = self.view.bounds;
        [self.view bringSubviewToFront:stage];
        [stage reloadAppsFromSwitcher];

        // Hide native switcher scrollViews cleanly while our 360° carousel is active
        for (UIView *sub in self.view.subviews) {
            if (sub == stage) continue;
            if ([sub isKindOfClass:[UIScrollView class]] || [NSStringFromClass([sub class]) containsString:@"Switcher"] || [NSStringFromClass([sub class]) containsString:@"Scroll"]) {
                sub.alpha = 0.0;
                sub.userInteractionEnabled = NO;
            }
        }

        stage.hidden = (stage.items.count == 0);
        stage.alpha = 1.0;
        if (!wasActive && !stage.hidden) {
            [stage triggerEntranceMotionBlur];
        }
    } else {
        // Leaving Switcher (Home Screen or Active App) OR using Classic Modes:
        // Hide Carousel immediately & restore native scrollViews 100%!
        if (stage) {
            [stage stopPhysics];
            stage.hidden = YES;
            stage.alpha = 0.0;
        }
        for (UIView *sub in self.view.subviews) {
            if (sub == stage) continue;
            if ([sub isKindOfClass:[UIScrollView class]] || [NSStringFromClass([sub class]) containsString:@"Switcher"] || [NSStringFromClass([sub class]) containsString:@"Scroll"]) {
                sub.alpha = 1.0;
                sub.userInteractionEnabled = YES;
            }
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
}

%new
- (void)_cs_refreshSwitcherUI {
    BOOL active = CSIsSpringBoardMainSwitcherVisible();
    [self _cs_setSwitcherActive:active];
}

%new
- (void)_cs_dismissSwitcherToHome {
    [self _cs_setSwitcherActive:NO];
    @try {
        NSArray<NSString *> *clsNames = @[@"SBMainSwitcherControllerCoordinator", @"SBMainSwitcherViewController"];
        for (NSString *clsName in clsNames) {
            Class cls = NSClassFromString(clsName);
            if (!cls || ![cls respondsToSelector:NSSelectorFromString(@"sharedInstance")]) continue;
            id inst = ((id (*)(id, SEL))objc_msgSend)(cls, NSSelectorFromString(@"sharedInstance"));
            if (!inst) continue;

            SEL toggleSel = NSSelectorFromString(@"toggleMainSwitcherNoninteractivelyWithSource:");
            if ([inst respondsToSelector:toggleSel]) {
                ((void (*)(id, SEL, NSInteger))objc_msgSend)(inst, toggleSel, 0);
                return;
            }
        }
        Class sbUI = NSClassFromString(@"SBUIController");
        if (sbUI && [sbUI respondsToSelector:NSSelectorFromString(@"sharedInstance")]) {
            id ui = ((id (*)(id, SEL))objc_msgSend)(sbUI, NSSelectorFromString(@"sharedInstance"));
            SEL homeSel = NSSelectorFromString(@"handleHomeButtonSinglePressUp");
            if (ui && [ui respondsToSelector:homeSel]) {
                ((void (*)(id, SEL))objc_msgSend)(ui, homeSel);
            }
        }
    } @catch (NSException *e) {}
}

%new
- (void)_cs_activateAppLayout:(id)appLayout bundleID:(NSString *)bundleID {
    // 1. Restore native SpringBoard views FIRST so fullscreen transition is 100% native!
    [self _cs_setSwitcherActive:NO];

    // 2. Activate app into 100% native fullscreen
    @try {
        if (bundleID.length > 0) {
            UIApplication *sbApp = [UIApplication sharedApplication];
            SEL launchSel = NSSelectorFromString(@"launchApplicationWithIdentifier:suspended:");
            if ([sbApp respondsToSelector:launchSel]) {
                ((void (*)(id, SEL, id, BOOL))objc_msgSend)(sbApp, launchSel, bundleID, NO);
                return;
            }
        }
    } @catch (NSException *e) {}

    [self _cs_dismissSwitcherToHome];
}

%new
- (void)_cs_killAppLayout:(id)appLayout bundleID:(NSString *)bundleID {
    if (!appLayout) return;
    @try {
        // 1. Try native container kill via delegate
        NSDictionary *vis = [self respondsToSelector:@selector(visibleItemContainers)] ? self.visibleItemContainers : nil;
        UIView *container = [vis isKindOfClass:[NSDictionary class]] ? vis[appLayout] : nil;
        if (container) {
            id del = [container valueForKey:@"_delegate"];
            SEL killContSel = NSSelectorFromString(@"killContainer:forReason:");
            if (del && [del respondsToSelector:killContSel]) {
                ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(del, killContSel, container, 0);
            }
        }

        // 2. Remove from SBRecentAppLayouts / SBMainSwitcherViewController so it stays closed
        NSArray<NSString *> *clsNames = @[@"SBMainSwitcherControllerCoordinator", @"SBMainSwitcherViewController"];
        for (NSString *clsName in clsNames) {
            Class cls = NSClassFromString(clsName);
            if (!cls || ![cls respondsToSelector:NSSelectorFromString(@"sharedInstance")]) continue;
            id inst = ((id (*)(id, SEL))objc_msgSend)(cls, NSSelectorFromString(@"sharedInstance"));
            if (!inst) continue;

            SEL delLayoutSel = NSSelectorFromString(@"_deleteAppLayout:forReason:");
            if ([inst respondsToSelector:delLayoutSel]) {
                ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(inst, delLayoutSel, appLayout, 0);
            }
            id recent = nil;
            @try { recent = [inst valueForKey:@"_recentAppLayouts"]; } @catch (NSException *ex) {}
            SEL remSel = NSSelectorFromString(@"remove:");
            if (recent && [recent respondsToSelector:remSel]) {
                ((void (*)(id, SEL, id))objc_msgSend)(recent, remSel, appLayout);
            }
        }
    } @catch (NSException *e) {}
}

%end

// ============================================================================
// Also Observe SBMainSwitcherViewController / Coordinator Transitions (iOS 14-16)
// ============================================================================

%hook SBMainSwitcherViewController

- (void)layoutStateTransitionCoordinator:(id)coordinator transitionDidBeginWithTransitionContext:(id)context {
    %orig(coordinator, context);
    @try {
        id toModeObj = [context valueForKeyPath:@"toLayoutState.unlockedEnvironmentMode"];
        if (toModeObj && [toModeObj respondsToSelector:@selector(integerValue)]) {
            gIsInAppSwitcher = ([toModeObj integerValue] == 2);
            [[NSNotificationCenter defaultCenter] postNotificationName:@"CSInternalPreferencesDidUpdate" object:nil];
        }
    } @catch (NSException *e) {}
}

- (void)layoutStateTransitionCoordinator:(id)coordinator transitionDidEndWithTransitionContext:(id)context {
    %orig(coordinator, context);
    @try {
        id toModeObj = [context valueForKeyPath:@"toLayoutState.unlockedEnvironmentMode"];
        if (toModeObj && [toModeObj respondsToSelector:@selector(integerValue)]) {
            gIsInAppSwitcher = ([toModeObj integerValue] == 2);
            [[NSNotificationCenter defaultCenter] postNotificationName:@"CSInternalPreferencesDidUpdate" object:nil];
        }
    } @catch (NSException *e) {}
}

%end


%hook SBMainSwitcherControllerCoordinator

- (void)layoutStateTransitionCoordinator:(id)coordinator transitionDidBeginWithTransitionContext:(id)context {
    %orig(coordinator, context);
    @try {
        id toModeObj = [context valueForKeyPath:@"toLayoutState.unlockedEnvironmentMode"];
        if (toModeObj && [toModeObj respondsToSelector:@selector(integerValue)]) {
            gIsInAppSwitcher = ([toModeObj integerValue] == 2);
            [[NSNotificationCenter defaultCenter] postNotificationName:@"CSInternalPreferencesDidUpdate" object:nil];
        }
    } @catch (NSException *e) {}
}

- (void)layoutStateTransitionCoordinator:(id)coordinator transitionDidEndWithTransitionContext:(id)context {
    %orig(coordinator, context);
    @try {
        id toModeObj = [context valueForKeyPath:@"toLayoutState.unlockedEnvironmentMode"];
        if (toModeObj && [toModeObj respondsToSelector:@selector(integerValue)]) {
            gIsInAppSwitcher = ([toModeObj integerValue] == 2);
            [[NSNotificationCenter defaultCenter] postNotificationName:@"CSInternalPreferencesDidUpdate" object:nil];
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
