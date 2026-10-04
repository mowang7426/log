#import "CAWorkbenchController.h"
#import "CAAI.h"
#import "CAWorkbench.h"
#import "CALogStore.h"
#import "CACaseStore.h"
#import <Preferences/PSSpecifier.h>
@interface CATextController : UIViewController
@property(nonatomic,retain) NSString *text; @property(nonatomic,retain) NSString *heading;
@end
@implementation CATextController
- (void)loadView { UITextView *v=[[UITextView alloc] initWithFrame:CGRectZero]; v.editable=NO; v.font=[UIFont systemFontOfSize:15]; v.textContainerInset=UIEdgeInsetsMake(18,16,18,16); self.view=v; [v release]; }
- (void)viewDidLoad { [super viewDidLoad]; self.title=_heading; ((UITextView *)self.view).text=_text; }
- (void)dealloc { [_text release]; [_heading release]; [super dealloc]; }
@end
void CAPresentText(UIViewController *owner,NSString *title,NSString *text) { CATextController *v=[CATextController new]; v.heading=title; v.text=text?:@""; [owner.navigationController pushViewController:v animated:YES]; [v release]; }
#import "CAEvidenceController.h"
void CAPresentEvidence(UIViewController *owner,NSString *title,NSArray *rows) { CAEvidenceController *v=[[CAEvidenceController alloc] initWithRows:rows title:title]; [owner.navigationController pushViewController:v animated:YES]; [v release]; }
@implementation CAWorkbenchController { NSDictionary *_report; }
- (instancetype)initWithSpecifier:(PSSpecifier *)s { if((self=[super init])) self.specifier=s; return self; }
- (void)dealloc { [_report release]; [super dealloc]; }
- (id)specifiers {
 if(!_specifiers){ NSMutableArray *a=[NSMutableArray array]; NSString *path=[self.specifier propertyForKey:@"reportPath"]; _report=[[[CALogStore sharedStore] reportAtPath:path] retain]; self.title=@"第四版诊断工作台";
  [a addObject:[PSSpecifier preferenceSpecifierNamed:@"证据浏览" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
  for(NSArray *x in @[@[@"故障线程（实际帧）",@"fault"],@[@"全部线程与帧",@"all"],@[@"镜像/模块（有限列表）",@"modules"]]) { PSSpecifier *p=[PSSpecifier preferenceSpecifierNamed:x[0] target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil]; [p setProperty:x[1] forKey:@"mode"]; p.buttonAction=@selector(showEvidence:); [a addObject:p]; }
  PSSpecifier *exp=[PSSpecifier preferenceSpecifierNamed:@"导出 Markdown / TXT（复制或分享）" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil]; exp.buttonAction=@selector(export:); [a addObject:exp];
  [a addObject:[PSSpecifier preferenceSpecifierNamed:@"AI 分析请求" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
  PSSpecifier *ai=[PSSpecifier preferenceSpecifierNamed:@"预检并确认付费请求" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil]; ai.buttonAction=@selector(ai:); [a addObject:ai];
  PSSpecifier *fresh=[PSSpecifier preferenceSpecifierNamed:@"手动全新分析（绕过精确缓存）" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil]; [fresh setProperty:@YES forKey:@"fresh"]; fresh.buttonAction=@selector(ai:); [a addObject:fresh];
  PSSpecifier *hist=[PSSpecifier preferenceSpecifierNamed:@"查看 AI 分析历史" target:self set:nil get:nil detail:[CAHistoryController class] cell:PSLinkCell edit:nil]; [a addObject:hist]; _specifiers=[a mutableCopy]; }
 return _specifiers;
}
- (void)showEvidence:(PSSpecifier *)s { CAPresentEvidence(self, s.name, [CAWorkbench evidence:_report mode:[s propertyForKey:@"mode"]]); }
- (void)export:(PSSpecifier *)s { (void)s; NSString *md=[CAWorkbench exportReport:_report local:[[CALogStore sharedStore] localAnalysisForReport:_report] historical:[[CACaseStore sharedStore] matchingCaseForReport:_report] history:[[CAAIService shared] historyForReport:_report]]; NSError *e=nil; NSURL *u=[CAWorkbench writeExport:md extension:@"md" error:&e]; if(!u){CAPresentText(self,@"导出失败",e.localizedDescription);return;} UIActivityViewController *v=[[UIActivityViewController alloc] initWithActivityItems:@[md,u] applicationActivities:nil]; v.popoverPresentationController.sourceView = self.view; v.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2,1,1); [self presentViewController:v animated:YES completion:nil]; [v release]; }
- (void)ai:(PSSpecifier *)s {
    if (!_report) { CAPresentText(self,@"日志不可读",@"请返回重新选择原日志。"); return; }
    NSError *e=nil;
    BOOL source=[NSUserDefaults.standardUserDefaults boolForKey:@"CAAIIncludeSource"];
    NSDictionary *p=[[CAAIService shared] prepareReport:_report includeSource:source error:&e];
    if (!p) { CAPresentText(self,@"预检失败",e.localizedDescription); return; }
    BOOL fresh=[[s propertyForKey:@"fresh"] boolValue];
    BOOL hit=NO;
    for (NSDictionary *entry in [[CAAIService shared] history]) if ([entry[@"key"] isEqual:p[@"key"]]) { hit=YES; break; }
    if (hit && !fresh) {
        [[CAAIService shared] runPrepared:p report:_report fresh:NO completion:^(NSString *r,NSError *err){ CAPresentText(self,err?@"读取失败":@"精确缓存（未联网）",err.localizedDescription ?: r); }];
        return;
    }
    NSString *msg=[NSString stringWithFormat:@"模型：%@\n范围：%@\npayload：%@ 字节（实际 HTTPBody）\n最大输出：2048 tokens\n缓存：%@\n接口：%@\n\n确认后可能计费。字节数不是 token 数或价格；不自动重试。取消可终止任务，但不能撤销服务端已发生的计费。",p[@"model"],p[@"scope"],p[@"bytes"],fresh?@"手动绕过精确缓存":@"未命中",p[@"endpoint"]];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"付费请求预检" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"确认请求" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){ [self startPrepared:p fresh:fresh]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)startPrepared:(NSDictionary *)p fresh:(BOOL)fresh {
    UIAlertController *wait=[UIAlertController alertControllerWithTitle:@"AI 请求进行中" message:@"请勿重复提交。取消将调用 NSURLSessionTask.cancel；不会自动重试。" preferredStyle:UIAlertControllerStyleAlert];
    __block BOOL cancelled=NO;
    [wait addAction:[UIAlertAction actionWithTitle:@"取消网络任务" style:UIAlertActionStyleCancel handler:^(UIAlertAction *x){ cancelled=YES; [[CAAIService shared] cancelAnalysis]; }]];
    [self presentViewController:wait animated:YES completion:^{
        [[CAAIService shared] runPrepared:p report:self->_report fresh:fresh completion:^(NSString *r,NSError *err){
            if (cancelled) return;
            [wait dismissViewControllerAnimated:YES completion:^{ CAPresentText(self,err?@"AI 失败":@"AI 参考结果",err.localizedDescription ?: r); }];
        }];
    }];
}

@end
@implementation CAHistoryController
- (id)specifiers { if(!_specifiers){ NSMutableArray *a=[NSMutableArray array]; self.title=@"AI 分析历史"; PSSpecifier *clear=[PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"清除全部历史（%lu 条）",(unsigned long)CAAIService.shared.history.count] target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil]; clear.buttonAction=@selector(clearAll:); [a addObject:clear]; for(NSDictionary *e in [[CAAIService shared] history]) { NSString *label=[NSString stringWithFormat:@"%@ · %@ · %@",e[@"model"],e[@"time"],e[@"scope"]]; PSSpecifier *p=[PSSpecifier preferenceSpecifierNamed:label target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil]; [p setProperty:e forKey:@"historyEntry"]; p.buttonAction=@selector(open:); [a addObject:p]; } if(!a.count)[a addObject:[PSSpecifier preferenceSpecifierNamed:@"暂无成功分析历史；不会保存密钥。" target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]]; _specifiers=[a mutableCopy]; } return _specifiers; }
- (void)clearAll:(id)s { (void)s; NSUInteger n=CAAIService.shared.history.count; UIAlertController *a=[UIAlertController alertControllerWithTitle:@"清除 AI 分析历史" message:[NSString stringWithFormat:@"将删除 %lu 条 AI 历史；原始日志与案例库不受影响。",(unsigned long)n] preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; [a addAction:[UIAlertAction actionWithTitle:@"删除全部" style:UIAlertActionStyleDestructive handler:^(id x){[CAAIService.shared deleteAllHistory]; [self reloadSpecifiers];}]]; [self presentViewController:a animated:YES completion:nil]; }
- (void)open:(PSSpecifier *)s { NSDictionary *entry=[s propertyForKey:@"historyEntry"]; UIAlertController *a=[UIAlertController alertControllerWithTitle:@"AI 历史" message:@"查看或删除这条 AI 历史。删除不影响原始日志。" preferredStyle:UIAlertControllerStyleActionSheet]; [a addAction:[UIAlertAction actionWithTitle:@"查看结果" style:UIAlertActionStyleDefault handler:^(id x){CAPresentText(self,@"历史 AI 参考（非当前结论）",entry[@"answer"]); }]]; [a addAction:[UIAlertAction actionWithTitle:@"删除此条" style:UIAlertActionStyleDestructive handler:^(id x){[CAAIService.shared deleteHistoryEntry:entry]; [self reloadSpecifiers];}]]; [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }
@end
