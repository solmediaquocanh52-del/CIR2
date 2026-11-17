#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>

// ============================================================================
// CircleSwitcher v2.0.0 — Complete 3D Hologram Cylinder, Orbital Orbs & Liquid Glass Engine
// Supports iOS 14.0 - 16.3.1+ (Rootless & Rootful)
// Fixes: Fullscreen App Scale/Border Bug, Corner Radius Restore, 3D Z-Sorting,
//        Header Overlap, Motion Blur Entrance, Infinite 360 Scroll, Hologram Base.
// ============================================================================

@interface CAFilter : NSObject
+ (instancetype)filterWithType:(NSString *)type;
+ (instancetype)filterWithName:(NSString *)name;
@end

@interface SBAppSwitcherPageView : UIView
@property (nonatomic, strong) UIView *view;
@property (nonatomic, assign) CGFloat cornerRadius;
- (void)_updateCornerRadius;
@end

@interface SBFluidSwitcherItemContainer : UIView
@property (nonatomic, strong) SBAppSwitcherPageView *pageView;
@property (nonatomic, assign) CGFloat contentPageViewScale;
- (void)_cs_applyTransformAndGlass;
- (void)_cs_resetToNativeFullscreen;
- (void)_cs_setupCustomOverlayViewsIfNeeded;
- (void)_cs_closeButtonTapped:(UIButton *)sender;
- (void)_cs_triggerEntranceMotionBlur;
@end

@interface SBFluidSwitcherViewController : UIViewController
- (void)_cs_refreshVisibleContainers;
- (void)_cs_updateHologramStageAndScroll;
@end

// ============================================================================
// Global Preferences & Runtime State
// ============================================================================

static NSString * const kCSDomain = @"com.vn.circleswitcher";
static NSString * const kCSReloadNotification = @"com.vn.circleswitcher/ReloadPrefs";

static BOOL kEnabled = YES;
// Layout Modes:
// 0: Vòng Trụ Thẻ 3D (3D Hologram Cylinder - Cards)
// 1: Icon Tròn Vòng Trụ 3D (3D Cylindrical Orbs - Standing Orbs)
// 2: Khung Tròn & Vành Đai Icon (Orbital Preview & Orbs)
// 3: Bánh Xe Icon 360° (Radial Ring Wheel)
// 4: Circle Wheel 3D (Classic Arc)
// 5: 3D Cards
// 6: Card Deck
// 7: CoverFlow
// 8: Inverse CoverFlow
// 9: 2D Flat Cards
static NSInteger kLayoutMode = 0;
static BOOL kInfiniteScroll = YES;
static BOOL kCircleMorph = NO;
static CGFloat kCircleRadius = 34.0f;
static CGFloat kWheelCurvature = 1.05f;
static CGFloat kCardScale = 0.86f;
static CGFloat kOrbSize = 0.72f;
static CGFloat kCardSpacing = 1.05f;

// App Title & Close Button
// 0: Top (Phía trên), 1: Center + Dim (Ở giữa - Làm mờ thẻ), 2: Bottom (Phía dưới), 3: Hidden (Ẩn)
static NSInteger kTitlePosition = 1;
static CGFloat kCenterDimAlpha = 0.45f;
static BOOL kShowCloseButton = YES;

// Liquid Glass & Rim Glow
static BOOL kLiquidGlass = YES;
static CGFloat kGlowIntensity = 0.65f;
static NSInteger kGlowColorIndex = 0;
static NSString *kGlowColorHex = @"#00E5FF";
static CGFloat kGlassRefract = 0.65f;
static CGFloat kGlassSpecular = 0.85f;
static CGFloat kGlassDispersion = 0.40f;

// Hologram 3D Base Ring & Stage Backdrop
static BOOL kHologramBaseEnabled = YES;
static BOOL kBaseSyncColor = YES;
static NSString *kBaseColorHex = @"#00E5FF";
static CGFloat kBaseIntensity = 0.75f;
static CGFloat kBaseScale = 1.0f;
static BOOL kBackdropEnabled = YES;

// Motion Blur & Physics & Icon FX
static BOOL kMotionBlurOn = YES;
static CGFloat kMotionBlurIntensity = 7.5f;
static BOOL kFadeIcons = YES;
static BOOL kScaleIcons = YES;
static BOOL kRollIcons = NO;
static BOOL kHapticFeedback = YES;

// Runtime Switcher Tracking
static BOOL gIsInAppSwitcher = NO;
static BOOL gIsTransitioningToApp = NO;
static CFTimeInterval gSwitcherEnterTimestamp = 0;
static CGFloat gScrollVelocityPhase = 0.0f;
static __weak UIView *kLastCenteredContainer = nil;
static UIImpactFeedbackGenerator *kHapticGenerator = nil;

// Associated Object Keys for Custom Overlay Views
static const void *kCSOverlayHostKey     = &kCSOverlayHostKey;
static const void *kCSDimViewKey         = &kCSDimViewKey;
static const void *kCSGlassRimViewKey    = &kCSGlassRimViewKey;
static const void *kCSOrbHaloViewKey     = &kCSOrbHaloViewKey;
static const void *kCSCenterAppIconKey   = &kCSCenterAppIconKey;
static const void *kCSCenterAppLabelKey  = &kCSCenterAppLabelKey;
static const void *kCSCloseButtonKey     = &kCSCloseButtonKey;
static const void *kCSStageViewKey       = &kCSStageViewKey;
static const void *kCSBaseRingViewKey    = &kCSBaseRingViewKey;
static const void *kCSBackdropViewKey    = &kCSBackdropViewKey;
static const void *kCSLastScrollOffsetKey = &kCSLastScrollOffsetKey;

// ============================================================================
// Color & Asset Helpers (Supports Rootless /var/jb & Rootful)
// ============================================================================

