#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>

// ============================================================================
// CircleSwitcher v3.0.1 — Native 3D Card Engine (Zero Overlay / Zero Freeze)
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
@property (nonatomic, strong) id appLayout;
- (void)_cs_applyNative3DTransform;
- (void)_cs_resetToNativeFullscreen;
@end

@interface SBFluidSwitcherViewController : UIViewController
@property (nonatomic, copy) NSArray *appLayouts;
@property (nonatomic, strong) NSDictionary *visibleItemContainers;
- (void)_cs_syncSwitcherVisualState:(BOOL)active;
- (void)_cs_killCenteredCard;
@end

@interface SBFloatingDockWindow : UIWindow
@end

@interface SBFloatingDockPlatterView : UIView
@end

@interface SBDockView : UIView
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

// Runtime State
static BOOL gSwitcherActive = NO;
static __weak SBFluidSwitcherViewController *gPrimarySwitcherVC = nil;
static __weak SBFluidSwitcherItemContainer *gCenteredContainer = nil;
static UIImpactFeedbackGenerator *kHapticGenerator = nil;

// Associated Object Keys
static const void *kCSGlassBevelKey = &kCSGlassBevelKey;
static const void *kCSCardBadgeKey  = &kCSCardBadgeKey;
static const void *kCSStageDecorKey = &kCSStageDecorKey;

// ============================================================================
// Color, Bundle & Icon Helpers
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

static void CSUpdateDockVisibility(BOOL switcherOpen) {
    BOOL hideDock = (kEnabled && switcherOpen);
    for (UIWindow *win in [UIApplication sharedApplication].windows) {
        NSString *clsName = NSStringFromClass([win class]);
        if ([clsName containsString:@"FloatingDock"]) {
            win.hidden = hideDock;
            win.alpha = hideDock ? 0.0 : 1.0;
        }
    }
}

static void CSRefreshVisibleSwitcherCards(void) {
    if (!gPrimarySwitcherVC) return;
    [gPrimarySwitcherVC _cs_syncSwitcherVisualState:gSwitcherActive];

    NSDictionary *containers = nil;
    @try {
        if ([gPrimarySwitcherVC respondsToSelector:@selector(visibleItemContainers)]) {
            containers = gPrimarySwitcherVC.visibleItemContainers;
        }
    } @catch (NSException *e) {}

    if ([containers isKindOfClass:[NSDictionary class]]) {
        for (id key in containers) {
            UIView *c = containers[key];
            if ([c isKindOfClass:objc_getClass("SBFluidSwitcherItemContainer")]) {
                if (gSwitcherActive && kEnabled) {
                    [(SBFluidSwitcherItemContainer *)c _cs_applyNative3DTransform];
                } else {
                    [(SBFluidSwitcherItemContainer *)c _cs_resetToNativeFullscreen];
                }
            }
        }
    }
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
        CSUpdateDockVisibility(gSwitcherActive);
        CSRefreshVisibleSwitcherCards();
    });
}

// ============================================================================
// Edge-to-Edge Vector Liquid Glass Bevel Overlay (Zero Black Crescents)
// ============================================================================

@interface CSNativeGlassBevelView : UIView
@property (nonatomic, strong) UIView *dimBackdrop;
@property (nonatomic, strong) CAGradientLayer *refractionTintLayer;
@property (nonatomic, strong) CAGradientLayer *specularDispersionLayer;
@property (nonatomic, strong) CAShapeLayer *innerBevelStroke;
@property (nonatomic, strong) UIImageView *circularRimImageView;
- (void)updateWithGlowColor:(UIColor *)glowCol
               cornerRadius:(CGFloat)cornerR
                 isCircular:(BOOL)isCircular
                frontWeight:(CGFloat)frontWeight
                 normalizedT:(CGFloat)t
                   dimAlpha:(CGFloat)dimAlpha;
@end

@implementation CSNativeGlassBevelView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor clearColor];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        self.dimBackdrop = [[UIView alloc] initWithFrame:self.bounds];
        self.dimBackdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.dimBackdrop.backgroundColor = [UIColor blackColor];
        self.dimBackdrop.alpha = 0.0;
        [self addSubview:self.dimBackdrop];

        self.refractionTintLayer = [CAGradientLayer layer];
        self.refractionTintLayer.frame = self.bounds;
        self.refractionTintLayer.startPoint = CGPointMake(0.0, 0.0);
        self.refractionTintLayer.endPoint = CGPointMake(1.0, 1.0);
        [self.layer addSublayer:self.refractionTintLayer];

        self.specularDispersionLayer = [CAGradientLayer layer];
        self.specularDispersionLayer.frame = self.bounds;
        self.specularDispersionLayer.startPoint = CGPointMake(0.0, 0.0);
        self.specularDispersionLayer.endPoint = CGPointMake(1.0, 1.0);
        [self.layer addSublayer:self.specularDispersionLayer];

        self.circularRimImageView = [[UIImageView alloc] initWithFrame:self.bounds];
        self.circularRimImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.circularRimImageView.contentMode = UIViewContentModeScaleToFill;
        self.circularRimImageView.image = CSLoadAsset(@"glass_rim", NO);
        self.circularRimImageView.alpha = 0.0;
        [self addSubview:self.circularRimImageView];

        self.innerBevelStroke = [CAShapeLayer layer];
        self.innerBevelStroke.fillColor = [UIColor clearColor].CGColor;
        self.innerBevelStroke.lineWidth = 1.3;
        [self.layer addSublayer:self.innerBevelStroke];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.refractionTintLayer.frame = self.bounds;
    self.specularDispersionLayer.frame = self.bounds;
    self.innerBevelStroke.frame = self.bounds;
}

