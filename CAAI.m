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
        PSSpecifier *endpoint=[PSSpecifier preferenceSpecifierNamed:@"接口地址" target:self set:@selector(setEndpoint:specifier:) get:@selector(endpoint:) detail:nil cell:PSTextFieldCell edit:nil];
        [endpoint setProperty:@"https://api.openai.com/v1/chat/completions" forKey:@"defaultValue"];
        [rows addObject:endpoint];
        PSSpecifier *model=[PSSpecifier preferenceSpecifierNamed:@"模型名称" target:self set:@selector(setModel:specifier:) get:@selector(model:) detail:nil cell:PSTextFieldCell edit:nil];
        [model setProperty:@"gpt-4o-mini" forKey:@"defaultValue"];
        [rows addObject:model];
        PSSpecifier *key=[PSSpecifier preferenceSpecifierNamed:@"API Key" target:self set:@selector(setKey:specifier:) get:@selector(key:) detail:nil cell:PSSecureEditTextCell edit:nil];
        [rows addObject:key];
        PSSpecifier *prompt=[PSSpecifier preferenceSpecifierNamed:@"系统提示词" target:self set:@selector(setPrompt:specifier:) get:@selector(prompt:) detail:nil cell:PSTextFieldCell edit:nil];
        [prompt setProperty:@"分析 iOS IPS 日志，区分事实与推测，引用证据并给出排查步骤。" forKey:@"defaultValue"];
        [rows addObject:prompt];
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"隐私" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        PSSpecifier *include=[PSSpecifier preferenceSpecifierNamed:@"发送完整源文件" target:self set:@selector(setIncludeSource:specifier:) get:@selector(includeSource:) detail:nil cell:PSSwitchCell edit:nil];
        [include setProperty:@NO forKey:@"defaultValue"];
        [rows addObject:include];
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"关闭时只发送解析后的结构化信息；开启后会把完整 .ips 内容发送到所配置的模型服务。" target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
        _specifiers=[rows mutableCopy];
    }
    return _specifiers;
}
- (NSUserDefaults *)defaults { return [NSUserDefaults standardUserDefaults]; }
- (id)get:(NSString *)key specifier:(PSSpecifier *)s { return [[self defaults] objectForKey:key] ?: [s propertyForKey:@"defaultValue"]; }
- (id)endpoint:(PSSpecifier *)s { return [self get:kCAAIEndpoint specifier:s]; }
- (id)model:(PSSpecifier *)s { return [self get:kCAAIMode specifier:s]; }
- (id)key:(PSSpecifier *)s { return [self get:kCAAIKey specifier:s]; }
- (id)prompt:(PSSpecifier *)s { return [self get:kCAAIPrompt specifier:s]; }
- (id)includeSource:(PSSpecifier *)s { return @([[self defaults] boolForKey:kCAAIIncludeSource]); }
- (void)setEndpoint:(id)v specifier:(PSSpecifier *)s { [[self defaults] setObject:v ?: @"" forKey:kCAAIEndpoint]; }
- (void)setModel:(id)v specifier:(PSSpecifier *)s { [[self defaults] setObject:v ?: @"" forKey:kCAAIMode]; }
- (void)setKey:(id)v specifier:(PSSpecifier *)s { [[self defaults] setObject:v ?: @"" forKey:kCAAIKey]; }
- (void)setPrompt:(id)v specifier:(PSSpecifier *)s { [[self defaults] setObject:v ?: @"" forKey:kCAAIPrompt]; }
- (void)setIncludeSource:(id)v specifier:(PSSpecifier *)s { [[self defaults] setBool:[v boolValue] forKey:kCAAIIncludeSource]; }
@end

@implementation CAAIService
+ (instancetype)shared { static CAAIService *s; static dispatch_once_t once; dispatch_once(&once,^{ s=[self new]; }); return s; }
- (void)analyzeReport:(NSDictionary *)report includeSource:(BOOL)includeSource completion:(void (^)(NSString *,NSError *))completion {
    NSUserDefaults *d=[NSUserDefaults standardUserDefaults];
    NSString *endpoint=[d stringForKey:kCAAIEndpoint] ?: @"https://api.openai.com/v1/chat/completions";
    NSString *model=[d stringForKey:kCAAIMode] ?: @"gpt-4o-mini";
    NSString *key=[d stringForKey:kCAAIKey];
    NSString *prompt=[d stringForKey:kCAAIPrompt] ?: @"分析 iOS IPS 日志，提供证据和排查步骤";
    if (!key.length) { if(completion) completion(nil,[NSError errorWithDomain:@"CrashAnalyzerAI" code:1 userInfo:@{NSLocalizedDescriptionKey:@"请先在 AI 模型配置填写 API Key。"}]); return; }
    NSURL *url=[NSURL URLWithString:endpoint];
    if (!url || !([url.scheme isEqualToString:@"https"] || [url.scheme isEqualToString:@"http"])) { if(completion) completion(nil,[NSError errorWithDomain:@"CrashAnalyzerAI" code:2 userInfo:@{NSLocalizedDescriptionKey:@"接口地址无效，请输入完整的 http(s) URL。"}]); return; }
    NSMutableDictionary *payload=[NSMutableDictionary dictionaryWithDictionary:report ?: @{}];
    NSString *path=[payload[@"path"] isKindOfClass:[NSString class]] ? payload[@"path"] : nil;
    [payload removeObjectForKey:@"path"];
    if (includeSource && path.length) {
        NSString *source=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        if (source) payload[@"source_file"]=source;
    }
    NSData *reportJSON=[NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingFragmentsAllowed error:nil];
    NSString *reportText=reportJSON ? [[NSString alloc] initWithData:reportJSON encoding:NSUTF8StringEncoding] : [payload description];
    NSString *content=[NSString stringWithFormat:@"%@\n\n请基于以下日志分析。明确区分日志事实与推测，不要把未出现的模块说成根因。\n%@",prompt,reportText ?: @"{}"];
    NSDictionary *requestBody=@{@"model":model,@"messages":@[@{@"role":@"user",@"content":content}],@"temperature":@0.2};
    NSData *requestData=[NSJSONSerialization dataWithJSONObject:requestBody options:0 error:nil];
    if (!requestData) { if(completion) completion(nil,[NSError errorWithDomain:@"CrashAnalyzerAI" code:3 userInfo:@{NSLocalizedDescriptionKey:@"无法编码请求内容。"}]); return; }
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:90];
    req.HTTPMethod=@"POST"; req.HTTPBody=requestData;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:[NSString stringWithFormat:@"Bearer %@",key] forHTTPHeaderField:@"Authorization"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
        NSError *outError=error; NSString *text=nil;
        if (!outError) {
            NSInteger status=[(NSHTTPURLResponse *)response statusCode];
            NSDictionary *obj=data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingFragmentsAllowed error:nil] : nil;
            if (status<200 || status>=300) { NSString *msg=obj[@"error"][@"message"] ?: [NSString stringWithFormat:@"HTTP %ld",(long)status]; outError=[NSError errorWithDomain:@"CrashAnalyzerAI" code:status userInfo:@{NSLocalizedDescriptionKey:msg}]; }
            else text=obj[@"choices"][0][@"message"][@"content"] ?: obj[@"message"] ?: obj[@"response"];
            if (!text.length && !outError) outError=[NSError errorWithDomain:@"CrashAnalyzerAI" code:4 userInfo:@{NSLocalizedDescriptionKey:@"模型响应格式无法识别，请确认服务兼容 OpenAI Chat Completions。"}];
        }
        dispatch_async(dispatch_get_main_queue(),^{ if(completion) completion(text,outError); });
    }] resume];
}
@end
