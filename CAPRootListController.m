#import "CAPRootListController.h"
#import "CALearningController.h"
#import "CAAI.h"
#import "CAWorkbenchController.h"
#import "CALogStore.h"
#import "CAReportViewController.h"
#import "CAConflictController.h"
#import "CAPluginEvidence.h"
#import "CAEvidenceUI.h"
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>

@interface CAAdvancedToolsController : PSListController
@end
@implementation CAAdvancedToolsController
- (id)specifiers {
    if (!_specifiers) {
        NSMutableArray *items=[NSMutableArray array];
        NSArray *reports=[CALogStore sharedStore].reports;
        PSSpecifier *g=[PSSpecifier preferenceSpecifierNamed:@"高级诊断/高级工具" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [g setProperty:@"以下信息面向需要进一步核对的用户；证据相关不代表确定根因。" forKey:@"footerText"]; [items addObject:g];
        NSArray *conflicts=[CAConflictController summaryForReports:reports limit:3];
        if (conflicts.count) for (NSDictionary *s in conflicts) {
            PSSpecifier *row=[PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"%@\n%@ · 相关报告 %@",s[@"name"],[CAPluginEvidence tierLabel:s[@"tier"]],s[@"participation"]] target:nil set:nil get:nil detail:[CAConflictDetailController class] cell:PSLinkCell edit:nil];
            [row setProperty:s forKey:@"conflictStats"]; [items addObject:row];
        }
        PSSpecifier *all=[PSSpecifier preferenceSpecifierNamed:@"查看全部疑似冲突插件" target:nil set:nil get:nil detail:[CAConflictController class] cell:PSLinkCell edit:nil]; [items addObject:all];
        NSDictionary *d=[CALogStore sharedStore].scanDiagnostics;
        [items addObject:[PSSpecifier preferenceSpecifierNamed:@"扫描状态" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        [items addObject:[PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"%@ · 发现 %@ 个 · 解析 %@ 个",[d[@"exists"] boolValue]?@"日志目录可访问":@"日志目录不可访问",d[@"matched"]?:@0,d[@"parsed"]?:@0] target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
        [items addObject:[PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"最后扫描：%@\n新增/变化 %@ · 复用 %@ · 移除 %@\n%@",d[@"lastScannedAt"]?:@"尚未扫描",d[@"changed"]?:@0,d[@"reused"]?:@0,d[@"removed"]?:@0,d[@"error"]?:@""] target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
        [items addObject:[PSSpecifier preferenceSpecifierNamed:@"诊断工作台" target:nil set:nil get:nil detail:[CAWorkbenchController class] cell:PSLinkCell edit:nil]];
        PSSpecifier *about=[PSSpecifier preferenceSpecifierNamed:@"版本与说明" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [about setProperty:@"MoWang · 已加载模块和案例均不等于已证实根因。" forKey:@"footerText"]; [items addObject:about];
        _specifiers=[items mutableCopy];
    } return _specifiers;
}
@end

@implementation CAPRootListController
- (id)specifiers {
    if (!_specifiers) {
        NSMutableArray *items=[NSMutableArray array];
        NSArray *reports=[CALogStore sharedStore].reports;
        PSSpecifier *head=[PSSpecifier preferenceSpecifierNamed:@"CrashAnalyzer · AI 日志分析" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [head setProperty:@"本地解析只描述日志证据，不会确认根因；AI 分析需你确认请求。" forKey:@"footerText"]; [items addObject:head];
        PSSpecifier *recent=[PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"最近日志 · %lu 条",(unsigned long)reports.count] target:nil set:nil get:nil detail:[CARecentReportsViewController class] cell:PSLinkCell edit:nil];
        [recent setProperty:@"查看最近扫描到的各类日志，选择一条查看说明或进行 AI 分析。" forKey:@"footerText"]; [items addObject:recent];
        PSSpecifier *local=[PSSpecifier preferenceSpecifierNamed:@"本地快速说明" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [local setProperty:@"根据本机已有日志字段整理现象、可能原因和下一步；不上传数据。" forKey:@"footerText"]; [items addObject:local];
        PSSpecifier *quick=[PSSpecifier preferenceSpecifierNamed:@"按类型查看日志" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]; [items addObject:quick];
        for (NSString *category in @[@"崩溃",@"内存",@"重启",@"资源",@"其他"]) {
            NSUInteger count=0; for (NSDictionary *r in reports) if ([r[@"category"] isEqualToString:category]) count++;
            Class cls=[category isEqualToString:@"崩溃"]?[CACrashReportViewController class]:([category isEqualToString:@"内存"]?[CAMemoryReportViewController class]:([category isEqualToString:@"重启"]?[CARestartReportViewController class]:([category isEqualToString:@"资源"]?[CAResourceReportViewController class]:[CAOtherReportViewController class])));
            PSSpecifier *row=[PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"%@ · %lu",category,(unsigned long)count] target:nil set:nil get:nil detail:cls cell:PSLinkCell edit:nil]; [row setProperty:category forKey:@"category"]; [items addObject:row];
        }
        [items addObject:[PSSpecifier preferenceSpecifierNamed:@"AI 分析" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        PSSpecifier *ai=[PSSpecifier preferenceSpecifierNamed:@"AI 分析配置" target:nil set:nil get:nil detail:[CAAIConfigController class] cell:PSLinkCell edit:nil]; [items addObject:ai];
        [items addObject:[PSSpecifier preferenceSpecifierNamed:@"AI 分析历史与结果" target:nil set:nil get:nil detail:[CAHistoryController class] cell:PSLinkCell edit:nil]];
        PSSpecifier *learn=[PSSpecifier preferenceSpecifierNamed:@"学习与案例" target:nil set:nil get:nil detail:[CALearningController class] cell:PSLinkCell edit:nil]; [items addObject:learn];
        PSSpecifier *advanced=[PSSpecifier preferenceSpecifierNamed:@"高级诊断/高级工具" target:nil set:nil get:nil detail:[CAAdvancedToolsController class] cell:PSLinkCell edit:nil];
        [advanced setProperty:@"插件证据、线程与模块、工作台及扫描技术信息。" forKey:@"footerText"]; [items addObject:advanced];
        PSSpecifier *refresh=[PSSpecifier preferenceSpecifierNamed:@"重新扫描日志" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil]; refresh.buttonAction=@selector(reloadNow:); [items addObject:refresh];
        _specifiers=[items mutableCopy];
    } return _specifiers;
}
- (CGFloat)tableView:(UITableView *)t heightForRowAtIndexPath:(NSIndexPath *)i { PSSpecifier *s=[self specifierAtIndexPath:i]; return [s propertyForKey:@"cellClass"]==[CAEvidenceWrappingCell class]?CAEvidenceRowHeight(t,s):[super tableView:t heightForRowAtIndexPath:i]; }
- (void)viewDidLoad { [super viewDidLoad]; self.title=@"分析日志"; [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(logStoreDidRefresh:) name:CALogStoreDidRefreshNotification object:[CALogStore sharedStore]; if (![CALogStore sharedStore].reportsReady) [[CALogStore sharedStore] refreshReports]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; if (!_specifiers) [self reloadSpecifiers]; [[CALogStore sharedStore] refreshReports]; }
- (void)logStoreDidRefresh:(NSNotification *)note { (void)note; [_specifiers release]; _specifiers=nil; if (self.viewIfLoaded.window) [self reloadSpecifiers]; }
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; [super dealloc]; }
- (void)reloadNow:(PSSpecifier *)specifier { (void)specifier; [[CALogStore sharedStore] refreshReports]; }
@end
