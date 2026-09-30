#import "CAReportViewController.h"
#import "CALogStore.h"
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>

@implementation CAReportViewController {
    NSArray *_items;
    NSString *_category;
}

- (instancetype)initWithSpecifier:(PSSpecifier *)specifier {
    self=[super init];
    if (self) {
        self.specifier=specifier;
        id category=[specifier propertyForKey:@"category"];
        _category=[category isKindOfClass:[NSString class]] ? [category copy] : @"其他";
    }
    return self;
}

- (id)specifiers {
    if (!_specifiers) {
        NSArray *reports=[[CALogStore sharedStore] reportsForCategory:_category];
        NSMutableArray *rows=[NSMutableArray array];
        PSSpecifier *header=[PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"%@ · %lu 条",_category,(unsigned long)reports.count] target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [header setProperty:@"点击日志行查看分析详情" forKey:@"footerText"];
        [rows addObject:header];
        for (NSDictionary *report in reports) {
            NSString *name=report[@"procName"] ?: report[@"app_name"] ?: report[@"fileName"] ?: @"未知日志";
            PSSpecifier *item=[PSSpecifier preferenceSpecifierNamed:name target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
            [item setProperty:report[@"path"] ?: @"" forKey:@"reportPath"];
            [item setProperty:NSStringFromSelector(@selector(openReport:)) forKey:@"action"];
            [item setProperty:[NSString stringWithFormat:@"%@  ·  %@",report[@"timestamp"]?:@"时间未知",report[@"diagnosis"]?:@"暂无摘要"] forKey:@"footerText"];
            [rows addObject:item];
        }
        if (!reports.count) [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"此分类暂无日志" target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
        _specifiers=[rows copy];
    }
    return _specifiers;
}

- (void)viewDidLoad { [super viewDidLoad]; self.title=_category ?: @"日志"; }
- (void)openReport:(PSSpecifier *)specifier {
    NSString *path=[specifier propertyForKey:@"reportPath"];
    NSDictionary *report=[[CALogStore sharedStore] reportAtPath:path];
    if (![report isKindOfClass:[NSDictionary class]]) return;
    NSString *message=[NSString stringWithFormat:@"分类：%@\n时间：%@\n异常：%@\n\n%@",report[@"category"]?:@"其他",report[@"timestamp"]?:@"未知",[report[@"exception"] isKindOfClass:[NSDictionary class]]?(report[@"exception"][@"type"]?:@"未知"):@"未知",report[@"diagnosis"]?:@""];
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:report[@"procName"]?:report[@"app_name"]?:@"日志详情" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
