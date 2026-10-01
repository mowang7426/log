#import "CALogStore.h"
#import <Foundation/Foundation.h>
static void Check3(BOOL ok, NSString *m) { if (!ok) { NSLog(@"FAIL: %@", m); abort(); } }
static void AssertKind(NSDictionary *a) { for (NSString *k in @[@"title", @"reason", @"evidence", @"actions", @"confidence", @"status"]) Check3(a[k] != nil, [@"missing " stringByAppendingString:k]); Check3([a[@"evidence"] isKindOfClass:NSArray.class], @"evidence array"); }
int main(void) { @autoreleasepool {
    CALogStore *s=[CALogStore new];
    NSDictionary *jetsam=@{@"bug_type":@"298", @"largestProcess":@"OtherApp"};
    NSDictionary *guard=@{@"exception":@{@"type":@"EXC_GUARD", @"codes":@"1"}};
    NSDictionary *unknown=@{@"bug_type":@"999"};
    NSDictionary *a=[s humanReadableAnalysisForReport:jetsam], *b=[s humanReadableAnalysisForReport:guard], *c=[s humanReadableAnalysisForReport:unknown];
    AssertKind(a); AssertKind(b); AssertKind(c);
    Check3([a[@"title"] containsString:@"内存"], @"Jetsam title");
    Check3([a[@"reason"] containsString:@"可能"], @"Jetsam possibility boundary");
    Check3([a[@"evidence"] count] > 0, @"Jetsam evidence");
    Check3([b[@"title"] containsString:@"保护"], @"EXC_GUARD title");
    Check3([b[@"evidence"] count] > 0, @"EXC_GUARD evidence");
    Check3([c[@"status"] containsString:@"未确认"], @"unknown status");
    Check3([b[@"evidence"] containsObject:@"事实：normalizedExceptionType = EXC_GUARD"], @"raw guard type evidence");
    Check3([b[@"evidence"] containsObject:@"事实：normalizedCodes = 1"], @"raw guard code evidence, not a root cause");
    Check3([[a[@"evidence"] componentsJoinedByString:@"\n"] containsString:@"不等于被终止"], @"largestProcess boundary");
    Check3([[s humanReadableAnalysisForReport:@{@"bug_type":@298}][@"title"] isEqual:a[@"title"]], @"numeric Jetsam tag");
    Check3([c[@"title"] isEqual:[s humanReadableAnalysisForReport:@{@"bug_type":@999, @"threads":@[@{@"symbol":@"watchdog panic jetsam"}], @"fileName":@"panic-full.ips", @"diagnosis":@"EXC_GUARD"}][@"title"]], @"unrelated prose must not classify");
    Check3([[s humanReadableAnalysisForReport:@{@"largestProcess":@"OtherApp"}][@"title"] isEqual:c[@"title"]], @"largestProcess alone does not identify Jetsam");
    NSArray *fixtures=@[@{@"exception":@{@"type":@"EXC_BAD_ACCESS"}}, @{@"termination":@{@"namespace":@"FRONTBOARD", @"code":@2343432205}}, @{@"panicString":@"panic test"}, @{@"exception":@{@"signal":@"SIGKILL"}}];
    NSArray *titles=@[@"内存访问", @"超时", @"重启", @"强制终止"];
    for (NSUInteger i=0;i<fixtures.count;i++) {
        NSDictionary *result=[s humanReadableAnalysisForReport:fixtures[i]];
        AssertKind(result);
        Check3([result[@"title"] containsString:titles[i]], @"remaining classification branches");
        Check3([result[@"status"] containsString:@"未确认"], @"recognized event is not confirmed cause");
    }
    for (id input in @[jetsam,guard,unknown,@{},@{@"parseError":@YES,@"bug_type":@298},@{@"watchdogTimeout":[NSNull null]},(id)@[]]) {
        NSDictionary *result=[s humanReadableAnalysisForReport:input]; AssertKind(result);
        Check3([NSJSONSerialization isValidJSONObject:result], @"JSON-compatible analysis");
        for (NSString *k in @[@"evidence",@"actions"]) for (id text in result[k]) Check3([text isKindOfClass:NSString.class], @"string array contract");
    }
    Check3([[s humanReadableAnalysisForReport:@{@"parseError":@YES,@"bug_type":@298}][@"reason"] containsString:@"未成功解析"], @"parse failure takes precedence");
    Check3([[s humanReadableAnalysisForReport:@{@"bug_type":@210}][@"confidence"] containsString:@"仅有类型"], @"panic number does not assert cause");
    NSMutableDictionary *preserved=[NSMutableDictionary dictionaryWithDictionary:guard]; preserved[@"path"]=@"/tmp/original.ips"; preserved[@"threads"]=@[@{@"frames":@[]}];
    NSDictionary *snapshot=[[preserved copy] autorelease]; [s humanReadableAnalysisForReport:preserved];
    Check3([preserved isEqual:snapshot], @"analysis does not alter fields, path, or source");
    NSLog(@"Human analysis regression tests passed");
#if !__has_feature(objc_arc)
    [s release];
#endif
} return 0; }