- (void)updateWithGlowColor:(UIColor *)glowCol
               cornerRadius:(CGFloat)cornerR
                 isCircular:(BOOL)isCircular
                frontWeight:(CGFloat)frontWeight
                 normalizedT:(CGFloat)t
                   dimAlpha:(CGFloat)dimAlpha {
    CGRect b = self.bounds;
    if (b.size.width < 4 || b.size.height < 4) return;

    self.dimBackdrop.alpha = dimAlpha;

    if (!kLiquidGlass || kGlowIntensity <= 0.01) {
        self.refractionTintLayer.opacity = 0.0;
        self.specularDispersionLayer.opacity = 0.0;
        self.innerBevelStroke.opacity = 0.0;
        self.circularRimImageView.alpha = 0.0;
        return;
    }

    // Full-bleed edge-to-edge Liquid Glass tint filling 100% of card frame
    CGFloat topTint = MIN(0.36, (0.08 + kGlassRefract * 0.20) * MAX(0.35, kGlowIntensity));
    CGFloat midTint = MIN(0.14, (0.02 + kGlassRefract * 0.08) * MAX(0.35, kGlowIntensity));
    CGFloat botTint = MIN(0.32, (0.06 + kGlassRefract * 0.18) * MAX(0.35, kGlowIntensity));
    self.refractionTintLayer.opacity = 1.0;
    self.refractionTintLayer.colors = @[
        (id)[glowCol colorWithAlphaComponent:topTint].CGColor,
        (id)[glowCol colorWithAlphaComponent:midTint].CGColor,
        (id)[glowCol colorWithAlphaComponent:botTint].CGColor
    ];
    self.refractionTintLayer.locations = @[@0.0, @0.5, @1.0];

    // Specular sheen + chromatic dispersion
    CGFloat specAlpha = MIN(0.48, (0.12 + (kGlassSpecular / 1.5) * 0.28) * (0.6 + 0.4 * frontWeight));
    CGFloat dispMix = MIN(0.32, kGlassDispersion * 0.28);
    UIColor *coolSpec = [UIColor colorWithRed:0.84 green:0.97 blue:1.0 alpha:specAlpha * (0.55 + dispMix)];
    UIColor *warmSpec = [UIColor colorWithRed:1.0 green:0.88 blue:0.96 alpha:specAlpha * (0.55 + dispMix)];

    CGFloat shift = MAX(-0.25, MIN(0.25, t * 0.22));
    self.specularDispersionLayer.opacity = 1.0;
    self.specularDispersionLayer.startPoint = CGPointMake(MAX(0.0, 0.12 + shift), 0.0);
    self.specularDispersionLayer.endPoint = CGPointMake(MIN(1.0, 0.88 + shift), 1.0);
    self.specularDispersionLayer.colors = @[
        (id)[[UIColor whiteColor] colorWithAlphaComponent:specAlpha].CGColor,
        (id)coolSpec.CGColor,
        (id)[UIColor clearColor].CGColor,
        (id)warmSpec.CGColor
    ];
    self.specularDispersionLayer.locations = @[@0.0, @0.22, @0.58, @1.0];

    // Exact vector inner bevel stroke (never stretches circular image onto rectangle!)
    CGRect insetRect = CGRectInset(b, 1.2, 1.2);
    CGFloat innerR = MAX(0.0, cornerR - 1.2);
    UIBezierPath *path = isCircular
        ? [UIBezierPath bezierPathWithOvalInRect:insetRect]
        : [UIBezierPath bezierPathWithRoundedRect:insetRect cornerRadius:innerR];
    self.innerBevelStroke.path = path.CGPath;
    self.innerBevelStroke.opacity = 1.0;
    self.innerBevelStroke.strokeColor = [[UIColor whiteColor] colorWithAlphaComponent:MIN(0.60, 0.20 + (kGlassSpecular / 1.5) * 0.32)].CGColor;

    // Only show circular glass_rim texture when card is circular
    if (isCircular && self.circularRimImageView.image) {
        self.circularRimImageView.alpha = MIN(0.80, 0.22 + kGlowIntensity * 0.42);
    } else {
        self.circularRimImageView.alpha = 0.0;
    }
}

