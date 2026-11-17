#import "CSCircleSwitcherPreviewHeader.h"
#import <QuartzCore/QuartzCore.h>
#import <math.h>

static UIColor *CSPreviewColorFromHex(NSString *hexStr, CGFloat alpha) {
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
    return [UIColor colorWithRed:((rgbVal & 0xFF0000) >> 16) / 255.0
                           green:((rgbVal & 0x00FF00) >> 8) / 255.0
                            blue:(rgbVal & 0x0000FF) / 255.0
                           alpha:alpha];
}

@interface CSCircleSwitcherPreviewHeader ()
@property (nonatomic, strong) UIVisualEffectView *blurBackground;
@property (nonatomic, strong) UIView *stageContainer;
@property (nonatomic, strong) UIImageView *backdropImageView;
@property (nonatomic, strong) UIView *hologramBaseView;
@property (nonatomic, strong) UIImageView *baseOuterHalo;
@property (nonatomic, strong) UIImageView *baseInnerHalo;
@property (nonatomic, strong) NSMutableArray<UIView *> *cardViews;
@property (nonatomic, strong) NSMutableArray<UIView *> *dimViews;
@property (nonatomic, strong) NSMutableArray<UIImageView *> *glassRimViews;
@property (nonatomic, strong) NSMutableArray<UIImageView *> *orbHaloViews;
@property (nonatomic, strong) NSMutableArray<UILabel *> *appTitleLabels;
@property (nonatomic, strong) NSMutableArray<UILabel *> *appIconBadges;
@property (nonatomic, strong) UILabel *topTitleBadge;
@property (nonatomic, strong) UIButton *closeButtonPreview;
@property (nonatomic, strong) UILabel *headerBannerLabel;
@property (nonatomic, strong) UILabel *hintFooterLabel;
@property (nonatomic, strong) UIButton *collapseButton;
@property (nonatomic, assign) CGFloat spinAngle; // Infinite 360 spin offset
@property (nonatomic, assign, readwrite) BOOL isCollapsed;
@end

@implementation CSCircleSwitcherPreviewHeader

