#import "CACaseStore.h"
#import <CommonCrypto/CommonDigest.h>
#import <dispatch/dispatch.h>

NSString * const CAAutoSaveCases=@"CAAutoSaveCases";
NSString * const CAUseHistoricalCases=@"CAUseHistoricalCases";
NSString * const CAOnlyValidatedCases=@"CAOnlyValidatedCases";
static NSString *S(id v) { return [v isKindOfClass:NSString.class] ? [v stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @""; }
static NSString *V(NSDictionary *r, NSArray *keys) { for (NSString *k in keys) { NSString *v=S(r[k]); if(v.length)return v; } return @""; }
static NSString *Pack(NSArray *parts) { NSMutableString *s=[NSMutableString string]; for(NSString *p in parts)[s appendFormat:@"%lu:%@;",(unsigned long)p.length,p]; return s; }
static NSString *Digest(NSString *key, NSString *evidence) {
    NSData *d=[Pack(@[@"CACase-v2",key,evidence]) dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(d.bytes,(CC_LONG)d.length,digest);
    NSMutableString *s=[NSMutableString string]; for(NSUInteger i=0;i<sizeof(digest);i++)[s appendFormat:@"%02x",digest[i]]; return s;
}
static BOOL ValidID(id v) {
    return [v isKindOfClass:NSString.class] && [v length]==64 && [v rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location==NSNotFound;
}
static BOOL ValidEvidence(id v) {
    if (![v isKindOfClass:NSString.class] || !S(v).length) return NO;
    NSArray *lines=[v componentsSeparatedByString:@"\n"];
    if(lines.count<3 || lines.count>8 || [NSSet setWithArray:lines].count<3) return NO;
    for(NSString *line in lines) { NSRange colon=[line rangeOfString:@":"]; if(colon.location==NSNotFound || !colon.location || colon.location+1>=line.length)return NO; }
    return YES;
}
static BOOL ValidEntry(id x) {
    if (![x isKindOfClass:NSDictionary.class]) return NO;
    if (![x[@"schemaVersion"] isKindOfClass:NSNumber.class] || ![x[@"schemaVersion"] isEqual:@2] || !ValidID(x[@"id"])) return NO;
    for(NSString *k in @[@"key",@"answer",@"createdAt",@"source"]) if(!S(x[k]).length)return NO;
    if(![x[@"source"] isEqual:@"AI"] || !ValidEvidence(x[@"evidence"]))return NO;
    for(NSString *k in @[@"confirmed",@"rejected"]) if(![x[k] isKindOfClass:NSNumber.class] || ![@[@0,@1] containsObject:x[k]])return NO;
    if(x[@"testNote"] && ![x[@"testNote"] isKindOfClass:NSString.class])return NO;
    if([x[@"confirmed"] boolValue] && !S(x[@"testNote"]).length)return NO;
    // Validate length-delimited identity fields, not just an arbitrary nonempty key.
    NSString *key=x[@"key"]; NSUInteger offset=0, count=0;
    while(offset<key.length) {
        NSRange colon=[key rangeOfString:@":" options:0 range:NSMakeRange(offset,key.length-offset)];
        if(colon.location==NSNotFound)return NO;
        NSString *length=[key substringWithRange:NSMakeRange(offset,colon.location-offset)];
        if(!length.length || [length rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location!=NSNotFound)return NO;
        NSUInteger n=[length integerValue]; offset=colon.location+1;
        if(n>key.length-offset || offset+n>=key.length || [key characterAtIndex:offset+n]!=';')return NO;
        // bundle, process, app version, system, exception, signal must be populated; build is optional.
        if(count!=3 && n==0)return NO;
        offset+=n+1; count++;
    }
    return count==7 && [x[@"id"] isEqual:Digest(key,x[@"evidence"])];
}
static NSString *Evidence(NSDictionary *r) {
    NSArray *threads=r[@"threads"], *images=r[@"usedImages"];
    if(![threads isKindOfClass:NSArray.class] || ![images isKindOfClass:NSArray.class])return @"";
    id index=r[@"normalizedFaultingThread"] ?: r[@"faultingThread"]; NSDictionary *thread=nil;
    if([index isKindOfClass:NSNumber.class] && [index doubleValue]>=0 && [index doubleValue]==[index unsignedIntegerValue] && [index unsignedIntegerValue]<threads.count) thread=threads[[index unsignedIntegerValue]];
    if(!thread)for(id t in threads)if([t isKindOfClass:NSDictionary.class] && [t[@"triggered"] isKindOfClass:NSNumber.class] && [t[@"triggered"] boolValue]){thread=t;break;}
    if(![thread isKindOfClass:NSDictionary.class] || ![thread[@"frames"] isKindOfClass:NSArray.class])return @"";
    NSMutableArray *tokens=[NSMutableArray array];
    for(id frame in thread[@"frames"]) {
        if(![frame isKindOfClass:NSDictionary.class])continue;
        NSString *symbol=S(frame[@"symbol"]); id i=frame[@"imageIndex"];
        if(!symbol.length || [symbol hasPrefix:@"0x"] || [symbol isEqual:@"???"] || [symbol containsString:@"\n"])continue;
        if(![i isKindOfClass:NSNumber.class] || [i doubleValue]<0 || [i doubleValue]!=[i unsignedIntegerValue] || [i unsignedIntegerValue]>=images.count)continue;
        id image=images[[i unsignedIntegerValue]]; NSString *module=[image isKindOfClass:NSDictionary.class] ? S(image[@"name"]) : @"";
        if(!module.length || [module containsString:@"\n"])continue;
        [tokens addObject:[NSString stringWithFormat:@"%@:%@",module,symbol]]; if(tokens.count==8)break;
    }
    NSString *e=[tokens componentsJoinedByString:@"\n"]; return ValidEvidence(e)?e:@"";
}

@implementation CACaseStore
@synthesize directory=_directory, defaults=_defaults;
+ (instancetype)sharedStore { static CACaseStore *s; static dispatch_once_t once; dispatch_once(&once,^{s=[self new];}); return s; }
- (instancetype)initWithDirectory:(NSString *)directory { self=[super init]; if(self)_directory=[directory copy]; return self; }
- (NSString *)directory { if(!_directory)_directory=[[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences/CrashAnalyzer/Cases"] copy]; return _directory; }
- (NSUserDefaults *)defaults { return _defaults ?: [NSUserDefaults standardUserDefaults]; }
- (BOOL)settingEnabled:(NSString *)key { id v=[self.defaults objectForKey:key]; return v ? [v boolValue] : YES; }
+ (NSDictionary *)evidenceForReport:(NSDictionary *)r {
    if(![r isKindOfClass:NSDictionary.class])return nil;
    NSArray *parts=@[V(r,@[@"normalizedBundleID",@"bundleID"]),V(r,@[@"normalizedProcessName",@"procName",@"app_name"]),V(r,@[@"app_version",@"build_version"]),S(r[@"build_version"]),V(r,@[@"normalizedSystemVersion",@"systemVersion"]),V(r,@[@"normalizedExceptionType",@"exceptionType"]),V(r,@[@"normalizedSignal",@"signal"])];
    for(NSUInteger i=0;i<parts.count;i++)if(i!=3 && ![parts[i] length])return nil;
    NSString *e=Evidence(r); if(!e.length)return nil; NSString *key=Pack(parts);
    return @{@"key":key,@"evidence":e,@"id":Digest(key,e)};
}
- (NSString *)pathForID:(NSString *)caseID { return ValidID(caseID)?[self.directory stringByAppendingPathComponent:[caseID stringByAppendingString:@".json"]]:nil; }
- (NSDictionary *)caseWithID:(NSString *)caseID {
    @synchronized(self) {
        NSString *path=[self pathForID:caseID]; if(!path)return nil;
        NSData *d=[NSData dataWithContentsOfFile:path]; id x=d?[NSJSONSerialization JSONObjectWithData:d options:0 error:nil]:nil;
        return ValidEntry(x) && [x[@"id"] isEqual:caseID]?x:nil;
    }
}
- (NSArray *)allCases {
    @synchronized(self) {
        NSMutableArray *out=[NSMutableArray array];
        for(NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.directory error:nil]) {
            if(![f.pathExtension isEqual:@"json"])continue;
            NSDictionary *c=[self caseWithID:f.stringByDeletingPathExtension]; if(c)[out addObject:c];
        }
        [out sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){ NSComparisonResult result=[b[@"createdAt"] compare:a[@"createdAt"]]; return result==NSOrderedSame?[a[@"id"] compare:b[@"id"]]:result; }];
        return out;
    }
}
- (NSDictionary *)summary {
    NSUInteger unverified=0,validated=0,rejected=0; NSArray *all=self.allCases;
    for(NSDictionary *c in all)if([c[@"rejected"] boolValue])rejected++; else if([c[@"confirmed"] boolValue])validated++; else unverified++;
    return @{@"total":@(all.count),@"unverified":@(unverified),@"validated":@(validated),@"rejected":@(rejected)};
}
- (NSDictionary *)matchingCaseForReport:(NSDictionary *)r {
    if(![self settingEnabled:CAUseHistoricalCases])return nil;
    NSDictionary *e=[CACaseStore evidenceForReport:r]; if(!e)return nil;
    NSDictionary *c=[self caseWithID:e[@"id"]];
    if(!c || [c[@"rejected"] boolValue] || ([self settingEnabled:CAOnlyValidatedCases] && ![c[@"confirmed"] boolValue]))return nil;
    return [c[@"key"] isEqual:e[@"key"]] && [c[@"evidence"] isEqual:e[@"evidence"]]?c:nil;
}
- (NSDictionary *)matchingAIReferenceForReport:(NSDictionary *)r {
    if(![self settingEnabled:CAUseHistoricalCases])return nil;
    NSDictionary *e=[CACaseStore evidenceForReport:r]; if(!e)return nil;
    NSDictionary *c=[self caseWithID:e[@"id"]];
    return (!c || [c[@"rejected"] boolValue]) ? nil : ([c[@"key"] isEqual:e[@"key"]] && [c[@"evidence"] isEqual:e[@"evidence"]] ? c : nil);
}
- (BOOL)writeEntry:(NSDictionary *)c {
    if(!ValidEntry(c))return NO;
    if(![[NSFileManager defaultManager] createDirectoryAtPath:self.directory withIntermediateDirectories:YES attributes:nil error:nil])return NO;
    NSData *d=[NSJSONSerialization dataWithJSONObject:c options:0 error:nil];
    return d && [d writeToFile:[self pathForID:c[@"id"]] options:NSDataWritingAtomic error:nil];
}
- (BOOL)saveAIReference:(NSString *)answer forReport:(NSDictionary *)r model:(NSString *)model scope:(NSString *)scope {
    @synchronized(self) {
        if(![self settingEnabled:CAAutoSaveCases] || !S(answer).length || !S(model).length || ![@[@"structured",@"source"] containsObject:scope])return NO;
        NSDictionary *e=[CACaseStore evidenceForReport:r]; if(!e)return NO;
        NSDictionary *existing=[self caseWithID:e[@"id"]]; if(existing)return YES;
        NSMutableDictionary *c=[NSMutableDictionary dictionaryWithDictionary:e];
        [c addEntriesFromDictionary:@{@"schemaVersion":@2,@"answer":S(answer),@"source":@"AI",@"createdAt":[NSDate date].description,@"confirmed":@NO,@"rejected":@NO,@"model":S(model),@"scope":scope,@"reportKey":e[@"key"],@"reportIdentity":e[@"id"]}];
        return [self writeEntry:c];
    }
}
- (BOOL)saveUnverifiedAnswer:(NSString *)answer forReport:(NSDictionary *)r {
    return [self saveAIReference:answer forReport:r model:@"unknown" scope:@"structured"];
}
- (BOOL)recordTestNote:(NSString *)note forCase:(NSDictionary *)entry {
    @synchronized(self) {
        if(!S(note).length || ![entry isKindOfClass:NSDictionary.class])return NO;
        NSDictionary *current=[self caseWithID:entry[@"id"]]; if(!current || [current[@"rejected"] boolValue])return NO;
        NSMutableDictionary *c=[NSMutableDictionary dictionaryWithDictionary:current]; c[@"testNote"]=S(note); c[@"confirmed"]=@YES; return [self writeEntry:c];
    }
}
- (BOOL)rejectCase:(NSDictionary *)entry {
    @synchronized(self) {
        if(![entry isKindOfClass:NSDictionary.class])return NO;
        NSDictionary *current=[self caseWithID:entry[@"id"]]; if(!current)return NO;
        NSMutableDictionary *c=[NSMutableDictionary dictionaryWithDictionary:current]; c[@"rejected"]=@YES; return [self writeEntry:c];
    }
}
- (BOOL)deleteCaseWithID:(NSString *)caseID {
    @synchronized(self) { NSString *path=[self pathForID:caseID]; return path && [[NSFileManager defaultManager] removeItemAtPath:path error:nil]; }
}
#if !__has_feature(objc_arc)
- (void)dealloc { [_directory release]; [_defaults release]; [super dealloc]; }
#endif
@end
