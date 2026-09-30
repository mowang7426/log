#import "CAPRootListController.h"
#import "CALogStore.h"
#import "CAReportViewController.h"
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>

@implementation CAPRootListController
- (id)specifiers {
    if (!_specifiers) {
        NSMutableArray *items=[NSMutableArray array];
        NSArray *reports=[[CALogStore sharedStore] reports];
        PSSpecifier *header=[PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"全部日志（%lu）",(unsigned long)reports.count] target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [header setProperty:@"按时间倒序显示系统分析日志" forKey:@"footerText"];
        [items addObject:header];
        for (NSDictionary *report in reports) {
            NSString *name=report[@"procName"] ?: report[@"app_name"] ?: report[@"fileName"] ?: @"未知日志";
            NSString *category=report[@"category"] ?: @"其他";
            PSSpecifier *row=[PSSpecifier preferenceSpecifierNamed:name target:self set:nil get:nil detail:[CAReportViewController class] cell:PSLinkCell edit:nil];
            [row setProperty:report[@"path"] forKey:@"reportPath"];
            [row setProperty:category forKey:@"category"];
            [row setProperty:@YES forKey:@"isController"];
            [items addObject:row];
        }
        NSArray *categories=@[@"崩溃",@"内存",@"重启",@"资源",@"其他"];
        for (NSString *category in categories) {
            NSUInteger count=0; for (NSDictionary *r in reports) if ([r[@"category"] isEqualToString:category]) count++;
            PSSpecifier *row=[PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"%@（%lu）",category,(unsigned long)count] target:self set:nil get:nil detail:[CAReportViewController class] cell:PSLinkCell edit:nil];
            [row setProperty:category forKey:@"category"];
            [row setProperty:@YES forKey:@"isController"];
            [items addObject:row];
        }
        NSDictionary *d=[[CALogStore sharedStore] scanDiagnostics];
        PSSpecifier *diag=[PSSpecifier preferenceSpecifierNamed:@"扫描诊断" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [diag setProperty:[NSString stringWithFormat:@"目录 %@ · 枚举 %@ · IPS %@ · 可读 %@ · 解析 %@",[d[@"exists"] boolValue]?@"可见":@"不可见",d[@"enumerated"]?:@0,d[@"matched"]?:@0,d[@"readable"]?:@0,d[@"parsed"]?:@0] forKey:@"footerText"];
        [items addObject:diag];
        _specifiers=[items copy];
    }
    return _specifiers;
}
- (void)viewDidLoad { [super viewDidLoad]; self.title=@"分析日志"; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; _specifiers=nil; [self reloadSpecifiers]; }
@end