- (UIImage *)loadBundleAsset:(NSString *)name asTemplate:(BOOL)asTemplate {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    UIImage *img = [UIImage imageNamed:name inBundle:bundle compatibleWithTraitCollection:nil];
    if (img && asTemplate) {
        img = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    return img;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.clipsToBounds = NO;
        self.spinAngle = 0.0f;
        self.isCollapsed = NO;

        // Floating Frosted Glass Container
        UIBlurEffectStyle style = UIBlurEffectStyleDark;
        if (@available(iOS 13.0, *)) {
            style = UIBlurEffectStyleSystemChromeMaterialDark;
        }
        self.blurBackground = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:style]];
        self.blurBackground.frame = self.bounds;
        self.blurBackground.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.blurBackground.layer.cornerRadius = 18.0;
        self.blurBackground.layer.masksToBounds = YES;
        self.blurBackground.layer.borderWidth = 0.75;
        self.blurBackground.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.16].CGColor;
        [self addSubview:self.blurBackground];

        // Drop shadow floating over scrolling preferences table
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.42;
        self.layer.shadowRadius = 14.0;
        self.layer.shadowOffset = CGSizeMake(0, 6);

        // Header banner + Collapse Toggle
        self.headerBannerLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 8, 260, 18)];
        self.headerBannerLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightSemibold];
        self.headerBannerLabel.textColor = [UIColor colorWithWhite:0.86 alpha:0.9];
        [self.blurBackground.contentView addSubview:self.headerBannerLabel];

        self.collapseButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.collapseButton.frame = CGRectMake(frame.size.width - 78, 4, 68, 24);
        self.collapseButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        self.collapseButton.titleLabel.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightSemibold];
        [self.collapseButton setTitleColor:[UIColor colorWithRed:0.25 green:0.85 blue:1.0 alpha:1.0] forState:UIControlStateNormal];
        [self.collapseButton addTarget:self action:@selector(toggleCollapse:) forControlEvents:UIControlEventTouchUpInside];
        [self.blurBackground.contentView addSubview:self.collapseButton];

        // 3D Stage Container
        self.stageContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 26, frame.size.width, MAX(120, frame.size.height - 48))];
        self.stageContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.stageContainer.clipsToBounds = YES;
        [self.blurBackground.contentView addSubview:self.stageContainer];

        // Ambient Backdrop
        self.backdropImageView = [[UIImageView alloc] initWithFrame:self.stageContainer.bounds];
        self.backdropImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.backdropImageView.image = [self loadBundleAsset:@"ambient_backdrop" asTemplate:YES];
        self.backdropImageView.contentMode = UIViewContentModeScaleAspectFill;
        [self.stageContainer addSubview:self.backdropImageView];

        // 3D Hologram Base Ring
        self.hologramBaseView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 220, 220)];
        self.hologramBaseView.userInteractionEnabled = NO;
        [self.stageContainer addSubview:self.hologramBaseView];

        self.baseOuterHalo = [[UIImageView alloc] initWithFrame:self.hologramBaseView.bounds];
        self.baseOuterHalo.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.baseOuterHalo.image = [self loadBundleAsset:@"orb_halo" asTemplate:YES];
        [self.hologramBaseView addSubview:self.baseOuterHalo];

        self.baseInnerHalo = [[UIImageView alloc] initWithFrame:CGRectInset(self.hologramBaseView.bounds, 34, 34)];
        self.baseInnerHalo.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.baseInnerHalo.image = [self loadBundleAsset:@"orb_halo" asTemplate:YES];
        [self.hologramBaseView addSubview:self.baseInnerHalo];

        // Fallback ring border if orb_halo asset not yet loaded
        if (!self.baseOuterHalo.image) {
            self.baseOuterHalo.layer.cornerRadius = 110.0;
            self.baseOuterHalo.layer.borderWidth = 5.0;
            self.baseInnerHalo.layer.cornerRadius = 76.0;
            self.baseInnerHalo.layer.borderWidth = 3.0;
        }

        // 6 Mock App Cards/Orbs for True 360 Cylinder Loop
        self.cardViews      = [NSMutableArray array];
        self.dimViews       = [NSMutableArray array];
        self.glassRimViews  = [NSMutableArray array];
        self.orbHaloViews   = [NSMutableArray array];
        self.appTitleLabels = [NSMutableArray array];
        self.appIconBadges  = [NSMutableArray array];

        NSArray<UIColor *> *palettes = @[
            [UIColor colorWithRed:0.15 green:0.46 blue:0.96 alpha:1.0], // Safari
            [UIColor colorWithRed:0.16 green:0.78 blue:0.38 alpha:1.0], // Messages
            [UIColor colorWithRed:0.95 green:0.52 blue:0.20 alpha:1.0], // Photos (Center default)
            [UIColor colorWithRed:0.42 green:0.45 blue:0.52 alpha:1.0], // Settings
            [UIColor colorWithRed:0.94 green:0.22 blue:0.40 alpha:1.0], // Music
            [UIColor colorWithRed:0.50 green:0.28 blue:0.94 alpha:1.0]  // Maps
        ];
        NSArray<NSString *> *icons = @[@"🧭", @"💬", @"🌺", @"⚙️", @"🎵", @"🗺️"];

        UIImage *rimImg = [self loadBundleAsset:@"glass_rim" asTemplate:NO];
        UIImage *haloImg = [self loadBundleAsset:@"orb_halo" asTemplate:YES];

        for (NSInteger i = 0; i < 6; i++) {
            UIImageView *halo = [[UIImageView alloc] initWithFrame:CGRectZero];
            halo.image = haloImg;
            halo.userInteractionEnabled = NO;
            [self.stageContainer addSubview:halo];
            [self.orbHaloViews addObject:halo];

            UIView *card = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 74, 112)];
            card.backgroundColor = palettes[i];
            card.layer.masksToBounds = YES;

            UIView *dim = [[UIView alloc] initWithFrame:card.bounds];
            dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            dim.backgroundColor = [UIColor colorWithWhite:0.0 alpha:1.0];
            dim.alpha = 0.0;
            [card addSubview:dim];

            UIImageView *rim = [[UIImageView alloc] initWithFrame:card.bounds];
            rim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            if (rimImg) {
                CGFloat cap = rimImg.size.width * 0.45f;
                rim.image = [rimImg resizableImageWithCapInsets:UIEdgeInsetsMake(cap, cap, cap, cap) resizingMode:UIImageResizingModeStretch];
            }
            [card addSubview:rim];

            UILabel *iconBadge = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 34, 34)];
            iconBadge.text = icons[i];
            iconBadge.font = [UIFont systemFontOfSize:22.0];
            iconBadge.textAlignment = NSTextAlignmentCenter;
            iconBadge.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.92];
            iconBadge.layer.cornerRadius = 8.5;
            iconBadge.layer.masksToBounds = YES;
            [card addSubview:iconBadge];

            UILabel *titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 72, 16)];
            titleLbl.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightBold];
            titleLbl.textColor = [UIColor whiteColor];
            titleLbl.textAlignment = NSTextAlignmentCenter;
            titleLbl.layer.shadowColor = [UIColor blackColor].CGColor;
            titleLbl.layer.shadowOpacity = 0.8;
            titleLbl.layer.shadowRadius = 2.5;
            titleLbl.layer.shadowOffset = CGSizeMake(0, 1);
            [card addSubview:titleLbl];

            [self.stageContainer addSubview:card];
            [self.cardViews addObject:card];
            [self.dimViews addObject:dim];
            [self.glassRimViews addObject:rim];
            [self.appIconBadges addObject:iconBadge];
            [self.appTitleLabels addObject:titleLbl];
        }

        // Top Floating App Title Pill (shown when titlePosition == 0)
        self.topTitleBadge = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 96, 24)];
        self.topTitleBadge.backgroundColor = [UIColor colorWithWhite:0.14 alpha:0.85];
        self.topTitleBadge.textColor = [UIColor whiteColor];
        self.topTitleBadge.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightSemibold];
        self.topTitleBadge.textAlignment = NSTextAlignmentCenter;
        self.topTitleBadge.layer.cornerRadius = 12.0;
        self.topTitleBadge.layer.masksToBounds = YES;
        self.topTitleBadge.layer.zPosition = 900.0;
        [self.stageContainer addSubview:self.topTitleBadge];

        // Quick Close (✕) Preview Pill
        self.closeButtonPreview = [UIButton buttonWithType:UIButtonTypeCustom];
        self.closeButtonPreview.frame = CGRectMake(0, 0, 26, 26);
        self.closeButtonPreview.backgroundColor = [UIColor colorWithWhite:0.20 alpha:0.88];
        self.closeButtonPreview.layer.cornerRadius = 13.0;
        self.closeButtonPreview.layer.borderWidth = 1.0;
        self.closeButtonPreview.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
        [self.closeButtonPreview setTitle:@"✕" forState:UIControlStateNormal];
        [self.closeButtonPreview setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.closeButtonPreview.titleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightBold];
        self.closeButtonPreview.layer.zPosition = 950.0;
        self.closeButtonPreview.userInteractionEnabled = NO;
        [self.stageContainer addSubview:self.closeButtonPreview];

        // Hint Footer
        self.hintFooterLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, frame.size.height - 20, frame.size.width - 24, 16)];
        self.hintFooterLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
        self.hintFooterLabel.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightMedium];
        self.hintFooterLabel.textColor = [UIColor colorWithWhite:0.75 alpha:0.85];
        self.hintFooterLabel.textAlignment = NSTextAlignmentCenter;
        [self.blurBackground.contentView addSubview:self.hintFooterLabel];

        // Pan Gesture for Infinite 360° Preview Spin
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self.stageContainer addGestureRecognizer:pan];

        [self reloadPreviewFromPreferences];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self reloadPreviewFromPreferences];
}

