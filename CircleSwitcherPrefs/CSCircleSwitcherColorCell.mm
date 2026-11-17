#import "CSCircleSwitcherColorCell.h"
#import <QuartzCore/QuartzCore.h>

static UIColor *CSCellColorFromHex(NSString *hexStr) {
    if (!hexStr || ![hexStr isKindOfClass:[NSString class]] || hexStr.length == 0) {
        return [UIColor colorWithRed:0.0 green:0.90 blue:1.0 alpha:1.0];
    }
    NSString *clean = [[hexStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    if ([clean hasPrefix:@"#"]) clean = [clean substringFromIndex:1];
    if ([clean hasPrefix:@"0X"]) clean = [clean substringFromIndex:2];
    if (clean.length != 6) {
        return [UIColor colorWithRed:0.0 green:0.90 blue:1.0 alpha:1.0];
    }
    unsigned int rgbVal = 0;
    [[NSScanner scannerWithString:clean] scanHexInt:&rgbVal];
    return [UIColor colorWithRed:((rgbVal & 0xFF0000) >> 16) / 255.0
                           green:((rgbVal & 0x00FF00) >> 8) / 255.0
                            blue:(rgbVal & 0x0000FF) / 255.0
                           alpha:1.0];
}

@interface CSCircleSwitcherColorCell ()
@property (nonatomic, strong) UIView *colorSwatchView;
@property (nonatomic, strong) UILabel *hexValueLabel;
@end

@implementation CSCircleSwitcherColorCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier];
    if (self) {
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

        self.colorSwatchView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 26, 26)];
        self.colorSwatchView.translatesAutoresizingMaskIntoConstraints = NO;
        self.colorSwatchView.layer.cornerRadius = 13.0;
        self.colorSwatchView.layer.borderWidth = 2.0;
        self.colorSwatchView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.65].CGColor;
        self.colorSwatchView.layer.shadowColor = [UIColor blackColor].CGColor;
        self.colorSwatchView.layer.shadowOpacity = 0.28;
        self.colorSwatchView.layer.shadowRadius = 4.0;
        self.colorSwatchView.layer.shadowOffset = CGSizeMake(0, 1);

        self.hexValueLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        self.hexValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.hexValueLabel.font = [UIFont monospacedSystemFontOfSize:12.0 weight:UIFontWeightMedium];
        if (@available(iOS 13.0, *)) {
            self.hexValueLabel.textColor = [UIColor secondaryLabelColor];
        } else {
            self.hexValueLabel.textColor = [UIColor grayColor];
        }

        [self.contentView addSubview:self.colorSwatchView];
        [self.contentView addSubview:self.hexValueLabel];

        [NSLayoutConstraint activateConstraints:@[
            [self.colorSwatchView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.colorSwatchView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8.0],
            [self.colorSwatchView.widthAnchor constraintEqualToConstant:26.0],
            [self.colorSwatchView.heightAnchor constraintEqualToConstant:26.0],

            [self.hexValueLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [self.hexValueLabel.trailingAnchor constraintEqualToAnchor:self.colorSwatchView.leadingAnchor constant:-8.0]
        ]];

        [self refreshCellContentsWithSpecifier:specifier];
    }
    return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];

    NSString *key = [specifier propertyForKey:@"colorKey"] ?: [specifier propertyForKey:@"key"];
    NSString *defaultHex = [specifier propertyForKey:@"defaultHex"] ?: @"#00E5FF";

    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.vn.circleswitcher"];
    [defaults synchronize];
    NSString *hex = key ? [defaults stringForKey:key] : nil;
    if (!hex || hex.length < 6) hex = defaultHex;

    self.colorSwatchView.backgroundColor = CSCellColorFromHex(hex);
    self.hexValueLabel.text = [hex uppercaseString];
}

@end
