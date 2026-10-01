#import "CAPRootListController.h"
#import "CALearningController.h"
#import "CAAI.h"
#import "CAWorkbenchController.h"
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
            Class detailClass=Nil;
            if ([category isEqualToString:@"崩溃"]) detailClass=[CACrashReportViewController class];
            else if ([category isEqualToString:@"内存"]) detailClass=[CAMemoryReportViewController class];
            else if ([category isEqualToString:@"重启"]) detailClass=[CARestartReportViewController class];
            else if ([category isEqualToString:@"资源"]) detailClass=[CAResourceReportViewController class];
            else detailClass=[CAOtherReportViewController class];
            PSSpecifier *row=[PSSpecifier preferenceSpecifierNamed:category target:nil set:nil get:nil detail:detailClass cell:PSLinkCell edit:nil];
            [row setProperty:[NSString stringWithFormat:@"%lu 条日志",(unsigned long)count] forKey:@"footerText"];
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

        PSSpecifier *learning=[PSSpecifier preferenceSpecifierNamed:@"本地学习与案例库" target:nil set:nil get:nil detail:[CALearningController class] cell:PSLinkCell edit:nil];
        [items addObject:learning];

        PSSpecifier *ai=[PSSpecifier preferenceSpecifierNamed:@"AI 分析配置" target:nil set:nil get:nil detail:[CAAIConfigController class] cell:PSLinkCell edit:nil];
        [items addObject:ai];

        [items addObject:[PSSpecifier preferenceSpecifierNamed:@"AI 分析历史" target:nil set:nil get:nil detail:[CAHistoryController class] cell:PSLinkCell edit:nil]];
        PSSpecifier *about=[PSSpecifier preferenceSpecifierNamed:@"关于 · CrashAnalyzer 1.1.0" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [about setProperty:@"第四版诊断工作台 · Build 8\nAuthor / Maintainer: MoWang\n已加载模块不是已证实根因；实测案例只是用户记录。" forKey:@"footerText"]; [items addObject:about];
        PSSpecifier *refresh=[PSSpecifier preferenceSpecifierNamed:@"重新扫描" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        refresh.buttonAction=@selector(reloadNow:);
        [items addObject:refresh];
        _specifiers=[items mutableCopy];
    }
    return _specifiers;
}

- (void)viewDidLoad { [super viewDidLoad]; self.title=@"分析日志"; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [_specifiers release]; _specifiers=nil; [self reloadSpecifiers]; }
- (void)reloadNow:(PSSpecifier *)specifier {
    (void)specifier;
    [_specifiers release]; _specifiers=nil;
    [self reloadSpecifiers];
}

@end
