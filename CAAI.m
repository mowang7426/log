#import "CAAI.h"
#import "CAWorkbenchController.h"
#import "CACaseStore.h"
#import "CALogStore.h"
#import <CommonCrypto/CommonDigest.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>

static NSString * const kEndpoint=@"CAAIEndpoint";
static NSString * const kModel=@"CAAIMode";
static NSString * const kKey=@"CAAIKey";
static NSString * const kPrompt=@"CAAIPrompt";
static NSString * const kSource=@"CAAIIncludeSource";
static NSString * const kModels=@"CAAIFetchedModels";


@implementation CAAIConfigController
- (id)specifiers {
    if (!_specifiers) {
        NSMutableArray *rows=[NSMutableArray array];
        NSUserDefaults *d=[NSUserDefaults standardUserDefaults];
        NSArray *models=[d arrayForKey:kModels] ?: @[];
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"OpenAI-compatible 模型" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        PSSpecifier *endpoint=[PSSpecifier preferenceSpecifierNamed:@"接口地址" target:self set:@selector(setEndpoint:specifier:) get:@selector(endpoint:) detail:nil cell:PSEditTextCell edit:nil];
        [endpoint setProperty:@"https://api.openai.com/v1/chat/completions" forKey:@"defaultValue"]; [rows addObject:endpoint];
        PSSpecifier *fetch=[PSSpecifier preferenceSpecifierNamed:@"获取模型列表" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil]; fetch.buttonAction=@selector(fetchModels:); [rows addObject:fetch];
        if (models.count) {
            PSSpecifier *picker=[PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"可选模型（%lu 个）",(unsigned long)models.count] target:nil set:nil get:nil detail:[CAAIModelPickerController class] cell:PSLinkCell edit:nil];
            [rows addObject:picker];
        }
        PSSpecifier *manual=[PSSpecifier preferenceSpecifierNamed:@"模型名称（也可手动填写）" target:self set:@selector(setModel:specifier:) get:@selector(model:) detail:nil cell:PSEditTextCell edit:nil]; [manual setProperty:@"deepseek-ai/DeepSeek-V4-Pro" forKey:@"placeholder"]; [rows addObject:manual];
        PSSpecifier *key=[PSSpecifier preferenceSpecifierNamed:@"API Key" target:self set:@selector(setKey:specifier:) get:@selector(key:) detail:nil cell:PSEditTextCell edit:nil]; [key setProperty:@YES forKey:@"isSecure"]; [key setProperty:@YES forKey:@"secureTextEntry"]; [rows addObject:key];
        PSSpecifier *prompt=[PSSpecifier preferenceSpecifierNamed:@"系统提示词" target:self set:@selector(setPrompt:specifier:) get:@selector(prompt:) detail:nil cell:PSEditTextCell edit:nil]; [prompt setProperty:@"分析 iOS IPS 日志，区分事实与推测，引用证据并给出排查步骤。" forKey:@"defaultValue"]; [rows addObject:prompt];
        PSSpecifier *test=[PSSpecifier preferenceSpecifierNamed:@"测试模型连接" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil]; test.buttonAction=@selector(testConnection:); [rows addObject:test];
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"隐私" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        PSSpecifier *include=[PSSpecifier preferenceSpecifierNamed:@"发送完整源文件" target:self set:@selector(setSource:specifier:) get:@selector(source:) detail:nil cell:PSSwitchCell edit:nil]; [include setProperty:@NO forKey:@"defaultValue"]; [rows addObject:include];
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"默认只发送结构化信息。开启后才发送完整 .ips 源文件。" target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
        _specifiers=[rows mutableCopy];
    } return _specifiers;
}
- (NSUserDefaults *)d { return [NSUserDefaults standardUserDefaults]; }
- (id)value:(NSString *)k specifier:(PSSpecifier *)s { return [[self d] objectForKey:k] ?: [s propertyForKey:@"defaultValue"]; }
- (id)endpoint:(PSSpecifier *)s { return [self value:kEndpoint specifier:s]; }
- (id)model:(PSSpecifier *)s { return [[self d] objectForKey:kModel] ?: @""; }
- (id)key:(PSSpecifier *)s { return [[self d] objectForKey:kKey] ?: @""; }
- (id)prompt:(PSSpecifier *)s { return [self value:kPrompt specifier:s]; }
- (id)source:(PSSpecifier *)s { return @([[self d] boolForKey:kSource]); }
- (void)setEndpoint:(id)v specifier:(PSSpecifier *)s { [[self d] setObject:v ?: @"" forKey:kEndpoint]; }
- (void)setModel:(id)v specifier:(PSSpecifier *)s { [[self d] setObject:v ?: @"" forKey:kModel]; }
- (void)setKey:(id)v specifier:(PSSpecifier *)s { [[self d] setObject:v ?: @"" forKey:kKey]; }
- (void)setPrompt:(id)v specifier:(PSSpecifier *)s { [[self d] setObject:v ?: @"" forKey:kPrompt]; }
- (void)setSource:(id)v specifier:(PSSpecifier *)s { [[self d] setBool:[v boolValue] forKey:kSource]; }
- (void)fetchModels:(PSSpecifier *)s {
    (void)s; UIAlertController *wait=[UIAlertController alertControllerWithTitle:@"获取模型" message:@"正在请求 /models …" preferredStyle:UIAlertControllerStyleAlert]; [self presentViewController:wait animated:YES completion:nil];
    [[CAAIService shared] fetchModels:^(NSArray *models,NSString *error){
        [wait dismissViewControllerAnimated:YES completion:^{
            if(models.count){ [[self d] setObject:models forKey:kModels]; self->_specifiers=nil; [self reloadSpecifiers]; }
            UIAlertController *a=[UIAlertController alertControllerWithTitle:(models.count?@"获取成功":@"获取失败") message:(models.count?[NSString stringWithFormat:@"获取到 %lu 个模型，请在列表中选择。",(unsigned long)models.count]:error ?: @"服务没有返回模型列表") preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil];
        }];
    }];
}
- (void)testConnection:(PSSpecifier *)s {
    (void)s; NSError *e=nil;
    NSDictionary *report=@{@"normalizedProcessName":@"connection test"};
    NSDictionary *p=[[CAAIService shared] prepareReport:report includeSource:NO error:&e];
    if (!p) { CAPresentText(self,@"预检失败",e.localizedDescription); return; }
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"确认连接测试（可能计费）" message:[NSString stringWithFormat:@"模型：%@\n范围：structured\n实际 payload：%@ 字节\n最大输出 2048 tokens\n接口：%@\n不会自动重试。",p[@"model"],p[@"bytes"],p[@"endpoint"]] preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"发送测试" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){
        UIAlertController *w=[UIAlertController alertControllerWithTitle:@"测试中" message:@"取消可终止网络任务；服务端可能已计费。" preferredStyle:UIAlertControllerStyleAlert];
        __block BOOL cancelled=NO;
        [w addAction:[UIAlertAction actionWithTitle:@"取消请求" style:UIAlertActionStyleCancel handler:^(UIAlertAction *y){ cancelled=YES; [[CAAIService shared] cancelAnalysis]; }]];
        [self presentViewController:w animated:YES completion:^{
            [[CAAIService shared] runPrepared:p report:report fresh:YES completion:^(NSString *r,NSError *error){ if (cancelled) return; [w dismissViewControllerAnimated:YES completion:^{ CAPresentText(self,error?@"测试失败":@"测试结果",error.localizedDescription ?: r); }]; }];
        }];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil];
}

@end

@implementation CAAIModelPickerController
- (id)specifiers {
    if (!_specifiers) {
        NSMutableArray *rows=[NSMutableArray array];
        NSArray *models=[[NSUserDefaults standardUserDefaults] arrayForKey:kModels] ?: @[];
        for (NSString *model in models) {
            PSSpecifier *row=[PSSpecifier preferenceSpecifierNamed:model target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
            [row setProperty:model forKey:@"modelValue"];
            row.buttonAction=@selector(selectModel:);
            [rows addObject:row];
        }
        if (!models.count) [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"暂无模型，请返回后重新获取" target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
        _specifiers=[rows mutableCopy];
    }
    return _specifiers;
}
- (void)selectModel:(PSSpecifier *)specifier {
    NSString *model=[specifier propertyForKey:@"modelValue"];
    if (model.length) [[NSUserDefaults standardUserDefaults] setObject:model forKey:kModel];
    [self.navigationController popViewControllerAnimated:YES];
}
@end
