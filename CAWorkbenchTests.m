#import "CAWorkbench.h"
#import <Foundation/Foundation.h>

static void Check(BOOL ok, NSString *message) { if (!ok) { NSLog(@"FAIL: %@", message); abort(); } }
static NSDictionary *Report(void) {
    return @{ @"normalizedProcessName": @"Demo", @"normalizedBundleID": @"com.example.demo",
              @"normalizedExceptionType": @"EXC_BAD_ACCESS", @"normalizedFaultingThread": @1,
              @"threads": @[
                  @{ @"triggered": @NO, @"frames": @[@{@"imageIndex": @0, @"symbol": @"other"}] },
                  @{ @"triggered": @YES, @"name": @"main", @"frames": @[@{@"imageIndex": @1, @"symbol": @"fault_symbol"}] }
              ],
              @"usedImages": @[
                  @{ @"name": @"App", @"path": @"/Applications/Demo.app/Demo" },
                  @{ @"name": @"Injected", @"path": @"/Library/MobileSubstrate/DynamicLibraries/X.dylib" },
                  @{ @"name": @"LoadedOnly", @"path": @"/usr/lib/TweakInject/Y.dylib" }
              ], @"path": @"/tmp/demo.ips", @"incident_id": @"incident" };
}
static void Write(id value, NSString *path) {
    Check([[NSJSONSerialization dataWithJSONObject:value options:0 error:nil] writeToFile:path atomically:YES], @"fixture write");
}
int main(void) {
    @autoreleasepool {
        NSDictionary *r=Report();
        NSArray *fault=[CAWorkbench evidence:r mode:@"fault"];
        Check(fault.count==2 && [fault[0] containsString:@"线程 #1"] && [fault[1] containsString:@"fault_symbol"], @"fault thread mapping");
        NSArray *modules=[CAWorkbench evidence:r mode:@"modules"];
        Check(modules.count==3 && [modules[0] containsString:@"仅已加载镜像；不排名、不归因"] && [modules[1] containsString:@"实际引用（并非根因证明）"] && [modules[2] containsString:@"注入路径线索；未在故障帧引用，不归因"], @"loaded modules are not causal");
        NSMutableDictionary *fallback=[NSMutableDictionary dictionaryWithDictionary:r];
        for (id index in @[@(-1), @0.5, @99, @"1", NSNull.null]) {
            fallback[@"normalizedFaultingThread"]=index;
            Check([[[CAWorkbench evidence:fallback mode:@"fault"] firstObject] containsString:@"线程 #1"], @"invalid fault index falls back to triggered thread");
        }
        Check([CAWorkbench evidence:r mode:@"all"].count==4, @"all threads retain their frames");
        NSDictionary *bad=[NSDictionary dictionaryWithObjectsAndKeys:@[@{@"frames":@[]}], @"threads", @[], @"usedImages", nil];
        Check([CAWorkbench evidence:bad mode:@"fault"].count==1, @"malformed evidence safe");

        NSError *e=nil; NSData *ok=[NSJSONSerialization dataWithJSONObject:@{ @"choices": @[@{ @"message": @{ @"content": @"answer" } }] } options:0 error:nil];
        Check([[CAWorkbench responseText:ok status:200 error:&e] isEqual:@"answer"] && !e, @"normal response");
        for (NSData *data in @[[NSJSONSerialization dataWithJSONObject:@{ @"choices": @[] } options:0 error:nil], [NSJSONSerialization dataWithJSONObject:@{ @"choices": @[@42] } options:0 error:nil]]) {
            e=nil; Check(![CAWorkbench responseText:data status:200 error:&e] && e, @"empty or non-dictionary choice rejected");
        }
        e=nil; Check(![CAWorkbench responseText:ok status:500 error:&e] && e.code==500, @"non-2xx rejected");

        NSDictionary *p=[CAWorkbench payload:r source:nil model:@"model-A" prompt:@"prompt"];
        Check([p[@"model"] isEqual:@"model-A"] && [p[@"max_tokens"] integerValue]==2048 && [p[@"messages"] count]==2, @"payload identity and max tokens");
        NSDictionary *withSource=[CAWorkbench payload:r source:@"RAW SOURCE" model:@"model-A" prompt:@"prompt"];
        Check([withSource[@"messages"][1][@"content"] containsString:@"RAW SOURCE"] && [withSource[@"messages"][1][@"content"] containsString:@"normalizedBundleID"], @"source and report identity payload");
        NSString *k1=[CAWorkbench cacheKeyForBody:[NSJSONSerialization dataWithJSONObject:p options:0 error:nil] endpoint:@"https://one.example/v1/chat/completions"];
        NSString *k2=[CAWorkbench cacheKeyForBody:[NSJSONSerialization dataWithJSONObject:p options:0 error:nil] endpoint:@"https://two.example/v1/chat/completions"];
        Check(k1.length==64 && ![k1 isEqual:k2], @"endpoint-bound cache identity");

        NSString *dir=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]; NSString *path=[dir stringByAppendingPathComponent:@"history.json"];
        Check([CAWorkbench historyAtPath:path].count==0, @"missing history safe");
        Check([CAWorkbench saveAnswer:@"saved" key:k1 model:@"model-A" scope:@"structured" path:path], @"save history");
        Check([CAWorkbench historyAtPath:path].count==1 && [[CAWorkbench historyAtPath:path][0][@"answer"] isEqual:@"saved"], @"history persistence");
        Write(@[@{@"schema":@1,@"key":@"short",@"answer":@"bad",@"model":@"m",@"scope":@"structured",@"time":@"t"}], path);
        Check([CAWorkbench historyAtPath:path].count==0, @"corrupt history rejected");
        [@"{" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]; Check([CAWorkbench historyAtPath:path].count==0, @"invalid JSON history safe");

        NSString *exported=[CAWorkbench exportReport:r local:@{ @"result": @"local" } historical:nil history:@[]];
        Check([exported containsString:@"故障线程证据"] && [exported containsString:@"Demo"], @"export text");
        NSURL *u=[CAWorkbench writeExport:exported extension:@"md" error:&e]; Check(u && [[NSFileManager defaultManager] fileExistsAtPath:u.path], @"export file");
        [[NSFileManager defaultManager] removeItemAtPath:dir error:nil]; [[NSFileManager defaultManager] removeItemAtPath:u.path error:nil];
#if !__has_feature(objc_arc)
        // Production helper is intentionally also compiled and exercised under MRC.
#endif
        NSLog(@"Workbench regression tests passed (production CAWorkbench)");
    }
    return 0;
}
