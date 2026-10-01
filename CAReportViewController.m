#import "CAReportViewController.h"
#import "CACaseStore.h"
#import "CAAI.h"
#import "CAWorkbenchController.h"
#import "CALogStore.h"
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
    label.lineBreakMode=NSLineBreakByWordWrapping;
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
        NSArray *reports=category.length ? [[CALogStore sharedStore] reportsForCategory:category] : @[];
        self.title=category ?: @"分类未绑定";
        {
            PSSpecifier *head=[PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"%@ · %lu 条",self.title,(unsigned long)reports.count] target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
            [head setProperty:@"点击一条日志查看详细分析" forKey:@"footerText"];
            [rows addObject:head];
            for (NSDictionary *r in reports) {
                NSString *name=r[@"fileName"] ?: r[@"procName"] ?: r[@"app_name"] ?: @"未知日志";
                PSSpecifier *item=[PSSpecifier preferenceSpecifierNamed:name target:nil set:nil get:nil detail:[CAReportDetailController class] cell:PSLinkCell edit:nil];
                [item setProperty:r forKey:@"reportSnapshot"];
                [item setProperty:r[@"path"] ?: @"" forKey:@"reportPath"];
                [item setProperty:r[@"category"] ?: @"其他" forKey:@"reportCategory"];
                [item setProperty:[NSString stringWithFormat:@"%@ · %@",r[@"timestamp"] ?: @"时间未知",r[@"diagnosis"] ?: @"暂无摘要"] forKey:@"footerText"];
                [rows addObject:item];
            }
            if (!reports.count) [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"没有匹配的日志" target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
        }
        _specifiers=[rows mutableCopy];
    }
    return _specifiers;
}
- (void)viewDidLoad { [super viewDidLoad]; self.title=[self reportCategory] ?: @"分类未绑定"; }
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
    NSDictionary *_human;
    NSString *_matchStatus;
    BOOL _loading;
    BOOL _loaded;
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // specifiers are immutable for this controller lifetime; returning must not reread the IPS file.
}
- (void)dealloc { [_report release]; [_match release]; [_human release]; [_matchStatus release]; [super dealloc]; }
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
            NSDictionary *human=report ? [[CALogStore sharedStore] humanReadableAnalysisForReport:report] : nil;
            NSString *status=![cases settingEnabled:CAUseHistoricalCases] ? @"历史案例检索已关闭" :
                (![CACaseStore evidenceForReport:report] ? @"证据不足，未检索历史案例" :
                (match ? ([match[@"confirmed"] boolValue] ? @"匹配到有用户实测记录的历史 AI 参考（不保证本次根因）" : @"匹配到未验证 AI 参考（已关闭仅实测限制）") : @"没有符合当前采用设置的精确历史案例"));
            dispatch_async(dispatch_get_main_queue(), ^{
                _report=[report retain]; _match=[match retain]; _human=[human retain]; _matchStatus=[status copy];
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
            _specifiers=[[NSMutableArray alloc] initWithObjects:[PSSpecifier preferenceSpecifierNamed:message target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil],nil];
            return _specifiers;
        }
        self.title=_report[@"procName"] ?: _report[@"app_name"] ?: @"日志详情";
        NSMutableArray *rows=[NSMutableArray array];
        NSDictionary *r=_report;
        NSDictionary *match=_match;
        NSString *matchStatus=_matchStatus;
        NSDictionary *human=_human;
        PSSpecifier *version=[PSSpecifier preferenceSpecifierNamed:@"本地分析" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [version setProperty:@"仅依据本地日志字段生成；不触发网络，根因仍需核对。" forKey:@"footerText"]; [rows addObject:version];
        NSArray *readableGroups=@[@[@"为什么会退出",@[human[@"title"],human[@"reason"]]], @[@"判断依据",human[@"evidence"]], @[@"建议处理",human[@"actions"]], @[@"结论状态",@[human[@"confidence"]]]];
        for (NSArray *groupData in readableGroups) {
            [rows addObject:[PSSpecifier preferenceSpecifierNamed:groupData[0] target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
            for (NSString *text in groupData[1]) [rows addObject:CAShortRow(text)];
        }
        NSString *caseFooter=match ? [NSString stringWithFormat:@"本地案例：%@；用户实测：%@。仅本机匹配，不触发网络；不证明本次根因。",match[@"source"] ?: @"本地案例库",[match[@"confirmed"] boolValue] ? @"是" : @"否"] : matchStatus;
        [rows addObject:CAShortRow(matchStatus)];
        if (match) {
            [rows addObject:CAShortRow([NSString stringWithFormat:@"本地案例来源：%@",match[@"source"] ?: @"未知"])];
            [rows addObject:CAShortRow([NSString stringWithFormat:@"用户实测：%@（非本次根因保证）",[match[@"confirmed"] boolValue] ? @"是" : @"否"])];
        }
        NSMutableString *full=[NSMutableString stringWithFormat:@"%@\n\n为什么会退出\n%@\n%@\n\n判断依据\n%@\n\n建议处理\n%@\n\n结论状态\n%@\n%@\n%@",CAAnalysisVersionTitle,human[@"title"],human[@"reason"],[human[@"evidence"] componentsJoinedByString:@"\n"],[human[@"actions"] componentsJoinedByString:@"\n"],human[@"confidence"],human[@"status"],caseFooter];
        if (match) [full appendFormat:@"\n案例 ID：%@\n用户实测记录：%@\n历史 AI 参考（非本次已确认根因）：%@",match[@"id"],match[@"testNote"] ?: @"无",match[@"answer"] ?: @"无"];
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"分析操作" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        [full appendFormat:@"\n\n底层本地分析 / 既有参考\n%@",r[@"diagnosis"] ?: @"暂无诊断"];
        PSSpecifier *analysis=[PSSpecifier preferenceSpecifierNamed:@"查看完整本地分析" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        [analysis setProperty:full forKey:@"analysisText"]; analysis.buttonAction=@selector(showAnalysis:); [rows addObject:analysis];
        PSSpecifier *workbench=[PSSpecifier preferenceSpecifierNamed:@"诊断工作台" target:nil set:nil get:nil detail:[CAWorkbenchController class] cell:PSLinkCell edit:nil];
        [workbench setProperty:r[@"path"] ?: @"" forKey:@"reportPath"]; [rows addObject:workbench];
        PSSpecifier *ai=[PSSpecifier preferenceSpecifierNamed:@"AI 分析此日志（预检）" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        ai.buttonAction=@selector(analyzeWithAI:); [rows addObject:ai];
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"报告概览" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        for (NSArray *f in @[@[@"应用",r[@"normalizedProcessName"] ?: @"未提供"],@[@"时间",r[@"timestamp"] ?: r[@"captureTime"] ?: @"未提供"],@[@"类型",r[@"category"] ?: @"其他"]]) [rows addObject:CAShortRow([NSString stringWithFormat:@"%@：%@",f[0],f[1]])];
        PSSpecifier *more=[PSSpecifier preferenceSpecifierNamed:@"技术详情" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        more.buttonAction=@selector(showMoreDetails:);
        [rows addObject:more];
        PSSpecifier *source=[PSSpecifier preferenceSpecifierNamed:@"查看源文件" target:nil set:nil get:nil detail:[CAReportSourceController class] cell:PSLinkCell edit:nil];
        [source setProperty:r[@"path"] ?: @"" forKey:@"reportPath"];
        [rows addObject:source];
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
