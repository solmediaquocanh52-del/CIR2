#import <UIKit/UIKit.h>

@protocol CSCircleSwitcherPreviewHeaderDelegate <NSObject>
@optional
- (void)previewHeaderDidToggleCollapse:(BOOL)collapsed;
@end

@interface CSCircleSwitcherPreviewHeader : UIView
@property (nonatomic, weak) id<CSCircleSwitcherPreviewHeaderDelegate> delegate;
@property (nonatomic, assign, readonly) BOOL isCollapsed;
- (void)reloadPreviewFromPreferences;
- (void)triggerMotionBlurDemo;
@end