@end

// ============================================================================
// Upright Sibling App Icon & Title Badge (Never Tilted by 3D Card Rotation!)
// ============================================================================

@interface CSNativeCardBadgeView : UIView
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, copy) NSString *cachedBundleID;
- (void)configureForBundleID:(NSString *)bundleID;
@end

@implementation CSNativeCardBadgeView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor clearColor];

        self.iconView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 64, 64)];
        self.iconView.contentMode = UIViewContentModeScaleAspectFill;
        self.iconView.layer.cornerRadius = 15.0;
        self.iconView.layer.masksToBounds = YES;
        self.iconView.layer.shadowColor = [UIColor blackColor].CGColor;
        self.iconView.layer.shadowOpacity = 0.55;
        self.iconView.layer.shadowRadius = 8.0;
        self.iconView.layer.shadowOffset = CGSizeMake(0, 4);
        [self addSubview:self.iconView];

        self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        self.titleLabel.font = [UIFont systemFontOfSize:15.5 weight:UIFontWeightBold];
        self.titleLabel.textColor = [UIColor whiteColor];
        self.titleLabel.textAlignment = NSTextAlignmentCenter;
        self.titleLabel.numberOfLines = 1;
        self.titleLabel.adjustsFontSizeToFitWidth = YES;
        self.titleLabel.minimumScaleFactor = 0.72;
        self.titleLabel.layer.shadowColor = [UIColor blackColor].CGColor;
        self.titleLabel.layer.shadowOpacity = 0.90;
        self.titleLabel.layer.shadowRadius = 4.0;
        self.titleLabel.layer.shadowOffset = CGSizeMake(0, 1.5);
        [self addSubview:self.titleLabel];
    }
    return self;
}

- (void)configureForBundleID:(NSString *)bundleID {
    if (!bundleID || bundleID.length == 0) return;
    if ([self.cachedBundleID isEqualToString:bundleID] && self.iconView.image != nil) return;
    self.cachedBundleID = bundleID;
    self.iconView.image = CSAppIconForBundleID(bundleID);
    self.titleLabel.text = CSAppDisplayNameForBundleID(bundleID);
}

@end

// ============================================================================
// Non-Blocking 3D Hologram Base & Quick Close (✕) Stage Decor View
// Passes 100% of card touches directly through to native iOS 16 Switcher!
// ============================================================================

@interface CSNativeStageDecorView : UIView
@property (nonatomic, weak) SBFluidSwitcherViewController *ownerVC;
@property (nonatomic, strong) UIImageView *ambientBackdrop;
@property (nonatomic, strong) UIView *hologramPlatform;
@property (nonatomic, strong) UIImageView *outerHalo;
@property (nonatomic, strong) UIImageView *innerHalo;
@property (nonatomic, strong) UIView *topHeaderPill;
@property (nonatomic, strong) UIImageView *topHeaderIcon;
@property (nonatomic, strong) UILabel *topHeaderLabel;
@property (nonatomic, strong) UIButton *closeButton;
- (void)updateStylingAndCenteredApp:(NSString *)centeredBundleID;
@end

@implementation CSNativeStageDecorView

- (instancetype)initWithFrame:(CGRect)frame owner:(SBFluidSwitcherViewController *)owner {
    self = [super initWithFrame:frame];
    if (self) {
        self.ownerVC = owner;
        self.backgroundColor = [UIColor clearColor];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        self.ambientBackdrop = [[UIImageView alloc] initWithFrame:self.bounds];
        self.ambientBackdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.ambientBackdrop.image = CSLoadAsset(@"ambient_backdrop", YES);
        self.ambientBackdrop.contentMode = UIViewContentModeScaleAspectFill;
        self.ambientBackdrop.userInteractionEnabled = NO;
        [self addSubview:self.ambientBackdrop];

        self.hologramPlatform = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 320)];
        self.hologramPlatform.userInteractionEnabled = NO;
        [self addSubview:self.hologramPlatform];

        UIImage *haloImg = CSLoadAsset(@"orb_halo", YES);
        self.outerHalo = [[UIImageView alloc] initWithFrame:self.hologramPlatform.bounds];
        self.outerHalo.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.outerHalo.image = haloImg;
        [self.hologramPlatform addSubview:self.outerHalo];

        self.innerHalo = [[UIImageView alloc] initWithFrame:CGRectInset(self.hologramPlatform.bounds, 46, 46)];
        self.innerHalo.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.innerHalo.image = haloImg;
        [self.hologramPlatform addSubview:self.innerHalo];

        self.topHeaderPill = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 194, 42)];
        self.topHeaderPill.backgroundColor = [UIColor colorWithWhite:0.10 alpha:0.84];
        self.topHeaderPill.layer.cornerRadius = 21.0;
        self.topHeaderPill.layer.borderWidth = 1.0;
        self.topHeaderPill.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.24].CGColor;
        self.topHeaderPill.userInteractionEnabled = NO;
        self.topHeaderPill.hidden = YES;
        [self addSubview:self.topHeaderPill];

        self.topHeaderIcon = [[UIImageView alloc] initWithFrame:CGRectMake(8, 7, 28, 28)];
        self.topHeaderIcon.layer.cornerRadius = 7.0;
        self.topHeaderIcon.layer.masksToBounds = YES;
        [self.topHeaderPill addSubview:self.topHeaderIcon];

        self.topHeaderLabel = [[UILabel alloc] initWithFrame:CGRectMake(42, 6, 142, 30)];
        self.topHeaderLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightBold];
        self.topHeaderLabel.textColor = [UIColor whiteColor];
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
        [self.closeButton addTarget:self action:@selector(handleCloseTap) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.closeButton];
    }
    return self;
}