static UIColor *CSColorFromHexString(NSString *hexStr, CGFloat alpha) {
    if (!hexStr || ![hexStr isKindOfClass:[NSString class]] || hexStr.length == 0) {
        return [UIColor colorWithRed:0.0 green:0.90 blue:1.0 alpha:alpha];
    }
    NSString *clean = [[hexStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    if ([clean hasPrefix:@"#"]) clean = [clean substringFromIndex:1];
    if ([clean hasPrefix:@"0X"]) clean = [clean substringFromIndex:2];
    if (clean.length != 6 && clean.length != 8) {
        return [UIColor colorWithRed:0.0 green:0.90 blue:1.0 alpha:alpha];
    }
    unsigned int rgbVal = 0;
    [[NSScanner scannerWithString:clean] scanHexInt:&rgbVal];
    if (clean.length == 8) {
        CGFloat r = ((rgbVal & 0xFF000000) >> 24) / 255.0;
        CGFloat g = ((rgbVal & 0x00FF0000) >> 16) / 255.0;
        CGFloat b = ((rgbVal & 0x0000FF00) >> 8)  / 255.0;
        return [UIColor colorWithRed:r green:g blue:b alpha:alpha];
    }
    CGFloat r = ((rgbVal & 0xFF0000) >> 16) / 255.0;
    CGFloat g = ((rgbVal & 0x00FF00) >> 8)  / 255.0;
    CGFloat b = (rgbVal & 0x0000FF)         / 255.0;
    return [UIColor colorWithRed:r green:g blue:b alpha:alpha];
}

static UIColor *CSActiveGlowColor(CGFloat alpha) {
    if (kGlowColorHex && kGlowColorHex.length >= 6 && kGlowColorIndex == 5) {
        return CSColorFromHexString(kGlowColorHex, alpha);
    }
    switch (kGlowColorIndex) {
        case 1:  return [UIColor colorWithRed:0.15 green:0.55 blue:1.00 alpha:alpha]; // Royal Blue
        case 2:  return [UIColor colorWithRed:0.68 green:0.35 blue:1.00 alpha:alpha]; // Nebula Violet
        case 3:  return [UIColor colorWithRed:0.15 green:0.90 blue:0.65 alpha:alpha]; // Emerald Mint
        case 4:  return [UIColor colorWithWhite:1.00 alpha:alpha];                     // Pure Specular White
        case 5:  return CSColorFromHexString(kGlowColorHex, alpha);                    // Custom RGB Color
        case 0:
        default: {
            if (kGlowColorHex && ![kGlowColorHex isEqualToString:@"#00E5FF"]) {
                return CSColorFromHexString(kGlowColorHex, alpha);
            }
            return [UIColor colorWithRed:0.00 green:0.90 blue:1.00 alpha:alpha];       // Hologram Ice Cyan
        }
    }
}

static UIColor *CSActiveBaseColor(CGFloat alpha) {
    if (kBaseSyncColor) {
        return CSActiveGlowColor(alpha);
    }
    return CSColorFromHexString(kBaseColorHex, alpha);
}

static NSBundle *CSPrefsResourceBundle(void) {
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

static UIImage *CSLoadAssetImage(NSString *name, BOOL asTemplate) {
    NSBundle *b = CSPrefsResourceBundle();
    UIImage *img = nil;
    if (b) {
        img = [UIImage imageNamed:name inBundle:b compatibleWithTraitCollection:nil];
    }
    if (!img) {
        NSArray<NSString *> *candidates = @[
            [NSString stringWithFormat:@"/var/jb/Library/PreferenceBundles/CircleSwitcherPrefs.bundle/%@@3x.png", name],
            [NSString stringWithFormat:@"/var/jb/Library/PreferenceBundles/CircleSwitcherPrefs.bundle/%@@2x.png", name],
            [NSString stringWithFormat:@"/Library/PreferenceBundles/CircleSwitcherPrefs.bundle/%@@3x.png", name],
            [NSString stringWithFormat:@"/Library/PreferenceBundles/CircleSwitcherPrefs.bundle/%@@2x.png", name]
        ];
        for (NSString *path in candidates) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
                img = [UIImage imageWithContentsOfFile:path];
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
// Preferences Loader
// ============================================================================

static NSDictionary *CSReadPreferencesDictionary(void) {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kCSDomain];
    [defaults synchronize];
    NSDictionary *dict = [defaults dictionaryRepresentation];
    if (dict && dict[@"enabled"] != nil) {
        return dict;
    }
    NSArray<NSString *> *paths = @[
        @"/var/jb/var/mobile/Library/Preferences/com.vn.circleswitcher.plist",
        @"/var/mobile/Library/Preferences/com.vn.circleswitcher.plist"
    ];
    for (NSString *path in paths) {
        NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
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
    kCircleRadius        = prefs[@"circleRadius"]        ? [prefs[@"circleRadius"] floatValue]        : 34.0f;
    kWheelCurvature      = prefs[@"wheelCurvature"]      ? [prefs[@"wheelCurvature"] floatValue]      : 1.05f;
    kCardScale           = prefs[@"cardScale"]           ? [prefs[@"cardScale"] floatValue]           : 0.86f;
    kOrbSize             = prefs[@"orbSize"]             ? [prefs[@"orbSize"] floatValue]             : 0.72f;
    kCardSpacing         = prefs[@"cardSpacing"]         ? [prefs[@"cardSpacing"] floatValue]         : 1.05f;

    kTitlePosition       = prefs[@"titlePosition"]       ? [prefs[@"titlePosition"] integerValue]    : 1;
    kCenterDimAlpha      = prefs[@"centerDimAlpha"]      ? [prefs[@"centerDimAlpha"] floatValue]      : 0.45f;
    kShowCloseButton     = prefs[@"showCloseButton"]     ? [prefs[@"showCloseButton"] boolValue]     : YES;

    kLiquidGlass         = prefs[@"liquidGlass"]         ? [prefs[@"liquidGlass"] boolValue]         : YES;
    kGlowIntensity       = prefs[@"glowIntensity"]       ? [prefs[@"glowIntensity"] floatValue]       : 0.65f;
    kGlowColorIndex      = prefs[@"glowColorIndex"]      ? [prefs[@"glowColorIndex"] integerValue]    : 0;
    kGlowColorHex        = prefs[@"glowColorHex"]        ? [prefs[@"glowColorHex"] description]       : @"#00E5FF";
    kGlassRefract        = prefs[@"glassRefract"]        ? [prefs[@"glassRefract"] floatValue]        : 0.65f;
    kGlassSpecular       = prefs[@"glassSpecular"]       ? [prefs[@"glassSpecular"] floatValue]       : 0.85f;
    kGlassDispersion     = prefs[@"glassDispersion"]     ? [prefs[@"glassDispersion"] floatValue]     : 0.40f;

    kHologramBaseEnabled = prefs[@"hologramBaseEnabled"] ? [prefs[@"hologramBaseEnabled"] boolValue] : YES;
    kBaseSyncColor       = prefs[@"baseSyncColor"]       ? [prefs[@"baseSyncColor"] boolValue]       : YES;
    kBaseColorHex        = prefs[@"baseColorHex"]        ? [prefs[@"baseColorHex"] description]        : @"#00E5FF";
    kBaseIntensity       = prefs[@"baseIntensity"]       ? [prefs[@"baseIntensity"] floatValue]       : 0.75f;
    kBaseScale           = prefs[@"baseScale"]           ? [prefs[@"baseScale"] floatValue]           : 1.0f;
    kBackdropEnabled     = prefs[@"backdropEnabled"]     ? [prefs[@"backdropEnabled"] boolValue]     : YES;

    kMotionBlurOn        = prefs[@"motionBlurOn"]        ? [prefs[@"motionBlurOn"] boolValue]        : YES;
    kMotionBlurIntensity = prefs[@"motionBlurIntensity"] ? [prefs[@"motionBlurIntensity"] floatValue] : 7.5f;
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
// Accurate Detection: Switcher Mode vs. Fullscreen App Mode
// Fixes Bug #1 & #2: Never shrink or border active fullscreen apps!
// ============================================================================

static BOOL CSIsContainerInSwitcherMode(SBFluidSwitcherItemContainer *container) {
    if (!kEnabled || !container || gIsTransitioningToApp) {
        return NO;
    }

    // Check 1: contentPageViewScale on SBFluidSwitcherItemContainer
    // In iOS 14-16, fullscreen apps have contentPageViewScale ~ 1.0 (0.95..1.0).
    // In the App Switcher, SpringBoard scales cards down (typically 0.35..0.82).
    if ([container respondsToSelector:@selector(contentPageViewScale)]) {
        CGFloat pageScale = container.contentPageViewScale;
        if (pageScale >= 0.93f) {
            return NO;
        }
        if (pageScale > 0.15f && pageScale < 0.91f) {
            return YES;
        }
    }

    // Check 2: Fallback KVC check on _contentPageViewScale
    @try {
        NSNumber *scaleNum = [container valueForKey:@"_contentPageViewScale"];
        if (scaleNum && [scaleNum isKindOfClass:[NSNumber class]]) {
            CGFloat s = [scaleNum floatValue];
            if (s >= 0.93f) return NO;
            if (s > 0.15f && s < 0.91f) return YES;
        }
    } @catch (NSException *e) {}

    return gIsInAppSwitcher;
}

// Helper to extract App Icon & Title from native SBFluidSwitcherItemContainer
static void CSExtractAppHeaderInfo(SBFluidSwitcherItemContainer *container, UIImage **outIcon, NSString **outTitle) {
    for (UIView *sub in container.subviews) {
        NSString *clsName = NSStringFromClass([sub class]);
        if ([clsName containsString:@"Header"] || [clsName containsString:@"Icon"]) {
            for (UIView *inner in sub.subviews) {
                if ([inner isKindOfClass:[UILabel class]] && outTitle && !*outTitle) {
                    NSString *txt = ((UILabel *)inner).text;
                    if (txt.length > 0) *outTitle = txt;
                } else if ([inner isKindOfClass:[UIImageView class]] && outIcon && !*outIcon) {
                    UIImage *img = ((UIImageView *)inner).image;
                    if (img) *outIcon = img;
                }
                for (UIView *deep in inner.subviews) {
                    if ([deep isKindOfClass:[UILabel class]] && outTitle && !*outTitle) {
                        NSString *txt = ((UILabel *)deep).text;
                        if (txt.length > 0) *outTitle = txt;
                    } else if ([deep isKindOfClass:[UIImageView class]] && outIcon && !*outIcon) {
                        UIImage *img = ((UIImageView *)deep).image;
                        if (img) *outIcon = img;
                    }
                }
            }
        }
    }
}

// ============================================================================
// Hook SBAppSwitcherPageView — Corner Radius & Rim Border with Full Restore
// ============================================================================

%hook SBAppSwitcherPageView

- (void)layoutSubviews {
    %orig;

    SBFluidSwitcherItemContainer *parentContainer = nil;
    UIView *sup = self.superview;
    while (sup) {
        if ([sup isKindOfClass:%c(SBFluidSwitcherItemContainer)]) {
            parentContainer = (SBFluidSwitcherItemContainer *)sup;
            break;
        }
        sup = sup.superview;
    }

    BOOL inSwitcher = parentContainer ? CSIsContainerInSwitcherMode(parentContainer) : NO;

    if (!kEnabled || !inSwitcher) {
        self.layer.borderWidth = 0.0;
        self.layer.shadowOpacity = 0.0;
        [self _updateCornerRadius];
        return;
    }

    CGFloat minSide = MIN(self.bounds.size.width, self.bounds.size.height);
    BOOL isCircularMode = (kLayoutMode == 1 || kLayoutMode == 2 || kLayoutMode == 3 || kCircleMorph);

    if (isCircularMode) {
        CGFloat targetR = (kLayoutMode == 1 || kLayoutMode == 2 || kLayoutMode == 3)
            ? (minSide * 0.5f)
            : MIN(minSide * 0.5f, kCircleRadius);
        self.layer.cornerRadius = targetR;
        self.layer.masksToBounds = YES;
        if (@available(iOS 13.0, *)) {
            self.layer.cornerCurve = (targetR >= minSide * 0.45f) ? kCACornerCurveCircular : kCACornerCurveContinuous;
        }
    } else {
        // Restore or apply clean card radius in 3D Cylinder Card Mode
        CGFloat cardR = (kLayoutMode == 0) ? MAX(24.0f, MIN(48.0f, kCircleRadius)) : 28.0f;
        self.layer.cornerRadius = MIN(minSide * 0.5f, cardR);
        self.layer.masksToBounds = YES;
        if (@available(iOS 13.0, *)) {
            self.layer.cornerCurve = kCACornerCurveContinuous;
        }
    }

    if (kLiquidGlass && kGlowIntensity > 0.01f) {
        self.layer.borderWidth = 2.0f;
        self.layer.borderColor = CSActiveGlowColor(MIN(0.96f, 0.42f + kGlowIntensity * 0.55f)).CGColor;
    } else {
        self.layer.borderWidth = 0.0f;
    }
}

- (void)_updateCornerRadius {
    %orig;

    SBFluidSwitcherItemContainer *parentContainer = nil;
    UIView *sup = self.superview;
    while (sup) {
        if ([sup isKindOfClass:%c(SBFluidSwitcherItemContainer)]) {
            parentContainer = (SBFluidSwitcherItemContainer *)sup;
            break;
        }
        sup = sup.superview;
    }

    BOOL inSwitcher = parentContainer ? CSIsContainerInSwitcherMode(parentContainer) : NO;
    if (!kEnabled || !inSwitcher) {
        // %orig already restored native cornerRadius for fullscreen!
        self.layer.borderWidth = 0.0f;
        return;
    }

    CGFloat minSide = MIN(self.bounds.size.width, self.bounds.size.height);
    if (kLayoutMode == 1 || kLayoutMode == 2 || kLayoutMode == 3) {
        self.layer.cornerRadius = minSide * 0.5f;
    } else if (kCircleMorph) {
        self.layer.cornerRadius = MIN(minSide * 0.5f, kCircleRadius);
    }
}

%end

// ============================================================================
// Hook SBFluidSwitcherItemContainer — 3D Cylinder, Orbs, Motion Blur & Overlays
// ============================================================================

%hook SBFluidSwitcherItemContainer

- (void)layoutSubviews {
    %orig;
    [self _cs_applyTransformAndGlass];
}

- (void)setCenter:(CGPoint)center {
    %orig;
    [self _cs_applyTransformAndGlass];
}

- (void)setContentPageViewScale:(CGFloat)scale {
    CGFloat prevScale = [self respondsToSelector:@selector(contentPageViewScale)] ? self.contentPageViewScale : 1.0f;
    %orig(scale);
    // Trigger subtle motion blur when morphing from fullscreen (scale >= 0.93) into switcher (scale < 0.88)
    if (kEnabled && kMotionBlurOn && prevScale >= 0.92f && scale < 0.90f) {
        [self _cs_triggerEntranceMotionBlur];
    }
    [self _cs_applyTransformAndGlass];
}

%new
- (void)_cs_triggerEntranceMotionBlur {
    if (!kMotionBlurOn || kMotionBlurIntensity <= 0.1f) return;
    UIView *targetView = ([self respondsToSelector:@selector(pageView)] && self.pageView) ? self.pageView : self.subviews.firstObject;
    if (!targetView) return;

    @try {
        Class filterCls = NSClassFromString(@"CAFilter");
        if (filterCls && [filterCls respondsToSelector:@selector(filterWithType:)]) {
            id blurFilter = [filterCls filterWithType:@"gaussianBlur"];
            if (blurFilter) {
                [blurFilter setValue:@"csMotionBlur" forKey:@"name"];
                [blurFilter setValue:@(kMotionBlurIntensity) forKey:@"inputRadius"];
                targetView.layer.filters = @[blurFilter];

                CABasicAnimation *blurAnim = [CABasicAnimation animationWithKeyPath:@"filters.csMotionBlur.inputRadius"];
                blurAnim.fromValue = @(kMotionBlurIntensity);
                blurAnim.toValue = @(0.0);
                blurAnim.duration = 0.28;
                blurAnim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
                [targetView.layer addAnimation:blurAnim forKey:@"csMotionBlurFade"];

                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.26 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    targetView.layer.filters = nil;
                });
            }
        }
    } @catch (NSException *e) {}
}

%new
- (void)_cs_setupCustomOverlayViewsIfNeeded {
    UIView *targetView = ([self respondsToSelector:@selector(pageView)] && self.pageView) ? self.pageView : self.subviews.firstObject;
    if (!targetView) return;

    UIView *overlayHost = objc_getAssociatedObject(self, kCSOverlayHostKey);
    if (!overlayHost) {
        overlayHost = [[UIView alloc] initWithFrame:targetView.bounds];
        overlayHost.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        overlayHost.userInteractionEnabled = NO;
        overlayHost.backgroundColor = [UIColor clearColor];
        [targetView addSubview:overlayHost];
        objc_setAssociatedObject(self, kCSOverlayHostKey, overlayHost, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        // 1. Center Dimming Layer (for Center App Title readability)
        UIView *dimView = [[UIView alloc] initWithFrame:overlayHost.bounds];
        dimView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        dimView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.45];
        dimView.alpha = 0.0;
        [overlayHost addSubview:dimView];
        objc_setAssociatedObject(self, kCSDimViewKey, dimView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        // 2. Liquid Glass Specular Rim Asset View (glass_rim)
        UIImageView *glassRimView = [[UIImageView alloc] initWithFrame:overlayHost.bounds];
        glassRimView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        UIImage *rimImg = CSLoadAssetImage(@"glass_rim", NO);
        if (rimImg) {
            CGFloat cap = rimImg.size.width * 0.45f;
            glassRimView.image = [rimImg resizableImageWithCapInsets:UIEdgeInsetsMake(cap, cap, cap, cap) resizingMode:UIImageResizingModeStretch];
        }
        glassRimView.alpha = 0.0;
        [overlayHost addSubview:glassRimView];
        objc_setAssociatedObject(self, kCSGlassRimViewKey, glassRimView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        // 3. Center App Icon & Title Label
        UIImageView *appIconView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 68, 68)];
        appIconView.layer.cornerRadius = 16.0;
        appIconView.layer.masksToBounds = YES;
        appIconView.contentMode = UIViewContentModeScaleAspectFit;
        appIconView.alpha = 0.0;
        [overlayHost addSubview:appIconView];
        objc_setAssociatedObject(self, kCSCenterAppIconKey, appIconView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        UILabel *appLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 220, 32)];
        appLabel.font = [UIFont systemFontOfSize:21.0 weight:UIFontWeightBold];
        appLabel.textColor = [UIColor whiteColor];
        appLabel.textAlignment = NSTextAlignmentCenter;
        appLabel.layer.shadowColor = [UIColor blackColor].CGColor;
        appLabel.layer.shadowOpacity = 0.75;
        appLabel.layer.shadowRadius = 4.0;
        appLabel.layer.shadowOffset = CGSizeMake(0, 2);
        appLabel.alpha = 0.0;
        [overlayHost addSubview:appLabel];
        objc_setAssociatedObject(self, kCSCenterAppLabelKey, appLabel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // 4. Outer Neon Halo Asset View (orb_halo) & Quick Close Button (✕) on Container
    UIImageView *haloView = objc_getAssociatedObject(self, kCSOrbHaloViewKey);
    if (!haloView) {
        haloView = [[UIImageView alloc] initWithFrame:CGRectZero];
        haloView.userInteractionEnabled = NO;
        haloView.image = CSLoadAssetImage(@"orb_halo", YES);
        haloView.alpha = 0.0;
        [self insertSubview:haloView atIndex:0];
        objc_setAssociatedObject(self, kCSOrbHaloViewKey, haloView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    UIButton *closeBtn = objc_getAssociatedObject(self, kCSCloseButtonKey);
    if (!closeBtn) {
        closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        closeBtn.frame = CGRectMake(0, 0, 42, 42);
        closeBtn.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.82];
        closeBtn.layer.cornerRadius = 21.0;
        closeBtn.layer.borderWidth = 1.2;
        closeBtn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
        [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
        [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        closeBtn.titleLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightBold];
        [closeBtn addTarget:self action:@selector(_cs_closeButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        closeBtn.alpha = 0.0;
        closeBtn.hidden = YES;
        [self addSubview:closeBtn];
        objc_setAssociatedObject(self, kCSCloseButtonKey, closeBtn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%new
- (void)_cs_closeButtonTapped:(UIButton *)sender {
    if (kHapticFeedback) {
        if (!kHapticGenerator) {
            kHapticGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        }
        [kHapticGenerator impactOccurred];
    }
    [UIView animateWithDuration:0.22 animations:^{
        self.alpha = 0.0;
        self.transform = CGAffineTransformMakeScale(0.5, 0.5);
    } completion:^(BOOL finished) {
        self.alpha = 1.0;
        self.transform = CGAffineTransformIdentity;
        // Trigger native container kill delegate if available
        @try {
            id delegate = [self valueForKey:@"_delegate"];
            SEL killSel = NSSelectorFromString(@"killContainer:forReason:");
            if (delegate && [delegate respondsToSelector:killSel]) {
                ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(delegate, killSel, self, 0);
            }
        } @catch (NSException *e) {}
    }];
}

%new
- (void)_cs_resetToNativeFullscreen {
    UIView *targetView = ([self respondsToSelector:@selector(pageView)] && self.pageView) ? self.pageView : self.subviews.firstObject;
    if (targetView) {
        targetView.layer.transform = CATransform3DIdentity;
        targetView.layer.borderWidth = 0.0;
        targetView.layer.shadowOpacity = 0.0;
        targetView.layer.filters = nil;
        if ([targetView respondsToSelector:@selector(_updateCornerRadius)]) {
            [(SBAppSwitcherPageView *)targetView _updateCornerRadius];
        }
    }
    self.layer.zPosition = 0.0;
    self.layer.shadowOpacity = 0.0;

    UIView *overlayHost = objc_getAssociatedObject(self, kCSOverlayHostKey);
    if (overlayHost) overlayHost.hidden = YES;

    UIImageView *haloView = objc_getAssociatedObject(self, kCSOrbHaloViewKey);
    if (haloView) haloView.alpha = 0.0;

    UIButton *closeBtn = objc_getAssociatedObject(self, kCSCloseButtonKey);
    if (closeBtn) {
        closeBtn.alpha = 0.0;
        closeBtn.hidden = YES;
    }

    // Restore native header visibility
    for (UIView *sub in self.subviews) {
        NSString *clsName = NSStringFromClass([sub class]);
        if ([clsName containsString:@"Header"] || [clsName containsString:@"Icon"]) {
            sub.alpha = 1.0;
            sub.transform = CGAffineTransformIdentity;
        }
    }
}

%new
- (void)_cs_applyTransformAndGlass {
    if (!CSIsContainerInSwitcherMode(self)) {
        [self _cs_resetToNativeFullscreen];
        return;
    }

    UIView *targetView = ([self respondsToSelector:@selector(pageView)] && self.pageView) ? self.pageView : self.subviews.firstObject;
    if (!targetView) return;

    [self _cs_setupCustomOverlayViewsIfNeeded];

    UIWindow *win = self.window;
    CGFloat screenW = win ? win.bounds.size.width : [UIScreen mainScreen].bounds.size.width;
    if (screenW <= 0) screenW = 390.0;

    CGPoint centerInScreen = [self.superview convertPoint:self.center toView:win];
    CGFloat deltaX = centerInScreen.x - (screenW * 0.5f);
    CGFloat t = (deltaX / (screenW * 0.52f)) / MAX(0.45f, kCardSpacing);

    // Infinite 360 Circular Wrap-around on normalized angle t
    if (kInfiniteScroll && (kLayoutMode == 0 || kLayoutMode == 1 || kLayoutMode == 2 || kLayoutMode == 3 || kLayoutMode == 4)) {
        CGFloat period = 3.6f; // Full 360 cylinder span in normalized units
        t = fmodf(t + period * 0.5f, period);
        if (t < 0) t += period;
        t -= period * 0.5f;
    }

    CGFloat clampedT = MAX(-1.8f, MIN(1.8f, t));
    CGFloat absT = fabs(clampedT);

    // Haptic tick when crossing the center slot
    if (kHapticFeedback && absT < 0.07f && kLastCenteredContainer != self) {
        kLastCenteredContainer = self;
        if (!kHapticGenerator) {
            kHapticGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        }
        [kHapticGenerator impactOccurred];
    }

    // Strict Depth Sorting (Z-Index) to eliminate 3D Plane Clipping / Z-fighting (Fix Bug #4)
    self.layer.zPosition = 500.0f - (absT * 260.0f);

    CATransform3D transform = CATransform3DIdentity;
    transform.m34 = -1.0f / (880.0f / MAX(0.35f, kWheelCurvature));

    CGFloat scaleX = kCardScale;
    CGFloat scaleY = kCardScale;
    CGFloat angleY = 0.0f;
    CGFloat angleZ = 0.0f;
    CGFloat transX = 0.0f;
    CGFloat transY = 0.0f;
    CGFloat transZ = 0.0f;

    CGFloat w = MAX(1.0f, targetView.bounds.size.width);
    CGFloat h = MAX(1.0f, targetView.bounds.size.height);
    CGFloat aspectCorrection = w / h; // Squashes tall pageView into a perfect 1:1 circle when needed

    switch (kLayoutMode) {
        case 0: {
            // Mode 0: Vòng Trụ Thẻ 3D (3D Hologram Cylinder — Carousel Cards)
            CGFloat theta = clampedT * (M_PI / 2.25f) * kWheelCurvature;
            CGFloat cylRadius = screenW * 0.58f * kCardSpacing;
            transX = (cylRadius * sinf(theta)) - deltaX;
            transZ = cylRadius * (cosf(theta) - 1.0f);
            transY = -fabsf(sinf(theta * 0.5f)) * 18.0f;
            angleY = -theta * 0.82f;
            CGFloat depthScale = kCardScale * (0.72f + 0.28f * (cosf(theta) * 0.5f + 0.5f));
            scaleX = depthScale;
            scaleY = depthScale;
            break;
        }
        case 1: {
            // Mode 1: Icon Tròn Vòng Trụ 3D (3D Cylindrical Orbs — Standing Orbs)
            CGFloat theta = clampedT * (M_PI / 2.25f) * kWheelCurvature;
            CGFloat cylRadius = screenW * 0.56f * kCardSpacing;
            transX = (cylRadius * sinf(theta)) - deltaX;
            transZ = cylRadius * (cosf(theta) - 1.0f);
            transY = -fabsf(sinf(theta * 0.5f)) * 22.0f;
            angleY = -theta * 0.85f;
            CGFloat orbBase = kOrbSize * (0.70f + 0.30f * (cosf(theta) * 0.5f + 0.5f));
            scaleX = orbBase;
            scaleY = orbBase * aspectCorrection; // Perfect 1:1 standing circle orb
            break;
        }
        case 2: {
            // Mode 2: Khung Tròn & Vành Đai Icon (Orbital Preview & Circular Side Orbs)
            CGFloat centerWeight = MAX(0.0f, 1.0f - absT * 1.65f);
            CGFloat baseScale = (centerWeight * kCardScale) + ((1.0f - centerWeight) * (kOrbSize * 0.62f));
            scaleX = baseScale;
            scaleY = baseScale * aspectCorrection; // Circular window at center + smaller orbs on sides
            angleY = -clampedT * (M_PI / 4.2f) * kWheelCurvature;
            transY = (absT * absT) * 26.0f * kWheelCurvature;
            transZ = -absT * 135.0f * kWheelCurvature;
            break;
        }
        case 3: {
            // Mode 3: Bánh Xe Icon 360° (Radial Ring Wheel)
            CGFloat theta = clampedT * (M_PI / 1.9f);
            CGFloat ringR = screenW * 0.38f * kCardSpacing;
            transX = (ringR * sinf(theta)) - deltaX;
            transY = -ringR * cosf(theta) + ringR * 0.35f;
            transZ = -absT * 55.0f;
            CGFloat orbBase = kOrbSize * (0.65f + 0.35f * MAX(0.0f, cosf(theta)));
            scaleX = orbBase;
            scaleY = orbBase * aspectCorrection;
            break;
        }
        case 4: {
            // Mode 4: Circle Wheel 3D (Classic Signature Arc)
            angleY = -clampedT * (M_PI / 5.2f) * kWheelCurvature;
            angleZ = clampedT * (M_PI / 18.0f) * kWheelCurvature;
            transY = (absT * absT) * 44.0f * kWheelCurvature;
            transZ = -absT * 95.0f * kWheelCurvature;
            scaleX = scaleY = kCardScale * MAX(0.72f, 1.0f - absT * 0.14f);
            break;
        }
        case 5: {
            // Mode 5: 3D Cards
            angleY = -clampedT * (M_PI / 6.5f) * kWheelCurvature;
            transZ = -absT * 60.0f * kWheelCurvature;
            scaleX = scaleY = kCardScale * MAX(0.78f, 1.0f - absT * 0.09f);
            break;
        }
        case 6: {
            // Mode 6: Card Deck
            angleY = -0.22f * kWheelCurvature;
            transZ = -absT * 110.0f * kWheelCurvature;
            transY = -absT * 14.0f;
            scaleX = scaleY = kCardScale * MAX(0.74f, 1.0f - absT * 0.11f);
            break;
        }
        case 7: {
            // Mode 7: CoverFlow
            CGFloat sign = (clampedT > 0) ? 1.0f : ((clampedT < 0) ? -1.0f : 0.0f);
            CGFloat flowFactor = MIN(1.0f, absT * 1.4f);
            angleY = -sign * flowFactor * (M_PI / 3.4f) * kWheelCurvature;
            transZ = -flowFactor * 120.0f * kWheelCurvature;
            scaleX = scaleY = kCardScale * (1.0f - flowFactor * 0.14f);
            break;
        }
        case 8: {
            // Mode 8: Inverse CoverFlow
            CGFloat sign = (clampedT > 0) ? 1.0f : ((clampedT < 0) ? -1.0f : 0.0f);
            CGFloat flowFactor = MIN(1.0f, absT * 1.4f);
            angleY = sign * flowFactor * (M_PI / 3.4f) * kWheelCurvature;
            transZ = -flowFactor * 120.0f * kWheelCurvature;
            scaleX = scaleY = kCardScale * (1.0f - flowFactor * 0.14f);
            break;
        }
        case 9:
        default: {
            // Mode 9: 2D Flat Cards
            scaleX = scaleY = kCardScale;
            break;
        }
    }

    if (kCircleMorph && kLayoutMode >= 4) {
        scaleY = scaleX * aspectCorrection;
    }

    transform = CATransform3DTranslate(transform, transX, transY, transZ);
    if (fabsf(angleY) > 0.0001f) {
        transform = CATransform3DRotate(transform, angleY, 0.0f, 1.0f, 0.0f);
    }
    if (fabsf(angleZ) > 0.0001f) {
        transform = CATransform3DRotate(transform, angleZ, 0.0f, 0.0f, 1.0f);
    }
    transform = CATransform3DScale(transform, scaleX, scaleY, 1.0f);

    targetView.layer.transform = transform;
    [targetView setNeedsLayout];

    // Update Custom Overlays (Liquid Glass Rim, Halo, App Title & Dimming, Close Button)
    UIView *overlayHost       = objc_getAssociatedObject(self, kCSOverlayHostKey);
    UIView *dimView           = objc_getAssociatedObject(self, kCSDimViewKey);
    UIImageView *glassRimView = objc_getAssociatedObject(self, kCSGlassRimViewKey);
    UIImageView *haloView     = objc_getAssociatedObject(self, kCSOrbHaloViewKey);
    UIImageView *appIconView  = objc_getAssociatedObject(self, kCSCenterAppIconKey);
    UILabel *appLabel         = objc_getAssociatedObject(self, kCSCenterAppLabelKey);
    UIButton *closeBtn        = objc_getAssociatedObject(self, kCSCloseButtonKey);

    if (overlayHost) {
        overlayHost.hidden = NO;
        overlayHost.frame = targetView.bounds;
    }

    // Extract App Icon & Title from native header
    UIImage *iconImg = nil;
    NSString *titleStr = nil;
    CSExtractAppHeaderInfo(self, &iconImg, &titleStr);

    // Hide/clean native header to eliminate overlapping text & icons (Fix Bug #5)
    for (UIView *sub in self.subviews) {
        NSString *clsName = NSStringFromClass([sub class]);
        if ([clsName containsString:@"Header"] || [clsName containsString:@"Icon"]) {
            if (kTitlePosition == 0) {
                // Only show top native header for center card, fade out sides cleanly
                sub.alpha = MAX(0.0f, 1.0f - absT * 1.45f);
                CGFloat iScale = MAX(0.70f, 1.0f - absT * 0.25f);
                sub.transform = CGAffineTransformMakeScale(iScale, iScale);
            } else {
                sub.alpha = 0.0f;
            }
        }
    }

    // Center App Title & Card Dimming
    if (kTitlePosition == 1 || kTitlePosition == 2 || kLayoutMode == 1 || kLayoutMode == 2 || kLayoutMode == 3) {
        if (dimView) {
            dimView.alpha = (kTitlePosition == 1) ? (kCenterDimAlpha * MAX(0.35f, 1.0f - absT * 0.4f)) : 0.15f;
        }
        if (appIconView && iconImg) {
            appIconView.image = iconImg;
            CGFloat iconDim = MIN(w, h) * 0.26f;
            CGFloat centerY = (kTitlePosition == 2) ? (h * 0.72f) : (h * 0.44f);
            appIconView.bounds = CGRectMake(0, 0, iconDim, iconDim);
            appIconView.center = CGPointMake(w * 0.5f, centerY);
            appIconView.layer.cornerRadius = iconDim * 0.22f;
            appIconView.alpha = MAX(0.25f, 1.0f - absT * 0.45f);
        }
        if (appLabel && titleStr) {
            appLabel.text = titleStr;
            CGFloat labelY = (kTitlePosition == 2) ? (h * 0.86f) : (h * 0.61f);
            appLabel.bounds = CGRectMake(0, 0, w * 0.88f, 38.0f);
            appLabel.center = CGPointMake(w * 0.5f, labelY);
            appLabel.font = [UIFont systemFontOfSize:MAX(16.0f, w * 0.065f) weight:UIFontWeightBold];
            appLabel.alpha = MAX(0.20f, 1.0f - absT * 0.55f);
        }
    } else {
        if (dimView) dimView.alpha = 0.0f;
        if (appIconView) appIconView.alpha = 0.0f;
        if (appLabel) appLabel.alpha = 0.0f;
    }

    // Liquid Glass Specular Rim & Neon Halo
    UIColor *glowCol = CSActiveGlowColor(1.0f);
    if (kLiquidGlass && kGlowIntensity > 0.01f) {
        if (glassRimView) {
            glassRimView.alpha = MIN(0.92f, 0.35f + kGlowIntensity * 0.55f);
        }
        if (haloView) {
            CGFloat haloSize = MIN(w * scaleX, h * scaleY) * 1.24f;
            haloView.bounds = CGRectMake(0, 0, haloSize, haloSize);
            haloView.center = CGPointMake(self.bounds.size.width * 0.5f + transX, self.bounds.size.height * 0.5f + transY);
            haloView.tintColor = glowCol;
            haloView.alpha = (kLayoutMode == 1 || kLayoutMode == 2 || kLayoutMode == 3)
                ? (kGlowIntensity * MAX(0.25f, 1.0f - absT * 0.45f))
                : 0.0f;
        }
        self.layer.shadowColor = glowCol.CGColor;
        self.layer.shadowOpacity = (float)(kGlowIntensity * MAX(0.25f, 1.0f - absT * 0.45f));
        self.layer.shadowRadius = 20.0f;
        self.layer.shadowOffset = CGSizeMake(0, 6);
    } else {
        if (glassRimView) glassRimView.alpha = 0.0f;
        if (haloView) haloView.alpha = 0.0f;
        self.layer.shadowOpacity = 0.0f;
    }

    // Quick Close (✕) Button at bottom of centered card/orb
    if (closeBtn) {
        if (kShowCloseButton && absT < 0.25f) {
            closeBtn.hidden = NO;
            closeBtn.alpha = MAX(0.0f, 1.0f - absT * 4.0f);
            CGFloat cardBottomY = (self.bounds.size.height * 0.5f) + (h * scaleY * 0.5f) + transY + 6.0f;
            closeBtn.center = CGPointMake(self.bounds.size.width * 0.5f + transX, cardBottomY);
        } else {
            closeBtn.alpha = 0.0f;
            closeBtn.hidden = YES;
        }
    }
}

%end

// ============================================================================
// Hook SBFluidSwitcherViewController — 3D Hologram Base Ring & Stage Manager
// ============================================================================

%hook SBFluidSwitcherViewController

- (void)viewDidLoad {
    %orig;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_cs_refreshVisibleContainers)
                                                 name:@"CSInternalPreferencesDidUpdate"
                                               object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig(animated);
    gIsInAppSwitcher = YES;
    gIsTransitioningToApp = NO;
    [self _cs_updateHologramStageAndScroll];
}

- (void)viewDidLayoutSubviews {
    %orig;
    [self _cs_updateHologramStageAndScroll];
}

%new
- (void)_cs_updateHologramStageAndScroll {
    if (!self.view) return;

    // Inspect layoutContext.layoutState.unlockedEnvironmentMode if available
    // (2 == AppSwitcher, 3 == Fullscreen App, 1 == HomeScreen)
    BOOL switcherVisible = NO;
    @try {
        id modeNum = [self valueForKeyPath:@"layoutContext.layoutState.unlockedEnvironmentMode"];
        if (modeNum && [modeNum respondsToSelector:@selector(integerValue)]) {
            NSInteger envMode = [modeNum integerValue];
            switcherVisible = (envMode == 2);
            gIsInAppSwitcher = switcherVisible;
            gIsTransitioningToApp = (envMode == 3);
        }
    } @catch (NSException *e) {
        switcherVisible = gIsInAppSwitcher;
    }

    UIView *stageView = objc_getAssociatedObject(self, kCSStageViewKey);
    UIImageView *backdropView = objc_getAssociatedObject(self, kCSBackdropViewKey);
    UIView *baseRingView = objc_getAssociatedObject(self, kCSBaseRingViewKey);

    if (!stageView) {
        stageView = [[UIView alloc] initWithFrame:self.view.bounds];
        stageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        stageView.userInteractionEnabled = NO;
        stageView.backgroundColor = [UIColor clearColor];
        [self.view insertSubview:stageView atIndex:0];
        objc_setAssociatedObject(self, kCSStageViewKey, stageView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        // Ambient Backdrop (ambient_backdrop@3x.png)
        backdropView = [[UIImageView alloc] initWithFrame:stageView.bounds];
        backdropView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        backdropView.image = CSLoadAssetImage(@"ambient_backdrop", YES);
        backdropView.contentMode = UIViewContentModeScaleAspectFill;
        [stageView addSubview:backdropView];
        objc_setAssociatedObject(self, kCSBackdropViewKey, backdropView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        // 3D Hologram Base Ring (Concentric Neon Rings tilted in 3D perspective)
        baseRingView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 320)];
        baseRingView.userInteractionEnabled = NO;
        [stageView addSubview:baseRingView];
        objc_setAssociatedObject(self, kCSBaseRingViewKey, baseRingView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        UIImageView *baseHalo = [[UIImageView alloc] initWithFrame:baseRingView.bounds];
        baseHalo.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        baseHalo.image = CSLoadAssetImage(@"orb_halo", YES);
        baseHalo.tag = 9001;
        [baseRingView addSubview:baseHalo];

        UIImageView *innerHalo = [[UIImageView alloc] initWithFrame:CGRectInset(baseRingView.bounds, 46, 46)];
        innerHalo.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        innerHalo.image = CSLoadAssetImage(@"orb_halo", YES);
        innerHalo.tag = 9002;
        [baseRingView addSubview:innerHalo];
    }

    if (!kEnabled || !switcherVisible) {
        stageView.hidden = YES;
        stageView.alpha = 0.0f;
        return;
    }

    stageView.hidden = NO;
    stageView.alpha = 1.0f;
    stageView.frame = self.view.bounds;

    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;

    // Configure Ambient Backdrop
    if (backdropView) {
        backdropView.hidden = !kBackdropEnabled;
        backdropView.tintColor = CSActiveGlowColor(0.28f * kGlowIntensity);
    }

    // Configure 3D Hologram Base Platform (for Cylinder & Orbital modes)
    if (baseRingView) {
        BOOL showBase = kHologramBaseEnabled && (kLayoutMode == 0 || kLayoutMode == 1 || kLayoutMode == 2);
        baseRingView.hidden = !showBase;
        if (showBase) {
            CGFloat ringDim = MIN(w, h) * 0.84f * kBaseScale;
            baseRingView.bounds = CGRectMake(0, 0, ringDim, ringDim);
            baseRingView.center = CGPointMake(w * 0.5f, h * 0.73f);

            UIColor *baseCol = CSActiveBaseColor(1.0f);
            UIImageView *outerH = (UIImageView *)[baseRingView viewWithTag:9001];
            UIImageView *innerH = (UIImageView *)[baseRingView viewWithTag:9002];
            outerH.tintColor = baseCol;
            innerH.tintColor = baseCol;
            baseRingView.alpha = MIN(1.0f, kBaseIntensity * 1.15f);

            CATransform3D baseTx = CATransform3DIdentity;
            baseTx.m34 = -1.0f / 520.0f;
            baseTx = CATransform3DRotate(baseTx, 1.24f, 1.0f, 0.0f, 0.0f);
            baseRingView.layer.transform = baseTx;
            baseRingView.layer.shadowColor = baseCol.CGColor;
            baseRingView.layer.shadowOpacity = (float)(kBaseIntensity * 0.85f);
            baseRingView.layer.shadowRadius = 24.0f;
            baseRingView.layer.shadowOffset = CGSizeMake(0, -6);
        }
    }

    // Enable Infinite Circular Scroll padding on Switcher UIScrollView
    for (UIView *sub in self.view.subviews) {
        if ([sub isKindOfClass:[UIScrollView class]]) {
            UIScrollView *sv = (UIScrollView *)sub;
            if (kInfiniteScroll && switcherVisible) {
                UIEdgeInsets targetInsets = UIEdgeInsetsMake(0, w * 1.5f, 0, w * 1.5f);
                if (fabs(sv.contentInset.left - targetInsets.left) > 10.0f) {
                    sv.contentInset = targetInsets;
                }
            } else if (!UIEdgeInsetsEqualToEdgeInsets(sv.contentInset, UIEdgeInsetsZero)) {
                sv.contentInset = UIEdgeInsetsZero;
            }
        }
    }
}

%new
- (void)_cs_refreshVisibleContainers {
    [self _cs_updateHologramStageAndScroll];
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    for (UIView *sub in self.view.subviews) {
        [sub setNeedsLayout];
        for (UIView *child in sub.subviews) {
            if ([child isKindOfClass:%c(SBFluidSwitcherItemContainer)]) {
                [(SBFluidSwitcherItemContainer *)child _cs_applyTransformAndGlass];
            }
        }
    }
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
