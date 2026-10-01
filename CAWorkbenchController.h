#import <Preferences/PSListController.h>
#import <UIKit/UIKit.h>
@class PSSpecifier;
@interface CAWorkbenchController : PSListController
- (instancetype)initWithSpecifier:(PSSpecifier *)specifier;
@end
@interface CAHistoryController : PSListController
@end
// Shared scrollable renderer for long results; no alert-message truncation.
FOUNDATION_EXPORT void CAPresentText(UIViewController *owner, NSString *title, NSString *text);
FOUNDATION_EXPORT void CAPresentEvidence(UIViewController *owner, NSString *title, NSArray *rows);
