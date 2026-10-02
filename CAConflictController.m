#import "CAConflictController.h"
#import <UIKit/UIKit.h>
#import "CALogStore.h"
#import "CAReportViewController.h"
#import "CAPluginEvidence.h"
#import "CAEvidenceUI.h"
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSListController.h>
static NSString *V(id v,NSString *fallback){ if([v isKindOfClass:NSString.class]&&[v length])return v; if([v isKindOfClass:NSNumber.class])return [v stringValue]; return fallback; }
static PSSpecifier *TextRow(NSString *text){ PSSpecifier *s=[PSSpecifier preferenceSpecifierNamed:text?:@"" target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]; CAWrapEvidenceRow(s); return s; }
static NSString *ReportName(NSDictionary *r){ return [NSString stringWithFormat:@"%@\n%@ · %@",V(r[@"fileName"],@"未知日志"),V(r[@"normalizedProcessName"]?:r[@"procName"]?:r[@"app_name"],@"进程未知"),V(r[@"timestamp"]?:r[@"captureTime"],@"时间未知")]; }
static NSString *RefText(NSDictionary *e){ NSMutableArray *a=[NSMutableArray array]; NSDictionary *r=e[@"report"]; [a addObject:[NSString stringWithFormat:@"证据：%@",[CAPluginEvidence tierLabel:e[@"tier"]]]]; [a addObject:[NSString stringWithFormat:@"进程：%@",V(r[@"normalizedProcessName"]?:r[@"procName"]?:r[@"app_name"],@"未提供")]]; [a addObject:[NSString stringWithFormat:@"异常：%@",V(r[@"normalizedExceptionType"]?:r[@"exceptionType"]?:([r[@"exception"] isKindOfClass:NSDictionary.class]?r[@"exception"][@"type"]:nil),@"未提供")]]; id ft=e[@"faultThread"]; [a addObject:[NSString stringWithFormat:@"故障线程索引：%@",ft==[NSNull null]?@"未提供":[ft description]]]; NSMutableArray *frames=[NSMutableArray array]; for(NSDictionary *f in e[@"references"]){[frames addObject:[NSString stringWithFormat:@"线程 %@ / 帧 %@ / imageIndex %@ / %@",f[@"thread"],f[@"frame"],f[@"imageIndex"],V(f[@"symbol"],@"符号未提供")]];} [a addObject:[NSString stringWithFormat:@"实际帧：%@",frames.count?[frames componentsJoinedByString:@"；"]:@"未提供"]]; [a addObject:[NSString stringWithFormat:@"原始报告：%@",V(r[@"path"],@"路径未提供")]]; return [a componentsJoinedByString:@"\n"]; }
@implementation CAConflictDetailController
- (instancetype)initWithSpecifier:(PSSpecifier *)s{if((self=[super init]))self.specifier=s;return self;}
- (id)specifiers{if(!_specifiers){NSDictionary *st=[self.specifier propertyForKey:@"conflictStats"]?:@{};self.title=V(st[@"name"],@"未知动态库");NSMutableArray *rows=[NSMutableArray array];[rows addObject:TextRow([NSString stringWithFormat:@"动态库：%@\n证据等级：%@\n故障线程引用报告数：%@（每个事件只计一次）\n相关报告总数：%@",V(st[@"name"],@"未知"),[CAPluginEvidence tierLabel:st[@"tier"]],st[@"main"]?:@0,st[@"participation"]?:@0])];[rows addObject:TextRow(@"说明：其他线程引用仅为辅助证据；仅 usedImages 加载不构成归因证据；未知表示数据缺失或索引无效。")];for(NSString *p in st[@"paths"]){[rows addObject:TextRow([NSString stringWithFormat:@"实际路径：\n%@",p])];PSSpecifier *copy=[PSSpecifier preferenceSpecifierNamed:@"复制完整路径" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];copy.buttonAction=@selector(copyPath:);[copy setProperty:p forKey:@"copyPath"];[rows addObject:copy];}[rows addObject:TextRow(@"各报告真实证据")];for(NSDictionary *e in st[@"entries"]){PSSpecifier *s=[PSSpecifier preferenceSpecifierNamed:ReportName(e[@"report"]) target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];CAWrapEvidenceRow(s);[rows addObject:s];[rows addObject:TextRow(RefText(e))];NSDictionary *r=e[@"report"];for(Class cls in @[[CAReportDetailController class],[CAReportSourceController class]]){PSSpecifier *link=[PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"%@：%@",cls==[CAReportDetailController class]?@"查看报告分析":@"查看原始证据",V(r[@"fileName"],@"未知日志")] target:nil set:nil get:nil detail:cls cell:PSLinkCell edit:nil];[link setProperty:r forKey:@"reportSnapshot"];[link setProperty:V(r[@"path"],@"") forKey:@"reportPath"];[link setProperty:V(r[@"category"],@"其他") forKey:@"reportCategory"];CAWrapEvidenceRow(link);[rows addObject:link];}}if(!st[@"entries"])[rows addObject:TextRow(@"暂无证据报告")];NSDictionary *record=[CAPluginEvidence validationForPlugin:st[@"identity"]];
[rows addObject:TextRow([NSString stringWithFormat:@"本地用户验证：%@\n实际测试日期：%@\nApp 版本：%@\n插件版本：%@\n备注：%@",V(record[@"state"],@"待验证"),V(record[@"testedAt"],@"未记录"),V(record[@"appVersion"],@"未提供"),V(record[@"pluginVersion"],@"未提供"),V(record[@"notes"],@"未提供")])];
[rows addObject:TextRow(@"未再发生仅是观察结果，不等于确认根因。请自行单独调整插件并记录对照；本工具绝不自动禁用或修改任何插件。")];
PSSpecifier *test=[PSSpecifier preferenceSpecifierNamed:@"记录/更新本地验证" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];test.buttonAction=@selector(recordValidation:);[rows addObject:test];
_specifiers=[rows mutableCopy];}return _specifiers;}
- (void)copyPath:(PSSpecifier *)s { [UIPasteboard generalPasteboard].string=[s propertyForKey:@"copyPath"]; }
- (void)recordValidation:(PSSpecifier *)s {
    (void)s;
    UIAlertController *choose=[UIAlertController alertControllerWithTitle:@"记录观察结果" message:@"只是本机记录，不会调整插件或确认根因。" preferredStyle:UIAlertControllerStyleAlert];
    for(NSString *state in [CAPluginEvidence validationStates]) [choose addAction:[UIAlertAction actionWithTitle:state style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){(void)a;[self editValidationState:state];}]];
    [choose addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:choose animated:YES completion:nil];
}
- (void)editValidationState:(NSString *)state {
    NSDictionary *st=[self.specifier propertyForKey:@"conflictStats"],*old=[CAPluginEvidence validationForPlugin:st[@"identity"]];
    NSDictionary *entry=[st[@"entries"] firstObject]?:@{};
    NSDateFormatter *fmt=[[[NSDateFormatter alloc] init] autorelease];fmt.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];fmt.dateFormat=@"yyyy-MM-dd HH:mm";fmt.lenient=NO;
    UIAlertController *edit=[UIAlertController alertControllerWithTitle:@"填写实际测试记录" message:@"日期为实际测试时间（本地时区），不是崩溃报告时间；空白版本表示未提供。" preferredStyle:UIAlertControllerStyleAlert];
    NSArray *values=@[V(old[@"testedAt"],[fmt stringFromDate:NSDate.date]),V(old[@"appVersion"],V(entry[@"appVersion"],@"")),V(old[@"pluginVersion"],V(entry[@"pluginVersion"],@"")),V(old[@"notes"],@"")];
    NSArray *labels=@[@"实际测试日期 yyyy-MM-dd HH:mm",@"App 版本（可选）",@"插件版本（可选）",@"备注/复现步骤（可选）"];
    for(NSUInteger i=0;i<labels.count;i++){[edit addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=labels[i];f.text=values[i];}];}
    [edit addAction:[UIAlertAction actionWithTitle:@"保存本机记录" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        (void)a;NSString *date=edit.textFields[0].text?:@"";
        BOOL valid=[fmt dateFromString:date]!=nil;
        NSDictionary *record=@{@"state":state,@"testedAt":date,@"appVersion":edit.textFields[1].text?:@"",@"pluginVersion":edit.textFields[2].text?:@"",@"notes":edit.textFields[3].text?:@""};
        if(valid && [CAPluginEvidence saveValidation:record forPlugin:st[@"identity"]]){[_specifiers release];_specifiers=nil;[self reloadSpecifiers];}
        else{UIAlertController *error=[UIAlertController alertControllerWithTitle:@"记录未保存" message:@"请使用有效的实际测试日期 yyyy-MM-dd HH:mm。" preferredStyle:UIAlertControllerStyleAlert];[error addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:error animated:YES completion:nil];}
    }]];
    [edit addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:edit animated:YES completion:nil];
}
- (CGFloat)tableView:(UITableView *)t heightForRowAtIndexPath:(NSIndexPath *)i{PSSpecifier*s=[self specifierAtIndexPath:i];return [s propertyForKey:@"cellClass"]==[CAEvidenceWrappingCell class]?CAEvidenceRowHeight(t,s):[super tableView:t heightForRowAtIndexPath:i];}
@end
@implementation CAConflictController
- (void)viewDidLoad {[super viewDidLoad];[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(storeUpdated:) name:CALogStoreDidRefreshNotification object:CALogStore.sharedStore];}
- (void)viewWillAppear:(BOOL)a {[super viewWillAppear:a];[_specifiers release];_specifiers=nil;[self reloadSpecifiers];[CALogStore.sharedStore refreshReports];}
- (void)storeUpdated:(NSNotification *)n {(void)n;[_specifiers release];_specifiers=nil;if(self.viewIfLoaded.window)[self reloadSpecifiers];}
- (void)dealloc {[[NSNotificationCenter defaultCenter] removeObserver:self];[super dealloc];}
- (CGFloat)tableView:(UITableView *)t heightForRowAtIndexPath:(NSIndexPath *)i {PSSpecifier *s=[self specifierAtIndexPath:i];return [s propertyForKey:@"cellClass"]==[CAEvidenceWrappingCell class]?CAEvidenceRowHeight(t,s):[super tableView:t heightForRowAtIndexPath:i];}
+ (NSArray *)summaryForReports:(NSArray *)r limit:(NSUInteger)n{return [CAPluginEvidence summaryForReports:r limit:n];}
- (id)specifiers{if(!_specifiers){self.title=@"疑似冲突插件";NSMutableArray *a=[NSMutableArray array];[a addObject:TextRow(@"证据排序，不是根因定案\n优先：故障线程实际引用；辅助：其他线程引用；仅加载不排序为中等嫌疑。")];NSArray*items=[CAConflictController summaryForReports:CALogStore.sharedStore.reports limit:0];for(NSDictionary*s in items){PSSpecifier*x=[PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"%@\n%@ · 故障线程引用报告数 %@ · 相关报告 %@",V(s[@"name"],@"未知"),[CAPluginEvidence tierLabel:s[@"tier"]],s[@"main"]?:@0,s[@"participation"]?:@0] target:nil set:nil get:nil detail:[CAConflictDetailController class] cell:PSLinkCell edit:nil];[x setProperty:s forKey:@"conflictStats"];CAWrapEvidenceRow(x);[a addObject:x];}if(!items.count)[a addObject:TextRow(CALogStore.sharedStore.scanInProgress?@"正在后台扫描…":(CALogStore.sharedStore.reportsReady?@"扫描完成：暂无可用插件证据":@"尚未扫描"))];_specifiers=[a mutableCopy];}return _specifiers;}
@end
