#import <UIKit/UIKit.h>
@class PSSpecifier;
@interface CAReportViewController : UITableViewController
@property(nonatomic, retain) PSSpecifier *specifier;
- (instancetype)initWithSpecifier:(PSSpecifier *)specifier;
@end
