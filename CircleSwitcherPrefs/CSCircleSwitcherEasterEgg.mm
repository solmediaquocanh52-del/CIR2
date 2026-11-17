#import "CSCircleSwitcherEasterEgg.h"

@implementation CSCircleSwitcherEasterEggController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.vn.circleswitcher"];
    [defaults synchronize];
    BOOL isEnglish = ([defaults integerForKey:@"language"] == 1);

    self.title = isEnglish ? @"CircleSwitcher Secret" : @"Bí Mật CircleSwitcher";
    if (@available(iOS 13.0, *)) {
        self.view.backgroundColor = [UIColor systemBackgroundColor];
    } else {
        self.view.backgroundColor = [UIColor whiteColor];
    }

    UILabel *badge = [[UILabel alloc] initWithFrame:CGRectZero];
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    badge.numberOfLines = 0;
    badge.textAlignment = NSTextAlignmentCenter;
    badge.font = [UIFont systemFontOfSize:16.5 weight:UIFontWeightSemibold];
    badge.text = isEnglish
        ? @"CircleSwitcher v2.0.0\n\nBuilt for iOS 14 - 16.3.1+ (Rootless & Rootful)\n3D Hologram Cylinder & Liquid Glass Engine\n\nDouble-tap anywhere for tracks"
        : @"CircleSwitcher v2.0.0\n\nHỗ trợ iOS 14 - 16.3.1+ (Rootless & Rootful)\nVòng Trụ 3D Hologram & Kính Lỏng\n\nChạm đúp vào màn hình để mở danh sách nhạc";

    [self.view addSubview:badge];
    [NSLayoutConstraint activateConstraints:@[
        [badge.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [badge.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [badge.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:24.0],
        [badge.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-24.0]
    ]];

    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showTracks)];
    doubleTap.numberOfTapsRequired = 2;
    [self.view addGestureRecognizer:doubleTap];
}

- (void)showTracks {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Easter Egg"
                                                                   message:@"Select a classic 3D Switcher track:"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    NSDictionary<NSString *, NSString *> *tracks = @{
        @"Track A": @"https://youtu.be/K2-F02R2j44",
        @"Track B": @"https://youtu.be/g926a67k9_U",
        @"Track C": @"https://youtu.be/7a4p5d_B_nE"
    };

    for (NSString *title in @[@"Track A", @"Track B", @"Track C"]) {
        [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSURL *url = [NSURL URLWithString:tracks[title]];
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    alert.popoverPresentationController.sourceView = self.view;
    alert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width * 0.5, self.view.bounds.size.height * 0.5, 1, 1);
    [self presentViewController:alert animated:YES completion:nil];
}

@end