// ONLY capture touches inside the (✕) button; let ALL other touches pass to native Switcher!
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || self.alpha < 0.05) return nil;
    if (!self.closeButton.hidden && self.closeButton.alpha > 0.1) {
        CGRect hitZone = CGRectInset(self.closeButton.frame, -14.0, -14.0);
        if (CGRectContainsPoint(hitZone, point)) {
            return self.closeButton;
        }
    }
    return nil;
}

- (void)handleCloseTap {
    if (self.ownerVC) {
        [self.ownerVC _cs_killCenteredCard];
    }
}

- (void)updateStylingAndCenteredApp:(NSString *)centeredBundleID {
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    if (w < 10 || h < 10) return;

    UIColor *glowCol = CSActiveGlowColor(1.0);
    UIColor *baseCol = CSActiveBaseColor(1.0);

    self.ambientBackdrop.hidden = !kBackdropEnabled;
    self.ambientBackdrop.tintColor = [glowCol colorWithAlphaComponent:0.22 * MAX(0.25, kGlowIntensity)];

    BOOL showBase = kHologramBaseEnabled && (kLayoutMode == 0 || kLayoutMode == 1 || kLayoutMode == 2);
    self.hologramPlatform.hidden = !showBase;
    if (showBase) {
        CGFloat ringDim = MIN(w, h) * 0.86 * kBaseScale;
        self.hologramPlatform.layer.transform = CATransform3DIdentity;
        self.hologramPlatform.bounds = CGRectMake(0, 0, ringDim, ringDim);
        self.hologramPlatform.center = CGPointMake(w * 0.5, h * 0.74);

        self.outerHalo.tintColor = baseCol;
        self.innerHalo.tintColor = baseCol;
        self.outerHalo.alpha = 0.92;
        self.innerHalo.alpha = 0.76;
        self.hologramPlatform.alpha = MIN(1.0, kBaseIntensity * 1.15);

        CATransform3D baseTx = CATransform3DIdentity;
        baseTx.m34 = -1.0 / 520.0;
        baseTx = CATransform3DRotate(baseTx, 1.24, 1.0, 0.0, 0.0);
        self.hologramPlatform.layer.transform = baseTx;
        self.hologramPlatform.layer.shadowColor = baseCol.CGColor;
        self.hologramPlatform.layer.shadowOpacity = (float)(kBaseIntensity * 0.85);
        self.hologramPlatform.layer.shadowRadius = 24.0;
        self.hologramPlatform.layer.shadowOffset = CGSizeMake(0, -6);
    }

    if (kTitlePosition == 0 && centeredBundleID.length > 0) {
        self.topHeaderPill.hidden = NO;
        self.topHeaderIcon.image = CSAppIconForBundleID(centeredBundleID);
        self.topHeaderLabel.text = CSAppDisplayNameForBundleID(centeredBundleID);
        self.topHeaderPill.center = CGPointMake(w * 0.5, 86.0);
    } else {
        self.topHeaderPill.hidden = YES;
    }

    self.closeButton.hidden = !kShowCloseButton;
    if (kShowCloseButton) {
        self.closeButton.center = CGPointMake(w * 0.5, h * 0.75);
    }
}

@end

// ============================================================================
// Hide Floating Dock & Bottom Horizontal Bar While Switcher Is Active
// ============================================================================

%hook SBFloatingDockWindow

- (void)setHidden:(BOOL)hidden {
    if (kEnabled && gSwitcherActive) {
        %orig(YES);
        return;
    }
    %orig(hidden);
}

- (void)setAlpha:(CGFloat)alpha {
    if (kEnabled && gSwitcherActive) {
        %orig(0.0);
        return;
    }
    %orig(alpha);
}

%end

%hook SBFloatingDockPlatterView

- (void)layoutSubviews {
    %orig;
    if (kEnabled && gSwitcherActive) {
        self.alpha = 0.0;
        self.hidden = YES;
    } else if (self.hidden) {
        self.hidden = NO;
        self.alpha = 1.0;
    }
}

