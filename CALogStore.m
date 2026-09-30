#import "CALogStore.h"

static NSString * const CAUnknown = @"其他";

@implementation CALogStore
+ (instancetype)sharedStore { static CALogStore *s; static dispatch_once_t once; dispatch_once(&once, ^{ s=[self new]; }); return s; }

- (NSArray<NSString *> *)roots {
    return @[@"/var/mobile/Library/Logs/CrashReporter",
             @"/var/mobile/Library/Logs/Analytics",
             @"/private/var/mobile/Library/Logs/CrashReporter",
             @"/private/var/mobile/Library/Logs/Analytics",
             @"/var/mobile/Library/Logs/DiagnosticReports"];
}

- (NSArray<NSDictionary *> *)reports {
    NSMutableArray *out=[NSMutableArray array]; NSFileManager *fm=NSFileManager.defaultManager;
    for (NSString *root in [self roots]) {
        NSArray *files=[fm contentsOfDirectoryAtPath:root error:nil];
        for (NSString *name in files) {
            if (![[name.pathExtension lowercaseString] isEqualToString:@"ips"]) continue;
            NSString *path=[root stringByAppendingPathComponent:name]; NSData *data=[NSData dataWithContentsOfFile:path options:0 error:nil]; if (!data) continue;
            NSDictionary *d=[self parse:data]; if (!d) continue;
            NSMutableDictionary *r=[d mutableCopy]; r[@"path"]=path; r[@"fileName"]=name; r[@"category"]=[self categoryForReport:r]; r[@"diagnosis"]=[self diagnosisForReport:r]; [out addObject:r];
        }
    }
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [b[@"timestamp"] compare:a[@"timestamp"]]; }]; return out;
}
- (NSDictionary *)parse:(NSData *)data {
    NSString *s=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]; if (!s) return nil;
    NSArray *lines=[s componentsSeparatedByString:@"\n"]; if (lines.count<2) return nil; NSError *e=nil; NSDictionary *head=[NSJSONSerialization JSONObjectWithData:[lines[0] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&e]; NSDictionary *body=nil; NSMutableString *json=[NSMutableString string]; for (NSUInteger i=1;i<lines.count;i++) [json appendString:lines[i]]; body=[NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil]; if (![body isKindOfClass:NSDictionary.class]) body=@{}; NSMutableDictionary *r=[body mutableCopy]; [r addEntriesFromDictionary:head ?: @{}]; return r;
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
