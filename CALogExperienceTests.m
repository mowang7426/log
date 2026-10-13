#import "CALogStore.h"
#import "CALogExperience.h"
@interface CALogStore (ExperienceTesting)
- (NSDictionary *)parse:(NSData *)data;
- (NSArray *)roots;
- (NSArray *)scanReportsWithDiagnostics:(NSDictionary **)d;
@end
@interface CAExperienceStore : CALogStore
@property(nonatomic,copy) NSString *testRoot;
@end
@implementation CAExperienceStore
- (NSArray *)roots { return @[self.testRoot]; }
- (void)dealloc { [_testRoot release]; [super dealloc]; }
@end
static void Check(BOOL ok,NSString *why) { if(!ok) { NSLog(@"FAIL %@",why); abort(); } }
static NSDictionary *Parse(CALogStore *s,NSString *text) { return [s parse:[text dataUsingEncoding:NSUTF8StringEncoding]]; }
int main(void) { @autoreleasepool {
    CAExperienceStore *s=[CAExperienceStore new];
    Check([Parse(s,@"{\"bug_type\":\"309\"}")[@"parseStatus"] isEqual:@"完整单 JSON"],@"compact");
    Check([Parse(s,@"\uFEFF{\r\n \"procName\": \"App\",\r\n \"exception\": {\"type\":\"EXC_BAD_ACCESS\"}\r\n}")[@"procName"] isEqual:@"App"],@"pretty BOM CRLF");
    NSDictionary *two=Parse(s,@"{\"bug_type\":\"309\",\"name\":\"brace } in string\"}\n{\n\"procName\":\"App\"\n}");
    Check([two[@"bodyParsed"] boolValue] && ![two[@"parsePartial"] boolValue],@"two objects");
    NSDictionary *partial=Parse(s,@"{\"bug_type\":\"309\"}\n{\"procName\":");
    Check([partial[@"parsePartial"] boolValue] && ![partial[@"bodyParsed"] boolValue],@"truncated body labelled");
    Check(!Parse(s,@"{broken") && !Parse(s,@"[]"),@"invalid and array rejected");
    Check([[s categoryForReport:@{@"procName":@"metrics",@"bug_type":@"999"}] isEqual:@"其他"],@"process name is not crash");
    Check([[s categoryForReport:@{@"bug_type":@"309",@"exception":@{@"type":@"EXC_RESOURCE"}}] isEqual:@"资源"],@"resource precedes crash tag");
    Check([[s categoryForReport:@{@"bug_type":@"309",@"termination":@{@"code":@2343432205}}] isEqual:@"资源"],@"watchdog precedes crash tag");
    Check([[s categoryForReport:@{@"threads":@[@{@"symbol":@"panic watchdog jetsam"}],@"largestProcess":@"App"}] isEqual:@"其他"],@"unrelated strings excluded");
    Check([[s categoryForReport:@{@"watchdogTimeout":NSNull.null,@"termination":@{@"code":NSNull.null}}] isEqual:@"其他"],@"null termination safe");
    NSDictionary *search=@{@"procName":@"Example",@"bundleInfo":@{@"CFBundleIdentifier":@"com.example.test"},@"fileName":@"Report.ips",@"exception":@{@"type":@"EXC_GUARD"}};
    for(NSString *q in @[@"example",@"com.example",@"report.IPS",@"exc_guard",@""]) Check(CAReportMatches(search,q),@"search real fields");
    Check(!CAReportMatches(search,@"not present"),@"search nonmatch");
    NSDate *a=CAReportDate(@{@"timestamp":@"2026-01-01 10:00:00 +0800"},nil),*b=CAReportDate(@{@"timestamp":@"2026-01-01T03:00:00Z"},nil);
    Check([a compare:b]==NSOrderedAscending,@"true timezone ordering"); Check([CAReportDate(@{@"timestamp":@"bad"},b) isEqualToDate:b],@"date fallback");
    NSArray *e=CASpecialEvidence(@{@"bug_type":@298,@"processes":@[@{@"name":@"A",@"reason":@"limit",@"rpages":@100},@{@"name":@"B",@"reason":@"pressure",@"rpages":@200}]});
    NSString *joined=[e componentsJoinedByString:@"\n"]; Check([joined containsString:@"A"] && [joined containsString:@"B"] && [joined containsString:@"未知"] && ![joined containsString:@"MiB"],@"all victims; no invented page size");
    Check([[CASpecialEvidence(@{@"bug_type":@298,@"memoryStatus":@{@"pageSize":@4096},@"processes":@[@{@"name":@"A",@"reason":@"limit",@"rpages":@256}]}) componentsJoinedByString:@"\n"] containsString:@"1.00 MiB"],@"real page conversion");
    NSFileManager *fm=NSFileManager.defaultManager; s.testRoot=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]; [fm createDirectoryAtPath:s.testRoot withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *one=[s.testRoot stringByAppendingPathComponent:@"one.ips"], *newPath=[s.testRoot stringByAppendingPathComponent:@"new.ips"], *dir=[s.testRoot stringByAppendingPathComponent:@"directory.ips"], *link=[s.testRoot stringByAppendingPathComponent:@"link.ips"];
    [@"{}" writeToFile:one atomically:YES encoding:NSUTF8StringEncoding error:NULL]; [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL]; [fm createSymbolicLinkAtPath:link withDestinationPath:one error:NULL];
    NSArray *frozen=[s deletableReportPaths]; Check(frozen.count==1 && [s countReportsAtPaths:@[one,one,dir,link]]==1,@"unique regular files only");
    [@"{}" writeToFile:newPath atomically:YES encoding:NSUTF8StringEncoding error:NULL]; Check([s deleteReportsAtPaths:frozen]==1 && [fm fileExistsAtPath:newPath],@"new arrivals excluded");
    Check([s deleteReportsAtPaths:@[dir,link,@"/tmp/outside.ips"]]==0,@"directories symlinks outsiders rejected");
    // deletion schedules an async scan; flush background work before removing test root.
    [fm removeItemAtPath:s.testRoot error:NULL];
    NSLog(@"Experience regressions passed"); [s release];
} return 0; }