%end

%hook SBDockView

- (void)layoutSubviews {
    %orig;
    if (kEnabled && gSwitcherActive) {
        self.alpha = 0.0;
    } else if (self.alpha < 1.0) {
        self.alpha = 1.0;
    }
}

%end

// ============================================================================
// Hide Default System Card Header Bar
// ============================================================================

%hook SBFluidSwitcherItemContainerHeaderView

- (void)setAlpha:(CGFloat)alpha {
    if (kEnabled && gSwitcherActive) {
        %orig(0.0);
        return;
    }
    %orig(alpha);
}

%end

// ============================================================================
// Hook SBAppSwitcherPageView — Clean Native Fullscreen Restoration
// ============================================================================

%hook SBAppSwitcherPageView

- (void)layoutSubviews {
    %orig;

    if (!kEnabled || !gSwitcherActive) {
        if (self.layer.cornerRadius != 0.0 || self.layer.borderWidth != 0.0) {
            self.layer.cornerRadius = 0.0;
            self.layer.masksToBounds = NO;
            self.layer.borderWidth = 0.0;
            self.layer.shadowOpacity = 0.0;
        }
        CSNativeGlassBevelView *bevel = objc_getAssociatedObject(self, kCSGlassBevelKey);
        if (bevel && !bevel.hidden) {
            bevel.hidden = YES;
        }
    }
}

- (void)_updateCornerRadius {
    %orig;
    if (!kEnabled || !gSwitcherActive) {
        if (self.layer.cornerRadius != 0.0 || self.layer.borderWidth != 0.0) {
            self.layer.cornerRadius = 0.0;
            self.layer.masksToBounds = NO;
            self.layer.borderWidth = 0.0;
        }
    }
}

%end

// ============================================================================
// Hook SBFluidSwitcherItemContainer — Direct 3D Card Transform + Upright Badge
// ============================================================================

%hook SBFluidSwitcherItemContainer

- (void)layoutSubviews {
    %orig;
    [self _cs_applyNative3DTransform];
}

- (void)setCenter:(CGPoint)center {
    %orig;
    [self _cs_applyNative3DTransform];
}

- (void)setContentPageViewScale:(CGFloat)scale {
    %orig(scale);
    [self _cs_applyNative3DTransform];
}

%new
- (void)_cs_resetToNativeFullscreen {
    if (self.alpha < 1.0) self.alpha = 1.0;
    if (self.layer.zPosition != 0.0) self.layer.zPosition = 0.0;
    if (self.layer.shadowOpacity != 0.0) self.layer.shadowOpacity = 0.0;

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
        }
        CSNativeGlassBevelView *bevel = objc_getAssociatedObject(targetView, kCSGlassBevelKey);
        if (bevel && !bevel.hidden) {
            bevel.hidden = YES;
        }
    }

    CSNativeCardBadgeView *badge = objc_getAssociatedObject(self, kCSCardBadgeKey);
    if (badge && !badge.hidden) {
        badge.hidden = YES;
    }
}

