#import "CAPRootListController.h"
#import "CALogStore.h"
#import "CAReportViewController.h"
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
@implementation CAPRootListController
- (id)specifiers { if (!_specifiers) { NSMutableArray *a=[NSMutableArray array]; for (NSString *c in @[@"崩溃",@"内存",@"重启",@"资源",@"其他"]) { PSSpecifier *s=[PSSpecifier preferenceSpecifierNamed:c target:self set:nil get:nil detail:[CAReportViewController class] cell:PSLinkCell edit:nil]; [s setProperty:c forKey:@"category"]; [a addObject:s]; } _specifiers=a; } return _specifiers; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; self.title=@"分析日志"; }
@end
