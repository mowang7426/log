#import "CAAI.h"
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>

static NSString * const kEndpoint=@"CAAIEndpoint";
static NSString * const kModel=@"CAAIMode";
static NSString * const kKey=@"CAAIKey";
static NSString * const kPrompt=@"CAAIPrompt";
static NSString * const kSource=@"CAAIIncludeSource";
static NSString * const kModels=@"CAAIFetchedModels";

static NSString * CAChatURL(NSString *raw) {
    NSString *s=[raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while (s.length && [s hasSuffix:@"/"]) s=[s substringToIndex:s.length-1];
    if ([s hasSuffix:@"/chat/completions"]) return s;
    if ([s hasSuffix:@"/v1"]) return [s stringByAppendingString:@"/chat/completions"];
    return [s stringByAppendingString:@"/v1/chat/completions"];
}
static NSString * CAModelsURL(NSString *raw) {
    NSString *chat=CAChatURL(raw);
    return [[chat substringToIndex:chat.length-@"/chat/completions".length] stringByAppendingString:@"/models"];
}

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
            PSSpecifier *picker=[PSSpecifier preferenceSpecifierNamed:@"选择模型" target:self set:@selector(setModel:specifier:) get:@selector(model:) detail:nil cell:PSMultiValueCell edit:nil];
            [picker setProperty:models forKey:@"values"]; [picker setProperty:models forKey:@"titles"]; [rows addObject:picker];
        }
        PSSpecifier *manual=[PSSpecifier preferenceSpecifierNamed:@"模型名称（也可手动填写）" target:self set:@selector(setModel:specifier:) get:@selector(model:) detail:nil cell:PSEditTextCell edit:nil]; [manual setProperty:@"deepseek-ai/DeepSeek-V4-Pro" forKey:@"placeholder"]; [rows addObject:manual];
        PSSpecifier *key=[PSSpecifier preferenceSpecifierNamed:@"API Key" target:self set:@selector(setKey:specifier:) get:@selector(key:) detail:nil cell:PSEditTextCell edit:nil]; [rows addObject:key];
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
- (void)testConnection:(PSSpecifier *)s { (void)s; UIAlertController *w=[UIAlertController alertControllerWithTitle:@"测试连接" message:@"发送最小测试请求…" preferredStyle:UIAlertControllerStyleAlert]; [self presentViewController:w animated:YES completion:nil]; [[CAAIService shared] testConnection:^(BOOL ok,NSString *message){ [w dismissViewControllerAnimated:YES completion:^{ UIAlertController *a=[UIAlertController alertControllerWithTitle:(ok?@"连接成功":@"连接失败") message:message preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }]; }]; }
@end

@implementation CAAIService
+ (instancetype)shared { static CAAIService *s; static dispatch_once_t once; dispatch_once(&once,^{s=[self new];}); return s; }
- (NSMutableURLRequest *)requestTo:(NSString *)url method:(NSString *)method body:(NSDictionary *)body {
    NSURL *u=[NSURL URLWithString:url]; if(!u)return nil; NSMutableURLRequest *q=[NSMutableURLRequest requestWithURL:u cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:45]; q.HTTPMethod=method;
    NSString *key=[[NSUserDefaults standardUserDefaults] stringForKey:kKey]; if(key.length)[q setValue:[NSString stringWithFormat:@"Bearer %@",key] forHTTPHeaderField:@"Authorization"];
    if(body){q.HTTPBody=[NSJSONSerialization dataWithJSONObject:body options:0 error:nil];[q setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];} return q;
}
- (void)fetchModels:(void (^)(NSArray *,NSString *))completion {
    NSUserDefaults *d=[NSUserDefaults standardUserDefaults]; NSString *raw=[d stringForKey:kEndpoint] ?: @""; NSString *url=CAModelsURL(raw); NSMutableURLRequest *q=[self requestTo:url method:@"GET" body:nil];
    if(!q){if(completion)completion(nil,@"接口地址格式无效。");return;}
    [[[NSURLSession sharedSession] dataTaskWithRequest:q completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){ NSDictionary *o=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil; NSInteger status=[(NSHTTPURLResponse *)response statusCode]; NSArray *items=o[@"data"]; NSMutableArray *ids=[NSMutableArray array]; for(NSDictionary *m in items)if([m[@"id"] isKindOfClass:[NSString class]])[ids addObject:m[@"id"]]; NSString *msg=error.localizedDescription ?: o[@"error"][@"message"] ?: [NSString stringWithFormat:@"HTTP %ld；确认服务支持 GET %@",(long)status,url]; dispatch_async(dispatch_get_main_queue(),^{if(completion)completion((status>=200&&status<300&&ids.count)?ids:nil,(status>=200&&status<300&&ids.count)?nil:msg);}); }]resume];
}
- (void)testConnection:(void (^)(BOOL,NSString *))completion {
    NSUserDefaults *d=[NSUserDefaults standardUserDefaults]; NSString *raw=[d stringForKey:kEndpoint] ?: @""; NSString *model=[d stringForKey:kModel] ?: @""; if(!model.length){if(completion)completion(NO,@"请填写或选择模型名称。");return;}
    NSDictionary *body=@{@"model":model,@"messages":@[@{@"role":@"user",@"content":@"Reply with exactly: connection-ok"}],@"max_tokens":@8}; NSMutableURLRequest *q=[self requestTo:CAChatURL(raw) method:@"POST" body:body]; if(!q){if(completion)completion(NO,@"接口地址无效。");return;}
    [[[NSURLSession sharedSession] dataTaskWithRequest:q completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){NSDictionary *o=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;NSInteger status=[(NSHTTPURLResponse *)response statusCode];NSString *text=o[@"choices"][0][@"message"][ @"content"];NSString *msg=error.localizedDescription ?: o[@"error"][@"message"] ?: text ?: [NSString stringWithFormat:@"HTTP %ld",(long)status];BOOL ok=!error&&status>=200&&status<300&&text.length;dispatch_async(dispatch_get_main_queue(),^{if(completion)completion(ok,msg);});}]resume];
}
- (void)analyzeReport:(NSDictionary *)report includeSource:(BOOL)includeSource completion:(void (^)(NSString *,NSError *))completion {
    NSUserDefaults *d=[NSUserDefaults standardUserDefaults]; NSString *model=[d stringForKey:kModel] ?: @""; if(!model.length){if(completion)completion(nil,[NSError errorWithDomain:@"CAAI" code:1 userInfo:@{NSLocalizedDescriptionKey:@"请先选择或填写模型名称。"}]);return;}
    NSMutableDictionary *p=[NSMutableDictionary dictionaryWithDictionary:report ?: @{}]; NSString *path=p[@"path"]; [p removeObjectForKey:@"path"]; if(includeSource&&path.length){NSString *src=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];if(src)p[@"source_file"]=src;}
    NSData *jd=[NSJSONSerialization dataWithJSONObject:p options:0 error:nil]; NSString *prompt=[d stringForKey:kPrompt] ?: @"分析 iOS IPS 日志，提供证据和排查步骤"; NSString *content=[NSString stringWithFormat:@"%@\n\n日志：%@",prompt,jd?[[NSString alloc]initWithData:jd encoding:NSUTF8StringEncoding]:p]; NSDictionary *body=@{@"model":model,@"messages":@[@{@"role":@"user",@"content":content}],@"temperature":@0.2}; NSMutableURLRequest *q=[self requestTo:CAChatURL([d stringForKey:kEndpoint] ?: @"") method:@"POST" body:body]; if(!q){if(completion)completion(nil,[NSError errorWithDomain:@"CAAI" code:2 userInfo:@{NSLocalizedDescriptionKey:@"接口地址无效。"}]);return;}
    [[[NSURLSession sharedSession] dataTaskWithRequest:q completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){NSDictionary *o=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;NSInteger status=[(NSHTTPURLResponse *)response statusCode];NSString *text=o[@"choices"][0][@"message"][@"content"];NSError *e=error;if(!text.length&&!e)e=[NSError errorWithDomain:@"CAAI" code:status userInfo:@{NSLocalizedDescriptionKey:o[@"error"][@"message"] ?: [NSString stringWithFormat:@"HTTP %ld",(long)status]}];dispatch_async(dispatch_get_main_queue(),^{if(completion)completion(text,e);});}]resume];
}
@end
