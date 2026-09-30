#import <Preferences/PSListController.h>
@class PSSpecifier;
@interface CAReportViewController : PSListController
@property(nonatomic, retain) PSSpecifier *specifier;
- (instancetype)initWithSpecifier:(PSSpecifier *)specifier;
@end
