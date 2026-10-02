#import "CAPluginEvidence.h"
#import <math.h>
static NSString *Text(id v) { return [v isKindOfClass:NSString.class] ? v : ([v isKindOfClass:NSNumber.class] ? [v stringValue] : @""); }
static NSArray *Array(id v) { return [v isKindOfClass:NSArray.class] ? v : @[]; }
static NSDictionary *Dict(id v) { return [v isKindOfClass:NSDictionary.class] ? v : @{}; }
static NSInteger Index(id v, NSUInteger count) {
    if (![v isKindOfClass:NSNumber.class]) return -1;
    double n=[v doubleValue];
    if (!isfinite(n) || n<0 || floor(n)!=n || n>=(double)count) return -1;
    return (NSInteger)n;
}
static NSString *Identity(NSDictionary *image) {
    NSString *p=Text(image[@"path"]);
    // A jailbreak root is not evidence that every library under it is a tweak.
    NSString *lower=p.lowercaseString;
    if (![lower containsString:@"/library/mobilesubstrate/dynamiclibraries/"] &&
        ![lower containsString:@"/usr/lib/tweakinject/"] && ![lower containsString:@"/library/tweakinject/"]) return nil;
    NSArray *markers=@[@"/library/mobilesubstrate/dynamiclibraries/",@"/usr/lib/tweakinject/",@"/library/tweakinject/"];
    for (NSString *marker in markers) {
        NSRange r=[lower rangeOfString:marker];
        if (r.location!=NSNotFound) return [p substringFromIndex:r.location];
    }
    return nil;
}
static NSString *Incident(NSDictionary *r) {
    NSString *uuid=Text(r[@"incident"] ?: r[@"incident_id"] ?: r[@"incidentIdentifier"]);
    if (uuid.length) return [@"incident:" stringByAppendingString:uuid];
    // Same copied report is one incident; recurring crashes with different time/PID
    // remain separate. A stack signature must never deduplicate distinct incidents.
    NSMutableDictionary *raw=[r mutableCopy];
    for (NSString *k in @[@"path",@"fileName",@"category",@"diagnosis"]) [raw removeObjectForKey:k];
    NSData *data=[NSJSONSerialization isValidJSONObject:raw] ? [NSJSONSerialization dataWithJSONObject:raw options:NSJSONWritingSortedKeys error:NULL] : nil;
#if !__has_feature(objc_arc)
    [raw release];
#endif
    return data ? [data base64EncodedStringWithOptions:0] : Text(r[@"path"]);
}
@implementation CAPluginEvidence
+ (NSString *)tierLabel:(NSString *)tier {
    if ([tier isEqual:@"fault"]) return @"优先核查：故障线程实际引用（不等于根因）";
    if ([tier isEqual:@"other"]) return @"辅助证据：仅其他线程引用";
    if ([tier isEqual:@"loaded"]) return @"仅加载，暂无归因证据";
    return @"未知：线程或帧数据缺失/无效，无法判断引用";
}
+ (NSArray *)summaryForReports:(NSArray *)reports limit:(NSUInteger)limit {
    NSMutableDictionary *all=[NSMutableDictionary dictionary];
    for (id value in Array(reports)) {
        if (![value isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *report=value;
        NSArray *images=Array(report[@"usedImages"]), *threads=Array(report[@"threads"]);
        NSInteger fault=Index(report[@"normalizedFaultingThread"] ?: report[@"faultingThread"],threads.count);
        if (fault<0) for (NSUInteger t=0;t<threads.count;t++) {
            id triggered=Dict(threads[t])[@"triggered"];
            if ([triggered isKindOfClass:NSNumber.class] && [triggered boolValue]) { fault=(NSInteger)t; break; }
        }
        NSMutableDictionary *refs=[NSMutableDictionary dictionary];
        BOOL complete=threads.count>0 && fault>=0;
        for (NSUInteger t=0;t<threads.count;t++) {
            NSDictionary *thread=Dict(threads[t]);
            if (![thread[@"frames"] isKindOfClass:NSArray.class]) complete=NO;
            NSArray *frames=Array(thread[@"frames"]);
            for (NSUInteger f=0;f<frames.count;f++) {
                NSDictionary *frame=Dict(frames[f]);
                NSInteger i=Index(frame[@"imageIndex"],images.count);
                if (i<0) { complete=NO; continue; }
                NSString *key=Identity(Dict(images[(NSUInteger)i]));
                if (!key) continue;
                NSMutableArray *list=refs[key];
                if (!list) { list=[NSMutableArray array]; refs[key]=list; }
                [list addObject:@{@"thread":@(t),@"frame":@(f),@"imageIndex":@(i),@"symbol":Text(frame[@"symbol"]),@"offset":Text(frame[@"symbolLocation"] ?: frame[@"imageOffset"]),@"fault":@(fault==(NSInteger)t)}];
            }
        }
        NSMutableSet *seen=[NSMutableSet set];
        for (id imageValue in images) {
            NSDictionary *image=Dict(imageValue); NSString *key=Identity(image);
            if (!key || [seen containsObject:key]) continue;
            [seen addObject:key];
            NSMutableDictionary *s=all[key];
            if (!s) { s=[NSMutableDictionary dictionaryWithDictionary:@{@"identity":key,@"name":Text(image[@"name"]).length ? Text(image[@"name"]).lastPathComponent : key.lastPathComponent,@"paths":[NSMutableArray array],@"incidents":[NSMutableDictionary dictionary]}]; all[key]=s; }
            NSMutableArray *paths=s[@"paths"]; NSString *path=Text(image[@"path"]);
            if (![paths containsObject:path]) [paths addObject:path];
            NSArray *references=refs[key] ?: @[];
            BOOL isFault=NO; for (NSDictionary *ref in references) if ([ref[@"fault"] boolValue]) isFault=YES;
            NSString *tier=isFault ? @"fault" : (references.count ? @"other" : (complete ? @"loaded" : @"unknown"));
            NSMutableDictionary *incidents=s[@"incidents"]; NSString *incident=Incident(report);
            NSDictionary *old=incidents[incident];
            NSArray *order=@[@"fault",@"other",@"loaded",@"unknown"];
            if (!old || [order indexOfObject:tier]<[order indexOfObject:old[@"tier"]])
                incidents[incident]=@{@"report":report,@"tier":tier,@"faultThread":fault>=0 ? @(fault) : [NSNull null],@"references":references,@"appVersion":Text(report[@"app_version"] ?: Dict(report[@"bundleInfo"])[@"CFBundleShortVersionString"]),@"pluginVersion":Text(image[@"version"])};
        }
    }
    NSMutableArray *out=[NSMutableArray array];
    for (NSMutableDictionary *s in all.allValues) {
        NSArray *entries=[s[@"incidents"] allValues]; NSUInteger fault=0,other=0,loaded=0;
        NSMutableArray *reportsOut=[NSMutableArray array];
        for (NSDictionary *e in entries) { fault += [e[@"tier"] isEqual:@"fault"]; other += [e[@"tier"] isEqual:@"other"]; loaded += [e[@"tier"] isEqual:@"loaded"]; [reportsOut addObject:e[@"report"]]; }
        s[@"main"]=@(fault); s[@"other"]=@(other); s[@"participation"]=@(entries.count);
        s[@"tier"]=fault ? @"fault" : (other ? @"other" : (loaded ? @"loaded" : @"unknown"));
        s[@"entries"]=entries; s[@"reports"]=reportsOut; [s removeObjectForKey:@"incidents"]; [out addObject:s];
    }
    NSArray *order=@[@"fault",@"other",@"loaded",@"unknown"];
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) {
        NSUInteger x=[order indexOfObject:a[@"tier"]], y=[order indexOfObject:b[@"tier"]];
        if (x!=y) return x<y?NSOrderedAscending:NSOrderedDescending;
        NSUInteger ac=[a[@"main"] unsignedIntegerValue],bc=[b[@"main"] unsignedIntegerValue];
        if(ac!=bc) return ac>bc?NSOrderedAscending:NSOrderedDescending;
        return [a[@"identity"] compare:b[@"identity"]];
    }];
    if (limit && out.count>limit) [out removeObjectsInRange:NSMakeRange(limit,out.count-limit)];
    return out;
}
+ (NSArray *)validationStates { return @[@"待验证",@"暂时禁用后未再发生",@"恢复启用后再次发生",@"禁用后仍然发生",@"忽略"]; }
+ (NSDictionary *)validationForPlugin:(NSString *)identity {
    return Dict([[NSUserDefaults standardUserDefaults] dictionaryForKey:@"CAPluginValidation"][identity]);
}
+ (BOOL)saveValidation:(NSDictionary *)record forPlugin:(NSString *)identity {
    if (!identity.length || ![[self validationStates] containsObject:record[@"state"]]) return NO;
    for (NSString *k in @[@"testedAt",@"appVersion",@"pluginVersion",@"notes"]) if (![record[k] isKindOfClass:NSString.class]) return NO;
    if (!Text(record[@"testedAt"]).length) return NO;
    NSMutableDictionary *all=[NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"CAPluginValidation"] ?: @{}];
    all[identity]=record; [[NSUserDefaults standardUserDefaults] setObject:all forKey:@"CAPluginValidation"];
    return YES;
}
@end
