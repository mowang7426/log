#import "CAAI.h"
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>

static NSString * const kCAAIEndpoint=@"CAAIEndpoint";
static NSString * const kCAAIMode=@"CAAIMode";
static NSString * const kCAAIKey=@"CAAIKey";
static NSString * const kCAAIPrompt=@"CAAIPrompt";
static NSString * const kCAAIIncludeSource=@"CAAIIncludeSource";

@implementation CAAIConfigController
- (id)specifiers {
    if (!_specifiers) {
        NSMutableArray *rows=[NSMutableArray array];
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"OpenAI-compatible 模型" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        PSSpecifier *endpoint=[PSSpecifier preferenceSpecifierNamed:@"接口地址" target:self set:@selector(setEndpoint:specifier:) get:@selector(endpoint:) detail:nil cell:PSEditTextCell edit:nil]; [endpoint setProperty:@"https://api.openai.com/v1/chat/completions" forKey:@"defaultValue"]; [rows addObject:endpoint];
        PSSpecifier *model=[PSSpecifier preferenceSpecifierNamed:@"模型名称" target:self set:@selector(setModel:specifier:) get:@selector(model:) detail:nil cell:PSEditTextCell edit:nil]; [model setProperty:@"gpt-4o-mini" forKey:@"defaultValue"]; [rows addObject:model];
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"API Key" target:self set:@selector(setKey:specifier:) get:@selector(key:) detail:nil cell:PSEditTextCell edit:nil]];
        PSSpecifier *prompt=[PSSpecifier preferenceSpecifierNamed:@"系统提示词" target:self set:@selector(setPrompt:specifier:) get:@selector(prompt:) detail:nil cell:PSEditTextCell edit:nil]; [prompt setProperty:@"分析 iOS IPS 日志，区分事实与推测，引用证据并给出排查步骤。" forKey:@"defaultValue"]; [rows addObject:prompt];
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"测试模型连接" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil]];
        PSSpecifier *test=[rows lastObject]; test.buttonAction=@selector(testConnection:);
        PSSpecifier *include=[PSSpecifier preferenceSpecifierNamed:@"发送完整源文件" target:self set:@selector(setIncludeSource:specifier:) get:@selector(includeSource:) detail:nil cell:PSSwitchCell edit:nil]; [include setProperty:@NO forKey:@"defaultValue"]; [rows addObject:include];
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"关闭时只发送结构化信息。开启后会发送完整 .ips。" target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
        _specifiers=[rows mutableCopy];
    } return _specifiers;
}
- (NSUserDefaults *)defaults { return [NSUserDefaults standardUserDefaults]; }
- (id)get:(NSString *)key specifier:(PSSpecifier *)s { return [[self defaults] objectForKey:key] ?: [s propertyForKey:@"defaultValue"]; }
- (id)endpoint:(PSSpecifier *)s{return [self get:kCAAIEndpoint specifier:s];} - (id)model:(PSSpecifier *)s{return [self get:kCAAIMode specifier:s];} - (id)key:(PSSpecifier *)s{return [self get:kCAAIKey specifier:s];} - (id)prompt:(PSSpecifier *)s{return [self get:kCAAIPrompt specifier:s];} - (id)includeSource:(PSSpecifier *)s{return @([[self defaults] boolForKey:kCAAIIncludeSource]);}
- (void)setEndpoint:(id)v specifier:(PSSpecifier *)s{[[self defaults]setObject:v?:@"" forKey:kCAAIEndpoint];} - (void)setModel:(id)v specifier:(PSSpecifier *)s{[[self defaults]setObject:v?:@"" forKey:kCAAIMode];} - (void)setKey:(id)v specifier:(PSSpecifier *)s{[[self defaults]setObject:v?:@"" forKey:kCAAIKey];} - (void)setPrompt:(id)v specifier:(PSSpecifier *)s{[[self defaults]setObject:v?:@"" forKey:kCAAIPrompt];} - (void)setIncludeSource:(id)v specifier:(PSSpecifier *)s{[[self defaults]setBool:[v boolValue] forKey:kCAAIIncludeSource];}
- (void)testConnection:(PSSpecifier *)specifier {
    (void)specifier;
    UIAlertController *loading=[UIAlertController alertControllerWithTitle:@"测试连接" message:@"正在发送最小测试请求…" preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loading animated:YES completion:nil];
    [[CAAIService shared] testConnection:^(BOOL ok, NSString *message){
        [loading dismissViewControllerAnimated:YES completion:^{
            UIAlertController *alert=[UIAlertController alertControllerWithTitle:(ok ? @"连接成功" : @"连接失败") message:message preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }];
    }];
}
@end

@implementation CAAIService
+ (instancetype)shared { static CAAIService *s; static dispatch_once_t once; dispatch_once(&once,^{s=[self new];}); return s; }
- (void)testConnection:(void (^)(BOOL,NSString *))completion {
    NSUserDefaults *d=[NSUserDefaults standardUserDefaults]; NSString *endpoint=[d stringForKey:kCAAIEndpoint]; NSString *model=[d stringForKey:kCAAIMode]; NSString *key=[d stringForKey:kCAAIKey];
    if (!endpoint.length || !model.length || !key.length) { if(completion) completion(NO,@"请先填写接口地址、模型名称和 API Key。"); return; }
    NSURL *url=[NSURL URLWithString:endpoint]; if(!url || !url.scheme.length){if(completion)completion(NO,@"接口地址无效。");return;}
    NSDictionary *body=@{@"model":model,@"messages":@[@{@"role":@"user",@"content":@"Reply with exactly: connection-ok"}],@"max_tokens":@8};
    NSMutableURLRequest *q=[NSMutableURLRequest requestWithURL:url cachePolicy:0 timeoutInterval:30]; q.HTTPMethod=@"POST"; q.HTTPBody=[NSJSONSerialization dataWithJSONObject:body options:0 error:nil]; [q setValue:@"application/json" forHTTPHeaderField:@"Content-Type"]; [q setValue:[NSString stringWithFormat:@"Bearer %@",key] forHTTPHeaderField:@"Authorization"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:q completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
        NSDictionary *obj=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil; NSInteger status=[(NSHTTPURLResponse *)response statusCode]; NSString *msg=obj[@"error"][@"message"] ?: obj[@"choices"][0][@"message"][@"content"];
        BOOL ok=!error && status>=200 && status<300 && msg.length; if(!msg.length) msg=error.localizedDescription ?: [NSString stringWithFormat:@"HTTP %ld",(long)status];
        dispatch_async(dispatch_get_main_queue(),^{if(completion)completion(ok,ok?[NSString stringWithFormat:@"HTTP %ld，模型已返回：%@",(long)status,msg]:msg);});
    }] resume];
}

