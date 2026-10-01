#import "CACaseStore.h"
#import <Foundation/Foundation.h>
@interface CACaseStoreTests : NSObject @end
@implementation CACaseStoreTests
- (void)run {
    NSString *dir=[NSTemporaryDirectory() stringByAppendingPathComponent:@"CACaseTests"];
    [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
    CACaseStore *s=[[CACaseStore alloc] initWithDirectory:dir];
    NSDictionary *r=@{ @"normalizedBundleID":@"com.example.app", @"normalizedProcessName":@"App", @"app_version":@"1", @"normalizedSystemVersion":@"iOS 17", @"normalizedExceptionType":@"EXC_BAD_ACCESS", @"normalizedSignal":@"SIGSEGV", @"normalizedFaultingThread":@0, @"threads":@[@{ @"triggered":@YES, @"frames":@[@{ @"symbol":@"a", @"imageIndex":@0 },@{ @"symbol":@"b", @"imageIndex":@0 },@{ @"symbol":@"c", @"imageIndex":@0 }] }], @"usedImages":@[@{ @"name":@"App" }] };
    NSCAssert([CACaseStore evidenceForReport:r], @"evidence should exist");
    NSCAssert([s saveUnverifiedAnswer:@"test answer" forReport:r], @"save should succeed");
    NSCAssert([s matchingCaseForReport:r], @"matching case should be found");
    NSDictionary *caseEntry=[s matchingCaseForReport:r];
    NSCAssert([s recordTestNote:@"verified" forCase:caseEntry], @"confirmation should succeed");
    NSMutableDictionary *changed=[r mutableCopy];
    changed[@"app_version"]=@"2";
    NSCAssert(![s matchingCaseForReport:changed],@"version changes must not match");
    [changed removeObjectForKey:@"threads"];
    NSCAssert(![CACaseStore evidenceForReport:changed],@"generic exception without stack must not match");
    NSCAssert([s rejectCase:[s matchingCaseForReport:r]],@"reject should succeed");
    NSCAssert(![s matchingCaseForReport:r],@"rejected case must not match");
    NSLog(@"Case regression tests passed");
}
@end
int main(void) { @autoreleasepool { [[[CACaseStoreTests alloc] init] run]; } return 0; }
