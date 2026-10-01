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
        NSArray *fields=@[
            @[@"进程",r[@"procName"] ?: r[@"app_name"] ?: @"未知"],
            @[@"分类",r[@"category"] ?: @"其他"],
            @[@"时间",r[@"timestamp"] ?: r[@"captureTime"] ?: @"未知"],
            @[@"异常",e[@"type"] ?: @"未知"],
            @[@"诊断",r[@"diagnosis"] ?: @"暂无诊断"],
            @[@"文件",r[@"fileName"] ?: @"未知"]
        ];
                PSSpecifier *source=[PSSpecifier preferenceSpecifierNamed:@"查看源文件" target:nil set:nil get:nil detail:[CAReportSourceController class] cell:PSLinkCell edit:nil];
                [source setProperty:r[@"path"] ?: @"" forKey:@"reportPath"];
                [rows addObject:source];
                for (NSArray *f in fields) [rows addObject:[PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"%@：%@",f[0],f[1]] target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
        _specifiers=[rows mutableCopy];
    }
    return _specifiers;
}
- (void)viewDidLoad { [super viewDidLoad]; self.title=_report[@"procName"] ?: _report[@"app_name"] ?: @"日志详情"; }
@end

@interface CAReportSourceController () <UITextViewDelegate>
@property(nonatomic,strong) NSString *sourcePath;
@property(nonatomic,strong) UITextView *textView;
@end
@implementation CAReportSourceController
- (instancetype)initWithSpecifier:(PSSpecifier *)specifier {
    self=[super init];
    if (self) {
        self.specifier=specifier;
        _sourcePath=[[specifier propertyForKey:@"reportPath"] copy];
        self.title=_sourcePath.lastPathComponent ?: @"源文件";
    }
    return self;
}
- (id)specifiers { return [NSMutableArray array]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=[UIColor systemBackgroundColor];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(shareSource)];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemEdit target:self action:@selector(copySource)];
    _textView=[[UITextView alloc] initWithFrame:self.view.bounds];
    _textView.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    _textView.editable=NO;
    _textView.selectable=YES;
    _textView.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    _textView.backgroundColor=[UIColor systemBackgroundColor];
    [self.view addSubview:_textView];
    NSData *data=[NSData dataWithContentsOfFile:_sourcePath options:0 error:nil];
    NSString *text=data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    _textView.text=text ?: @"无法读取源文件。请确认文件仍存在且插件具有访问权限。";
}
- (void)copySource {
    [UIPasteboard generalPasteboard].string=_textView.text ?: @"";
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"已复制" message:@"源文件内容已复制到剪贴板。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)shareSource {
    if (!_sourcePath.length) return;
    NSString *name=_sourcePath.lastPathComponent ?: @"report.ips";
    NSString *sharePath=[NSTemporaryDirectory() stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] removeItemAtPath:sharePath error:nil];
    if (![[NSFileManager defaultManager] copyItemAtPath:_sourcePath toPath:sharePath error:nil]) return;
    NSURL *url=[NSURL fileURLWithPath:sharePath];
    UIActivityViewController *vc=[[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    vc.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;
    [self presentViewController:vc animated:YES completion:nil];
}
@end
