#import "CAReportViewController.h"
#import "CALogStore.h"
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>

@implementation CAReportViewController {
    NSString *_category;
    NSDictionary *_singleReport;
}

- (instancetype)initWithSpecifier:(PSSpecifier *)specifier {
    self=[super init];
    if (self) {
        self.specifier=specifier;
        id category=[specifier propertyForKey:@"category"];
        if (![category isKindOfClass:[NSString class]] || ![category length]) category=specifier.name;
        if ([category isKindOfClass:[NSString class]]) {
            NSArray *known=@[@"崩溃",@"内存",@"重启",@"资源",@"其他",@"全部日志"];
            for (NSString *value in known) {
                if ([category hasPrefix:value]) { _category=[value copy]; break; }
            }
        }
        id path=[specifier propertyForKey:@"reportPath"];
        if (![path isKindOfClass:[NSString class]] || ![path length]) path=specifier.properties[@"reportPath"];
        if ([path isKindOfClass:[NSString class]] && [path length]) _singleReport=[[[CALogStore sharedStore] reportAtPath:path] copy];
        if (!_category && [_singleReport[@"category"] isKindOfClass:[NSString class]]) _category=[_singleReport[@"category"] copy];
        if (!_category) _category=@"全部日志";
    }
    return self;
}

- (id)specifiers {
    if (!_specifiers) {
        NSMutableArray *rows=[NSMutableArray array];
        if (_singleReport) {
            NSDictionary *r=_singleReport;
            NSString *exception=([r[@"exception"] isKindOfClass:[NSDictionary class]]) ? (r[@"exception"][@"type"] ?: @"未知") : @"未知";
            NSArray *fields=@[
                @[@"进程",r[@"procName"] ?: r[@"app_name"] ?: @"未知"],
                @[@"分类",r[@"category"] ?: @"其他"],
                @[@"时间",r[@"timestamp"] ?: r[@"captureTime"] ?: @"未知"],
                @[@"异常",exception],
                @[@"诊断",r[@"diagnosis"] ?: @"暂无规则分析"],
                @[@"文件",r[@"fileName"] ?: @"未知"]
            ];
            for (NSArray *f in fields) {
                PSSpecifier *line=[PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"%@：%@",f[0],f[1]] target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
                [rows addObject:line];
            }
        } else {
            NSArray *reports=nil;
            if ([_category isEqualToString:@"全部日志"]) reports=[[CALogStore sharedStore] reports];
            else reports=[[CALogStore sharedStore] reportsForCategory:_category];
            PSSpecifier *head=[PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"%@ · %lu 条",_category,(unsigned long)reports.count] target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
            [head setProperty:@"点击一条日志查看详细分析" forKey:@"footerText"];
            [rows addObject:head];
            for (NSDictionary *r in reports) {
                NSString *name=r[@"procName"] ?: r[@"app_name"] ?: r[@"fileName"] ?: @"未知日志";
                PSSpecifier *item=[PSSpecifier preferenceSpecifierNamed:name target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
                [item setProperty:r[@"path"] ?: @"" forKey:@"reportPath"];
                [item setProperty:NSStringFromSelector(@selector(openReport:)) forKey:@"action"];
                [item setProperty:[NSString stringWithFormat:@"%@ · %@",r[@"timestamp"] ?: @"时间未知",r[@"diagnosis"] ?: @"暂无摘要"] forKey:@"footerText"];
                [rows addObject:item];
            }
            if (!reports.count) [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"没有匹配的日志" target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
        }
        _specifiers=[rows copy];
    }
    return _specifiers;
}
- (void)viewDidLoad { [super viewDidLoad]; self.title=_singleReport ? (_singleReport[@"procName"] ?: @"日志详情") : (_category ?: @"全部日志"); }

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
