#import "CACaseStore.h"
#import <Foundation/Foundation.h>

static void Check(BOOL ok, NSString *message) { if(!ok){ NSLog(@"FAIL: %@",message); abort(); } }
static NSDictionary *Report(NSArray *symbols) {
    NSMutableArray *frames=[NSMutableArray array]; for(NSString *s in symbols)[frames addObject:@{@"symbol":s,@"imageIndex":@0}];
    return @{@"normalizedBundleID":@"com.example.app",@"normalizedProcessName":@"App",@"app_version":@"1",@"build_version":@"10",@"normalizedSystemVersion":@"iOS 17",@"normalizedExceptionType":@"EXC_BAD_ACCESS",@"normalizedSignal":@"SIGSEGV",@"normalizedFaultingThread":@0,@"threads":@[@{@"triggered":@YES,@"frames":frames}],@"usedImages":@[@{@"name":@"App"}]};
}
static void WriteJSON(id value, NSString *path) { Check([[NSJSONSerialization dataWithJSONObject:value options:0 error:nil] writeToFile:path atomically:YES],@"write fixture"); }
int main(void) {
    @autoreleasepool {
        NSString *suite=[@"CACaseTests." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSString *dir=[NSTemporaryDirectory() stringByAppendingPathComponent:suite];
        NSUserDefaults *defaults=[[NSUserDefaults alloc] initWithSuiteName:suite];
        [defaults removePersistentDomainForName:suite];
        CACaseStore *s=[[CACaseStore alloc] initWithDirectory:dir]; s.defaults=defaults;
        NSDictionary *r=Report(@[@"a",@"b",@"c"]), *other=Report(@[@"d",@"e",@"f"]);
        NSDictionary *e=[CACaseStore evidenceForReport:r]; NSString *caseID=e[@"id"];
        Check(e!=nil && [caseID isEqual:[CACaseStore evidenceForReport:r][@"id"]],@"deterministic identity");
        Check(![caseID isEqual:[CACaseStore evidenceForReport:other][@"id"]],@"different stack has different ID");
        for(NSString *key in @[CAAutoSaveCases,CAUseHistoricalCases,CAOnlyValidatedCases])Check([s settingEnabled:key],@"defaults enabled");
        Check(![s saveUnverifiedAnswer:@" \n" forReport:r],@"no blank answers");
        Check([s saveUnverifiedAnswer:@"first answer" forReport:r],@"save reference");
        Check(s.allCases.count==1 && ![s matchingCaseForReport:r],@"unverified visible but default not adopted");
        [defaults setBool:NO forKey:CAOnlyValidatedCases];
        Check([s matchingCaseForReport:r]!=nil,@"opt-in unverified adoption");
        Check([s saveUnverifiedAnswer:@"second failure" forReport:other] && s.allCases.count==2,@"distinct failures not overwritten");
        NSDictionary *original=[s caseWithID:caseID];
        Check(![s recordTestNote:@" \n" forCase:original],@"empty note rejected");
        Check([s recordTestNote:@"iOS 17; reproduced, fix did not resolve" forCase:original],@"actual note persisted");
        [defaults setBool:YES forKey:CAOnlyValidatedCases];
        Check([s matchingCaseForReport:r]!=nil && ![s matchingCaseForReport:other],@"only recorded cases adopted");
        Check([s saveUnverifiedAnswer:@"replacement" forReport:r],@"repeat save idempotent");
        Check([[s caseWithID:caseID][@"answer"] isEqual:@"first answer"] && [[s caseWithID:caseID][@"confirmed"] boolValue],@"repeat save preserves tested answer");
        CACaseStore *reopened=[[CACaseStore alloc] initWithDirectory:dir]; reopened.defaults=defaults;
        Check([[reopened caseWithID:caseID][@"testNote"] containsString:@"did not resolve"],@"reopen persistence");
        for(NSString *key in @[@"normalizedBundleID",@"normalizedProcessName",@"app_version",@"build_version",@"normalizedSystemVersion",@"normalizedExceptionType",@"normalizedSignal"]) {
            NSMutableDictionary *changed=[NSMutableDictionary dictionaryWithDictionary:r]; changed[key]=@"changed";
            Check(![s matchingCaseForReport:changed],[@"strict mismatch " stringByAppendingString:key]);
            if(![key isEqual:@"build_version"]){[changed removeObjectForKey:key]; if([key isEqual:@"app_version"])[changed removeObjectForKey:@"build_version"]; Check(![CACaseStore evidenceForReport:changed],@"missing required identity");}
        }
        Check(![CACaseStore evidenceForReport:Report(@[@"a",@"b"])],@"two symbols weak");
        Check(![CACaseStore evidenceForReport:Report(@[@"a",@"a",@"a"])],@"repeated symbols weak");
        Check(![CACaseStore evidenceForReport:Report(@[@"0x123",@"???",@"c"])],@"unsymbolicated weak");
        Check(![CACaseStore evidenceForReport:(id)@[]],@"malformed report safe");
        NSMutableDictionary *bad=[NSMutableDictionary dictionaryWithDictionary:r]; bad[@"threads"]=@[@42];
        Check(![CACaseStore evidenceForReport:bad],@"malformed thread safe");
        bad[@"threads"]=[NSNull null]; Check(![CACaseStore evidenceForReport:bad],@"null threads safe");
        [defaults setBool:NO forKey:CAUseHistoricalCases];
        Check(![s matchingCaseForReport:r] && s.allCases.count==2,@"disabled match leaves library visible");
        [defaults setBool:YES forKey:CAUseHistoricalCases];
        [defaults setBool:NO forKey:CAAutoSaveCases];
        Check(![s saveUnverifiedAnswer:@"disabled" forReport:Report(@[@"x",@"y",@"z"]) ] && s.allCases.count==2,@"save toggle honored");
        [defaults setBool:YES forKey:CAAutoSaveCases];
        Check([s rejectCase:original] && ![s matchingCaseForReport:r],@"rejection reads current record");
        Check([[s caseWithID:caseID][@"testNote"] length]>0,@"stale rejection preserves latest note");
        Check(![s recordTestNote:@"new" forCase:original],@"rejected case cannot be confirmed again");
        Check([s saveUnverifiedAnswer:@"retry" forReport:r] && ![s matchingCaseForReport:r],@"repeat save does not revive rejected case");
        NSDictionary *summary=s.summary;
        Check([summary[@"total"] integerValue]==2 && [summary[@"rejected"] integerValue]==1 && [summary[@"unverified"] integerValue]==1,@"summary partitions cases");
        NSString *path=[dir stringByAppendingPathComponent:[caseID stringByAppendingString:@".json"]];
        NSDictionary *good=[s caseWithID:caseID];
        for(id invalid in @[@[],@{@"answer":@"legacy v1"}]){WriteJSON(invalid,path);Check(![s caseWithID:caseID] && ![s matchingCaseForReport:r],@"legacy or wrong JSON shape ignored");}
        for(NSString *key in @[@"schemaVersion",@"id",@"key",@"evidence",@"answer",@"confirmed",@"rejected",@"source",@"createdAt",@"testNote"]) {
            NSMutableDictionary *corrupt=[NSMutableDictionary dictionaryWithDictionary:good]; corrupt[key]=[NSNull null]; WriteJSON(corrupt,path);
            Check(![s caseWithID:caseID],[@"corrupt field ignored " stringByAppendingString:key]);
        }
        for(id invalidEvidence in @[@"",@"App:a",@"App:a\nApp:a\nApp:a",@[]]) {
            NSMutableDictionary *corrupt=[NSMutableDictionary dictionaryWithDictionary:good]; corrupt[@"evidence"]=invalidEvidence; WriteJSON(corrupt,path); Check(![s caseWithID:caseID],@"weak stored evidence ignored");
        }
        NSMutableDictionary *future=[NSMutableDictionary dictionaryWithDictionary:good]; future[@"schemaVersion"]=@3; WriteJSON(future,path); Check(![s caseWithID:caseID],@"future schema ignored");
        [@"{invalid JSON" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        Check(![s caseWithID:caseID] && s.allCases.count==1,@"corrupt JSON omitted from list");
        Check(![s caseWithID:@"../escape"] && ![s deleteCaseWithID:@"../escape"],@"invalid IDs cannot escape directory");
        WriteJSON(good,path);
        Check([s deleteCaseWithID:caseID] && ![s caseWithID:caseID],@"delete persisted");
        Check(![s recordTestNote:@"stale" forCase:original] && ![s rejectCase:original],@"stale actions cannot resurrect deleted case");
        Check(![s deleteCaseWithID:caseID],@"repeat delete reports missing");
        Check([s deleteCaseWithID:[CACaseStore evidenceForReport:other][@"id"]] && [s.summary[@"total"] integerValue]==0,@"empty summary after deletion");
        [[NSFileManager defaultManager] removeItemAtPath:dir error:nil]; [defaults removePersistentDomainForName:suite];
#if !__has_feature(objc_arc)
        [reopened release]; [s release]; [defaults release];
#endif
        NSLog(@"Case regression tests passed (production CACaseStore)");
    }
    return 0;
}
