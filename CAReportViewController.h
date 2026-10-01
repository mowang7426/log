#import <Preferences/PSListController.h>
@class PSSpecifier;
@interface CAReportViewController : PSListController
- (instancetype)initWithSpecifier:(PSSpecifier *)specifier;
- (NSString *)reportCategory;
@end

@interface CACrashReportViewController : CAReportViewController
@end
@interface CAMemoryReportViewController : CAReportViewController
@end
@interface CARestartReportViewController : CAReportViewController
@end
@interface CAResourceReportViewController : CAReportViewController
@end
@interface CAOtherReportViewController : CAReportViewController
@end
@interface CAReportDetailController : PSListController
- (instancetype)initWithSpecifier:(PSSpecifier *)specifier;
@end
@interface CAReportSourceController : PSListController
- (instancetype)initWithSpecifier:(PSSpecifier *)specifier;
@end
