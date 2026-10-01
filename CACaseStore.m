#import "CACaseStore.h"
#import <CommonCrypto/CommonDigest.h>

static NSString *S(id v){ return [v isKindOfClass:[NSString class]] ? [v stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : (v ? [v description] : @""); }
static NSString *V(NSDictionary *r, NSArray *keys){ for(NSString *k in keys){NSString *v=S(r[k]);if(v.length)return v;}return @""; }
static NSString *Key(NSDictionary *r){return [NSString stringWithFormat:@"%@|%@|%@|%@|%@|%@",V(r,@[@"normalizedBundleID",@"bundleID"]),V(r,@[@"normalizedProcessName",@"procName",@"app_name"]),V(r,@[@"app_version",@"build_version"]),V(r,@[@"normalizedSystemVersion",@"systemVersion"]),V(r,@[@"normalizedExceptionType",@"exceptionType"]),V(r,@[@"normalizedSignal",@"signal"])];}
static NSString *Evidence(NSDictionary *r) {
    NSArray *threads=r[@"threads"], *images=r[@"usedImages"];
    if (![threads isKindOfClass:NSArray.class]) return @"";
    id index=r[@"normalizedFaultingThread"] ?: r[@"faultingThread"];
    NSDictionary *thread=nil;
    if ([index respondsToSelector:@selector(unsignedIntegerValue)] && [index unsignedIntegerValue]<threads.count) thread=threads[[index unsignedIntegerValue]];
    if (!thread) for (id t in threads) if ([t isKindOfClass:NSDictionary.class] && [t[@"triggered"] boolValue]) { thread=t; break; }
    if (![thread isKindOfClass:NSDictionary.class]) return @"";
    NSArray *frames=thread[@"frames"];
    if (![frames isKindOfClass:NSArray.class]) return @"";
    NSMutableArray *tokens=[NSMutableArray array];
    for (id frame in frames) {
        if (![frame isKindOfClass:NSDictionary.class]) continue;
        NSString *symbol=[frame[@"symbol"] isKindOfClass:NSString.class] ? frame[@"symbol"] : @"";
        if (!symbol.length || [symbol hasPrefix:@"0x"]) continue;
        NSString *module=@"";
        id imageIndex=frame[@"imageIndex"];
        if ([images isKindOfClass:NSArray.class] && [imageIndex respondsToSelector:@selector(unsignedIntegerValue)] && [imageIndex unsignedIntegerValue]<images.count) {
            id image=images[[imageIndex unsignedIntegerValue]];
            if ([image isKindOfClass:NSDictionary.class]) module=S(image[@"name"]);
        }
        [tokens addObject:[NSString stringWithFormat:@"%@:%@",module,symbol]];
        if (tokens.count==8) break;
    }
    return tokens.count>=3 ? [tokens componentsJoinedByString:@"\n"] : @"";
}
@implementation CACaseStore
+ (instancetype)sharedStore{static CACaseStore*s;static dispatch_once_t once;dispatch_once(&once,^{s=[self new];});return s;}
- (instancetype)initWithDirectory:(NSString*)directory{self=[super init];if(self)_directory=[directory copy];return self;}
- (NSString*)directory{if(!_directory)_directory=[[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences/CrashAnalyzer/Cases"] copy];return _directory;}
+ (NSDictionary*)evidenceForReport:(NSDictionary*)r{NSString*k=Key(r),*e=Evidence(r);if(!k.length||!e.length)return nil;return @{ @"key":k,@"evidence":e};}
- (NSArray*)allCases{NSArray*fs=[[NSFileManager defaultManager]contentsOfDirectoryAtPath:self.directory error:nil];NSMutableArray*out=[NSMutableArray array];for(NSString*f in fs)if([f.pathExtension isEqualToString:@"json"]){NSData*d=[NSData dataWithContentsOfFile:[self.directory stringByAppendingPathComponent:f]];id x=d?[NSJSONSerialization JSONObjectWithData:d options:0 error:nil]:nil;if([x isKindOfClass:NSDictionary.class]&&[x[@"answer"] isKindOfClass:NSString.class])[out addObject:x];}return out;}
- (NSDictionary*)matchingCaseForReport:(NSDictionary*)r{NSDictionary*e=[CACaseStore evidenceForReport:r];if(!e)return nil;for(NSDictionary*c in self.allCases)if(![c[@"rejected"] boolValue]&&[c[@"key"] isEqual:e[@"key"]]&&[e[@"evidence"] rangeOfString:c[@"evidence"]].location!=NSNotFound)return c;return nil;}
- (NSString*)fileForKey:(NSString*)key{NSData *bytes=[key dataUsingEncoding:NSUTF8StringEncoding];unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(bytes.bytes,(CC_LONG)bytes.length,digest);NSMutableString *h=[NSMutableString string];for(NSUInteger i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[h appendFormat:@"%02x",digest[i]];return[self.directory stringByAppendingPathComponent:[h stringByAppendingString:@".json"]];}
- (BOOL)saveUnverifiedAnswer:(NSString*)answer forReport:(NSDictionary*)r{NSDictionary*e=[CACaseStore evidenceForReport:r];if(!answer.length||!e)return NO;[[NSFileManager defaultManager]createDirectoryAtPath:self.directory withIntermediateDirectories:YES attributes:nil error:nil];NSMutableDictionary*c=[@{ @"key":e[@"key"],@"evidence":e[@"evidence"],@"answer":answer,@"confirmed":@NO,@"rejected":@NO,@"source":@"AI",@"createdAt":[NSDate date].description}mutableCopy];NSData*d=[NSJSONSerialization dataWithJSONObject:c options:0 error:nil];return[d writeToFile:[self fileForKey:e[@"key"]] options:NSDataWritingAtomic error:nil];}
- (BOOL)recordTestNote:(NSString*)note forCase:(NSDictionary*)entry{if(!note.length)return NO;NSString*key=entry[@"key"];if(!key.length)return NO;NSMutableDictionary*m=[entry mutableCopy];m[@"testNote"]=note;m[@"confirmed"]=@YES;NSData*d=[NSJSONSerialization dataWithJSONObject:m options:0 error:nil];return[d writeToFile:[self fileForKey:key] options:NSDataWritingAtomic error:nil];}
- (BOOL)rejectCase:(NSDictionary*)entry{NSString*key=entry[@"key"];if(!key.length)return NO;NSMutableDictionary*m=[entry mutableCopy];m[@"rejected"]=@YES;NSData*d=[NSJSONSerialization dataWithJSONObject:m options:0 error:nil];return[d writeToFile:[self fileForKey:key] options:NSDataWritingAtomic error:nil];}
@end
