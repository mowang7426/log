#import "CAWorkbench.h"
#import <CommonCrypto/CommonDigest.h>
#if __has_feature(objc_arc)
#define CAAutorelease(x) (x)
#else
#define CAAutorelease(x) [(x) autorelease]
#endif
static NSString *S(id x) { return [x isKindOfClass:NSString.class] ? x : @""; }
static NSArray *A(id x) { return [x isKindOfClass:NSArray.class] ? x : @[]; }
static NSDictionary *D(id x) { return [x isKindOfClass:NSDictionary.class] ? x : @{}; }
static BOOL Index(id x, NSUInteger count) { return [x isKindOfClass:NSNumber.class] && [x doubleValue]>=0 && [x doubleValue]==[x unsignedIntegerValue] && [x unsignedIntegerValue]<count; }
@implementation CAWorkbench
+ (NSArray *)evidence:(NSDictionary *)r mode:(NSString *)mode {
    NSArray *threads=A(r[@"threads"]), *images=A(r[@"usedImages"]);
    id fault=r[@"normalizedFaultingThread"] ?: r[@"faultingThread"];
    if (!Index(fault,threads.count)) { fault=nil; for (NSUInteger i=0;i<threads.count;i++) { id t=D(threads[i])[@"triggered"]; if ([t isKindOfClass:NSNumber.class] && [t boolValue]) { fault=@(i); break; } } }
    NSMutableSet *faultImages=[NSMutableSet set];
    if (Index(fault,threads.count)) for (id item in A(D(threads[[fault unsignedIntegerValue]])[@"frames"])) { id ix=D(item)[@"imageIndex"]; if (Index(ix,images.count)) [faultImages addObject:ix]; }
    NSMutableArray *rows=[NSMutableArray array];
    if ([mode isEqual:@"modules"]) {
        for (NSUInteger i=0;i<images.count;i++) {
            NSDictionary *im=D(images[i]); NSString *path=S(im[@"path"]), *name=S(im[@"name"]);
            BOOL injected=[path containsString:@"/MobileSubstrate/"] || [path containsString:@"/TweakInject/"] || [path containsString:@"/usr/lib/Tweak"];
            NSString *role=[faultImages containsObject:@(i)] ? @"故障线程帧实际引用（并非根因证明）" : (injected ? @"注入路径线索；未在故障帧引用，不归因" : @"仅已加载镜像；不排名、不归因");
            [rows addObject:[NSString stringWithFormat:@"镜像 #%lu %@\n%@\n路径：%@\nUUID：%@ · base：%@ · size：%@",(unsigned long)i,name.length?name:@"未知",role,path, S(im[@"uuid"]),im[@"base"] ?: @"未知",im[@"size"] ?: @"未知"]];
        }
    } else {
        for (NSUInteger i=0;i<threads.count;i++) {
            if ([mode isEqual:@"fault"] && (!Index(fault,threads.count) || i!=[fault unsignedIntegerValue])) continue;
            NSDictionary *t=D(threads[i]); NSArray *frames=A(t[@"frames"]);
            [rows addObject:[NSString stringWithFormat:@"线程 #%lu %@\n名称：%@ · queue：%@ · %lu 帧",(unsigned long)i,Index(fault,threads.count)&&i==[fault unsignedIntegerValue]?@"故障线程":@"其他线程",S(t[@"name"]),S(t[@"queue"]),(unsigned long)frames.count]];
            for (NSUInteger j=0;j<frames.count;j++) {
                NSDictionary *f=D(frames[j]); id ix=f[@"imageIndex"]; NSDictionary *im=Index(ix,images.count)?D(images[[ix unsignedIntegerValue]]):@{};
                [rows addObject:[NSString stringWithFormat:@"线程 %lu · 帧 %lu\n%@ · %@\nimageIndex：%@ · offset：%@\n%@",(unsigned long)i,(unsigned long)j,S(im[@"name"]).length?S(im[@"name"]):@"镜像未解析",S(f[@"symbol"]).length?S(f[@"symbol"]):@"符号未知",ix ?: @"未知",f[@"imageOffset"] ?: @"未知",S(im[@"path"])]];
            }
        }
    }
    if (!rows.count) [rows addObject:@"无可解析的结构化证据；未知不代表根因。请核对源文件。"];
    return rows;
}
+ (NSArray *)filterCases:(NSArray *)cases query:(NSString *)query status:(NSString *)status {
    NSMutableArray *out=[NSMutableArray array];
    for (id item in A(cases)) {
        NSDictionary *c=D(item); BOOL rejected=[c[@"rejected"] boolValue], verified=[c[@"confirmed"] boolValue];
        if ([status isEqual:@"validated"] && (!verified||rejected)) continue;
        if ([status isEqual:@"unverified"] && (verified||rejected)) continue;
        if ([status isEqual:@"rejected"] && !rejected) continue;
        NSString *search=[NSString stringWithFormat:@"%@ %@",c[@"key"] ?: @"",c[@"evidence"] ?: @""];
        if (query.length && [search rangeOfString:query options:NSCaseInsensitiveSearch].location==NSNotFound) continue;
        [out addObject:c];
    } return out;
}
+ (NSString *)responseText:(NSData *)data status:(NSInteger)status error:(NSError **)error {
    id parsed=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSDictionary *o=D(parsed); NSArray *choices=A(o[@"choices"]); NSString *text=choices.count?S(D(D(choices[0])[@"message"])[@"content"]):@"";
    if (status>=200 && status<300 && text.length && text.length<=1000000) return text;
    if (error) *error=[NSError errorWithDomain:@"CAAI" code:status ?: -1 userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"HTTP %ld：响应格式无效、内容为空或服务报错（%lu 字节）。",(long)status,(unsigned long)data.length]}];
    return nil;
}
+ (NSDictionary *)payload:(NSDictionary *)r source:(NSString *)source model:(NSString *)model prompt:(NSString *)prompt {
    NSMutableDictionary *safe=[NSMutableDictionary dictionary];
    for (NSString *k in @[@"normalizedProcessName",@"normalizedBundleID",@"normalizedSystemVersion",@"normalizedExceptionType",@"normalizedSignal",@"normalizedCodes",@"normalizedFaultingThread",@"timestamp",@"bug_type",@"app_version",@"build_version",@"exception",@"termination"]) if (r[k] && r[k]!=NSNull.null) safe[k]=r[k];
    NSArray *ev=[self evidence:r mode:@"fault"]; safe[@"faultEvidence"]=[ev subarrayWithRange:NSMakeRange(0,MIN(ev.count,80))];
    if (source) safe[@"source_file"]=source;
    NSData *json=[NSJSONSerialization dataWithJSONObject:safe options:NSJSONWritingSortedKeys error:nil];
    NSString *content=json?CAAutorelease([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]):@"{}";
    return @{@"model":model ?: @"",@"messages":@[@{@"role":@"system",@"content":prompt ?: @"区分事实与推测，不将已加载模块认定根因。"},@{@"role":@"user",@"content":content}],@"temperature":@0.2,@"max_tokens":@2048};
}
+ (NSString *)cacheKeyForBody:(NSData *)body endpoint:(NSString *)endpoint {
    NSMutableData *d=[NSMutableData dataWithData:[(endpoint ?: @"") dataUsingEncoding:NSUTF8StringEncoding]]; [d appendBytes:"\0" length:1]; [d appendData:body ?: [NSData data]];
    unsigned char hash[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(d.bytes,(CC_LONG)d.length,hash); NSMutableString *s=[NSMutableString string]; for (NSUInteger i=0;i<sizeof(hash);i++) [s appendFormat:@"%02x",hash[i]]; return s;
}
+ (NSArray *)historyAtPath:(NSString *)path {
    NSData *data=[NSData dataWithContentsOfFile:path]; if (!data || data.length>12000000) return @[];
    id parsed=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]; NSMutableArray *out=[NSMutableArray array];
    for (id x in A(parsed)) { NSDictionary *e=D(x); if ([e[@"schema"] isEqual:@1] && S(e[@"key"]).length==64 && S(e[@"answer"]).length && S(e[@"answer"]).length<=100000 && S(e[@"model"]).length && S(e[@"time"]).length && [@[@"structured",@"source"] containsObject:e[@"scope"]]) { [out addObject:@{@"schema":@1,@"key":e[@"key"],@"model":e[@"model"],@"time":e[@"time"],@"scope":e[@"scope"],@"answer":e[@"answer"]}]; if (out.count==100) break; } } return out;
}
+ (BOOL)saveAnswer:(NSString *)answer key:(NSString *)key model:(NSString *)model scope:(NSString *)scope path:(NSString *)path {
    if (!answer.length || answer.length>100000 || key.length!=64 || !model.length || ![@[@"structured",@"source"] containsObject:scope]) return NO;
    NSMutableArray *a=[NSMutableArray arrayWithArray:[self historyAtPath:path]];
    [a insertObject:@{@"schema":@1,@"key":key,@"model":model,@"scope":scope,@"time":[NSDate date].description,@"answer":answer} atIndex:0]; if (a.count>100) [a removeObjectsInRange:NSMakeRange(100,a.count-100)];
    if (![[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:nil]) return NO;
    NSData *data=[NSJSONSerialization dataWithJSONObject:a options:NSJSONWritingSortedKeys error:nil]; return [data writeToFile:path options:NSDataWritingAtomic error:nil];
}
+ (NSString *)exportReport:(NSDictionary *)r local:(NSDictionary *)local historical:(NSDictionary *)historical history:(NSArray *)history {
    NSMutableString *s=[NSMutableString stringWithFormat:@"# CrashAnalyzer 1.1.0 · MoWang\n\n来源：本地诊断；所有结论仍需验证。\n原始文件链接/路径：%@\n事件：%@ · 应用：%@\n\n## 本地结果\n%@\n\n## 故障线程证据（最多 80 项，完整证据见浏览页/原文件）\n%@\n",S(r[@"path"]),S(r[@"incident_id"]),S(r[@"normalizedProcessName"]),local ?: @{},[[[self evidence:r mode:@"fault"] subarrayWithRange:NSMakeRange(0,MIN([[self evidence:r mode:@"fault"] count],80))] componentsJoinedByString:@"\n\n"]];
    if (historical) [s appendFormat:@"\n## 严格匹配历史案例（不是本次确定根因）\nID：%@\n实测仅表示用户记录：%@\n%@\n%@\n",S(historical[@"id"]),historical[@"confirmed"] ?: @NO,S(historical[@"testNote"]),S(historical[@"answer"])];
    for (NSDictionary *e in history) [s appendFormat:@"\n## AI 历史参考（不是当前确定根因）\n模型：%@ · 时间：%@ · 范围：%@ · payload key：%@\n%@\n",S(e[@"model"]),S(e[@"time"]),S(e[@"scope"]),S(e[@"key"]),S(e[@"answer"])];
    return s;
}
+ (NSURL *)writeExport:(NSString *)text extension:(NSString *)ext error:(NSError **)error {
    NSString *name=[NSString stringWithFormat:@"CrashAnalyzer-%@.%@",NSUUID.UUID.UUIDString,[ext isEqual:@"md"]?@"md":@"txt"];
    NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:name]; return [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error]?[NSURL fileURLWithPath:path]:nil;
}
@end
