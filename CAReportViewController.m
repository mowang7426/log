#import "CAReportViewController.h"
#import "CALogStore.h"
#import <Preferences/PSSpecifier.h>

@implementation CAReportViewController {
    NSArray *_items;
    NSString *_category;
}

- (instancetype)initWithSpecifier:(PSSpecifier *)specifier {
    self=[super init];
    if (self) {
        self.specifier=specifier;
        _category=[specifier.properties[@"category"] copy] ?: @"其他";
    }
    return self;
}

- (id)specifiers {
    if (!_specifiers) {
        [self reloadReports];
        NSMutableArray *rows=[NSMutableArray array];
        for (NSDictionary *report in _items) {
            NSString *name=report[@"procName"] ?: report[@"app_name"] ?: report[@"fileName"] ?: @"未知日志";
            NSString *detail=report[@"diagnosis"] ?: @"点击查看日志详情";
            PSSpecifier *row=[PSSpecifier preferenceSpecifierNamed:name target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
            [row setProperty:detail forKey:@"footerText"];
            [row setProperty:report forKey:@"report"];
            [rows addObject:row];
        }
        if (!rows.count) {
            PSSpecifier *empty=[PSSpecifier preferenceSpecifierNamed:@"没有发现此类日志" target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
            [rows addObject:empty];
        }
        _specifiers=[rows copy];
    }
    return _specifiers;
}

- (void)reloadReports {
    _items=[[[CALogStore sharedStore] reportsForCategory:_category] copy];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=_category ?: @"分析日志";
}

- (void)reloadSpecifiers {
    _specifiers=nil;
    [self reloadReports];
    [super reloadSpecifiers];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *specifier=[self specifierAtIndexPath:indexPath];
    NSDictionary *report=[specifier propertyForKey:@"report"];
    if (![report isKindOfClass:[NSDictionary class]]) return;
    NSString *text=[NSString stringWithFormat:@"%@\n\n%@\n\n%@", report[@"fileName"] ?: @"日志", report[@"diagnosis"] ?: @"", report[@"path"] ?: @""];
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:report[@"procName"] ?: report[@"app_name"] ?: @"日志" message:text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
