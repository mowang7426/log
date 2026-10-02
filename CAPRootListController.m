#import "CAPRootListController.h"
#import "CALearningController.h"
#import "CAAI.h"
#import "CAWorkbenchController.h"
#import "CALogStore.h"
#import "CAReportViewController.h"
#import "CAConflictController.h"
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>

@implementation CAPRootListController

- (id)specifiers {
    if (!_specifiers) {
        NSMutableArray *items=[NSMutableArray array];
        NSArray *reports=[[CALogStore sharedStore] reports];
        PSSpecifier *intro=[PSSpecifier preferenceSpecifierNamed:@"日志分类" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
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
            PSSpecifier *row=[PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"%@ · %lu 条",category,(unsigned long)count] target:nil set:nil get:nil detail:detailClass cell:PSLinkCell edit:nil];
            [row setProperty:[NSString stringWithFormat:@"%lu 条日志",(unsigned long)count] forKey:@"footerText"];
            [row setProperty:category forKey:@"category"];
            [row setProperty:@YES forKey:@"isController"];
            [items addObject:row];
        }

        NSArray *conflicts=[CAConflictController summaryForReports:reports limit:3];
        PSSpecifier *conflictGroup=[PSSpecifier preferenceSpecifierNamed:@"疑似冲突插件" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [conflictGroup setProperty:@"按故障线程证据排序；仅供排查，不等于确定根因。" forKey:@"footerText"]; [items addObject:conflictGroup];
        if (conflicts.count) {
            for (NSDictionary *s in conflicts) {
                NSUInteger main=[s[@"main"] unsignedIntegerValue], part=[s[@"participation"] unsignedIntegerValue];
                NSString *label=[NSString stringWithFormat:@"%@ · %@ %lu 次 · 参与 %lu 次",s[@"name"],main?@"主嫌疑":@"参与",(unsigned long)(main?:part),(unsigned long)part];
                [items addObject:[PSSpecifier preferenceSpecifierNamed:label target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
            }
        } else {
            [items addObject:[PSSpecifier preferenceSpecifierNamed:@"正在等待日志扫描结果…" target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
        }
        PSSpecifier *allConflicts=[PSSpecifier preferenceSpecifierNamed:@"查看全部疑似冲突插件" target:nil set:nil get:nil detail:[CAConflictController class] cell:PSLinkCell edit:nil]; [items addObject:allConflicts];

        NSDictionary *diagnostics=[[CALogStore sharedStore] scanDiagnostics];
        PSSpecifier *status=[PSSpecifier preferenceSpecifierNamed:@"扫描状态" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [status setProperty:@"CrashReporter 目录与解析器状态" forKey:@"footerText"];
        [items addObject:status];
        NSString *line=[[CALogStore sharedStore] reportsReady] ? [NSString stringWithFormat:@"%@ · 发现 %@ 个 IPS · 解析 %@ 个", [diagnostics[@"exists"] boolValue] ? @"目录可访问" : @"目录不可访问", diagnostics[@"matched"] ?: @0, diagnostics[@"parsed"] ?: @0] : @"正在后台扫描日志…";
        [items addObject:[PSSpecifier preferenceSpecifierNamed:line target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];

        [items addObject:[PSSpecifier preferenceSpecifierNamed:@"工具与设置" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        PSSpecifier *learning=[PSSpecifier preferenceSpecifierNamed:@"本地学习与案例库" target:nil set:nil get:nil detail:[CALearningController class] cell:PSLinkCell edit:nil];
        [items addObject:learning];

        PSSpecifier *ai=[PSSpecifier preferenceSpecifierNamed:@"AI 分析配置" target:nil set:nil get:nil detail:[CAAIConfigController class] cell:PSLinkCell edit:nil];
        [items addObject:ai];

        [items addObject:[PSSpecifier preferenceSpecifierNamed:@"AI 分析历史" target:nil set:nil get:nil detail:[CAHistoryController class] cell:PSLinkCell edit:nil]];
        PSSpecifier *about=[PSSpecifier preferenceSpecifierNamed:@"关于 · CrashAnalyzer 1.1.3" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [about setProperty:@"第四版诊断工作台 · Build 10\nAuthor / Maintainer: MoWang\n已加载模块不是已证实根因；实测案例只是用户记录。" forKey:@"footerText"]; [items addObject:about];
        PSSpecifier *refresh=[PSSpecifier preferenceSpecifierNamed:@"重新扫描" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        refresh.buttonAction=@selector(reloadNow:);
        [items addObject:refresh];
        _specifiers=[items mutableCopy];
    }
    return _specifiers;
}

- (void)viewDidLoad { [super viewDidLoad]; self.title=@"分析日志"; [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(logStoreDidRefresh:) name:CALogStoreDidRefreshNotification object:[CALogStore sharedStore]]; if (![[CALogStore sharedStore] reportsReady]) [[CALogStore sharedStore] refreshReports]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; if (!_specifiers) [self reloadSpecifiers]; if (![[CALogStore sharedStore] reportsReady]) [[CALogStore sharedStore] refreshReports]; }
- (void)logStoreDidRefresh:(NSNotification *)note { (void)note; [_specifiers release]; _specifiers=nil; if (self.viewIfLoaded.window) [self reloadSpecifiers]; }
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; [super dealloc]; }
- (void)reloadNow:(PSSpecifier *)specifier {
    (void)specifier;
    [[CALogStore sharedStore] refreshReports];
}

@end
