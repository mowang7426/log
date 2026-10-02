#import "CAConflictController.h"
#import <UIKit/UIKit.h>
#import "CALogStore.h"
#import "CAWorkbenchController.h"
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSListController.h>

static NSString *CAImageName(NSDictionary *im) {
    NSString *name=[im[@"name"] isKindOfClass:[NSString class]] ? im[@"name"] : @"";
    if (name.length) return name.lastPathComponent;
    NSString *path=[im[@"path"] isKindOfClass:[NSString class]] ? im[@"path"] : @"";
    return path.lastPathComponent.length ? path.lastPathComponent : @"未知动态库";
}
static BOOL CAInjectedImage(NSDictionary *im) {
    NSString *p=[im[@"path"] isKindOfClass:[NSString class]] ? [im[@"path"] lowercaseString] : @"";
    return [p containsString:@"mobilesubstrate"] || [p containsString:@"tweakinject"] || [p containsString:@"/dynam"] || [p containsString:@"/var/jb/"];
}
static NSMutableDictionary *CAStats(NSArray *reports) {
    NSMutableDictionary *all=[NSMutableDictionary dictionary];
    for (NSDictionary *r in reports) {
        NSArray *images=[r[@"usedImages"] isKindOfClass:[NSArray class]] ? r[@"usedImages"] : @[];
        NSMutableSet *fault=[NSMutableSet set];
        id ti=r[@"normalizedFaultingThread"] ?: r[@"faultingThread"];
        NSUInteger thread=([ti isKindOfClass:[NSNumber class]] ? [ti unsignedIntegerValue] : NSNotFound);
        NSArray *threads=[r[@"threads"] isKindOfClass:[NSArray class]] ? r[@"threads"] : @[];
        if (thread>=threads.count) {
            for (NSUInteger i=0;i<threads.count;i++) if ([threads[i][@"triggered"] boolValue]) { thread=i; break; }
        }
        if (thread<threads.count) for (NSDictionary *f in ([threads[thread][@"frames"] isKindOfClass:[NSArray class]] ? threads[thread][@"frames"] : @[])) if ([f[@"imageIndex"] isKindOfClass:[NSNumber class]]) [fault addObject:f[@"imageIndex"]];
        NSMutableSet *seen=[NSMutableSet set];
        for (NSUInteger i=0;i<images.count;i++) {
            NSDictionary *im=[images[i] isKindOfClass:[NSDictionary class]] ? images[i] : @{};
            if (!CAInjectedImage(im)) continue;
            NSString *name=CAImageName(im); if (!name.length || [seen containsObject:name]) continue; [seen addObject:name];
            NSMutableDictionary *s=all[name];
            if (!s) { s=[@{ @"name":name, @"main":@0, @"participation":@0, @"paths":[NSMutableArray array], @"reports":[NSMutableArray array] } mutableCopy]; all[name]=s; [s release]; }
            s[@"participation"]=@([s[@"participation"] unsignedIntegerValue]+1);
            if ([fault containsObject:@(i)]) s[@"main"]=@([s[@"main"] unsignedIntegerValue]+1);
            NSMutableArray *paths=s[@"paths"]; NSString *path=im[@"path"]; if ([path isKindOfClass:[NSString class]] && path.length && ![paths containsObject:path]) [paths addObject:path];
            NSMutableArray *rp=s[@"reports"]; NSString *reportPath=r[@"path"]; if ([reportPath isKindOfClass:[NSString class]] && reportPath.length && ![rp containsObject:reportPath]) [rp addObject:reportPath];
        }
    }
    return all;
}
static NSString *CAConflictText(NSDictionary *s) {
    return [NSString stringWithFormat:@"%@\n\n证据强度：%@\n主嫌疑次数：%@\n参与次数：%@\n\n注入路径：\n%@\n\n相关日志：\n%@\n\n说明：动态库出现在故障现场并不等于确定根因。建议结合禁用后是否停止复现进行验证。",s[@"name"],[s[@"main"] unsignedIntegerValue]?@"高（故障线程帧引用）":@"中（仅出现在相关日志）",s[@"main"],s[@"participation"],[s[@"paths"] componentsJoinedByString:@"\n"],[s[@"reports"] componentsJoinedByString:@"\n"]];
}

