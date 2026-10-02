#import "CAPluginEvidence.h"
#import <Foundation/Foundation.h>
static void Check(BOOL ok,NSString *s){ if(!ok){NSLog(@"FAIL: %@",s);abort();} }
static NSDictionary *Image(NSString *path){return @{@"name":@"Example.dylib",@"path":path};}
static NSDictionary *Report(NSString *incident,NSArray *images,NSArray *threads,id fault){return @{@"incident":incident,@"path":[@"/tmp/" stringByAppendingFormat:@"%@.ips",incident],@"fileName":[incident stringByAppendingString:@".ips"],@"procName":@"RealApp",@"exception":@{@"type":@"EXC_BAD_ACCESS"},@"usedImages":images,@"threads":threads,@"faultingThread":fault};}
int main(void){@autoreleasepool{
    NSDictionary *i=Image(@"/var/jb/Library/MobileSubstrate/DynamicLibraries/Example.dylib");
    NSDictionary *f=@{@"imageIndex":@0,@"symbol":@"real_symbol"};
    NSDictionary *r=Report(@"a",@[i,i],@[@{@"frames":@[f,f]}],@0);
    NSMutableDictionary *copy=[NSMutableDictionary dictionaryWithDictionary:r];copy[@"path"]=@"/tmp/copy.ips.synced";copy[@"fileName"]=@"copy.ips.synced";
    NSDictionary *s=[[CAPluginEvidence summaryForReports:@[r,r,copy] limit:0] firstObject];
    Check([s[@"main"] intValue]==1 && [s[@"participation"] intValue]==1,@"one count per report and duplicate incident");
    Check([s[@"tier"] isEqual:@"fault"],@"fault tier");
    NSDictionary *e=[s[@"entries"] firstObject],*ref=[e[@"references"] firstObject];
    Check([ref[@"frame"] isEqual:@0] && [ref[@"thread"] isEqual:@0] && [ref[@"symbol"] isEqual:@"real_symbol"],@"actual frame indexes and symbols");
    Check([e[@"report"][@"path"] isEqual:r[@"path"]] && [e[@"report"][@"fileName"] isEqual:@"a.ips"],@"original link identity");
    NSDictionary *other=Report(@"other",@[i],@[@{@"frames":@[]},@{@"frames":@[f]}],@0);
    NSDictionary *loaded=Report(@"loaded",@[i],@[@{@"frames":@[]}],@0);
    NSDictionary *unknown=Report(@"unknown",@[i],@[],@-1);
    Check([[[CAPluginEvidence summaryForReports:@[other] limit:0] firstObject][@"tier"] isEqual:@"other"],@"other-thread auxiliary");
    Check([[[CAPluginEvidence summaryForReports:@[loaded] limit:0] firstObject][@"tier"] isEqual:@"loaded"],@"loaded has no attribution");
    Check([[[CAPluginEvidence summaryForReports:@[unknown] limit:0] firstObject][@"tier"] isEqual:@"unknown"],@"missing threads explicit");
    for(id bad in @[@-1,@99,@0.5,@"0",[NSNull null]]){
        NSDictionary *b=Report(@"bad",@[i],@[@{@"frames":@[@{@"imageIndex":bad}]}],bad);
        NSDictionary *bs=[[CAPluginEvidence summaryForReports:@[b] limit:0] firstObject];
        Check([bs[@"main"] intValue]==0 && [bs[@"tier"] isEqual:@"unknown"],@"invalid indexes safely unknown");
    }
    NSDictionary *mal=@{@"usedImages":@[[NSNull null],i],@"threads":@[[NSNull null],@{@"triggered":[NSNull null],@"frames":@[[NSNull null],@"bad"]}],@"faultingThread":@"garbage"};
    Check([CAPluginEvidence summaryForReports:@[[NSNull null],@[],mal] limit:0].count==1,@"malformed container robustness");
    NSArray *sys=@[Image(@"/usr/lib/libobjc.A.dylib"),Image(@"/var/jb/usr/lib/libSystem.B.dylib"),Image(@"/private/var/containers/Bundle/Application/.jbroot-123/usr/lib/libSystem.dylib")];
    Check([CAPluginEvidence summaryForReports:@[Report(@"sys",sys,@[],@0)] limit:0].count==0,@"rootless system libraries not tweaks");
    NSDictionary *hide=Image(@"/private/var/containers/Bundle/Application/.jbroot-123/Library/MobileSubstrate/DynamicLibraries/Example.dylib");
    NSArray *merged=[CAPluginEvidence summaryForReports:@[r,Report(@"b",@[hide],@[@{@"frames":@[f]}],@0)] limit:0];
    Check(merged.count==1 && [merged[0][@"main"] intValue]==2,@"rootless and roothide same logical tweak, different incidents counted");
    NSArray *different=[CAPluginEvidence summaryForReports:@[r,Report(@"c",@[Image(@"/var/jb/usr/lib/TweakInject/Example.dylib")],@[],@0)] limit:0];
    Check(different.count==2,@"same basename in different injection paths has distinct identity");
    NSMutableDictionary *noUUID=[NSMutableDictionary dictionaryWithDictionary:r];[noUUID removeObjectForKey:@"incident"];noUUID[@"timestamp"]=@"one";
    NSMutableDictionary *copied=[NSMutableDictionary dictionaryWithDictionary:noUUID];copied[@"path"]=@"/tmp/dup.ips";
    NSMutableDictionary *later=[NSMutableDictionary dictionaryWithDictionary:noUUID];later[@"timestamp"]=@"two";
    Check([[[CAPluginEvidence summaryForReports:@[noUUID,copied,later] limit:0] firstObject][@"main"] intValue]==2,@"content copies dedupe, distinct recurrence survives");
    NSDictionary *record=@{@"state":@"暂时禁用后未再发生",@"testedAt":@"2026-10-02 23:00",@"appVersion":@"1.0",@"pluginVersion":@"",@"notes":@"observation not cause"};
    Check([CAPluginEvidence validationStates].count==5,@"all approved validation states");
    Check([CAPluginEvidence saveValidation:record forPlugin:@"test-only-plugin"],@"save local validation");
    Check([[CAPluginEvidence validationForPlugin:@"test-only-plugin"] isEqual:record],@"real date and notes persisted");
    Check(![CAPluginEvidence saveValidation:@{@"state":@"confirmed"} forPlugin:@"test-only-plugin"],@"no confirmed cause state");
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"CAPluginValidation"];
    NSLog(@"Plugin evidence regressions passed");
}return 0;}