- (void)analyzeReport:(NSDictionary *)report includeSource:(BOOL)includeSource completion:(void (^)(NSString *,NSError *))completion {
 NSUserDefaults *d=[NSUserDefaults standardUserDefaults]; NSString *endpoint=[d stringForKey:kCAAIEndpoint]?:@"https://api.openai.com/v1/chat/completions"; NSString *model=[d stringForKey:kCAAIMode]?:@"gpt-4o-mini"; NSString *key=[d stringForKey:kCAAIKey]; NSString *prompt=[d stringForKey:kCAAIPrompt]?:@"分析 iOS IPS 日志，提供证据和排查步骤";
 if(!key.length){if(completion)completion(nil,[NSError errorWithDomain:@"CrashAnalyzerAI" code:1 userInfo:@{NSLocalizedDescriptionKey:@"请先填写 API Key。"}]);return;} NSMutableDictionary *p=[NSMutableDictionary dictionaryWithDictionary:report?:@{}]; NSString *path=p[@"path"]; [p removeObjectForKey:@"path"]; if(includeSource&&path.length){NSString *src=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];if(src)p[@"source_file"]=src;} NSData *jd=[NSJSONSerialization dataWithJSONObject:p options:0 error:nil]; NSString *content=[NSString stringWithFormat:@"%@\n\n日志：%@",prompt,jd?[[NSString alloc]initWithData:jd encoding:NSUTF8StringEncoding]:p]; NSDictionary *rb=@{@"model":model,@"messages":@[@{@"role":@"user",@"content":content}],@"temperature":@0.2}; NSMutableURLRequest *q=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:endpoint] cachePolicy:0 timeoutInterval:90]; q.HTTPMethod=@"POST";q.HTTPBody=[NSJSONSerialization dataWithJSONObject:rb options:0 error:nil];[q setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];[q setValue:[NSString stringWithFormat:@"Bearer %@",key] forHTTPHeaderField:@"Authorization"];
 [[[NSURLSession sharedSession]dataTaskWithRequest:q completionHandler:^(NSData *data,NSURLResponse *resp,NSError *err){NSDictionary *o=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;NSString *text=o[@"choices"][0][@"message"][@"content"];if(!text.length)text=o[@"error"][@"message"];if(!text.length)text=@"模型没有返回结果。";dispatch_async(dispatch_get_main_queue(),^{if(completion)completion(text,err);});}]resume];
}
@end
