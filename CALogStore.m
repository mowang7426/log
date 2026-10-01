#import "CALogStore.h"
#import "CACaseStore.h"
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

NSString * const CAAnalysisVersionTitle = @"本地智能分析 · 第三版";
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
        NSString *lower=relative.lowercaseString;
        if ([lower hasSuffix:@".ips"] || [lower hasSuffix:@".ips.synced"]) {
            [paths addObject:[root stringByAppendingPathComponent:relative]];
        }
    }
    return paths;
}

- (NSDictionary *)normalizedReport:(NSDictionary *)report {
    NSMutableDictionary *r=[[report mutableCopy] autorelease];
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
    NSMutableDictionary *report=parsed ? [[[self normalizedReport:parsed] mutableCopy] autorelease] : [NSMutableDictionary dictionary];
    if (!parsed) report[@"parseError"]=@YES;
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
        NSMutableDictionary *r=d ? [[[self normalizedReport:d] mutableCopy] autorelease] : [NSMutableDictionary dictionary];
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
    NSString *s=[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
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
        NSMutableDictionary *entry=[[[self analysisCacheForFingerprint:fingerprint] mutableCopy] autorelease];
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

- (NSDictionary *)humanReadableAnalysisForReport:(NSDictionary *)report {
    // Read structured fields only: filenames, stacks and AI prose are not causal evidence.
    NSDictionary *r=[self normalizedReport:[report isKindOfClass:[NSDictionary class]] ? report : @{}];
    NSString *bug=CAStableString(r[@"bug_type"]);
    NSString *exception=[CAStableString(r[@"normalizedExceptionType"]) uppercaseString];
    NSString *signal=[CAStableString(r[@"normalizedSignal"]) uppercaseString];
    NSDictionary *term=[r[@"normalizedTermination"] isKindOfClass:[NSDictionary class]] ? r[@"normalizedTermination"] : @{};
    NSString *terminationText=[CAStableString(term) lowercaseString];
    BOOL unreadable=[r[@"parseError"] respondsToSelector:@selector(boolValue)] && [r[@"parseError"] boolValue];
    BOOL jetsam=[bug isEqualToString:@"298"];
    BOOL watchdog=r[@"watchdogTimeout"] && r[@"watchdogTimeout"] != [NSNull null];
    watchdog=watchdog || [terminationText containsString:@"watchdog"] ||
        [terminationText containsString:@"8badf00d"] || [CAStableString(term[@"code"]) isEqualToString:@"2343432205"];
    BOOL panic=CAStableString(r[@"panicString"]).length>0;
    BOOL killed=[signal isEqualToString:@"SIGKILL"] ||
        ([[CAStableString(term[@"namespace"]) uppercaseString] isEqualToString:@"SIGNAL"] && [CAStableString(term[@"code"]) isEqualToString:@"9"]);
    NSMutableArray *evidence=[NSMutableArray array];
    for (NSString *key in @[@"bug_type", @"normalizedExceptionType", @"normalizedSignal", @"normalizedCodes", @"normalizedSubtype", @"normalizedAddress", @"normalizedFaultingThread", @"normalizedTermination", @"watchdogTimeout", @"panicString", @"largestProcess"]) {
        NSString *value=CAStableString(r[key]);
        if (value.length) [evidence addObject:[NSString stringWithFormat:@"事实：%@ = %@",key,value]];
    }
    NSString *title=@"暂时无法判断退出原因";
    NSString *reason=@"未确认：现有字段不足以解释这次退出；报告编号和分类不能单独证明根因。";
    NSString *confidence=@"证据不足；根因未确认";
    NSArray *actions=@[@"先查看源文件并记录发生时间、操作和应用版本。", @"更新应用与系统；若反复出现，将完整日志交给应用开发者核对。"];
    if (unreadable) {
        [evidence addObject:@"事实：日志文件存在，但内容未成功解析。"];
        reason=@"未确认：日志未成功解析，当前无法判断为何退出。";
        actions=@[@"查看源文件确认是否完整；保留原文件，稍后重新读取。"];
    } else if (jetsam) {
        title=@"系统记录了内存资源终止事件";
        reason=@"可能：系统为控制内存资源终止了某个进程；需核对被终止项，才能区分应用达到限制还是系统整体压力。不是已确认的内存泄漏。";
        confidence=@"已识别事件类型；具体根因待核对";
        [evidence addObject:@"事实：bug_type 298 是 Jetsam 事件类型标记，不代表某个应用一定泄漏或被终止。"];
        if (r[@"largestProcess"]) [evidence addObject:@"未确认：largestProcess 只表示最大进程，不等于被终止进程。"];
        actions=@[@"重新打开应用，记录退出前是否处理大文件或运行高负载任务。", @"更新应用；反复出现时提供完整日志，由开发者核对 processes 中的终止项、reason 和内存压力。"];
    } else if ([exception isEqualToString:@"EXC_BAD_ACCESS"]) {
        title=@"应用发生了内存访问异常";
        reason=@"可能：程序访问了无效或不允许访问的内存；具体代码、插件或责任模块尚未确认，不代表设备内存容量不足。";
        confidence=@"异常类型明确；责任模块未确认";
        actions=@[@"更新应用并记录可重复触发的操作。", @"将异常地址和完整故障线程日志交给开发者核对；不要仅因日志出现某个插件就认定它有问题。"];
    } else if ([exception isEqualToString:@"EXC_GUARD"]) {
        title=@"应用触发了系统资源保护";
        reason=@"可能：应用对受保护资源执行了不允许的操作；需核对 subtype、codes 和故障线程，才能确定具体资源及责任代码。";
        confidence=@"异常类型明确；保护对象未确认";
        actions=@[@"更新应用，记录退出前的操作并保留完整日志。", @"请开发者核对保护异常子类型与代码；不能只凭异常编号判断是文件、端口或某个插件导致。"];
    } else if (watchdog) {
        title=@"系统检测到响应超时线索";
        reason=@"可能：应用在启动、恢复或退出等阶段未及时响应；超时阶段与阻塞原因需要进一步核对，不等于内存不足。";
        confidence=@"存在超时线索；阻塞原因未确认";
        actions=@[@"记录当时的操作，重新打开并更新应用。", @"反复出现时请开发者核对 termination 中的超时阶段、预算及主线程；不要凭终止代码直接确定根因。"];
    } else if (panic || [bug isEqualToString:@"210"]) {
        title=panic ? @"系统记录了异常重启线索" : @"报告属于异常重启类型";
        reason=@"可能：系统发生了内核异常；仅凭报告类型不能判断是系统、驱动、外设还是硬件问题，也不能归咎于某个应用。";
        confidence=panic ? @"存在 panic 内容；根因未确认" : @"仅有类型标记；根因未确认";
        actions=@[@"保留完整 panic 日志，并记录是否重复出现及当时连接的外设。", @"更新系统；若持续重启，备份数据并联系技术支持检测，不要据此直接更换硬件。"];
    } else if (killed) {
        title=@"进程收到了强制终止信号";
        reason=@"未确认：SIGKILL 说明进程被强制结束，但信号本身不说明是谁终止、为何终止，也不能证明是内存问题。";
        confidence=@"终止信号明确；终止原因未知";
        actions=@[@"记录发生时间，核对同一时间的其他日志。", @"请开发者结合 termination 的来源及 Jetsam、watchdog 记录检查终止原因。"];
    }
    if (!evidence.count) [evidence addObject:@"事实：没有可用于本地判断的异常或终止字段。"];
    return @{@"title":title, @"reason":reason, @"evidence":evidence, @"actions":actions,
             @"confidence":confidence, @"status":@"本次根因未确认；本地规则不替代实测验证"};
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
    NSDictionary *entry=[[CACaseStore sharedStore] matchingCaseForReport:r];
    if (entry) return [NSString stringWithFormat:@"%@\n\n【本地历史案例：%@，本次根因仍需验证】\n%@\n用户实测记录：%@\n案例 ID：%@",local[@"summary"],[entry[@"confirmed"] boolValue] ? @"含用户实测记录（不保证根因）" : @"AI 未验证参考",entry[@"answer"],entry[@"testNote"] ?: @"无",entry[@"id"]];
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
