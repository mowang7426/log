#import "CALogStore.h"
#import <CommonCrypto/CommonDigest.h>

// Canonical, length-delimited strings avoid dictionary-order and separator collisions.
static NSString *CAStableString(id value) {
    if (!value || value == [NSNull null]) return @"";
    if ([value isKindOfClass:[NSString class]])
        return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([value isKindOfClass:[NSNumber class]]) return [value stringValue];
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableString *out=[NSMutableString stringWithString:@"["];
        for (id item in value) {
            NSString *part=CAStableString(item);
            [out appendFormat:@"%lu:%@",(unsigned long)part.length,part];
        }
        [out appendString:@"]"];
        return out;
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSMutableString *out=[NSMutableString stringWithString:@"{"];
        NSArray *keys=[[value allKeys] sortedArrayUsingSelector:@selector(compare:)];
        for (NSString *key in keys) {
            NSString *part=CAStableString(value[key]);
            [out appendFormat:@"%lu:%@%lu:%@",(unsigned long)key.length,key,(unsigned long)part.length,part];
        }
        [out appendString:@"}"];
        return out;
    }
    return @"";
}

static BOOL CAValidFingerprint(NSString *fingerprint) {
    if (![fingerprint isKindOfClass:[NSString class]] || fingerprint.length != 64) return NO;
    NSCharacterSet *invalid=[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet];
    return [fingerprint rangeOfCharacterFromSet:invalid].location == NSNotFound;
}

static BOOL CAStringArray(id value) {
    if (![value isKindOfClass:[NSArray class]]) return NO;
    for (id item in value) if (![item isKindOfClass:[NSString class]]) return NO;
    return YES;
}

static BOOL CAValidCache(NSDictionary *cache, NSString *fingerprint) {
    if (![cache isKindOfClass:[NSDictionary class]] || ![cache[@"fingerprint"] isEqual:fingerprint]) return NO;
    if (![cache[@"createdAt"] isKindOfClass:[NSString class]] || ![cache[@"createdAt"] length]) return NO;
    if (![cache[@"localDiagnosis"] isKindOfClass:[NSDictionary class]]) return NO;
    NSDictionary *local=cache[@"localDiagnosis"];
    if (!CAStringArray(local[@"facts"]) || !CAStringArray(local[@"recommendations"]) ||
        ![local[@"summary"] isKindOfClass:[NSString class]]) return NO;
    return [cache[@"aiDiagnosis"] isKindOfClass:[NSString class]] &&
        [cache[@"confirmed"] isKindOfClass:[NSNumber class]] &&
        [cache[@"rootCause"] isKindOfClass:[NSString class]] && CAStringArray(cache[@"recommendations"]);
}

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

- (NSDictionary *)normalizedReport:(NSDictionary *)report {
    NSMutableDictionary *r=[report mutableCopy];
    NSDictionary *bundle=[report[@"bundleInfo"] isKindOfClass:[NSDictionary class]] ? report[@"bundleInfo"] : @{};
    NSDictionary *os=[report[@"osVersion"] isKindOfClass:[NSDictionary class]] ? report[@"osVersion"] : @{};
    NSDictionary *ex=[report[@"exception"] isKindOfClass:[NSDictionary class]] ? report[@"exception"] : @{};
    NSDictionary *term=[report[@"termination"] isKindOfClass:[NSDictionary class]] ? report[@"termination"] : @{};
    id process=report[@"procName"] ?: report[@"processName"] ?: report[@"app_name"] ?: report[@"name"];
    id bundleID=report[@"bundleID"] ?: report[@"bundleIdentifier"] ?: bundle[@"CFBundleIdentifier"];
    id pid=report[@"pid"] ?: report[@"processID"] ?: report[@"process_id"];
    id system=report[@"systemVersion"] ?: report[@"os_version"] ?: os[@"train"];
    id exceptionType=report[@"exceptionType"] ?: ex[@"type"];
    id signal=report[@"signal"] ?: ex[@"signal"];
    id codes=report[@"codes"] ?: ex[@"codes"];
    id subtype=report[@"subtype"] ?: ex[@"subtype"];
    id address=report[@"address"] ?: ex[@"address"];
    if (process) r[@"normalizedProcessName"]=process;
    if (bundleID) r[@"normalizedBundleID"]=bundleID;
    if (pid) r[@"normalizedPID"]=pid;
    if (system) r[@"normalizedSystemVersion"]=system;
    if (exceptionType) r[@"normalizedExceptionType"]=exceptionType;
    if (signal) r[@"normalizedSignal"]=signal;
    if (codes) r[@"normalizedCodes"]=codes;
    if (subtype) r[@"normalizedSubtype"]=subtype;
    if (address) r[@"normalizedAddress"]=address;
    if (report[@"faultingThread"]) r[@"normalizedFaultingThread"]=report[@"faultingThread"];
    if (term.count) r[@"normalizedTermination"]=term;
    r[@"normalizedThreadCount"]=@([report[@"threads"] isKindOfClass:[NSArray class]] ? [report[@"threads"] count] : 0);
    r[@"normalizedImageCount"]=@([report[@"usedImages"] isKindOfClass:[NSArray class]] ? [report[@"usedImages"] count] : 0);
    return r;
}

