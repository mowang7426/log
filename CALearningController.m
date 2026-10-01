#import "CALearningController.h"
#import "CACaseStore.h"
#import "CAWorkbench.h"
#import "CAWorkbenchController.h"
#import <UIKit/UIKit.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>

static NSString *CaseStatus(NSDictionary *c) {
    return [c[@"rejected"] boolValue]?@"已拒绝":([c[@"confirmed"] boolValue]?@"有用户实测记录（非根因保证）":@"未验证 AI 参考");
}
@implementation CALearningController {
    NSString *_query;
    NSString *_filter;
    NSUInteger _page;
}
- (void)dealloc { [_query release]; [_filter release]; [super dealloc]; }
- (void)searchCases:(PSSpecifier *)s {
    (void)s;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"按应用 / 模块搜索" message:@"只筛选显示；不改变严格历史匹配规则。空白清除搜索。" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){ f.text=self->_query; f.placeholder=@"Bundle ID、应用或模块符号"; }];
    __block UIAlertController *alert=a;
    [a addAction:[UIAlertAction actionWithTitle:@"搜索" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ [self->_query release]; self->_query=[alert.textFields.firstObject.text copy]; self->_page=0; [self refreshCases]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}
- (void)filterCases:(PSSpecifier *)s {
    (void)s; UIAlertController *a=[UIAlertController alertControllerWithTitle:@"显示验证状态" message:@"实测状态仅表示用户提交记录，并不证明根因。" preferredStyle:UIAlertControllerStyleAlert];
    for(NSArray *pair in @[@[@"全部",@"all"],@[@"有用户实测记录",@"validated"],@[@"未验证",@"unverified"],@[@"已拒绝",@"rejected"]]) [a addAction:[UIAlertAction actionWithTitle:pair[0] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){ [self->_filter release]; self->_filter=[pair[1] copy]; self->_page=0; [self refreshCases]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}
- (void)pageCases:(PSSpecifier *)s { if ([[s propertyForKey:@"previous"] boolValue]) { if(_page)_page--; } else _page++; [self refreshCases]; }
- (void)viewDidLoad { [super viewDidLoad]; self.title=@"本地学习与案例库"; }
- (void)refreshCases {
    [_specifiers release]; _specifiers=nil;
    [self reloadSpecifiers];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self refreshCases]; }
- (id)specifiers {
    if(!_specifiers) {
        NSMutableArray *rows=[NSMutableArray array];
        PSSpecifier *intro=[PSSpecifier preferenceSpecifierNamed:@"本地学习与案例库" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [intro setProperty:@"仅在本机保存 AI 参考与用户实测记录，不是模型训练。默认只采用有实测记录的案例；未验证案例仍可查看。记录不保证本次根因。此页不保存账号、接口或凭据。" forKey:@"footerText"]; [rows addObject:intro];
        NSArray *names=@[@"自动保存 AI 参考",@"使用历史相似案例",@"仅采用有用户实测记录的案例"];
        NSArray *keys=@[CAAutoSaveCases,CAUseHistoricalCases,CAOnlyValidatedCases];
        for(NSUInteger i=0;i<keys.count;i++) {
            PSSpecifier *s=[PSSpecifier preferenceSpecifierNamed:names[i] target:self set:@selector(setSetting:specifier:) get:@selector(setting:) detail:nil cell:PSSwitchCell edit:nil];
            [s setProperty:keys[i] forKey:@"caseSetting"]; [s setProperty:@YES forKey:@"defaultValue"]; [rows addObject:s];
        }
        NSDictionary *counts=[[CACaseStore sharedStore] summary];
        PSSpecifier *group=[PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"案例库 · %@ 条",counts[@"total"]] target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [group setProperty:[NSString stringWithFormat:@"未验证 %@ · 有实测记录 %@ · 已拒绝 %@\n仅在应用、应用/构建版本、系统、异常类型、信号及故障线程符号证据均精确一致时检索。不会自动发起云端请求。",counts[@"unverified"],counts[@"validated"],counts[@"rejected"]] forKey:@"footerText"]; [rows addObject:group];
        PSSpecifier *search=[PSSpecifier preferenceSpecifierNamed:@"搜索应用 / 模块" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil]; search.buttonAction=@selector(searchCases:); [rows addObject:search];
        PSSpecifier *filter=[PSSpecifier preferenceSpecifierNamed:@"筛选验证状态" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil]; filter.buttonAction=@selector(filterCases:); [rows addObject:filter];
        NSArray *visible=[CAWorkbench filterCases:[[CACaseStore sharedStore] allCases] query:_query status:_filter ?: @"all"];
        NSUInteger start=MIN(_page*100,visible.count), end=MIN(start+100,visible.count);
        for(NSDictionary *c in [visible subarrayWithRange:NSMakeRange(start,end-start)]) {
            NSString *shortID=[c[@"id"] substringToIndex:12];
            PSSpecifier *button=[PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"%@ · %@",shortID,CaseStatus(c)] target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
            [button setProperty:c[@"id"] forKey:@"caseID"]; [button setProperty:c[@"createdAt"] forKey:@"footerText"];
            button.buttonAction=@selector(showCase:); [rows addObject:button];
        }
        if(![counts[@"total"] unsignedIntegerValue])[rows addObject:[PSSpecifier preferenceSpecifierNamed:@"暂无案例；手动 AI 分析成功且证据充分时保存参考。" target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"搜索：%@ · 状态：%@ · 匹配 %lu 项 · 第 %lu 页",_query ?: @"全部",_filter ?: @"all",(unsigned long)visible.count,(unsigned long)_page+1] target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        if (_page) { PSSpecifier *p=[PSSpecifier preferenceSpecifierNamed:@"上一页" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil]; [p setProperty:@YES forKey:@"previous"]; p.buttonAction=@selector(pageCases:); [rows addObject:p]; }
        if (end<visible.count) { PSSpecifier *p=[PSSpecifier preferenceSpecifierNamed:@"下一页" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil]; p.buttonAction=@selector(pageCases:); [rows addObject:p]; }
        PSSpecifier *refresh=[PSSpecifier preferenceSpecifierNamed:@"刷新案例库" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        refresh.buttonAction=@selector(refreshPressed:); [rows addObject:refresh];
        _specifiers=[rows mutableCopy];
    }
    return _specifiers;
}
- (id)setting:(PSSpecifier *)s { return @([[CACaseStore sharedStore] settingEnabled:[s propertyForKey:@"caseSetting"]]); }
- (void)setSetting:(id)value specifier:(PSSpecifier *)s {
    [[[CACaseStore sharedStore] defaults] setBool:[value boolValue] forKey:[s propertyForKey:@"caseSetting"]];
    [self refreshCases];
}
- (void)refreshPressed:(PSSpecifier *)s { (void)s; [self refreshCases]; }
- (void)showMessage:(NSString *)message {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"案例库" message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}
- (void)showCase:(PSSpecifier *)s {
    NSString *caseID=[s propertyForKey:@"caseID"];
    NSDictionary *c=[[CACaseStore sharedStore] caseWithID:caseID];
    if(!c){[self refreshCases];[self showMessage:@"案例已删除或文件损坏，请刷新。"] ;return;}
    NSString *text=[NSString stringWithFormat:@"状态：%@\n来源：%@（不是已证实的根因）\n时间：%@\nID：%@\n\n应用/版本/系统/异常/信号精确键：\n%@\n\n故障线程符号证据：\n%@\n\nAI 参考：\n%@\n\n用户实测记录：\n%@\n\nconfirmed 仅表示用户提交过实测记录，不保证当前问题根因。",CaseStatus(c),c[@"source"],c[@"createdAt"],caseID,c[@"key"],c[@"evidence"],c[@"answer"],c[@"testNote"] ?: @"尚未记录"];
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"案例详情" message:text preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"复制详情" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){ [UIPasteboard generalPasteboard].string=text; }]];
    if(![c[@"rejected"] boolValue]) {
        [a addAction:[UIAlertAction actionWithTitle:@"记录实际验证结果" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){ [self noteForID:caseID]; }]];
        [a addAction:[UIAlertAction actionWithTitle:@"拒绝此案例" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){ [self rejectID:caseID]; }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"删除此案例" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){ [self deleteID:caseID]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)noteForID:(NSString *)caseID {
    NSDictionary *current=[[CACaseStore sharedStore] caseWithID:caseID];
    if(!current || [current[@"rejected"] boolValue]){[self refreshCases];[self showMessage:@"案例已删除或拒绝，不能记录。"] ;return;}
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"实际验证记录" message:@"填写实际操作、环境和结果（包括未解决）。这不是当前根因的保证；空白记录不会保存。" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *field){field.placeholder=@"操作、版本、结果与观察"; field.text=current[@"testNote"] ?: @"";}];
    __block UIAlertController *noteAlert=a; // nonretaining under MRC; avoid alert/action cycle
    [a addAction:[UIAlertAction actionWithTitle:@"保存记录" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        NSDictionary *latest=[[CACaseStore sharedStore] caseWithID:caseID];
        BOOL ok=[[CACaseStore sharedStore] recordTestNote:noteAlert.textFields.firstObject.text forCase:latest];
        [self refreshCases]; if(!ok)[self showMessage:@"保存失败：记录为空、案例已删除/拒绝或目录不可写。"];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}
- (void)rejectID:(NSString *)caseID {
    NSDictionary *latest=[[CACaseStore sharedStore] caseWithID:caseID];
    BOOL ok=[[CACaseStore sharedStore] rejectCase:latest]; [self refreshCases]; if(!ok)[self showMessage:@"拒绝失败，案例可能已删除或目录不可写。"];
}
- (void)deleteID:(NSString *)caseID {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"删除案例？" message:@"将删除此本地参考及实测记录，不会删除原始日志；不可撤销。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){
        BOOL ok=[[CACaseStore sharedStore] deleteCaseWithID:caseID]; [self refreshCases]; if(!ok)[self showMessage:@"删除失败，文件可能已删除或目录不可写。"];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}
@end
