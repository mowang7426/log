#import "CAReportViewController.h"
#import "CAAI.h"
#import "CALogStore.h"
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>

@implementation CAReportViewController

// Resolve category when rendering, regardless of how Preferences constructs us.
- (NSString *)reportCategory { return nil; }

- (void)setSpecifier:(PSSpecifier *)specifier {
    [super setSpecifier:specifier];
    _specifiers=nil;
}

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
}
- (void)setSpecifier:(PSSpecifier *)specifier {
    [super setSpecifier:specifier];
    _report=nil;
    _specifiers=nil;
}
- (instancetype)initWithSpecifier:(PSSpecifier *)specifier {
    self=[super init];
    if (self) self.specifier=specifier;
    return self;
}
- (id)specifiers {
    if (!_specifiers) {
        NSString *path=[self.specifier propertyForKey:@"reportPath"];
        _report=[[CALogStore sharedStore] reportAtPath:path];
        if (!_report) {
            self.title=@"日志读取失败";
            NSString *message=([path isKindOfClass:[NSString class]] && path.length)
                ? [NSString stringWithFormat:@"无法读取日志，文件可能已删除或没有访问权限：%@",path]
                : @"未收到所选日志的完整路径，请返回列表重新进入。";
            _specifiers=[NSMutableArray arrayWithObject:[PSSpecifier preferenceSpecifierNamed:message target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
            return _specifiers;
        }
        self.title=_report[@"procName"] ?: _report[@"app_name"] ?: @"日志详情";
        NSMutableArray *rows=[NSMutableArray array];
        NSDictionary *r=_report;
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"分析结论" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        NSString *diagnosis=r[@"diagnosis"] ?: @"暂无诊断";
        PSSpecifier *analysis=[PSSpecifier preferenceSpecifierNamed:@"查看完整分析结论" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        [analysis setProperty:diagnosis forKey:@"analysisText"];
        analysis.buttonAction=@selector(showAnalysis:);
        [rows addObject:analysis];
        PSSpecifier *ai=[PSSpecifier preferenceSpecifierNamed:@"AI 分析此日志" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        ai.buttonAction=@selector(analyzeWithAI:);
        [rows addObject:ai];
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"崩溃现场" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        NSArray *scene=@[
            @[@"触发方式",r[@"normalizedExceptionType"] ?: @"未知"],
            @[@"异常信号",r[@"normalizedSignal"] ?: @"未知"],
            @[@"异常代码",r[@"normalizedCodes"] ?: @"未知"],
            @[@"故障线程",r[@"normalizedFaultingThread"] ?: @"未知"]
        ];
        for (NSArray *f in scene) [rows addObject:[PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"%@：%@",f[0],f[1]] target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"基本信息" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        NSArray *basic=@[
            @[@"进程",r[@"normalizedProcessName"] ?: @"未知"],
            @[@"Bundle ID",r[@"normalizedBundleID"] ?: @"未知"],
            @[@"进程 ID",r[@"normalizedPID"] ?: @"未知"],
            @[@"报告类型",r[@"bug_type"] ?: @"未知"],
            @[@"版本",r[@"app_version"] ?: r[@"build_version"] ?: @"未知"],
            @[@"系统版本",r[@"normalizedSystemVersion"] ?: @"未知"],
            @[@"崩溃时间",r[@"timestamp"] ?: r[@"captureTime"] ?: @"未知"],
            @[@"事件 ID",r[@"incident_id"] ?: @"未知"],
            @[@"线程数",r[@"normalizedThreadCount"] ?: @0],
            @[@"镜像数",r[@"normalizedImageCount"] ?: @0],
            @[@"文件",r[@"fileName"] ?: @"未知"]
        ];
        for (NSArray *f in basic) [rows addObject:[PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"%@：%@",f[0],f[1]] target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
        PSSpecifier *more=[PSSpecifier preferenceSpecifierNamed:@"更多详情" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        more.buttonAction=@selector(showMoreDetails:);
        [rows addObject:more];
        PSSpecifier *source=[PSSpecifier preferenceSpecifierNamed:@"查看源文件" target:nil set:nil get:nil detail:[CAReportSourceController class] cell:PSLinkCell edit:nil];
        [source setProperty:r[@"path"] ?: @"" forKey:@"reportPath"];
        [rows addObject:source];
        _specifiers=[rows mutableCopy];
    }
    return _specifiers;
}
- (void)showMoreDetails:(PSSpecifier *)specifier {
    (void)specifier;
    NSDictionary *r=_report ?: @{};
    NSDictionary *e=[r[@"exception"] isKindOfClass:[NSDictionary class]] ? r[@"exception"] : @{};
    NSDictionary *t=[r[@"termination"] isKindOfClass:[NSDictionary class]] ? r[@"termination"] : @{};
    NSMutableArray *parts=[NSMutableArray array];
    void (^add)(NSString *,id)=^(NSString *label,id value){ if (value && value != [NSNull null]) [parts addObject:[NSString stringWithFormat:@"%@：%@",label,value]]; };
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
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"更多详情" message:text preferredStyle:UIAlertControllerStyleAlert];
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
    NSDate *started=[NSDate date];
    __block BOOL cancelled=NO;
    __block NSTimer *timer=nil;
    UIAlertController *loading=[UIAlertController alertControllerWithTitle:@"AI 分析中" message:@"准备请求…\n阶段：准备数据" preferredStyle:UIAlertControllerStyleAlert];
    [loading addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a){ cancelled=YES; [timer invalidate]; }]];
    [self presentViewController:loading animated:YES completion:nil];
    timer=[NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t){
        if (cancelled) return;
        NSTimeInterval elapsed=[[NSDate date] timeIntervalSinceDate:started];
        loading.message=[NSString stringWithFormat:@"已用时 %.0f 秒\n阶段：等待模型响应\n网络请求仍在进行，请勿重复点击",elapsed];
    }];
    BOOL include=[[NSUserDefaults standardUserDefaults] boolForKey:@"CAAIIncludeSource"];
    [[CAAIService shared] analyzeReport:_report includeSource:include completion:^(NSString *result,NSError *error){
        [timer invalidate];
        if (cancelled) return;
        [loading dismissViewControllerAnimated:YES completion:^{
            NSString *title=error ? @"AI 分析失败" : @"AI 分析结果";
            NSString *text=error.localizedDescription ?: result ?: @"模型没有返回结果。";
            UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:text preferredStyle:UIAlertControllerStyleAlert];
            if (!error) [alert addAction:[UIAlertAction actionWithTitle:@"复制" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ [UIPasteboard generalPasteboard].string=text; }]];
            [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }];
    }];
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
        NSString *text=data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"无法读取源文件。";
        NSMutableArray *rows=[NSMutableArray array];
        PSSpecifier *copy=[PSSpecifier preferenceSpecifierNamed:@"复制源文件" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        copy.buttonAction=@selector(copySource);
        [rows addObject:copy];
        PSSpecifier *share=[PSSpecifier preferenceSpecifierNamed:@"分享源文件" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        share.buttonAction=@selector(shareSource);
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
- (void)copySource {
    NSString *path=[self.specifier propertyForKey:@"reportPath"];
    NSData *data=[NSData dataWithContentsOfFile:path options:0 error:nil];
    [UIPasteboard generalPasteboard].string=data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
}
- (void)shareSource {
    NSString *path=[self.specifier propertyForKey:@"reportPath"];
    if (!path.length) return;
    NSString *dst=[NSTemporaryDirectory() stringByAppendingPathComponent:path.lastPathComponent ?: @"report.ips"];
    [[NSFileManager defaultManager] removeItemAtPath:dst error:nil];
    if (![[NSFileManager defaultManager] copyItemAtPath:path toPath:dst error:nil]) return;
    UIActivityViewController *vc=[[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:dst]] applicationActivities:nil];
    [self presentViewController:vc animated:YES completion:nil];
}
@end
