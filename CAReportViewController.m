#import "CAReportViewController.h"
#import "CACaseStore.h"
#import "CAAI.h"
#import "CAWorkbenchController.h"
#import "CALogStore.h"
#import "CAEvidenceUI.h"
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>

// Detail text wraps to the available width; never truncate the stored value.
@interface CAWrappingTextCell : PSTableCell
@end
@implementation CAWrappingTextCell
- (void)layoutSubviews {
    [super layoutSubviews];
    UILabel *label=self.titleLabel ?: self.textLabel;
    label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    label.adjustsFontForContentSizeCategory=YES;
    label.textColor=[UIColor labelColor];
    label.numberOfLines=0;
    label.lineBreakMode=NSLineBreakByCharWrapping;
    label.frame=CGRectMake(16,10,MAX(1,self.contentView.bounds.size.width-32),MAX(1,self.contentView.bounds.size.height-20));
}
@end
static PSSpecifier *CAShortRow(NSString *text) {
    PSSpecifier *row=[PSSpecifier preferenceSpecifierNamed:text ?: @"" target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
    [row setProperty:[CAWrappingTextCell class] forKey:@"cellClass"];
    return row;
}

@implementation CAReportViewController

// Resolve category when rendering, regardless of how Preferences constructs us.
- (NSString *)reportCategory { return nil; }

- (instancetype)initWithSpecifier:(PSSpecifier *)specifier {
    self=[super init];
    if (self) self.specifier=specifier;
    return self;
}

- (id)specifiers {
    if (!_specifiers) {
        NSMutableArray *rows=[NSMutableArray array];
        NSString *category=[self reportCategory];
        NSArray *reports=category.length ? [[CALogStore sharedStore] reportsForCategory:category] : [[CALogStore sharedStore] reports];
        self.title=category ?: @"最近日志";
        {
            PSSpecifier *head=[PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"%@ · %lu 条",self.title,(unsigned long)reports.count] target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
            [head setProperty:@"点击一条日志查看详细分析" forKey:@"footerText"];
            [rows addObject:head];
            for (NSDictionary *r in reports) {
                NSString *name=r[@"fileName"] ?: r[@"procName"] ?: r[@"app_name"] ?: @"未知日志";
                PSSpecifier *item=[PSSpecifier preferenceSpecifierNamed:name target:nil set:nil get:nil detail:[CAReportDetailController class] cell:PSLinkCell edit:nil];
                CAWrapEvidenceRow(item);
                [item setName:[NSString stringWithFormat:@"%@\n%@",name,r[@"timestamp"] ?: @"时间未知"]];
                [item setProperty:r forKey:@"reportSnapshot"];
                [item setProperty:r[@"path"] ?: @"" forKey:@"reportPath"];
                [item setProperty:r[@"category"] ?: @"其他" forKey:@"reportCategory"];
                [item setProperty:[NSString stringWithFormat:@"%@ · %@",r[@"timestamp"] ?: @"时间未知",r[@"diagnosis"] ?: @"暂无摘要"] forKey:@"footerText"];
                [rows addObject:item];
            }
            NSDictionary *scan=CALogStore.sharedStore.scanDiagnostics;
            if (CALogStore.sharedStore.reportsReady && (![scan[@"exists"] boolValue] || [scan[@"error"] length])) [rows addObject:CAShortRow([NSString stringWithFormat:@"扫描错误：%@",[scan[@"error"] length]?scan[@"error"]:@"日志目录不存在或不可访问"])];
            if (!reports.count) [rows addObject:[PSSpecifier preferenceSpecifierNamed:CALogStore.sharedStore.scanInProgress?@"正在后台扫描…":@"扫描完成：没有匹配的日志" target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
        }
        _specifiers=[rows mutableCopy];
    }
    return _specifiers;
}
- (CGFloat)tableView:(UITableView *)t heightForRowAtIndexPath:(NSIndexPath *)i {PSSpecifier *s=[self specifierAtIndexPath:i];return [s propertyForKey:@"cellClass"]==[CAEvidenceWrappingCell class]?CAEvidenceRowHeight(t,s):[super tableView:t heightForRowAtIndexPath:i];}
- (void)viewDidLoad { [super viewDidLoad]; self.title=[self reportCategory] ?: @"分类未绑定"; [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(scanUpdated:) name:CALogStoreDidRefreshNotification object:CALogStore.sharedStore]; }
- (void)viewWillAppear:(BOOL)a {[super viewWillAppear:a];[CALogStore.sharedStore refreshReports];}
- (void)scanUpdated:(NSNotification *)n {(void)n;[_specifiers release];_specifiers=nil;if(self.viewIfLoaded.window)[self reloadSpecifiers];}
- (void)dealloc {[[NSNotificationCenter defaultCenter] removeObserver:self];[super dealloc];}
@end
@implementation CARecentReportsViewController
- (NSString *)reportCategory { return nil; }
@end
@implementation CACrashReportViewController
- (NSString *)reportCategory { return @"崩溃"; }
@end
@implementation CAMemoryReportViewController
- (NSString *)reportCategory { return @"内存"; }
@end
@implementation CARestartReportViewController
- (NSString *)reportCategory { return @"重启"; }
@end
@implementation CAResourceReportViewController
- (NSString *)reportCategory { return @"资源"; }
@end
@implementation CAOtherReportViewController
- (NSString *)reportCategory { return @"其他"; }
@end

@implementation CAReportDetailController {
    NSDictionary *_report;
    NSDictionary *_match;
    NSDictionary *_aiReference;
    NSDictionary *_human;
    NSString *_matchStatus;
    BOOL _loading;
    BOOL _loaded;
}
- (void)copyReportPath:(PSSpecifier *)specifier { (void)specifier;[UIPasteboard generalPasteboard].string=_report[@"path"] ?: [self.specifier propertyForKey:@"reportPath"]; }
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // specifiers are immutable for this controller lifetime; returning must not reread the IPS file.
}
- (void)dealloc { [_report release]; [_match release]; [_aiReference release]; [_human release]; [_matchStatus release]; [super dealloc]; }
- (void)loadReport {
    if (_loading || _loaded) return;
    _loading=YES;
    NSString *path=[self.specifier propertyForKey:@"reportPath"];
    NSDictionary *snapshot=[self.specifier propertyForKey:@"reportSnapshot"];
    // GCD copies both blocks; their captured objects (including self) survive under MRC.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), ^{
        @autoreleasepool {
            NSDictionary *report=snapshot ?: [[CALogStore sharedStore] reportAtPath:path];
            CACaseStore *cases=[CACaseStore sharedStore];
            NSDictionary *match=report ? [cases matchingCaseForReport:report] : nil;
            NSDictionary *aiReference=report ? [cases matchingAIReferenceForReport:report] : nil;
            NSDictionary *human=report ? [[CALogStore sharedStore] humanReadableAnalysisForReport:report] : nil;
            NSString *status=![cases settingEnabled:CAUseHistoricalCases] ? @"历史案例检索已关闭" :
                (![CACaseStore evidenceForReport:report] ? @"证据不足，未检索历史案例" :
                (aiReference ? @"匹配到之前类似日志的 AI 参考（未验证也可查看；不保证本次根因）" : @"没有符合当前采用设置的精确历史案例"));
            dispatch_async(dispatch_get_main_queue(), ^{
                _report=[report retain]; _match=[match retain]; _aiReference=[aiReference retain]; _human=[human retain]; _matchStatus=[status copy];
                _loaded=YES; _loading=NO;
                [_specifiers release]; _specifiers=nil;
                if (self.viewIfLoaded.window) [self reloadSpecifiers];
            });
        }
    });
}
- (instancetype)initWithSpecifier:(PSSpecifier *)specifier {
    self=[super init];
    if (self) self.specifier=specifier;
    return self;
}
- (id)specifiers {
    if (!_specifiers) {
        if (!_loaded) {
            _specifiers=[[NSMutableArray alloc] initWithObjects:CAShortRow(@"正在加载本地分析…"),nil];
            [self loadReport];
            return _specifiers;
        }
        NSString *path=[self.specifier propertyForKey:@"reportPath"];
        if (!_report) {
            self.title=@"日志读取失败";
            NSString *message=([path isKindOfClass:[NSString class]] && path.length)
                ? [NSString stringWithFormat:@"无法读取日志，文件可能已删除或没有访问权限：%@",path]
                : @"未收到所选日志的完整路径，请返回列表重新进入。";
            _specifiers=[[NSMutableArray alloc] initWithObjects:CAShortRow(message),nil];
            return _specifiers;
        }
        self.title=_report[@"procName"] ?: _report[@"app_name"] ?: @"日志详情";
        NSMutableArray *rows=[NSMutableArray array];
        NSDictionary *r=_report;
        NSDictionary *match=_match;
        NSString *matchStatus=_matchStatus;
        NSDictionary *human=_human;
        PSSpecifier *ai=[PSSpecifier preferenceSpecifierNamed:@"AI 分析此日志" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        [ai setProperty:@"先检查发送内容与费用，再由你确认是否请求；取消和历史结果仍可在工作台查看。" forKey:@"footerText"];
        ai.buttonAction=@selector(analyzeWithAI:); [rows addObject:ai];
        PSSpecifier *version=[PSSpecifier preferenceSpecifierNamed:@"本地快速说明" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [version setProperty:@"依据本机日志字段整理；可能原因不是已确认根因。AI 分析需另行确认。" forKey:@"footerText"]; [rows addObject:version];
        // 首屏只保留可执行的结论；原始字段、路径和完整 AI 原文放到下方入口。
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"这次发生了什么" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        [rows addObject:CAShortRow(human[@"title"] ?: @"暂时无法判断退出原因")];
        [rows addObject:CAShortRow(human[@"reason"] ?: @"暂无可读结论")];
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"AI 之前怎么判断" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        if (_aiReference) {
            NSString *answer=_aiReference[@"answer"];
            NSString *preview=[self boundedPreview:answer];
            [rows addObject:CAShortRow(@"这是历史 AI 参考，不是本次已确认根因；不会覆盖本地事实。")];
            [rows addObject:CAShortRow([NSString stringWithFormat:@"原文预览：%@",preview])];
            PSSpecifier *fullAI=[PSSpecifier preferenceSpecifierNamed:@"查看完整 AI 原文" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
            [fullAI setProperty:answer ?: @"暂无内容" forKey:@"aiAnswer"]; fullAI.buttonAction=@selector(showAIAnswer:); [rows addObject:fullAI];
        } else {
            [rows addObject:CAShortRow(matchStatus ?: @"没有符合当前设置的精确历史参考")];
        }
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"现在建议先做什么" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        for (NSString *action in ([human[@"actions"] isKindOfClass:[NSArray class]] ? human[@"actions"] : @[])) [rows addObject:CAShortRow(action)];
        [rows addObject:CAShortRow(human[@"confidence"] ?: @"根因未确认")];
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"是否有相似历史日志" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        NSString *caseFooter=match ? [NSString stringWithFormat:@"找到本地精确匹配（来源：%@；用户实测：%@）。仅供参考，不证明本次根因。",match[@"source"] ?: @"本地案例库",[match[@"confirmed"] boolValue] ? @"有" : @"无"] : (matchStatus ?: @"没有符合当前采用设置的精确历史案例");
        [rows addObject:CAShortRow(caseFooter)];
        if (!match && ![[CACaseStore sharedStore] settingEnabled:CAAutoSaveCases]) [rows addObject:CAShortRow(@"自动保存 AI 参考已关闭；新的 AI 结果不会关联到日志历史。")];
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"详细信息 / 技术证据" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        NSMutableString *full=[NSMutableString stringWithFormat:@"%@\n\n这次发生了什么\n%@\n%@\n\nAI 之前怎么判断\n%@\n\n现在建议先做什么\n%@\n\n判断把握与边界\n%@\n%@\n%@",CAAnalysisVersionTitle,human[@"title"],human[@"reason"],[human[@"evidence"] componentsJoinedByString:@"\n"],[human[@"actions"] componentsJoinedByString:@"\n"],human[@"confidence"],human[@"status"],caseFooter];
        PSSpecifier *analysis=[PSSpecifier preferenceSpecifierNamed:@"查看完整本地说明与证据" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        [analysis setProperty:full forKey:@"analysisText"]; analysis.buttonAction=@selector(showAnalysis:); [rows addObject:analysis];
        PSSpecifier *workbench=[PSSpecifier preferenceSpecifierNamed:@"线程、模块与 AI 请求工作台" target:nil set:nil get:nil detail:[CAWorkbenchController class] cell:PSLinkCell edit:nil];
        [workbench setProperty:r[@"path"] ?: @"" forKey:@"reportPath"]; [rows addObject:workbench];
        PSSpecifier *source=[PSSpecifier preferenceSpecifierNamed:@"查看原始日志文件" target:nil set:nil get:nil detail:[CAReportSourceController class] cell:PSLinkCell edit:nil];
        [source setProperty:r[@"path"] ?: @"" forKey:@"reportPath"]; [rows addObject:source];
        PSSpecifier *copyPath=[PSSpecifier preferenceSpecifierNamed:@"复制原始日志路径" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil]; copyPath.buttonAction=@selector(copyReportPath:); [rows addObject:copyPath];
        PSSpecifier *more=[PSSpecifier preferenceSpecifierNamed:@"查看技术字段、ID 与原始异常" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil]; more.buttonAction=@selector(showMoreDetails:); [rows addObject:more];
        for (PSSpecifier *row in rows) if (row.cellType==PSStaticTextCell) [row setProperty:[CAWrappingTextCell class] forKey:@"cellClass"];
        _specifiers=[rows mutableCopy];
    }
    return _specifiers;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *s=[self specifierAtIndexPath:indexPath];
    if ([s propertyForKey:@"cellClass"] != [CAWrappingTextCell class]) return [super tableView:tableView heightForRowAtIndexPath:indexPath];
    NSString *text=[s name] ?: @"";
    CGFloat width=MAX(1.0,tableView.bounds.size.width-72.0);
    UIFont *font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    CGRect box=[text boundingRectWithSize:CGSizeMake(width,CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading attributes:@{NSFontAttributeName:font} context:nil];
    return MAX(52.0,ceil(box.size.height)+28.0);
}
- (NSString *)boundedPreview:(id)value {
    if (![value isKindOfClass:[NSString class]] || ![(NSString *)value length]) return @"暂无内容";
    NSString *text=(NSString *)value;
    NSUInteger limit=320;
    if (text.length<=limit) return text;
    return [[text substringToIndex:limit] stringByAppendingString:@"\n…已折叠，查看完整 AI 原文。"];
}
- (void)showAIAnswer:(PSSpecifier *)specifier {
    NSString *text=[specifier propertyForKey:@"aiAnswer"] ?: @"暂无内容";
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"完整 AI 原文（历史参考）" message:text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"复制" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ [UIPasteboard generalPasteboard].string=text; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)showMoreDetails:(PSSpecifier *)specifier {
    (void)specifier;
    NSDictionary *r=_report ?: @{};
    NSDictionary *e=[r[@"exception"] isKindOfClass:[NSDictionary class]] ? r[@"exception"] : @{};
    NSDictionary *t=[r[@"termination"] isKindOfClass:[NSDictionary class]] ? r[@"termination"] : @{};
    NSMutableArray *parts=[NSMutableArray array];
    void (^add)(NSString *,id)=^(NSString *label,id value){ if (value && value != [NSNull null]) [parts addObject:[NSString stringWithFormat:@"%@：%@",label,value]]; };
    for (NSString *k in @[@"normalizedBundleID",@"normalizedPID",@"bug_type",@"app_version",@"normalizedSystemVersion",@"incident_id",@"normalizedThreadCount",@"normalizedImageCount",@"fileName"]) add(k,r[k]);
    add(@"原始异常类型",e[@"type"] ?: @"未知");
    add(@"原始信号",e[@"signal"] ?: @"未知");
    add(@"异常子类型",e[@"subtype"] ?: @"未知");
    add(@"异常地址",e[@"address"] ?: @"未知");
    add(@"异常代码",e[@"codes"] ?: @"未知");
    add(@"终止代码",t[@"code"] ?: @"未知");
    add(@"终止来源",t[@"byProc"] ?: @"未知");
    add(@"终止说明",t[@"indicator"] ?: @"未知");
    add(@"进程角色",r[@"procRole"] ?: @"未知");
    add(@"运行状态",r[@"coalitionID"] ? [NSString stringWithFormat:@"coalition %@",r[@"coalitionID"]] : @"未知");
    add(@"原始故障线程",r[@"faultingThread"] ?: @"未知");
    NSString *text=[parts componentsJoinedByString:@"\n"];
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"技术详情" message:text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"复制" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ [UIPasteboard generalPasteboard].string=text; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)showAnalysis:(PSSpecifier *)specifier {
    NSString *text=[specifier propertyForKey:@"analysisText"] ?: @"暂无分析结论";
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"完整分析结论" message:text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"复制" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ [UIPasteboard generalPasteboard].string=text; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)analyzeWithAI:(PSSpecifier *)specifier {
    (void)specifier;
    PSSpecifier *s=[PSSpecifier preferenceSpecifierNamed:@"第四版诊断工作台" target:nil set:nil get:nil detail:nil cell:PSLinkCell edit:nil];
    [s setProperty:_report[@"path"] ?: @"" forKey:@"reportPath"];
    CAWorkbenchController *v=[[CAWorkbenchController alloc] initWithSpecifier:s];
    [self.navigationController pushViewController:v animated:YES]; [v release];
}
- (void)viewDidLoad { [super viewDidLoad]; self.title=_report[@"procName"] ?: _report[@"app_name"] ?: @"日志详情"; }
@end

@implementation CAReportSourceController
- (instancetype)initWithSpecifier:(PSSpecifier *)specifier {
    self=[super init];
    if (self) self.specifier=specifier;
    return self;
}
- (id)specifiers {
    if (!_specifiers) {
        NSString *path=[self.specifier propertyForKey:@"reportPath"];
        NSData *data=[NSData dataWithContentsOfFile:path options:0 error:nil];
        NSString *text=data ? [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease] : @"无法读取源文件。";
        NSMutableArray *rows=[NSMutableArray array];
        PSSpecifier *copy=[PSSpecifier preferenceSpecifierNamed:@"复制源文件" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        copy.buttonAction=@selector(copySource:);
        [rows addObject:copy];
        PSSpecifier *share=[PSSpecifier preferenceSpecifierNamed:@"分享源文件" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        share.buttonAction=@selector(shareSource:);
        [rows addObject:share];
        NSArray *lines=[text componentsSeparatedByString:@"\n"];
        for (NSString *lineText in lines) {
            if (!lineText.length) { [rows addObject:[PSSpecifier preferenceSpecifierNamed:@" " target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]]; continue; }
            for (NSUInteger i=0; i<lineText.length; i+=96) {
                NSUInteger n=MIN((NSUInteger)96,lineText.length-i);
                NSString *part=[lineText substringWithRange:NSMakeRange(i,n)];
                [rows addObject:[PSSpecifier preferenceSpecifierNamed:part target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
            }
        }
        _specifiers=[rows mutableCopy];
        self.title=path.lastPathComponent ?: @"源文件";
    }
    return _specifiers;
}
- (void)copySource:(PSSpecifier *)specifier {
    (void)specifier;
    NSString *path=[self.specifier propertyForKey:@"reportPath"];
    NSData *data=[NSData dataWithContentsOfFile:path options:0 error:nil];
    [UIPasteboard generalPasteboard].string=data ? [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease] : @"";
}
- (void)shareSource:(PSSpecifier *)specifier {
    (void)specifier;
    NSString *path=[self.specifier propertyForKey:@"reportPath"];
    if (!path.length) return;
    NSString *dst=[NSTemporaryDirectory() stringByAppendingPathComponent:path.lastPathComponent ?: @"report.ips"];
    [[NSFileManager defaultManager] removeItemAtPath:dst error:nil];
    if (![[NSFileManager defaultManager] copyItemAtPath:path toPath:dst error:nil]) return;
    UIActivityViewController *vc=[[[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:dst]] applicationActivities:nil] autorelease];
    [self presentViewController:vc animated:YES completion:nil];
}
@end