@implementation CAConflictDetailController
- (id)specifiers {
    if (!_specifiers) {
        NSDictionary *s=[self.specifier propertyForKey:@"conflictStats"];
        self.title=s[@"name"] ?: @"插件详情";
        NSMutableArray *rows=[NSMutableArray array];
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:s[@"name"] ?: @"未知动态库" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"证据强度：%@",[s[@"main"] unsignedIntegerValue]?@"高（故障线程帧引用）":@"中（仅出现在相关日志）"] target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"主嫌疑次数：%@",s[@"main"]] target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:[NSString stringWithFormat:@"参与次数：%@",s[@"participation"]] target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"注入路径" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        for (NSString *x in s[@"paths"]) [rows addObject:[PSSpecifier preferenceSpecifierNamed:x target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"相关日志" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        for (NSString *x in s[@"reports"]) [rows addObject:[PSSpecifier preferenceSpecifierNamed:x target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"注意：动态库出现在故障现场并不等于确定根因。建议结合禁用后是否停止复现进行验证。" target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
        _specifiers=[rows mutableCopy];
    } return _specifiers;
}
@end

@implementation CAConflictController
+ (NSArray *)summaryForReports:(NSArray *)reports limit:(NSUInteger)limit {
    NSMutableArray *a=[NSMutableArray arrayWithArray:[CAStats(reports) allValues]];
    [a sortUsingComparator:^NSComparisonResult(NSDictionary *x, NSDictionary *y) { NSUInteger xm=[x[@"main"] unsignedIntegerValue], ym=[y[@"main"] unsignedIntegerValue]; if(xm!=ym)return xm>ym?NSOrderedAscending:NSOrderedDescending; NSUInteger xp=[x[@"participation"] unsignedIntegerValue],yp=[y[@"participation"] unsignedIntegerValue]; return xp>yp?NSOrderedAscending:(xp<yp?NSOrderedDescending:NSOrderedSame); }];
    if (limit && a.count>limit) [a removeObjectsInRange:NSMakeRange(limit,a.count-limit)];
    return a;
}
- (id)specifiers {
    if (!_specifiers) {
        self.title=@"疑似冲突插件"; NSMutableArray *rows=[NSMutableArray array]; NSArray *reports=[CALogStore.sharedStore reports]; NSArray *items=[CAConflictController summaryForReports:reports limit:0];
        PSSpecifier *intro=[PSSpecifier preferenceSpecifierNamed:@"证据排序，不是根因定案" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]; [intro setProperty:@"高：出现在故障线程帧；中：仅参与相关日志。请结合禁用/恢复测试验证。" forKey:@"footerText"]; [rows addObject:intro];
        for (NSDictionary *s in items) { NSUInteger main=[s[@"main"] unsignedIntegerValue], part=[s[@"participation"] unsignedIntegerValue]; NSString *level=main?@"高嫌疑":@"中嫌疑"; NSString *label=[NSString stringWithFormat:@"%@ · %@ · 主嫌疑 %lu 次 · 参与 %lu 次",s[@"name"],level,(unsigned long)main,(unsigned long)part]; PSSpecifier *p=[PSSpecifier preferenceSpecifierNamed:label target:nil set:nil get:nil detail:[CAConflictDetailController class] cell:PSLinkCell edit:nil]; [p setProperty:s forKey:@"conflictStats"]; [rows addObject:p]; }
        if (!items.count) [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"暂未发现可排序的注入动态库" target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
        _specifiers=[rows mutableCopy];
    } return _specifiers;
}
- (void)open:(PSSpecifier *)p { NSDictionary *s=[p propertyForKey:@"conflictStats"]; CAPresentText(self,s[@"name"],CAConflictText(s)); }
@end
