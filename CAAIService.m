#import "CAAI.h"
#import "CAWorkbench.h"
#import "CACaseStore.h"
#import "CALogStore.h"
static NSError *Failure(NSString *s) { return [NSError errorWithDomain:@"CAAI" code:-1 userInfo:@{NSLocalizedDescriptionKey:s}]; }
static NSString *ChatURL(NSString *raw) {
    NSString *s=[raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([s hasSuffix:@"/"]) s=[s substringToIndex:s.length-1];
    if ([s hasSuffix:@"/chat/completions"]) return s;
    return [s stringByAppendingString:[s hasSuffix:@"/v1"]?@"/chat/completions":@"/v1/chat/completions"];
}
@implementation CAAIService {
    NSURLSession *_session;
    NSURLSessionDataTask *_active;
}
+ (instancetype)shared { static CAAIService *s; static dispatch_once_t once; dispatch_once(&once,^{s=[self new];}); return s; }
- (NSURLSession *)session {
    if (!_session) { NSURLSessionConfiguration *c=[NSURLSessionConfiguration ephemeralSessionConfiguration]; c.timeoutIntervalForRequest=180; c.timeoutIntervalForResource=180; _session=[[NSURLSession sessionWithConfiguration:c delegate:self delegateQueue:nil] retain]; }
    return _session;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler {
    // Refuse all redirects: never forward a bearer credential to another origin.
    completionHandler(nil);
}
- (NSString *)historyPath { return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/CrashAnalyzer/ai-history-v1.json"]; }
- (NSArray *)history { return [CAWorkbench historyAtPath:[self historyPath]]; }
- (NSArray *)historyForReport:(NSDictionary *)report {
    NSMutableArray *out=[NSMutableArray array];
    // Only exact current payload keys; model/prompt/endpoint changes cannot become a current answer.
    for (NSNumber *include in @[@NO,@YES]) {
        NSDictionary *p=[self prepareReport:report includeSource:include.boolValue error:nil];
        for (NSDictionary *e in [self history]) if ([e[@"key"] isEqual:p[@"key"]] && ![out containsObject:e]) [out addObject:e];
    } return out;
}
- (NSMutableURLRequest *)request:(NSString *)endpoint body:(NSData *)body {
    NSURL *u=[NSURL URLWithString:endpoint];
    if (![u.scheme.lowercaseString isEqual:@"https"] || !u.host.length || u.user.length || u.password.length || u.query.length || u.fragment.length) return nil;
    NSMutableURLRequest *r=[NSMutableURLRequest requestWithURL:u]; r.HTTPMethod=body?@"POST":@"GET"; r.HTTPBody=body;
    NSString *key=[[NSUserDefaults standardUserDefaults] stringForKey:@"CAAIKey"]; if (key.length) [r setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    if (body) [r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"]; return r;
}
- (NSDictionary *)prepareReport:(NSDictionary *)report includeSource:(BOOL)include error:(NSError **)error {
    NSUserDefaults *d=NSUserDefaults.standardUserDefaults; NSString *model=[d stringForKey:@"CAAIMode"] ?: @"";
    NSString *endpoint=ChatURL([d stringForKey:@"CAAIEndpoint"] ?: @"");
    if (!model.length || ![self request:endpoint body:nil]) { if(error)*error=Failure(@"填写模型与有效 HTTPS 接口（不允许用户信息、查询参数）。"); return nil; }
    NSString *source=nil;
    if (include) {
        NSString *path=[report[@"path"] isKindOfClass:NSString.class]?report[@"path"]:nil;
        NSDictionary *attrs=path?[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil]:nil;
        if (!attrs || [attrs fileSize]>600000) { if(error)*error=Failure(@"源文件不可读或超过 600000 字节；请选择结构化范围。"); return nil; }
        source=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        if (!source) { if(error)*error=Failure(@"源文件不是可读取的 UTF-8 文本。"); return nil; }
    }
    NSDictionary *body=[CAWorkbench payload:report source:source model:model prompt:[d stringForKey:@"CAAIPrompt"]];
    NSData *data=[NSJSONSerialization dataWithJSONObject:body options:NSJSONWritingSortedKeys error:nil];
    if (!data || data.length>900000) { if(error)*error=Failure(@"请求超过 900000 字节；关闭完整源文件范围。"); return nil; }
    return @{@"data":data,@"bytes":@(data.length),@"key":[CAWorkbench cacheKeyForBody:data endpoint:endpoint],@"model":model,@"endpoint":endpoint,@"scope":include?@"source":@"structured"};
}
- (void)cancelAnalysis { [_active cancel]; }
- (void)runPrepared:(NSDictionary *)p report:(NSDictionary *)report fresh:(BOOL)fresh completion:(void (^)(NSString *,NSError *))completion {
    if (_active) { completion(nil,Failure(@"已有请求进行中，请等待或取消。")); return; }
    if (!fresh) {
        NSDictionary *reference=[[CACaseStore sharedStore] matchingAIReferenceForReport:report];
        if (reference) { completion([NSString stringWithFormat:@"之前类似日志的 AI 参考（不收费，未联网）\n模型：%@ · 时间：%@ · 范围：%@\n仅供参考，不代表本次确定根因。\n\n%@",reference[@"model"] ?: @"未知",reference[@"createdAt"] ?: @"未知",reference[@"scope"] ?: @"未知",reference[@"answer"] ?: @""],nil); return; }
        for (NSDictionary *entry in [self history]) if ([entry[@"key"] isEqual:p[@"key"]]) { completion([NSString stringWithFormat:@"精确 payload 缓存（不收费）\n模型：%@ · 时间：%@ · 范围：%@\n仅供参考，不代表本次确定根因。\n\n%@",entry[@"model"],entry[@"time"],entry[@"scope"],entry[@"answer"]],nil); return; }
    }
    NSMutableURLRequest *request=[self request:p[@"endpoint"] body:p[@"data"]]; if(!request){completion(nil,Failure(@"HTTPS 接口无效。"));return;}
    _active=[[[self session] dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *networkError){
        NSError *error=networkError; NSInteger status=[response isKindOfClass:NSHTTPURLResponse.class]?[(NSHTTPURLResponse *)response statusCode]:0;
        NSString *text=error?nil:[CAWorkbench responseText:data status:status error:&error];
        __block NSString *shown=text;
        dispatch_async(dispatch_get_main_queue(),^{
            [self->_active release]; self->_active=nil;
            if (text && !error) {
                BOOL saved=[CAWorkbench saveAnswer:text key:p[@"key"] model:p[@"model"] scope:p[@"scope"] path:[self historyPath]];
                BOOL referenceSaved=[[CACaseStore sharedStore] saveAIReference:text forReport:report model:p[@"model"] scope:p[@"scope"]];
                shown=[NSString stringWithFormat:@"AI 参考；不是确定根因\n模型：%@ · 时间：%@ · 范围：%@\n%@\n%@\n\n%@",p[@"model"],[NSDate date].description,p[@"scope"],saved?@"已保存历史":@"历史保存失败（目录或容量限制）",referenceSaved?@"已关联日志指纹/证据":([NSUserDefaults.standardUserDefaults boolForKey:CAAutoSaveCases]?@"日志关联保存失败（目录或容量限制）":@"自动保存 AI 参考已关闭，未写入日志历史"),text];
            }
            completion(shown,error);
        });
    }] retain]; [_active resume];
}
- (void)analyzeReport:(NSDictionary *)report includeSource:(BOOL)include completion:(void (^)(NSString *,NSError *))completion {
    // Compatibility entry must not silently send a paid request without UI preflight.
    completion(nil,Failure(@"请使用诊断工作台预检并确认请求。"));
}
- (void)fetchModels:(void (^)(NSArray *,NSString *))completion {
    NSString *chat=ChatURL([NSUserDefaults.standardUserDefaults stringForKey:@"CAAIEndpoint"] ?: @""); NSString *url=[[chat substringToIndex:chat.length-@"/chat/completions".length] stringByAppendingString:@"/models"];
    NSMutableURLRequest *q=[self request:url body:nil]; if(!q){completion(nil,@"请使用有效 HTTPS 接口。");return;}
    [[[self session] dataTaskWithRequest:q completionHandler:^(NSData *data,NSURLResponse *r,NSError *e){
        id json=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
        id items=[json isKindOfClass:NSDictionary.class]?json[@"data"]:nil;
        NSMutableArray *models=[NSMutableArray array]; NSInteger status=[r isKindOfClass:NSHTTPURLResponse.class]?[(NSHTTPURLResponse *)r statusCode]:0;
        if (!e && status>=200 && status<300 && [items isKindOfClass:NSArray.class]) for(id m in items) if([m isKindOfClass:NSDictionary.class] && [m[@"id"] isKindOfClass:NSString.class]) { [models addObject:m[@"id"]]; if(models.count==500)break; }
        dispatch_async(dispatch_get_main_queue(),^{completion(models.count?models:nil,models.count?nil:@"请求失败或模型列表格式无效。");});
    }] resume];
}
- (void)testConnection:(void (^)(BOOL,NSString *))completion {
    // Kept for compatibility; config directs paid checks through explicit confirmation.
    NSDictionary *r=@{@"normalizedProcessName":@"connection test"}; NSError *e=nil; NSDictionary *p=[self prepareReport:r includeSource:NO error:&e];
    if(!p){completion(NO,e.localizedDescription);return;}
    [self runPrepared:p report:r fresh:YES completion:^(NSString *text,NSError *error){completion(!error,error.localizedDescription ?: text);}];
}
@end
