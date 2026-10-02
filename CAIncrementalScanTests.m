#import "CALogStore.h"
#import <Foundation/Foundation.h>
@interface CALogStore (Testing)
- (NSArray *)scanReportsWithDiagnostics:(NSDictionary **)diagnostics;
- (NSArray *)roots;
@end
@interface CATestLogStore : CALogStore
@property(nonatomic,copy) NSString *testRoot;
@property(nonatomic) NSUInteger parses;
@end
@implementation CATestLogStore
- (NSArray *)roots { return @[self.testRoot]; }
- (NSDictionary *)parse:(NSData *)data { self.parses++;return [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]; }
- (void)dealloc {[_testRoot release];[super dealloc];}
@end
static void Check(BOOL ok,NSString *msg){if(!ok){NSLog(@"FAIL: %@",msg);abort();}}
int main(void){@autoreleasepool{
    CATestLogStore *s=[CATestLogStore new];s.testRoot=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSFileManager *fm=NSFileManager.defaultManager;[fm createDirectoryAtPath:s.testRoot withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *a=[s.testRoot stringByAppendingPathComponent:@"a.ips"],*b=[s.testRoot stringByAppendingPathComponent:@"b.ips.synced"];
    [@"{\"bug_type\":\"309\",\"incident\":\"first\"}" writeToFile:a atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSDictionary *d=nil;NSArray *first=[s scanReportsWithDiagnostics:&d];Check(first.count==1 && s.parses==1,@"initial parse");
    NSArray *same=[s scanReportsWithDiagnostics:&d];Check(s.parses==1 && [d[@"reused"] intValue]==1,@"unchanged reused");Check(first[0]==same[0],@"immutable snapshot object reused");
    [@"{\"bug_type\":\"309\",\"incident\":\"changed-longer\"}" writeToFile:a atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [@"{\"bug_type\":\"298\"}" writeToFile:b atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    Check([s scanReportsWithDiagnostics:&d].count==2 && s.parses==3,@"changed and added parsed only");
    [fm removeItemAtPath:a error:NULL];NSArray *remaining=[s scanReportsWithDiagnostics:&d];Check(remaining.count==1 && s.parses==3 && [d[@"removed"] intValue]==1,@"deletion removed without reparsing");
    Check([d[@"lastScannedAt"] length]>0,@"actual last scanned time");
    [fm removeItemAtPath:s.testRoot error:NULL];Check([s scanReportsWithDiagnostics:&d].count==0 && ![d[@"exists"] boolValue],@"directory disappears safely");
    [s release];NSLog(@"Incremental scan regressions passed");
}return 0;}
