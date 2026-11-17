#import "CSCircleSwitcherLogoCell.h"

@implementation CSCircleSwitcherLogoCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.backgroundView = [[UIView alloc] init];
        self.backgroundView.backgroundColor = [UIColor clearColor];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.vn.circleswitcher"];
        [defaults synchronize];
        BOOL isEnglish = ([defaults integerForKey:@"language"] == 1);

        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.text = @"CircleSwitcher 2.0.0";
        titleLabel.font = [UIFont systemFontOfSize:24.0 weight:UIFontWeightBold];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        if (@available(iOS 13.0, *)) {
            titleLabel.textColor = [UIColor labelColor];
        }

        UILabel *subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        subtitleLabel.text = isEnglish
            ? @"3D Hologram Cylinder, Orbital Orbs & Liquid Glass"
            : @"Vòng Trụ 3D Hologram, Icon Tròn & Kính Lỏng";
        subtitleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
        subtitleLabel.textAlignment = NSTextAlignmentCenter;
        if (@available(iOS 13.0, *)) {
            subtitleLabel.textColor = [UIColor secondaryLabelColor];
        } else {
            subtitleLabel.textColor = [UIColor grayColor];
        }

        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, subtitleLabel]];
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        stack.axis = UILayoutConstraintAxisVertical;
        stack.alignment = UIStackViewAlignmentCenter;
        stack.spacing = 4.0;

        [self.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
            [stack.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor]
        ]];
    }
    return self;
}

@end
