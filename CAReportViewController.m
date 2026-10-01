#import "CAReportViewController.h"
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

- (void)openReport:(PSSpecifier *)specifier {
    NSString *path=[specifier propertyForKey:@"reportPath"];
    NSDictionary *report=[[CALogStore sharedStore] reportAtPath:path];
    if (![report isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *exception=report[@"exception"];
    NSString *exceptionType=[exception isKindOfClass:[NSDictionary class]] ? (exception[@"type"] ?: @"未知") : @"未知";
    NSString *message=[NSString stringWithFormat:@"分类：%@\n时间：%@\n异常：%@\n\n%@\n\n文件：%@", report[@"category"] ?: @"其他", report[@"timestamp"] ?: @"未知", exceptionType, report[@"diagnosis"] ?: @"暂无诊断", report[@"fileName"] ?: @"未知"];
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:report[@"procName"] ?: report[@"app_name"] ?: @"日志详情" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
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
        NSDictionary *e=[r[@"exception"] isKindOfClass:[NSDictionary class]] ? r[@"exception"] : @{};
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"分析结论" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        NSString *diagnosis=r[@"diagnosis"] ?: @"暂无诊断";
        NSString *preview=diagnosis.length>48 ? [[diagnosis substringToIndex:48] stringByAppendingString:@"…"] : diagnosis;
        PSSpecifier *analysis=[PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"分析结论：%@",preview] target:nil set:nil get:nil detail:[CAAnalysisController class] cell:PSLinkCell edit:nil];
        [analysis setProperty:diagnosis forKey:@"analysisText"];
        [rows addObject:analysis];
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
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"异常信息" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        NSArray *exceptionInfo=@[
            @[@"原始异常类型",e[@"type"] ?: @"未知"],
            @[@"原始信号",e[@"signal"] ?: @"未知"],
            @[@"异常子类型",e[@"subtype"] ?: @"未知"],
            @[@"异常地址",e[@"address"] ?: @"未知"],
            @[@"终止信息",r[@"termination"] ?: @"未知"]
        ];
        for (NSArray *f in exceptionInfo) [rows addObject:[PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"%@：%@",f[0],f[1]] target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
        PSSpecifier *source=[PSSpecifier preferenceSpecifierNamed:@"查看源文件" target:nil set:nil get:nil detail:[CAReportSourceController class] cell:PSLinkCell edit:nil];
        [source setProperty:r[@"path"] ?: @"" forKey:@"reportPath"];
        [rows addObject:source];
        _specifiers=[rows mutableCopy];
    }
    return _specifiers;
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

@implementation CAAnalysisController
- (instancetype)initWithSpecifier:(PSSpecifier *)specifier {
    self=[super init];
    if (self) self.specifier=specifier;
    return self;
}
- (id)specifiers {
    if (!_specifiers) {
        NSString *text=[self.specifier propertyForKey:@"analysisText"] ?: @"暂无分析结论";
        PSSpecifier *open=[PSSpecifier preferenceSpecifierNamed:@"查看完整分析结论" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        [open setProperty:text forKey:@"analysisText"];
        open.buttonAction=@selector(showAnalysis);
        _specifiers=[NSMutableArray arrayWithObject:open];
        self.title=@"完整分析结论";
    }
    return _specifiers;
}
- (void)showAnalysis {
    NSString *text=[self.specifier propertyForKey:@"analysisText"] ?: @"暂无分析结论";
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"完整分析结论" message:text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"复制" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){ [UIPasteboard generalPasteboard].string=text; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
