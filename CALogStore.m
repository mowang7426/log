#import "CALogStore.h"

static NSString * const CAUnknown = @"其他";

@implementation CALogStore
+ (instancetype)sharedStore { static CALogStore *s; static dispatch_once_t once; dispatch_once(&once, ^{ s=[self new]; }); return s; }

- (NSArray<NSString *> *)roots {
    return @[@"/var/mobile/Library/Logs/CrashReporter",
             @"/var/mobile/Library/Logs/Analytics",
             @"/var/mobile/Library/Logs/DiagnosticReports",
             @"/var/mobile/Library/Logs/CrashReporter/DiagnosticLogs",
             @"/var/mobile/Library/Logs/CrashReporter/Retired",
             @"/var/mobile/Library/Logs/CrashReporter/Legacy",
             @"/private/var/mobile/Library/Logs/CrashReporter",
             @"/private/var/mobile/Library/Logs/CrashReporter/DiagnosticLogs",
             @"/private/var/mobile/Library/Logs/Analytics",
             @"/private/var/mobile/Library/Logs/Analytics/DiagnosticLogs",
             @"/private/var/mobile/Library/Logs/DiagnosticReports",
             @"/var/db/diagnostics",
             @"/var/jb/var/mobile/Library/Logs/CrashReporter",
             @"/var/jb/var/mobile/Library/Logs/Analytics",
             @"/var/jb/var/mobile/Library/Logs/DiagnosticReports",
             @"/var/jb/private/var/mobile/Library/Logs/CrashReporter",
             @"/var/jb/private/var/mobile/Library/Logs/Analytics"];
}

- (NSArray<NSString *> *)ipsPaths {
    NSMutableArray *paths=[NSMutableArray array];
    NSFileManager *fm=NSFileManager.defaultManager;
    for (NSString *root in [self roots]) {
        BOOL isDirectory=NO;
        if (![fm fileExistsAtPath:root isDirectory:&isDirectory] || !isDirectory) continue;
        NSArray *relativePaths=[fm subpathsAtPath:root];
        for (NSString *relative in relativePaths) {
            NSString *lower=[relative.lowercaseString copy];
            if ([lower hasSuffix:@".ips"] || [lower hasSuffix:@".ips.synced"]) {
                [paths addObject:[root stringByAppendingPathComponent:relative]];
            }
        }
    }
    return paths;
}

- (NSArray<NSDictionary *> *)reports {
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
- (NSString *)categoryForReport:(NSDictionary *)r {
    NSString *blob=[[r description] lowercaseString]; NSString *bug=[r[@"bug_type"] description];
    if ([blob containsString:@"jetsam"]||[blob containsString:@"memory pressure"]||[blob containsString:@"memorystatus"]) return @"内存";
    if ([blob containsString:@"panic"]||[blob containsString:@"unexpected restart"]||[bug isEqualToString:@"210"]) return @"重启";
    if ([blob containsString:@"watchdog"]||[blob containsString:@"resource"]||[blob containsString:@"cpu"]||[blob containsString:@"thermal"]) return @"资源";
    if (r[@"exception"]||[bug isEqualToString:@"309"]||[blob containsString:@"crash"]) return @"崩溃";
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
    NSMutableArray *matches=[NSMutableArray array];
    for (NSDictionary *report in [self reports]) {
        if ([report[@"category"] isEqualToString:category]) [matches addObject:report];
    }
    return matches;
}
@end
