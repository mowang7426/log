#import "CAPRootListController.h"
#import "CALogStore.h"
#import "CAReportViewController.h"
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>

@implementation CAPRootListController

- (void)loadView {
    [super loadView];
    self.table.tableFooterView=[UIView new];
    self.view.backgroundColor=[UIColor systemGroupedBackgroundColor];
}

- (id)specifiers {
    if (!_specifiers) {
        NSMutableArray *items=[NSMutableArray array];
        PSSpecifier *header=[PSSpecifier preferenceSpecifierNamed:@"日志分类"
            target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [header setProperty:@"自动扫描系统分析日志，并按事件类型归类" forKey:@"footerText"];
        [items addObject:header];

        NSArray *categories=@[
            @[@"崩溃", @"应用、系统进程和 SpringBoard 崩溃"],
            @[@"内存", @"Jetsam 和内存压力终止"],
            @[@"重启", @"Panic、异常重启和启动事件"],
            @[@"资源", @"看门狗、CPU 和资源异常"],
            @[@"其他", @"暂未识别的分析日志"]
        ];
        for (NSArray *entry in categories) {
            PSSpecifier *specifier=[PSSpecifier preferenceSpecifierNamed:entry[0]
                target:self set:nil get:nil detail:[CAReportViewController class]
                cell:PSLinkCell edit:nil];
            [specifier setProperty:entry[1] forKey:@"footerText"];
            [specifier setProperty:entry[0] forKey:@"category"];
            [specifier setProperty:@YES forKey:@"isController"];
            [items addObject:specifier];
        }

        NSDictionary *diagnostics=[[CALogStore sharedStore] scanDiagnostics];
        PSSpecifier *about=[PSSpecifier preferenceSpecifierNamed:@"扫描诊断"
            target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [about setProperty:@"用于确认路径、权限和日志解析状态" forKey:@"footerText"];
        [items addObject:about];

        NSArray *statusRows=@[
            [NSString stringWithFormat:@"扫描目录：%@", diagnostics[@"path"] ?: @"未知"],
            [NSString stringWithFormat:@"目录状态：%@", [diagnostics[@"exists"] boolValue] ? @"可见" : @"不存在或不可访问"],
            [NSString stringWithFormat:@"枚举文件：%@", diagnostics[@"enumerated"] ?: @0],
            [NSString stringWithFormat:@"IPS 文件：%@", diagnostics[@"matched"] ?: @0],
            [NSString stringWithFormat:@"可读取：%@", diagnostics[@"readable"] ?: @0],
            [NSString stringWithFormat:@"解析成功：%@", diagnostics[@"parsed"] ?: @0]
        ];
        for (NSString *text in statusRows) {
            PSSpecifier *row=[PSSpecifier preferenceSpecifierNamed:text
                target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
            [items addObject:row];
        }
        NSString *scanError=diagnostics[@"error"];
        if (scanError.length) {
            PSSpecifier *row=[PSSpecifier preferenceSpecifierNamed:[@"扫描错误：" stringByAppendingString:scanError]
                target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
            [items addObject:row];
        }
        PSSpecifier *scanButton=[PSSpecifier preferenceSpecifierNamed:@"立即扫描日志"
            target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        [scanButton setProperty:@"手动重新扫描系统 CrashReporter 目录" forKey:@"footerText"];
        [scanButton setProperty:NSStringFromSelector(@selector(scanNow)) forKey:@"action"];
        [items addObject:scanButton];
        _specifiers=[items copy];
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"分析日志";
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];
}

- (void)scanNow {
    NSDictionary *d=[[CALogStore sharedStore] scanDiagnostics];
    NSString *message=[NSString stringWithFormat:@"路径：%@\n目录：%@\n枚举文件：%@\nIPS 文件：%@\n可读取：%@\n解析成功：%@", d[@"path"] ?: @"未知", [d[@"exists"] boolValue] ? @"可见" : @"不存在或不可访问", d[@"enumerated"] ?: @0, d[@"matched"] ?: @0, d[@"readable"] ?: @0, d[@"parsed"] ?: @0];
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"扫描完成" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        self->_specifiers=nil;
        [super reloadSpecifiers];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

    _specifiers=nil;
    [super reloadSpecifiers];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    (void)value;
    (void)specifier;
    _specifiers=nil;
    [self reloadSpecifiers];
}

@end