- (void)toggleCollapse:(UIButton *)sender {
    self.isCollapsed = !self.isCollapsed;
    self.stageContainer.hidden = self.isCollapsed;
    self.hintFooterLabel.hidden = self.isCollapsed;
    [self reloadPreviewFromPreferences];
    if ([self.delegate respondsToSelector:@selector(previewHeaderDidToggleCollapse:)]) {
        [self.delegate previewHeaderDidToggleCollapse:self.isCollapsed];
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self.stageContainer];
    if (pan.state == UIGestureRecognizerStateChanged) {
        self.spinAngle += (translation.x / 110.0f);
        [pan setTranslation:CGPointZero inView:self.stageContainer];
        [self reloadPreviewFromPreferences];
    } else if (pan.state == UIGestureRecognizerStateEnded) {
        CGFloat velocityX = [pan velocityInView:self.stageContainer].x;
        CGFloat targetSpin = self.spinAngle + (velocityX / 1200.0f);
        // Snap gently to nearest card index (step = 2*PI / 6)
        CGFloat step = (2.0f * M_PI) / 6.0f;
        CGFloat snapped = roundf(targetSpin / step) * step;
        [UIView animateWithDuration:0.38 delay:0 usingSpringWithDamping:0.76 initialSpringVelocity:0.4 options:UIViewAnimationOptionAllowUserInteraction animations:^{
            self.spinAngle = snapped;
            [self reloadPreviewFromPreferences];
        } completion:nil];
    }
}