- (NSDictionary *)reportAtPath:(NSString *)path {
    if (![path isKindOfClass:[NSString class]] || !path.length) return nil;
    NSData *data=[NSData dataWithContentsOfFile:path options:0 error:nil];
    if (!data) return nil;
    NSDictionary *parsed=[self parse:data];
    NSMutableDictionary *report=parsed ? [[self normalizedReport:parsed] mutableCopy] : [NSMutableDictionary dictionary];
    report[@"path"]=path;
    report[@"fileName"]=path.lastPathComponent;
    report[@"category"]=[self categoryForReport:report];
    report[@"diagnosis"]=[self diagnosisForReport:report];
    return report;
}

- (NSArray<NSDictionary *> *)reports {
    NSMutableArray *out=[NSMutableArray array];
    for (NSString *path in [self ipsPaths]) {
        NSData *data=[NSData dataWithContentsOfFile:path options:0 error:nil];
        if (!data) continue;
        NSDictionary *d=[self parse:data];
        NSMutableDictionary *r=d ? [[self normalizedReport:d] mutableCopy] : [NSMutableDictionary dictionary];
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
- (NSString *)fingerprintForReport:(NSDictionary *)report {
    NSDictionary *r=[self normalizedReport:report ?: @{}];
    NSMutableString *signature=[NSMutableString stringWithString:@"CAFingerprint-v1;"];
    NSArray *fields=@[@"category", @"bug_type", @"normalizedExceptionType", @"normalizedSignal",
                      @"normalizedProcessName", @"normalizedBundleID", @"normalizedCodes",
                      @"normalizedSubtype", @"normalizedTermination", @"watchdogTimeout", @"panicString",
                      @"largestProcess", @"parseError"];
    for (NSString *key in fields) {
        id value=[key isEqualToString:@"category"] ? [self categoryForReport:r] : r[key];
        NSString *part=CAStableString(value);
        [signature appendFormat:@"%lu:%@%lu:%@;",(unsigned long)key.length,key,(unsigned long)part.length,part];
    }
    NSData *bytes=[signature dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    // Chunking avoids truncation when NSUInteger exceeds CommonCrypto's CC_LONG.
    const unsigned char *cursor=bytes.bytes;
    NSUInteger remaining=bytes.length;
    while (remaining) {
        CC_LONG count=(CC_LONG)MIN(remaining,(NSUInteger)1048576);
        CC_SHA256_Update(&context,cursor,count);
        cursor+=count;
        remaining-=count;
    }
    CC_SHA256_Final(digest,&context);
    NSMutableString *result=[NSMutableString stringWithCapacity:64];
    for (NSUInteger i=0; i<CC_SHA256_DIGEST_LENGTH; i++) [result appendFormat:@"%02x",digest[i]];
    return result;
}

- (NSString *)analysisCacheDirectory {
    // Preferences plugins run in the host's home; no new entitlement or framework is needed.
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences/CrashAnalyzer/AnalysisCache"];
}

- (NSDictionary *)analysisCacheForFingerprint:(NSString *)fingerprint {
    if (!CAValidFingerprint(fingerprint)) return nil;
    @synchronized (self) {
        NSString *path=[[self analysisCacheDirectory] stringByAppendingPathComponent:[fingerprint stringByAppendingString:@".json"]];
        NSData *data=[NSData dataWithContentsOfFile:path options:0 error:nil];
        if (!data) return nil;
        id cache=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        return CAValidCache(cache,fingerprint) ? cache : nil;
    }
}

- (BOOL)saveAnalysisCache:(NSDictionary *)cache forFingerprint:(NSString *)fingerprint {
    if (!CAValidFingerprint(fingerprint) || ![cache isKindOfClass:[NSDictionary class]]) return NO;
    @synchronized (self) {
        NSMutableDictionary *entry=[[self analysisCacheForFingerprint:fingerprint] mutableCopy];
        if (!entry) {
            NSDateFormatter *format=[NSDateFormatter new];
            format.locale=[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
            format.timeZone=[NSTimeZone timeZoneForSecondsFromGMT:0];
            format.dateFormat=@"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
            entry=[@{@"fingerprint":fingerprint, @"localDiagnosis":@{@"facts":@[], @"recommendations":@[], @"summary":@""},
                     @"createdAt":[format stringFromDate:[NSDate date]], @"aiDiagnosis":@"", @"confirmed":@NO,
                     @"rootCause":@"", @"recommendations":@[]} mutableCopy];
        }
        // Whitelist fields. Callers cannot alter the entry identity or original creation time.
        for (NSString *key in @[@"localDiagnosis", @"aiDiagnosis", @"confirmed", @"rootCause", @"recommendations"])
            if (cache[key]) entry[key]=cache[key];
        if (!CAValidCache(entry,fingerprint) || ![NSJSONSerialization isValidJSONObject:entry]) return NO;
        NSData *data=[NSJSONSerialization dataWithJSONObject:entry options:0 error:nil];
        if (!data) return NO;
        NSString *directory=[self analysisCacheDirectory];
        if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil]) return NO;
        NSString *path=[directory stringByAppendingPathComponent:[fingerprint stringByAppendingString:@".json"]];
        return [data writeToFile:path options:NSDataWritingAtomic error:nil];
    }
}

- (NSDictionary *)localAnalysisForReport:(NSDictionary *)report {
    NSDictionary *r=[self normalizedReport:report ?: @{}];
    NSMutableArray *facts=[NSMutableArray array];
    NSMutableArray *advice=[NSMutableArray array];
    NSString *bug=CAStableString(r[@"bug_type"]);
    NSString *process=CAStableString(r[@"normalizedProcessName"]);
    if (!process.length) process=@"未知进程";
    NSString *exception=[CAStableString(r[@"normalizedExceptionType"]) uppercaseString];
    NSString *signal=[CAStableString(r[@"normalizedSignal"]) uppercaseString];
    NSDictionary *term=[r[@"normalizedTermination"] isKindOfClass:[NSDictionary class]] ? r[@"normalizedTermination"] : @{};
    NSString *evidence=[[NSString stringWithFormat:@"%@ %@ %@ %@ %@",CAStableString(term),
                         CAStableString(r[@"normalizedCodes"]), CAStableString(r[@"normalizedSubtype"]),
                         CAStableString(r[@"reason"]), CAStableString(r[@"event"])] lowercaseString];
    BOOL parseError=[r[@"parseError"] respondsToSelector:@selector(boolValue)] && [r[@"parseError"] boolValue];
    BOOL matched=NO;
    if (parseError) {
        [facts addObject:@"已找到日志文件，但格式暂未解析。"];
        [advice addObject:@"打开源文件核对格式；当前无法据此判断根因。"];
    } else {
        [facts addObject:[NSString stringWithFormat:@"进程：%@；报告类型：%@；分类：%@。",process,bug.length ? bug : @"未知",[self categoryForReport:r]]];
        if ([bug isEqualToString:@"298"] || r[@"largestProcess"] || [evidence containsString:@"jetsam"]) {
            matched=YES;
            [facts addObject:@"日志包含 Jetsam / 内存资源终止线索；不能仅凭此证明某个进程发生内存泄漏。"];
            if (r[@"largestProcess"]) [facts addObject:[NSString stringWithFormat:@"largestProcess：%@（不等于已确认被终止的进程）。",CAStableString(r[@"largestProcess"])]];
            [advice addObject:@"查看 processes 中被终止项的 reason、内存占用和系统压力；区分单进程内存上限与全局内存不足，再排查峰值分配和泄漏。"];
        }
        if ([exception containsString:@"EXC_BAD_ACCESS"]) {
            matched=YES;
            [facts addObject:[NSString stringWithFormat:@"异常类型为 %@，属于内存访问异常；具体责任模块尚未确定。",exception]];
            [advice addObject:@"结合异常地址、subtype、故障线程和符号化堆栈排查无效指针、释放后使用或越界；镜像中出现第三方模块并不能证明其导致异常。"];
        }
        BOOL watchdog=r[@"watchdogTimeout"] != nil || [evidence containsString:@"watchdog"] ||
            [evidence containsString:@"8badf00d"] || [CAStableString(term[@"code"]) isEqualToString:@"2343432205"];
        if (watchdog) {
            matched=YES;
            [facts addObject:@"终止字段或超时字段包含 watchdog（看门狗）线索，提示系统监测到响应超时。"];
            [advice addObject:@"核对 termination 的超时阶段与预算，检查启动、恢复、退出期间主线程阻塞、同步 I/O、死锁及长任务；超时不等同于系统内存不足。"];
        }
        if ([bug isEqualToString:@"210"] || CAStableString(r[@"panicString"]).length) {
            matched=YES;
            [facts addObject:@"报告类型或 panicString 表明存在内核 panic / 异常重启事件，不能直接归因于某个应用或硬件故障。"];
            [advice addObject:@"核对 panicString、关联时间和重复模式，区分驱动、系统、外设及硬件线索；保留完整 panic 日志，反复发生时再进一步检测。"];
        }
        BOOL sigkill=[signal containsString:@"SIGKILL"] ||
            ([[CAStableString(term[@"namespace"]) uppercaseString] isEqualToString:@"SIGNAL"] && [CAStableString(term[@"code"]) isEqualToString:@"9"]);
        if (sigkill) {
            matched=YES;
            [facts addObject:@"日志记录 SIGKILL（强制终止）；信号本身不说明是谁终止进程，也不证明是内存问题。"];
            [advice addObject:@"结合 termination 的 namespace、code、byProc、indicator 以及同一时间的 Jetsam/watchdog 日志定位终止来源；信息不足时不要下确定结论。"];
        }
        if (!matched) {
            if (exception.length) [facts addObject:[NSString stringWithFormat:@"记录的异常类型：%@。",exception]];
            if (signal.length) [facts addObject:[NSString stringWithFormat:@"记录的信号：%@。",signal]];
            [facts addObject:@"当前本地规则未命中特定根因；分类仅用于整理日志。"];
            [advice addObject:@"查看原始日志、终止字段与故障线程；需要时使用 AI 辅助分析，并用原始证据验证其结论。"];
        }
    }
    NSString *summary=[NSString stringWithFormat:@"【事实】\n%@\n\n【建议（非已确认根因）】\n%@",[facts componentsJoinedByString:@"\n"],[advice componentsJoinedByString:@"\n"]];
    return @{@"facts":facts, @"recommendations":advice, @"summary":summary, @"rootCause":@"", @"confirmed":@NO};
}

- (NSString *)diagnosisForReport:(NSDictionary *)r {
    // Recompute cheap local rules to avoid stale evidence; only persist changes.
    NSDictionary *local=[self localAnalysisForReport:r];
    NSString *fingerprint=[self fingerprintForReport:r];
    NSDictionary *cached=[self analysisCacheForFingerprint:fingerprint];
    if (![cached[@"localDiagnosis"] isEqual:local]) {
        NSMutableDictionary *update=[@{@"localDiagnosis":local} mutableCopy];
        if (!cached) update[@"recommendations"]=local[@"recommendations"];
        [self saveAnalysisCache:update forFingerprint:fingerprint];
    }
    // Existing list/detail controllers still receive an NSString in report["diagnosis"].
    NSString *ai=cached[@"aiDiagnosis"];
    if (ai.length) return [NSString stringWithFormat:@"%@\n\n【缓存 AI 分析（需核实）】\n%@",local[@"summary"],ai];
    return local[@"summary"];
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
