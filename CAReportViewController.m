#import "CAReportViewController.h"
#import "CALogStore.h"
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>

@implementation CAReportViewController {
    NSArray *_items;
    NSString *_category;
    NSDictionary *_singleReport;
}
- (instancetype)initWithSpecifier:(PSSpecifier *)specifier {
    self=[super init];
    if (self) {
        self.specifier=specifier;
        NSDictionary *properties=specifier.properties;
        id category=properties[@"category"];
        if ([category isKindOfClass:[NSString class]]) _category=[category copy];
        id path=properties[@"reportPath"];
        if ([path isKindOfClass:[NSString class]]) {
            _singleReport=[[[CALogStore sharedStore] reportAtPath:path] copy];
        }
        if (!_category && _singleReport[@"category"]) _category=[_singleReport[@"category"] copy];
    }
    return self;
}
- (id)specifiers {
    if (!_specifiers) {
        NSMutableArray *rows=[NSMutableArray array];
        if (_singleReport) {
            NSDictionary *r=_singleReport;
            NSArray *fields=@[
                @[@"进程",r[@"procName"]?:r[@"app_name"]?:@"未知"],
                @[@"分类",r[@"category"]?:@"其他"],
                @[@"时间",r[@"timestamp"]?:r[@"captureTime"]?:@"未知"],
                @[@"异常",[r[@"exception"] isKindOfClass:[NSDictionary class]]?(r[@"exception"][@"type"]?:@"未知"):@"无"],
                @[@"诊断",r[@"diagnosis"]?:@"暂无规则分析"],
                @[@"文件",r[@"fileName"]?:@"未知"]
            ];
            for (NSArray *f in fields) [rows addObject:[PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"%@：%@",f[0],f[1]] target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
        } else {
            NSArray *reports=_category.length?[[CALogStore sharedStore] reportsForCategory:_category]:[[CALogStore sharedStore] reports];
            PSSpecifier *head=[PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"%@（%lu）",_category?:@"全部日志",(unsigned long)reports.count] target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
            [rows addObject:head];
            for (NSDictionary *r in reports) {
                NSString *title=r[@"procName"]?:r[@"app_name"]?:r[@"fileName"]?:@"未知日志";
                NSString *sub=[NSString stringWithFormat:@"%@ · %@",r[@"timestamp"]?:@"时间未知",r[@"diagnosis"]?:@""];
                PSSpecifier *item=[PSSpecifier preferenceSpecifierNamed:title target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
                [item setProperty:sub forKey:@"footerText"];
                [rows addObject:item];
            }
            if (!reports.count) [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"没有匹配的日志" target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
        }
        _specifiers=[rows copy];
    }
    return _specifiers;
}
- (void)viewDidLoad { [super viewDidLoad]; self.title=_singleReport?(_singleReport[@"procName"]?:@"日志详情"):_category?:@"全部日志"; }
@end