- (void)triggerMotionBlurDemo {
    [UIView animateWithDuration:0.14 animations:^{
        self.stageContainer.alpha = 0.65;
        self.stageContainer.transform = CGAffineTransformMakeScale(0.95, 0.95);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.22 animations:^{
            self.stageContainer.alpha = 1.0;
            self.stageContainer.transform = CGAffineTransformIdentity;
        }];
    }];
}

- (void)reloadPreviewFromPreferences {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.vn.circleswitcher"];
    [defaults synchronize];
    NSDictionary *prefs = [defaults dictionaryRepresentation];

    BOOL isEnglish         = ([prefs[@"language"] integerValue] == 1);
    NSInteger mode         = prefs[@"layoutMode"]          ? [prefs[@"layoutMode"] integerValue]       : 0;
    BOOL circleMorph       = prefs[@"circleMorph"]         ? [prefs[@"circleMorph"] boolValue]         : NO;
    CGFloat radius         = prefs[@"circleRadius"]        ? [prefs[@"circleRadius"] floatValue]       : 34.0f;
    CGFloat curvature      = prefs[@"wheelCurvature"]      ? [prefs[@"wheelCurvature"] floatValue]     : 1.05f;
    CGFloat cardScale      = prefs[@"cardScale"]           ? [prefs[@"cardScale"] floatValue]          : 0.86f;
    CGFloat orbSize        = prefs[@"orbSize"]             ? [prefs[@"orbSize"] floatValue]            : 0.72f;
    CGFloat spacing        = prefs[@"cardSpacing"]         ? [prefs[@"cardSpacing"] floatValue]        : 1.05f;
    NSInteger titlePos     = prefs[@"titlePosition"]       ? [prefs[@"titlePosition"] integerValue]    : 1;
    CGFloat centerDim      = prefs[@"centerDimAlpha"]      ? [prefs[@"centerDimAlpha"] floatValue]     : 0.45f;
    BOOL showClose         = prefs[@"showCloseButton"]     ? [prefs[@"showCloseButton"] boolValue]     : YES;
    BOOL glass             = prefs[@"liquidGlass"]         ? [prefs[@"liquidGlass"] boolValue]         : YES;
    CGFloat glow           = prefs[@"glowIntensity"]       ? [prefs[@"glowIntensity"] floatValue]      : 0.65f;
    NSString *glowHex      = prefs[@"glowColorHex"]        ? [prefs[@"glowColorHex"] description]      : @"#00E5FF";
    BOOL baseEnabled       = prefs[@"hologramBaseEnabled"] ? [prefs[@"hologramBaseEnabled"] boolValue] : YES;
    BOOL baseSync          = prefs[@"baseSyncColor"]       ? [prefs[@"baseSyncColor"] boolValue]       : YES;
    NSString *baseHex      = prefs[@"baseColorHex"]        ? [prefs[@"baseColorHex"] description]      : @"#00E5FF";
    CGFloat baseIntensity  = prefs[@"baseIntensity"]       ? [prefs[@"baseIntensity"] floatValue]      : 0.75f;
    CGFloat baseScale      = prefs[@"baseScale"]           ? [prefs[@"baseScale"] floatValue]          : 1.0f;
    BOOL backdropOn        = prefs[@"backdropEnabled"]     ? [prefs[@"backdropEnabled"] boolValue]     : YES;

    self.headerBannerLabel.text = isEnglish
        ? @"3D LIVE PREVIEW (PINNED)"
        : @"XEM TRƯỚC 3D (LUÔN GHIM Ở TRÊN)";
    self.hintFooterLabel.text = isEnglish
        ? @"Swipe horizontally to test 360° infinite rotation"
        : @"Vuốt ngang để xoay thử nghiệm 360° vô tận";
    [self.collapseButton setTitle:(self.isCollapsed ? (isEnglish ? @"Expand ▾" : @"Mở rộng ▾") : (isEnglish ? @"Hide ▴" : @"Thu gọn ▴"))
                         forState:UIControlStateNormal];

    if (self.isCollapsed) return;

    NSArray<NSString *> *namesVI = @[@"Safari", @"Tin nhắn", @"Ảnh", @"Cài đặt", @"Nhạc", @"Bản đồ"];
    NSArray<NSString *> *namesEN = @[@"Safari", @"Messages", @"Photos", @"Settings", @"Music", @"Maps"];
    NSArray<NSString *> *names = isEnglish ? namesEN : namesVI;

    UIColor *glowColor = CSPreviewColorFromHex(glowHex, 1.0f);
    UIColor *baseColor = baseSync ? glowColor : CSPreviewColorFromHex(baseHex, 1.0f);

    CGFloat w = self.stageContainer.bounds.size.width > 0 ? self.stageContainer.bounds.size.width : 330.0f;
    CGFloat h = self.stageContainer.bounds.size.height > 0 ? self.stageContainer.bounds.size.height : 148.0f;

    // Backdrop
    self.backdropImageView.hidden = !backdropOn;
    self.backdropImageView.tintColor = [glowColor colorWithAlphaComponent:0.26f * glow];

    // 3D Hologram Base Ring
    BOOL showBase = baseEnabled && (mode == 0 || mode == 1 || mode == 2);
    self.hologramBaseView.hidden = !showBase;
    if (showBase) {
        CGFloat ringDim = MIN(w * 0.72f, 220.0f) * baseScale;
        self.hologramBaseView.bounds = CGRectMake(0, 0, ringDim, ringDim);
        self.hologramBaseView.center = CGPointMake(w * 0.5f, h * 0.76f);
        self.baseOuterHalo.tintColor = baseColor;
        self.baseInnerHalo.tintColor = baseColor;
        if (!self.baseOuterHalo.image) {
            self.baseOuterHalo.layer.borderColor = baseColor.CGColor;
            self.baseInnerHalo.layer.borderColor = [baseColor colorWithAlphaComponent:0.7f].CGColor;
        }
        self.hologramBaseView.alpha = MIN(1.0f, baseIntensity * 1.15f);

        CATransform3D baseTx = CATransform3DIdentity;
        baseTx.m34 = -1.0f / 420.0f;
        baseTx = CATransform3DRotate(baseTx, 1.24f, 1.0f, 0.0f, 0.0f);
        self.hologramBaseView.layer.transform = baseTx;
        self.hologramBaseView.layer.zPosition = -150.0f;
        self.hologramBaseView.layer.shadowColor = baseColor.CGColor;
        self.hologramBaseView.layer.shadowOpacity = (float)(baseIntensity * 0.85f);
        self.hologramBaseView.layer.shadowRadius = 16.0f;
    }

    NSInteger count = (NSInteger)self.cardViews.count;
    NSInteger frontIndex = 2;
    CGFloat bestFrontScore = -999.0f;

    for (NSInteger i = 0; i < count; i++) {
        UIView *card = self.cardViews[i];
        UIView *dim = self.dimViews[i];
        UIImageView *rim = self.glassRimViews[i];
        UIImageView *halo = self.orbHaloViews[i];
        UILabel *iconLbl = self.appIconBadges[i];
        UILabel *titleLbl = self.appTitleLabels[i];

        // Angular position around full 360 cylinder (index 2 starts at front theta=0)
        CGFloat rawTheta = ((i - 2) * (2.0f * M_PI / (CGFloat)count)) + self.spinAngle;
        // Wrap to [-PI, +PI]
        CGFloat theta = fmodf(rawTheta + M_PI, 2.0f * M_PI);
        if (theta < 0) theta += 2.0f * M_PI;
        theta -= M_PI;

        CGFloat cosT = cosf(theta);
        CGFloat sinT = sinf(theta);
        CGFloat normT = theta / (M_PI * 0.55f);
        CGFloat absNormT = fabsf(normT);

        if (cosT > bestFrontScore) {
            bestFrontScore = cosT;
            frontIndex = i;
        }

        BOOL isCircular = (mode == 1 || mode == 2 || mode == 3 || circleMorph);
        CGFloat cardW = 68.0f * cardScale;
        CGFloat cardH = 104.0f * cardScale;

        if (mode == 1) {
            // Standing Circular Orbs on 3D Cylinder
            cardW = cardH = 74.0f * orbSize;
        } else if (mode == 2) {
            // Center large circle window + side smaller orbs
            CGFloat focus = MAX(0.0f, cosT);
            CGFloat sz = (focus > 0.72f) ? (92.0f * cardScale) : (56.0f * orbSize);
            cardW = cardH = sz;
        } else if (mode == 3) {
            // Radial Ring Wheel Orbs
            cardW = cardH = 54.0f * orbSize;
        } else if (circleMorph) {
            cardW = cardH = 78.0f * cardScale;
        }

        CGFloat cornerR = isCircular ? (cardW * 0.5f) : MIN(cardW * 0.48f, MAX(12.0f, radius * 0.42f));

        CGFloat posX = w * 0.5f;
        CGFloat posY = h * 0.48f;
        CGFloat transZ = 0.0f;
        CGFloat angleY = 0.0f;
        CGFloat depthScale = 1.0f;

        if (mode == 0 || mode == 1) {
            // 3D Hologram Cylinder (Cards or Standing Orbs)
            CGFloat cylR = (w * 0.34f) * spacing;
            posX = (w * 0.5f) + cylR * sinT;
            posY = (h * 0.46f) - (1.0f - cosT) * 8.0f;
            transZ = (cosT - 1.0f) * 95.0f * curvature;
            angleY = -theta * 0.78f * curvature;
            depthScale = 0.62f + 0.38f * ((cosT + 1.0f) * 0.5f);
        } else if (mode == 2) {
            // Orbital Preview & Side Orbs
            CGFloat cylR = (w * 0.37f) * spacing;
            posX = (w * 0.5f) + cylR * sinT;
            posY = (h * 0.50f);
            transZ = (cosT - 1.0f) * 80.0f * curvature;
            angleY = -sinT * 0.65f * curvature;
            depthScale = 0.68f + 0.32f * ((cosT + 1.0f) * 0.5f);
        } else if (mode == 3) {
            // Radial 360 Ring Wheel
            CGFloat ringR = MIN(w, h) * 0.34f * spacing;
            posX = (w * 0.5f) + ringR * sinT;
            posY = (h * 0.50f) - ringR * cosT * 0.72f;
            transZ = (cosT - 1.0f) * 35.0f;
            depthScale = 0.75f + 0.25f * ((cosT + 1.0f) * 0.5f);
        } else if (mode == 7 || mode == 8) {
            // CoverFlow / Inverse CoverFlow
            CGFloat sign = (sinT >= 0) ? 1.0f : -1.0f;
            posX = (w * 0.5f) + sinT * (w * 0.38f) * spacing;
            transZ = -fabsf(sinT) * 75.0f;
            angleY = (mode == 7 ? -sign : sign) * MIN(1.0f, fabsf(sinT) * 1.4f) * (M_PI / 3.5f) * curvature;
            depthScale = 0.74f + 0.26f * MAX(0.0f, cosT);
        } else {
            // Circle Wheel / 3D Cards / Deck / 2D Flat
            posX = (w * 0.5f) + sinT * (w * 0.36f) * spacing;
            posY = (h * 0.48f) + ((mode == 4) ? (sinT * sinT * 16.0f * curvature) : 0.0f);
            transZ = (cosT - 1.0f) * 60.0f;
            angleY = (mode == 9) ? 0.0f : (-sinT * (M_PI / 5.2f) * curvature);
            depthScale = 0.74f + 0.26f * MAX(0.0f, cosT);
        }

        // Reset transform before updating bounds/center
        card.layer.transform = CATransform3DIdentity;
        card.bounds = CGRectMake(0, 0, cardW, cardH);
        card.center = CGPointMake(posX, posY);
        card.layer.cornerRadius = cornerR;
        card.layer.zPosition = cosT * 200.0f;
        card.alpha = (mode == 0 || mode == 1 || mode == 2 || mode == 3)
            ? MAX(0.35f, 0.45f + 0.55f * ((cosT + 1.0f) * 0.5f))
            : MAX(0.15f, cosT + 0.35f);

        // Glass Rim & Border
        if (glass && glow > 0.01f) {
            card.layer.borderWidth = 1.8f;
            card.layer.borderColor = [glowColor colorWithAlphaComponent:MIN(0.95f, 0.45f + glow * 0.5f)].CGColor;
            rim.alpha = MIN(0.9f, 0.35f + glow * 0.55f);
        } else {
            card.layer.borderWidth = 0.0f;
            rim.alpha = 0.0f;
        }

        // Outer Orb Halo
        if (halo.image && glass && glow > 0.01f && isCircular) {
            halo.hidden = NO;
            CGFloat hDim = cardW * depthScale * 1.32f;
            halo.bounds = CGRectMake(0, 0, hDim, hDim);
            halo.center = CGPointMake(posX, posY);
            halo.tintColor = glowColor;
            halo.alpha = glow * MAX(0.25f, (cosT + 1.0f) * 0.5f);
            halo.layer.zPosition = card.layer.zPosition - 1.0f;
        } else {
            halo.hidden = YES;
        }

        // App Icon & Title Layout inside card
        titleLbl.text = names[i];
        CGFloat iconSide = MIN(cardW, cardH) * 0.42f;
        iconLbl.bounds = CGRectMake(0, 0, iconSide, iconSide);
        iconLbl.font = [UIFont systemFontOfSize:iconSide * 0.65f];
        iconLbl.layer.cornerRadius = iconSide * 0.24f;

        if (titlePos == 1) {
            // Centered Title + Card Dimming
            dim.alpha = centerDim;
            iconLbl.center = CGPointMake(cardW * 0.5f, cardH * 0.42f);
            titleLbl.bounds = CGRectMake(0, 0, cardW - 6.0f, 16.0f);
            titleLbl.center = CGPointMake(cardW * 0.5f, cardH * 0.72f);
            iconLbl.alpha = 1.0f;
            titleLbl.alpha = 1.0f;
        } else if (titlePos == 2) {
            // Bottom Title
            dim.alpha = 0.12f;
            iconLbl.center = CGPointMake(cardW * 0.5f, cardH * 0.46f);
            titleLbl.bounds = CGRectMake(0, 0, cardW - 6.0f, 16.0f);
            titleLbl.center = CGPointMake(cardW * 0.5f, cardH * 0.84f);
            iconLbl.alpha = 1.0f;
            titleLbl.alpha = 1.0f;
        } else if (titlePos == 0) {
            // Top Floating Title (Card stays bright)
            dim.alpha = 0.0f;
            iconLbl.center = CGPointMake(cardW * 0.5f, cardH * 0.50f);
            iconLbl.alpha = isCircular ? 1.0f : 0.85f;
            titleLbl.alpha = 0.0f;
        } else {
            // Hidden Title
            dim.alpha = 0.0f;
            iconLbl.center = CGPointMake(cardW * 0.5f, cardH * 0.50f);
            iconLbl.alpha = isCircular ? 1.0f : 0.75f;
            titleLbl.alpha = 0.0f;
        }

        CATransform3D tx = CATransform3DIdentity;
        tx.m34 = -1.0f / 500.0f;
        tx = CATransform3DTranslate(tx, 0, 0, transZ);
        if (fabsf(angleY) > 0.0001f) {
            tx = CATransform3DRotate(tx, angleY, 0.0f, 1.0f, 0.0f);
        }
        tx = CATransform3DScale(tx, depthScale, depthScale, 1.0f);
        card.layer.transform = tx;
    }

    // Top Floating Badge when titlePos == 0
    if (titlePos == 0) {
        self.topTitleBadge.hidden = NO;
        self.topTitleBadge.text = names[frontIndex];
        self.topTitleBadge.center = CGPointMake(w * 0.5f, 16.0f);
    } else {
        self.topTitleBadge.hidden = YES;
    }

    // Close Button (✕) below centered card
    self.closeButtonPreview.hidden = !showClose;
    if (showClose) {
        self.closeButtonPreview.center = CGPointMake(w * 0.5f, h * 0.85f);
    }
}

@end
