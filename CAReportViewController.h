#import <Preferences/PSListController.h>
@class PSSpecifier;
@interface CAReportViewController : PSListController
- (instancetype)initWithSpecifier:(PSSpecifier *)specifier;
- (instancetype)initWithCategory:(NSString *)category;
@end
