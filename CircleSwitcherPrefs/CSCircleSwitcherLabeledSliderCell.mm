#import "CSCircleSwitcherLabeledSliderCell.h"

@interface CSCircleSwitcherLabeledSliderCell ()
@property (nonatomic, strong) UILabel *titleField;
@property (nonatomic, strong) UILabel *valueField;
@property (nonatomic, strong) UISlider *sliderControl;
@property (nonatomic, copy) NSString *prefKey;
@property (nonatomic, copy) NSString *valueFormat;
@end

@implementation CSCircleSwitcherLabeledSliderCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        self.titleField = [[UILabel alloc] initWithFrame:CGRectZero];
        self.titleField.translatesAutoresizingMaskIntoConstraints = NO;
        self.titleField.font = [UIFont systemFontOfSize:14.5 weight:UIFontWeightMedium];
        if (@available(iOS 13.0, *)) {
            self.titleField.textColor = [UIColor labelColor];
        }

        self.valueField = [[UILabel alloc] initWithFrame:CGRectZero];
        self.valueField.translatesAutoresizingMaskIntoConstraints = NO;
        self.valueField.font = [UIFont monospacedDigitSystemFontOfSize:13.5 weight:UIFontWeightSemibold];
        self.valueField.textAlignment = NSTextAlignmentRight;
        if (@available(iOS 13.0, *)) {
            self.valueField.textColor = [UIColor secondaryLabelColor];
        } else {
            self.valueField.textColor = [UIColor grayColor];
        }

        self.sliderControl = [[UISlider alloc] initWithFrame:CGRectZero];
        self.sliderControl.translatesAutoresizingMaskIntoConstraints = NO;
        self.sliderControl.continuous = YES;
        [self.sliderControl addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
        [self.sliderControl addTarget:self action:@selector(sliderFinished:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];

        [self.contentView addSubview:self.titleField];
        [self.contentView addSubview:self.valueField];
        [self.contentView addSubview:self.sliderControl];

        [NSLayoutConstraint activateConstraints:@[
            [self.titleField.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8.0],
            [self.titleField.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [self.titleField.trailingAnchor constraintLessThanOrEqualToAnchor:self.valueField.leadingAnchor constant:-8.0],

            [self.valueField.centerYAnchor constraintEqualToAnchor:self.titleField.centerYAnchor],
            [self.valueField.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
            [self.valueField.widthAnchor constraintGreaterThanOrEqualToConstant:48.0],

            [self.sliderControl.topAnchor constraintEqualToAnchor:self.titleField.bottomAnchor constant:4.0],
            [self.sliderControl.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
            [self.sliderControl.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
            [self.sliderControl.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8.0]
        ]];

        [self refreshCellContentsWithSpecifier:specifier];
    }
    return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    // Hide default PSTableCell textLabel so it never overlaps our custom top label
    self.textLabel.text = nil;
    self.textLabel.hidden = YES;

    self.prefKey = [specifier propertyForKey:@"key"];
    self.valueFormat = [specifier propertyForKey:@"valueFormat"] ?: @"%.2f";

    NSString *label = [specifier propertyForKey:@"sliderTitle"] ?: [specifier name];
    self.titleField.text = label ?: @"";

    float minVal = [[specifier propertyForKey:@"min"] floatValue];
    float maxVal = [specifier propertyForKey:@"max"] ? [[specifier propertyForKey:@"max"] floatValue] : 1.0f;
    float defVal = [specifier propertyForKey:@"default"] ? [[specifier propertyForKey:@"default"] floatValue] : minVal;

    self.sliderControl.minimumValue = minVal;
    self.sliderControl.maximumValue = maxVal;

    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.vn.circleswitcher"];
    [defaults synchronize];
    id saved = self.prefKey ? [defaults objectForKey:self.prefKey] : nil;
    float current = saved ? [saved floatValue] : defVal;
    current = MAX(minVal, MIN(maxVal, current));

    self.sliderControl.value = current;
    self.valueField.text = [NSString stringWithFormat:self.valueFormat, current];
}

- (void)sliderChanged:(UISlider *)sender {
    float val = sender.value;
    self.valueField.text = [NSString stringWithFormat:self.valueFormat, val];

    if (self.prefKey) {
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.vn.circleswitcher"];
        [defaults setObject:@(val) forKey:self.prefKey];
        [defaults synchronize];

        [[NSNotificationCenter defaultCenter] postNotificationName:@"CSPrefsSliderLiveChanged"
                                                            object:nil
                                                          userInfo:@{@"key": self.prefKey, @"value": @(val)}];
    }
}

- (void)sliderFinished:(UISlider *)sender {
    [self sliderChanged:sender];
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.vn.circleswitcher/ReloadPrefs"),
        NULL,
        NULL,
        YES
    );
}

@end
