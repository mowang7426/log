#import "CAPRootListController.h"
#import "CALogStore.h"
#import "CAReportViewController.h"
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
@implementation CAPRootListController
- (id)specifiers {
    if (!_specifiers) {
        NSMutableArray *items=[NSMutableArray array];
        NSArray *categories=@[@"崩溃", @"内存", @"重启", @"资源", @"其他"];
        for (NSString *category in categories) {
            PSSpecifier *specifier=[PSSpecifier preferenceSpecifierNamed:category
                target:self set:nil get:nil detail:[CAReportViewController class]
                cell:PSLinkCell edit:nil];
            [specifier setProperty:category forKey:@"category"];
            [specifier setProperty:@YES forKey:@"isController"];
            [items addObject:specifier];
        }
        _specifiers=[items copy];
    }
    return _specifiers;
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; self.title=@"分析日志"; }
@end
