#import "CALogExperience.h"
static NSString *Text(id v) { return [v isKindOfClass:NSString.class] ? v : ([v isKindOfClass:NSNumber.class] ? [v stringValue] : @"未知"); }
NSString *CAProcessName(NSDictionary *r) { for (NSString *k in @[@"normalizedProcessName",@"procName",@"app_name",@"processName"]) if ([r[k] isKindOfClass:NSString.class] && [r[k] length]) return r[k]; return @"未知进程"; }
BOOL CAReportMatches(NSDictionary *r, NSString *query) {
    if (!query.length) return YES;
    NSMutableArray *parts=[NSMutableArray arrayWithObject:CAProcessName(r)];
    for (NSString *k in @[@"normalizedBundleID",@"bundleID",@"fileName",@"normalizedExceptionType",@"timestamp",@"category",@"bug_type",@"panicString",@"watchdogTimeout",@"reason",@"largestProcess"]) [parts addObject:Text(r[k])];
    if ([r[@"exception"] isKindOfClass:NSDictionary.class]) [parts addObject:[r[@"exception"] description]];
    if ([r[@"termination"] isKindOfClass:NSDictionary.class]) [parts addObject:[r[@"termination"] description]];
    if ([r[@"bundleInfo"] isKindOfClass:NSDictionary.class]) [parts addObject:Text(r[@"bundleInfo"][@"CFBundleIdentifier"])];
    NSString *haystack=[parts componentsJoinedByString:@" "];
    return [haystack rangeOfString:query options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch].location!=NSNotFound;
}
NSDate *CAReportDate(NSDictionary *r, NSDate *fallback) {
    id value=r[@"timestamp"] ?: r[@"captureTime"];
    if ([value isKindOfClass:NSDate.class]) return value;
    if ([value isKindOfClass:NSString.class]) {
        NSDateFormatter *f=[[NSDateFormatter alloc] init]; f.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]; f.timeZone=[NSTimeZone timeZoneForSecondsFromGMT:0]; f.lenient=NO;
        NSDate *d=nil;
        for (NSString *format in @[@"yyyy-MM-dd HH:mm:ss.SSS Z",@"yyyy-MM-dd HH:mm:ss Z",@"yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",@"yyyy-MM-dd'T'HH:mm:ssXXXXX"]) { f.dateFormat=format; d=[f dateFromString:value]; if (d) break; }
        [f release]; if (d) return d;
    }
    return fallback ?: [NSDate distantPast];
}
NSArray *CASpecialEvidence(NSDictionary *r) {
    NSMutableArray *a=[NSMutableArray array]; NSString *bug=Text(r[@"bug_type"]);
    if ([bug isEqual:@"298"]) {
        [a addObject:[NSString stringWithFormat:@"Jetsam：reason=%@；largestProcess=%@（最大进程不等于被杀进程）",Text(r[@"reason"]),Text(r[@"largestProcess"])]];
        NSDictionary *memory=[r[@"memoryStatus"] isKindOfClass:NSDictionary.class]?r[@"memoryStatus"]:@{};
        id page=r[@"pageSize"] ?: memory[@"pageSize"];
        BOOL known=[page isKindOfClass:NSNumber.class] && [page doubleValue]>0;
        [a addObject:known?[NSString stringWithFormat:@"pageSize=%@ 字节（日志值）",page]:@"pageSize 未知；仅展示页数，不假定 16384 字节"];
        id processes=r[@"processes"]; NSUInteger victims=0;
        if ([processes isKindOfClass:NSArray.class]) for (id p in processes) {
            if (![p isKindOfClass:NSDictionary.class] || !p[@"reason"] || p[@"reason"]==NSNull.null) continue;
            victims++; NSString *pages=Text(p[@"rpages"] ?: p[@"pages"]);
            [a addObject:[NSString stringWithFormat:@"被终止项 %@ (pid %@)：reason=%@；resident=%@ 页%@",Text(p[@"name"] ?: p[@"procName"]),Text(p[@"pid"]),Text(p[@"reason"]),pages,known && [p[@"rpages"] isKindOfClass:NSNumber.class] ? [NSString stringWithFormat:@"，约 %.2f MiB",[p[@"rpages"] doubleValue]*[page doubleValue]/1048576.0]:@""]];
        }
        if (!victims) [a addObject:@"未发现含 reason 的被终止项；不能凭最大进程猜测受害进程。"];
    }
    if ([bug isEqual:@"210"] || [r[@"panicString"] isKindOfClass:NSString.class]) {
        NSString *panic=Text(r[@"panicString"]);
        [a addObject:[NSString stringWithFormat:@"Panic 原始摘要：%@",[panic substringToIndex:MIN(panic.length,(NSUInteger)1600)]]];
        [a addObject:@"摘要可能截断，请查看原文；不由关键词推断硬件故障或确定根因。"];
    }
    NSDictionary *term=[r[@"termination"] isKindOfClass:NSDictionary.class]?r[@"termination"]:@{};
    NSString *ns=Text(term[@"namespace"]); NSString *ex=Text(r[@"normalizedExceptionType"]);
    if ((r[@"watchdogTimeout"] && r[@"watchdogTimeout"]!=NSNull.null) || [ns.uppercaseString containsString:@"WATCHDOG"] || [Text(term[@"code"]) isEqual:@"2343432205"] || [ex isEqual:@"EXC_RESOURCE"]) {
        for (NSString *k in @[@"namespace",@"code",@"indicator",@"byProc",@"reason"]) [a addObject:[NSString stringWithFormat:@"termination.%@ = %@",k,Text(term[k])]];
        [a addObject:[NSString stringWithFormat:@"watchdogTimeout = %@；只描述终止/超时字段，不推断触发操作。",Text(r[@"watchdogTimeout"])]];
    }
    return a;
}