%new
- (void)_cs_applyNative3DTransform {
    if (!kEnabled || !gSwitcherActive) {
        [self _cs_resetToNativeFullscreen];
        return;
    }

    // As soon as card expands toward fullscreen (>0.92), immediately restore native view!
    if ([self respondsToSelector:@selector(contentPageViewScale)] && self.contentPageViewScale >= 0.92) {
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
    CGFloat t = (deltaX / (screenW * 0.56)) / MAX(0.55, kCardSpacing);
    CGFloat clampedT = MAX(-1.85, MIN(1.85, t));
    CGFloat absT = fabs(clampedT);
    CGFloat frontWeight = MAX(0.0, 1.0 - MIN(1.0, absT));

    // Track centered container & trigger subtle center haptic
    if (absT < 0.14 && gCenteredContainer != self) {
        gCenteredContainer = self;
        if (kHapticFeedback) {
            if (!kHapticGenerator) {
                kHapticGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
            }
            [kHapticGenerator impactOccurred];
        }
        if (gPrimarySwitcherVC) {
            CSNativeStageDecorView *decor = objc_getAssociatedObject(gPrimarySwitcherVC, kCSStageDecorKey);
            id layout = [self respondsToSelector:@selector(appLayout)] ? self.appLayout : nil;
            [decor updateStylingAndCenteredApp:CSBundleIDFromAppLayout(layout)];
        }
    }

    self.layer.zPosition = 500.0 - (absT * 240.0);

    // Determine shape: circular orb vs rounded card
    BOOL isCircularMode = (kLayoutMode == 1 || kLayoutMode == 2 || kLayoutMode == 3) || kCircleMorph;
    CGFloat cardW = targetView.bounds.size.width;
    CGFloat cardH = targetView.bounds.size.height;
    CGFloat minSide = MIN(cardW, cardH);

    // Compute 3D geometry per mode
    CATransform3D transform = CATransform3DIdentity;
    transform.m34 = -1.0 / (920.0 / MAX(0.35, kWheelCurvature));

    CGFloat scale = kCardScale;
    CGFloat angleY = 0.0;
    CGFloat angleZ = 0.0;
    CGFloat transY = 0.0;
    CGFloat transZ = 0.0;

    switch (kLayoutMode) {
        case 0: { // 3D Hologram Cylinder (Cards)
            angleY = -clampedT * (M_PI / 4.8) * kWheelCurvature;
            transY = -(absT * absT) * 14.0 * kWheelCurvature;
            transZ = -absT * 95.0 * kWheelCurvature;
            scale  = kCardScale * (kScaleIcons ? MAX(0.68, 1.0 - absT * 0.18) : MAX(0.88, 1.0 - absT * 0.06));
            break;
        }
        case 1: { // 3D Cylindrical Orbs (Standing)
            angleY = -clampedT * (M_PI / 5.2) * kWheelCurvature;
            transZ = -absT * 85.0 * kWheelCurvature;
            scale  = kOrbSize * (kScaleIcons ? MAX(0.70, 1.0 - absT * 0.16) : 1.0);
            break;
        }
        case 2: { // Orbital Preview & Circular Orbs (Big front orb, compact non-overlapping side orbs)
            CGFloat focus = pow(frontWeight, 2.4);
            CGFloat bigScale = kCardScale * 0.96;
            CGFloat smallScale = kOrbSize * 0.56;
            scale = smallScale + (bigScale - smallScale) * focus;
            angleY = -clampedT * (M_PI / 7.5) * kWheelCurvature;
            transY = (1.0 - focus) * 26.0;
            transZ = -(1.0 - focus) * 110.0 * kWheelCurvature;
            break;
        }
        case 3: { // Radial 360° Icon Ring
            scale = kOrbSize * (kScaleIcons ? MAX(0.72, 1.0 - absT * 0.15) : 1.0);
            transY = -(absT * absT) * 56.0 * kWheelCurvature;
            transZ = -absT * 60.0;
            break;
        }
        case 4: { // Circle Wheel 3D (Arc)
            angleY = -clampedT * (M_PI / 5.2) * kWheelCurvature;
            angleZ = clampedT * (M_PI / 18.0) * kWheelCurvature;
            transY = (absT * absT) * 44.0 * kWheelCurvature;
            transZ = -absT * 95.0 * kWheelCurvature;
            scale  = kCardScale * (kScaleIcons ? MAX(0.72, 1.0 - absT * 0.14) : 1.0);
            break;
        }
        case 5: { // 3D Cards
            angleY = -clampedT * (M_PI / 6.5) * kWheelCurvature;
            transZ = -absT * 60.0 * kWheelCurvature;
            scale  = kCardScale * (kScaleIcons ? MAX(0.78, 1.0 - absT * 0.09) : 1.0);
            break;
        }
        case 6: { // Card Deck
            angleY = -0.22 * kWheelCurvature;
            transZ = -absT * 110.0 * kWheelCurvature;
            transY = -absT * 14.0;
            scale  = kCardScale * (kScaleIcons ? MAX(0.74, 1.0 - absT * 0.11) : 1.0);
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
        default: {
            scale = kCardScale;
            break;
        }
    }

    if (kRollIcons) {
        angleZ += clampedT * 0.22;
    }

    self.alpha = kFadeIcons ? MAX(0.42, 0.46 + 0.54 * frontWeight) : 1.0;

    // Corner radius & outer glowing rim flush with card edge
    CGFloat cornerR = isCircularMode ? (minSide * 0.5) : MAX(18.0, kCircleRadius);
    targetView.layer.cornerRadius = cornerR;
    targetView.layer.masksToBounds = YES;
    if (@available(iOS 13.0, *)) {
        targetView.layer.cornerCurve = isCircularMode ? kCACornerCurveCircular : kCACornerCurveContinuous;
    }

    UIColor *glowCol = CSActiveGlowColor(1.0);
    if (kLiquidGlass && kGlowIntensity > 0.01) {
        CGFloat rimAlpha = MIN(0.98, (0.50 + kGlowIntensity * 0.48) * (0.65 + 0.35 * frontWeight));
        targetView.layer.borderWidth = 2.0 + kGlowIntensity * 1.1;
        targetView.layer.borderColor = [glowCol colorWithAlphaComponent:rimAlpha].CGColor;
    } else {
        targetView.layer.borderWidth = 0.0;
    }

    // Apply 3D transform to card pageView
    transform = CATransform3DTranslate(transform, 0.0, transY, transZ);
    if (fabs(angleY) > 0.0001) {
        transform = CATransform3DRotate(transform, angleY, 0.0, 1.0, 0.0);
    }
    if (fabs(angleZ) > 0.0001) {
        transform = CATransform3DRotate(transform, angleZ, 0.0, 0.0, 1.0);
    }
    transform = CATransform3DScale(transform, scale, scale, 1.0);
    targetView.layer.transform = transform;

    // Edge-to-edge Liquid Glass bevel inside targetView
    CSNativeGlassBevelView *bevel = objc_getAssociatedObject(targetView, kCSGlassBevelKey);
    if (!bevel) {
        bevel = [[CSNativeGlassBevelView alloc] initWithFrame:targetView.bounds];
        [targetView addSubview:bevel];
        objc_setAssociatedObject(targetView, kCSGlassBevelKey, bevel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    bevel.frame = targetView.bounds;
    bevel.hidden = NO;
    [targetView bringSubviewToFront:bevel];

    CGFloat dimAlpha = (kTitlePosition == 1) ? kCenterDimAlpha : ((kTitlePosition == 2) ? 0.16 : 0.0);
    [bevel updateWithGlowColor:glowCol
                  cornerRadius:cornerR
                    isCircular:isCircularMode
                   frontWeight:frontWeight
                    normalizedT:clampedT
                      dimAlpha:dimAlpha];

    // Upright Sibling Badge (Icon + Title NEVER skewed by angleY!)
    CSNativeCardBadgeView *badge = objc_getAssociatedObject(self, kCSCardBadgeKey);
    if (!badge) {
        badge = [[CSNativeCardBadgeView alloc] initWithFrame:self.bounds];
        [self addSubview:badge];
        objc_setAssociatedObject(self, kCSCardBadgeKey, badge, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    id layout = [self respondsToSelector:@selector(appLayout)] ? self.appLayout : nil;
    NSString *bid = CSBundleIDFromAppLayout(layout);
    [badge configureForBundleID:bid];

    badge.hidden = NO;
    [self bringSubviewToFront:badge];
    badge.bounds = CGRectMake(0, 0, cardW, cardH);
    badge.center = targetView.center;

    // Scale & translate badge to match card center, WITHOUT angleY 3D perspective skew!
    CATransform3D badgeTx = CATransform3DIdentity;
    badgeTx = CATransform3DTranslate(badgeTx, 0.0, transY, 0.0);
    badgeTx = CATransform3DScale(badgeTx, scale, scale, 1.0);
    badge.layer.transform = badgeTx;

    CGFloat iconSide = isCircularMode ? MIN(96.0, minSide * 0.34) : 74.0;
    badge.iconView.bounds = CGRectMake(0, 0, iconSide, iconSide);
    badge.iconView.layer.cornerRadius = iconSide * 0.23;

    if (kTitlePosition == 1) {
        badge.iconView.center = CGPointMake(cardW * 0.5, cardH * 0.45);
        badge.titleLabel.hidden = NO;
        badge.titleLabel.bounds = CGRectMake(0, 0, cardW * 0.84, 24.0);
        badge.titleLabel.center = CGPointMake(cardW * 0.5, cardH * 0.45 + iconSide * 0.5 + 18.0);
    } else if (kTitlePosition == 2) {
        badge.iconView.center = CGPointMake(cardW * 0.5, cardH * 0.50);
        badge.titleLabel.hidden = NO;
        badge.titleLabel.bounds = CGRectMake(0, 0, cardW * 0.84, 24.0);
        badge.titleLabel.center = CGPointMake(cardW * 0.5, cardH * 0.84);
    } else {
        badge.iconView.center = CGPointMake(cardW * 0.5, cardH * 0.50);
        badge.titleLabel.hidden = YES;
    }
}

%end

// ============================================================================
// Hook SBFluidSwitcherViewController — Non-Blocking Stage Decor & Single Kill
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
            BOOL open = (toMode == 2);
            gSwitcherActive = open;
            CSUpdateDockVisibility(open);
            [self _cs_syncSwitcherVisualState:open];
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
            BOOL open = (toMode == 2);
            gSwitcherActive = open;
            CSUpdateDockVisibility(open);
            [self _cs_syncSwitcherVisualState:open];
            CSRefreshVisibleSwitcherCards();
        }
    } @catch (NSException *e) {}
}

%new
- (void)_cs_syncSwitcherVisualState:(BOOL)active {
    CSNativeStageDecorView *decor = objc_getAssociatedObject(self, kCSStageDecorKey);

    if (kEnabled && active) {
        if (!decor) {
            decor = [[CSNativeStageDecorView alloc] initWithFrame:self.view.bounds owner:self];
            [self.view insertSubview:decor atIndex:0];
            objc_setAssociatedObject(self, kCSStageDecorKey, decor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        decor.frame = self.view.bounds;
        decor.hidden = NO;
        decor.alpha = 1.0;

        // Keep decor BEHIND native card scrollView so cards receive 100% of touches,
        // while closeButton sits on top via hitTest!
        [self.view sendSubviewToBack:decor];
        decor.layer.zPosition = 900.0;

        id centeredLayout = (gCenteredContainer && [gCenteredContainer respondsToSelector:@selector(appLayout)]) ? gCenteredContainer.appLayout : nil;
        [decor updateStylingAndCenteredApp:CSBundleIDFromAppLayout(centeredLayout)];
    } else if (decor) {
        decor.hidden = YES;
        decor.alpha = 0.0;
    }
}

%new
- (void)_cs_killCenteredCard {
    SBFluidSwitcherItemContainer *target = gCenteredContainer;
    if (!target) {
        NSDictionary *containers = [self respondsToSelector:@selector(visibleItemContainers)] ? self.visibleItemContainers : nil;
        CGFloat screenCenterX = self.view.bounds.size.width * 0.5;
        CGFloat minDist = 9999.0;
        for (id key in containers) {
            UIView *c = containers[key];
            if (![c isKindOfClass:objc_getClass("SBFluidSwitcherItemContainer")]) continue;
            CGPoint pt = [c.superview convertPoint:c.center toView:self.view];
            CGFloat dist = fabs(pt.x - screenCenterX);
            if (dist < minDist) {
                minDist = dist;
                target = (SBFluidSwitcherItemContainer *)c;
            }
        }
    }
    if (!target) return;

    if (kHapticFeedback) {
        if (!kHapticGenerator) {
            kHapticGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        }
        [kHapticGenerator impactOccurred];
    }

    id layout = [target respondsToSelector:@selector(appLayout)] ? target.appLayout : nil;
    NSString *bid = CSBundleIDFromAppLayout(layout);

    // Native single-card kill selector on SBFluidSwitcherViewController
    SEL killContainerSel = NSSelectorFromString(@"killContainer:forReason:");
    if ([self respondsToSelector:killContainerSel]) {
        ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(self, killContainerSel, target, 1);
        return;
    }

    SEL deleteLayoutSel = NSSelectorFromString(@"_deleteAppLayout:forReason:");
    if (layout && [self respondsToSelector:deleteLayoutSel]) {
        ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(self, deleteLayoutSel, layout, 1);
        return;
    }

    if (layout) {
        for (NSString *clsName in @[@"SBMainSwitcherControllerCoordinator", @"SBMainSwitcherViewController"]) {
            Class cls = NSClassFromString(clsName);
            if (!cls || ![cls respondsToSelector:NSSelectorFromString(@"sharedInstance")]) continue;
            id inst = ((id (*)(id, SEL))objc_msgSend)(cls, NSSelectorFromString(@"sharedInstance"));
            if (inst && [inst respondsToSelector:killContainerSel]) {
                ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(inst, killContainerSel, target, 1);
                break;
            }
        }
    }

    if (bid.length > 0) {
        Class fbSvcCls = NSClassFromString(@"FBSSystemService");
        if (fbSvcCls && [fbSvcCls respondsToSelector:NSSelectorFromString(@"sharedService")]) {
            id svc = ((id (*)(id, SEL))objc_msgSend)(fbSvcCls, NSSelectorFromString(@"sharedService"));
            SEL termSel = NSSelectorFromString(@"terminateApplication:forReason:andReport:withDescription:");
            if (svc && [svc respondsToSelector:termSel]) {
                ((void (*)(id, SEL, id, NSInteger, BOOL, id))objc_msgSend)(svc, termSel, bid, 1, NO, @"CircleSwitcher Close");
            }
        }
    }
}

%end

// ============================================================================
// Coordinator Backup Hooks
// ============================================================================

%hook SBMainSwitcherControllerCoordinator

- (void)layoutStateTransitionCoordinator:(id)coordinator transitionDidBeginWithTransitionContext:(id)context {
    %orig(coordinator, context);
    @try {
        id toModeObj = [context valueForKeyPath:@"toLayoutState.unlockedEnvironmentMode"];
        if (toModeObj && [toModeObj respondsToSelector:@selector(integerValue)]) {
            gSwitcherActive = ([toModeObj integerValue] == 2);
            CSUpdateDockVisibility(gSwitcherActive);
            if (gPrimarySwitcherVC) [gPrimarySwitcherVC _cs_syncSwitcherVisualState:gSwitcherActive];
        }
    } @catch (NSException *e) {}
}

- (void)layoutStateTransitionCoordinator:(id)coordinator transitionDidEndWithTransitionContext:(id)context {
    %orig(coordinator, context);
    @try {
        id toModeObj = [context valueForKeyPath:@"toLayoutState.unlockedEnvironmentMode"];
        if (toModeObj && [toModeObj respondsToSelector:@selector(integerValue)]) {
            gSwitcherActive = ([toModeObj integerValue] == 2);
            CSUpdateDockVisibility(gSwitcherActive);
            CSRefreshVisibleSwitcherCards();
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
