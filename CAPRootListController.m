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
        PSSpecifier *intro=[PSSpecifier preferenceSpecifierNamed:@"分析日志" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [intro setProperty:@"系统分析报告 · 自动分类 · 本地解析" forKey:@"footerText"];
        [items addObject:intro];

        NSArray *categories=@[@"崩溃", @"内存", @"重启", @"资源", @"其他"];
        for (NSString *category in categories) {
            NSUInteger count=0;
            for (NSDictionary *report in reports) if ([report[@"category"] isEqualToString:category]) count++;
            NSString *title=[NSString stringWithFormat:@"%@    %lu 条", category, (unsigned long)count];
            PSSpecifier *row=[PSSpecifier preferenceSpecifierNamed:title target:self set:nil get:nil detail:[CAReportViewController class] cell:PSLinkCell edit:nil];
            [row setProperty:category forKey:@"category"];
            [row setProperty:@YES forKey:@"isController"];
            [items addObject:row];
        }

        NSDictionary *diagnostics=[[CALogStore sharedStore] scanDiagnostics];
        PSSpecifier *status=[PSSpecifier preferenceSpecifierNamed:@"扫描状态" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [status setProperty:@"CrashReporter 目录与解析器状态" forKey:@"footerText"];
        [items addObject:status];
        NSString *line=[NSString stringWithFormat:@"%@ · 发现 %@ 个 IPS · 解析 %@ 个", [diagnostics[@"exists"] boolValue] ? @"目录可访问" : @"目录不可访问", diagnostics[@"matched"] ?: @0, diagnostics[@"parsed"] ?: @0];
        [items addObject:[PSSpecifier preferenceSpecifierNamed:line target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];

        PSSpecifier *refresh=[PSSpecifier preferenceSpecifierNamed:@"重新扫描" target:self set:@selector(reloadNow) get:nil detail:nil cell:PSButtonCell edit:nil];
        [items addObject:refresh];
        _specifiers=[items copy];
    }
    return _specifiers;
}

- (void)viewDidLoad { [super viewDidLoad]; self.title=@"分析日志"; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; _specifiers=nil; [self reloadSpecifiers]; }
- (void)reloadNow { _specifiers=nil; [self reloadSpecifiers]; }
@end
