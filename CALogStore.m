#import "CALogStore.h"

static NSString * const CAUnknown = @"其他";

@implementation CALogStore
+ (instancetype)sharedStore { static CALogStore *s; static dispatch_once_t once; dispatch_once(&once, ^{ s=[self new]; }); return s; }

- (NSArray<NSString *> *)roots {
    return @[@"/var/mobile/Library/Logs/CrashReporter"];
}

- (NSArray<NSString *> *)ipsPaths {
    NSMutableArray *paths=[NSMutableArray array];
    NSFileManager *fm=[NSFileManager defaultManager];
    NSString *root=@"/var/mobile/Library/Logs/CrashReporter";
    NSDirectoryEnumerator *enumerator=[fm enumeratorAtPath:root];
    NSString *relative=nil;
    while ((relative=[enumerator nextObject])) {
        NSString *lower=[relative.lowercaseString copy];
        if ([lower hasSuffix:@".ips"] || [lower hasSuffix:@".ips.synced"]) {
            [paths addObject:[root stringByAppendingPathComponent:relative]];
        }
    }
    return paths;
}

- (NSDictionary *)reportAtPath:(NSString *)path {
    if (![path isKindOfClass:[NSString class]] || !path.length) return nil;
    NSData *data=[NSData dataWithContentsOfFile:path options:0 error:nil];
    if (!data) return nil;
    NSDictionary *parsed=[self parse:data];
    NSMutableDictionary *report=parsed ? [parsed mutableCopy] : [NSMutableDictionary dictionary];
    report[@"path"]=path;
    report[@"fileName"]=path.lastPathComponent;
    report[@"category"]=[self categoryForReport:report];
    report[@"diagnosis"]=[self diagnosisForReport:report];
    return report;
}

    NSMutableArray *out=[NSMutableArray array];
    for (NSString *path in [self ipsPaths]) {
        NSData *data=[NSData dataWithContentsOfFile:path options:0 error:nil];
        if (!data) continue;
        NSDictionary *d=[self parse:data];
        NSMutableDictionary *r=d ? [d mutableCopy] : [NSMutableDictionary dictionary];
        if (!d) {
            r[@"bug_type"]=@"unknown";
            r[@"parseError"]=@YES;
        }
        r[@"path"]=path;
        r[@"fileName"]=path.lastPathComponent;
        r[@"category"]=[self categoryForReport:r];
        r[@"diagnosis"]=[self diagnosisForReport:r];
        [out addObject:r];
    }
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSString *ta=[a[@"timestamp"] description] ?: @"";
        NSString *tb=[b[@"timestamp"] description] ?: @"";
        return [tb compare:ta];
    }];
    return out;
}
- (NSDictionary *)parse:(NSData *)data {
    NSString *s=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!s) return nil;
    NSArray *lines=[s componentsSeparatedByString:@"\n"];
    if (!lines.count) return nil;
    NSMutableDictionary *result=[NSMutableDictionary dictionary];
    NSDictionary *header=[NSJSONSerialization JSONObjectWithData:[lines[0] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if ([header isKindOfClass:[NSDictionary class]]) [result addEntriesFromDictionary:header];
    if (lines.count>1) {
        NSMutableString *bodyText=[NSMutableString string];
        for (NSUInteger i=1; i<lines.count; i++) [bodyText appendString:lines[i]];
        NSDictionary *body=[NSJSONSerialization JSONObjectWithData:[bodyText dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if ([body isKindOfClass:[NSDictionary class]]) [result addEntriesFromDictionary:body];
    }
    return result.count ? result : nil;
}
- (NSDictionary *)scanDiagnostics {
    NSString *root=@"/var/mobile/Library/Logs/CrashReporter";
    NSFileManager *fm=[NSFileManager defaultManager];
    BOOL isDirectory=NO;
    BOOL exists=[fm fileExistsAtPath:root isDirectory:&isDirectory];
    NSError *error=nil;
    NSDirectoryEnumerator *enumerator=exists && isDirectory ? [fm enumeratorAtPath:root] : nil;
    NSUInteger enumerated=0, matched=0, readable=0, parsed=0;
    NSString *relative=nil;
    while ((relative=[enumerator nextObject])) {
        enumerated++;
        NSString *lower=relative.lowercaseString;
        if (![lower hasSuffix:@".ips"] && ![lower hasSuffix:@".ips.synced"]) continue;
        matched++;
        NSString *path=[root stringByAppendingPathComponent:relative];
        NSData *data=[NSData dataWithContentsOfFile:path options:0 error:&error];
        if (!data) continue;
        readable++;
        if ([self parse:data]) parsed++;
    }
    return @{@"path":root, @"exists":@(exists), @"isDirectory":@(isDirectory),
             @"enumerated":@(enumerated), @"matched":@(matched), @"readable":@(readable),
             @"parsed":@(parsed), @"error":error.localizedDescription ?: @""};
}

- (NSString *)categoryForReport:(NSDictionary *)r {
    id bugValue=r[@"bug_type"];
    NSString *bug=[bugValue isKindOfClass:[NSString class]] ? bugValue : [bugValue description];
    NSDictionary *exception=[r[@"exception"] isKindOfClass:[NSDictionary class]] ? r[@"exception"] : nil;
    NSString *blob=[[r description] lowercaseString];

    /* Prefer stable IPS fields. Do not search the entire report description:
       stack strings can contain unrelated words such as "resource" or "cpu". */
    if ([bug isEqualToString:@"309"] || exception != nil || r[@"exceptionType"] || r[@"faultingThread"])
        return @"崩溃";
    if ([bug isEqualToString:@"298"] || [blob containsString:@"jetsam event"] || r[@"largestProcess"])
        return @"内存";
    if ([bug isEqualToString:@"210"] || r[@"panicString"] || [blob containsString:@"panic-full"])
        return @"重启";
    if (r[@"watchdogTimeout"] || [blob containsString:@"watchdog timeout"] || [blob containsString:@"resource_exception"])
        return @"资源";
    if ([r[@"procName"] isKindOfClass:[NSString class]] || [r[@"app_name"] isKindOfClass:[NSString class]])
        return @"崩溃";
    return CAUnknown;
}
- (NSString *)diagnosisForReport:(NSDictionary *)r {
    if ([r[@"parseError"] boolValue]) return @"已找到日志文件，但格式暂未解析；请打开原始日志查看。";
    NSString *cat=r[@"category"] ?: [self categoryForReport:r]; NSString *p=r[@"procName"] ?: r[@"app_name"] ?: @"未知进程"; NSDictionary *ex=r[@"exception"]; NSString *x=ex[@"type"] ?: @"未提供异常类型";
    if ([cat isEqualToString:@"崩溃"]) return [NSString stringWithFormat:@"%@ 发生崩溃，异常为 %@。请结合触发线程和 injected images 排查第三方模块。",p,x];
    if ([cat isEqualToString:@"内存"]) return [NSString stringWithFormat:@"%@ 可能因内存压力或 Jetsam 被终止。",p];
    if ([cat isEqualToString:@"重启"]) return @"检测到 panic 或异常重启相关线索。";
    if ([cat isEqualToString:@"资源"]) return @"检测到资源、看门狗或系统负载相关事件。";
    return @"暂未识别日志类型，请查看原始内容。";
}
- (NSArray<NSDictionary *> *)reportsForCategory:(NSString *)category {
    NSArray *all=[self reports];
    if (![category isKindOfClass:[NSString class]] || category.length==0) return all;
    NSMutableArray *matches=[NSMutableArray array];
    for (NSDictionary *report in all) {
        NSString *value=report[@"category"];
        if ([value isEqualToString:category]) [matches addObject:report];
    }
    return matches;
}
@end
