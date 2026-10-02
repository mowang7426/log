#import "CAConflictController.h"
#import <UIKit/UIKit.h>
#import "CALogStore.h"
#import "CAReportViewController.h"
#import "CAWorkbenchController.h"
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSTableCell.h>

@interface CAConflictWrappingCell : PSTableCell
@end
@implementation CAConflictWrappingCell
- (void)layoutSubviews {
    [super layoutSubviews];
    UILabel *label=self.titleLabel ?: self.textLabel;
    label.numberOfLines=0;
    label.lineBreakMode=NSLineBreakByWordWrapping;
    label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    label.adjustsFontForContentSizeCategory=YES;
    label.frame=CGRectMake(16,10,MAX(1,self.contentView.bounds.size.width-32),MAX(1,self.contentView.bounds.size.height-20));
}
@end

static PSSpecifier *CAConflictTextRow(NSString *text) {
    PSSpecifier *row=[PSSpecifier preferenceSpecifierNamed:text ?: @"" target:nil set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
    [row setProperty:[CAConflictWrappingCell class] forKey:@"cellClass"];
    return row;
}
static NSString *CAConflictValue(id value, NSString *fallback) {
    if ([value isKindOfClass:[NSString class]] && [value length]) return value;
    if ([value isKindOfClass:[NSNumber class]]) return [value stringValue];
    return fallback;
}
static NSString *CAImageName(NSDictionary *image) {
    NSString *name=CAConflictValue(image[@"name"], @"");
    NSString *path=CAConflictValue(image[@"path"], @"");
    if (name.length) return name.lastPathComponent;
    if (path.length) return path.lastPathComponent;
    return @"未知动态库";
}
static BOOL CAInjectedImage(NSDictionary *image) {
    NSString *path=[CAConflictValue(image[@"path"], @"") lowercaseString];
    return [path containsString:@"mobilesubstrate"] || [path containsString:@"tweakinject"] ||
        [path containsString:@"/var/jb/"] || [path containsString:@"/.jbroot/"] ||
        [path containsString:@"/usr/lib/substrate"];
}
static NSUInteger CAFaultingThreadIndex(NSDictionary *report, NSArray *threads) {
    id value=report[@"normalizedFaultingThread"] ?: report[@"faultingThread"];
    if ([value isKindOfClass:[NSNumber class]] && [value unsignedIntegerValue]<threads.count) return [value unsignedIntegerValue];
    for (NSUInteger i=0;i<threads.count;i++) if ([threads[i] isKindOfClass:[NSDictionary class]] && [threads[i][@"triggered"] boolValue]) return i;
    return NSNotFound;
}
static NSMutableDictionary *CAStats(NSArray *reports) {
    NSMutableDictionary *all=[NSMutableDictionary dictionary];
    for (NSDictionary *report in reports) {
        NSArray *images=[report[@"usedImages"] isKindOfClass:[NSArray class]] ? report[@"usedImages"] : @[];
        NSArray *threads=[report[@"threads"] isKindOfClass:[NSArray class]] ? report[@"threads"] : @[];
        NSMutableSet *faultingImages=[NSMutableSet set];
        NSUInteger thread=CAFaultingThreadIndex(report,threads);
        if (thread!=NSNotFound) {
            NSArray *frames=[threads[thread][@"frames"] isKindOfClass:[NSArray class]] ? threads[thread][@"frames"] : @[];
            for (NSDictionary *frame in frames) if ([frame isKindOfClass:[NSDictionary class]] && [frame[@"imageIndex"] isKindOfClass:[NSNumber class]]) [faultingImages addObject:frame[@"imageIndex"]];
        }
        NSMutableSet *seen=[NSMutableSet set];
        for (NSUInteger i=0;i<images.count;i++) {
            NSDictionary *image=[images[i] isKindOfClass:[NSDictionary class]] ? images[i] : @{};
            if (!CAInjectedImage(image)) continue;
            NSString *name=CAImageName(image); NSString *path=CAConflictValue(image[@"path"], @"");
            NSString *key=name;
            if (!key.length || [seen containsObject:key]) continue;
            [seen addObject:key];
            NSMutableDictionary *stats=all[key];
            if (!stats) {
                stats=[@{ @"name":name, @"main":@0, @"participation":@0, @"paths":[NSMutableArray array], @"reports":[NSMutableArray array] } mutableCopy];
                all[key]=stats; [stats release];
            }
            stats[@"participation"]=@([stats[@"participation"] unsignedIntegerValue]+1);
            if ([faultingImages containsObject:@(i)]) stats[@"main"]=@([stats[@"main"] unsignedIntegerValue]+1);
            NSMutableArray *paths=stats[@"paths"]; if (path.length && ![paths containsObject:path]) [paths addObject:path];
            NSMutableArray *associated=stats[@"reports"];
            NSString *reportPath=CAConflictValue(report[@"path"], @"");
            if (reportPath.length && ![associated containsObject:report]) [associated addObject:report];
        }
    }
    return all;
}
static NSString *CAEvidence(NSDictionary *stats) {
    NSUInteger main=[stats[@"main"] unsignedIntegerValue], participation=[stats[@"participation"] unsignedIntegerValue];
    if (main) return [NSString stringWithFormat:@"高：故障线程帧实际引用该动态库（%lu 次）",(unsigned long)main];
    if (participation) return @"中：动态库出现在相关日志，但未被故障线程帧引用";
    return @"未知：没有可用的故障线程帧引用或参与记录";
}
static NSString *CAReportLabel(NSDictionary *report) {
    NSString *file=CAConflictValue(report[@"fileName"], @"");
    NSString *process=CAConflictValue(report[@"normalizedProcessName"] ?: report[@"procName"] ?: report[@"app_name"], @"");
    NSString *time=CAConflictValue(report[@"timestamp"] ?: report[@"captureTime"], @"");
    NSMutableArray *parts=[NSMutableArray array]; if (file.length) [parts addObject:file]; if (process.length) [parts addObject:process]; if (time.length) [parts addObject:time];
    return parts.count ? [parts componentsJoinedByString:@" · "] : @"未知日志";
}

@implementation CAConflictDetailController
- (instancetype)initWithSpecifier:(PSSpecifier *)specifier { self=[super init]; if (self) self.specifier=specifier; return self; }
- (id)specifiers {
    if (!_specifiers) {
        NSDictionary *stats=[self.specifier propertyForKey:@"conflictStats"] ?: @{};
        NSString *name=CAConflictValue(stats[@"name"], @"未知动态库"); self.title=name;
        NSMutableArray *rows=[NSMutableArray array];
        PSSpecifier *overview=[PSSpecifier preferenceSpecifierNamed:@"插件概览" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [overview setProperty:@"仅展示扫描到的真实日志字段；未提供的数据不会被推断。" forKey:@"footerText"]; [rows addObject:overview];
        [rows addObject:CAConflictTextRow([NSString stringWithFormat:@"动态库：%@",name])];
        [rows addObject:CAConflictTextRow([NSString stringWithFormat:@"证据强度：%@",CAEvidence(stats)])];
        [rows addObject:CAConflictTextRow([NSString stringWithFormat:@"主嫌疑次数：%@（故障线程帧引用）",stats[@"main"] ?: @"未知"])];
        [rows addObject:CAConflictTextRow([NSString stringWithFormat:@"参与次数：%@（实际包含该动态库的日志）",stats[@"participation"] ?: @"未知"])];
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"实际注入路径" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        NSArray *paths=stats[@"paths"];
        if ([paths isKindOfClass:[NSArray class]] && paths.count) for (NSString *path in paths) [rows addObject:CAConflictTextRow(path)];
        else [rows addObject:CAConflictTextRow(@"未提供")];
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"相关日志" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        NSArray *reports=stats[@"reports"];
        if ([reports isKindOfClass:[NSArray class]] && reports.count) for (NSDictionary *report in reports) {
            PSSpecifier *item=[PSSpecifier preferenceSpecifierNamed:CAReportLabel(report) target:nil set:nil get:nil detail:[CAReportDetailController class] cell:PSLinkCell edit:nil];
            [item setProperty:report forKey:@"reportSnapshot"]; [item setProperty:CAConflictValue(report[@"path"], @"") forKey:@"reportPath"]; [item setProperty:report[@"category"] ?: @"其他" forKey:@"reportCategory"]; [rows addObject:item];
        } else [rows addObject:CAConflictTextRow(@"未提供")];
        [rows addObject:[PSSpecifier preferenceSpecifierNamed:@"不确定性说明" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]];
        [rows addObject:CAConflictTextRow(@"动态库出现在故障现场不等于已确认根因。证据强度只反映故障线程帧引用和日志参与情况；请通过禁用、恢复及复现对照进一步验证。")];
        _specifiers=[rows mutableCopy];
    }
    return _specifiers;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *specifier=[self specifierAtIndexPath:indexPath];
    if ([specifier propertyForKey:@"cellClass"] != [CAConflictWrappingCell class]) return [super tableView:tableView heightForRowAtIndexPath:indexPath];
    NSString *text=[specifier name] ?: @""; UIFont *font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody]; CGFloat width=MAX(1,tableView.bounds.size.width-72);
    CGRect box=[text boundingRectWithSize:CGSizeMake(width,CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading attributes:@{NSFontAttributeName:font} context:nil];
    return MAX(52,ceil(box.size.height)+28);
}
@end

@implementation CAConflictController
+ (NSArray *)summaryForReports:(NSArray *)reports limit:(NSUInteger)limit {
    NSMutableArray *items=[NSMutableArray arrayWithArray:[CAStats(reports) allValues]];
    [items sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { NSUInteger am=[a[@"main"] unsignedIntegerValue], bm=[b[@"main"] unsignedIntegerValue]; if (am!=bm) return am>bm?NSOrderedAscending:NSOrderedDescending; NSUInteger ap=[a[@"participation"] unsignedIntegerValue], bp=[b[@"participation"] unsignedIntegerValue]; if (ap!=bp) return ap>bp?NSOrderedAscending:NSOrderedDescending; return [a[@"name"] localizedStandardCompare:b[@"name"]]; }];
    if (limit && items.count>limit) [items removeObjectsInRange:NSMakeRange(limit,items.count-limit)];
    return items;
}
- (id)specifiers {
    if (!_specifiers) {
        self.title=@"疑似冲突插件"; NSMutableArray *rows=[NSMutableArray array];
        PSSpecifier *intro=[PSSpecifier preferenceSpecifierNamed:@"证据排序，不是根因定案" target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil]; [intro setProperty:@"高：故障线程帧实际引用；中：仅参与相关日志。点击插件查看真实路径及原始日志。" forKey:@"footerText"]; [rows addObject:intro];
        NSArray *items=[CAConflictController summaryForReports:[CALogStore.sharedStore reports] limit:0];
        for (NSDictionary *stats in items) {
            NSString *label=[NSString stringWithFormat:@"%@ · 主嫌疑 %@ 次 · 参与 %@ 次",CAConflictValue(stats[@"name"],@"未知动态库"),stats[@"main"] ?: @"未知",stats[@"participation"] ?: @"未知"];
            PSSpecifier *item=[PSSpecifier preferenceSpecifierNamed:label target:nil set:nil get:nil detail:[CAConflictDetailController class] cell:PSLinkCell edit:nil]; [item setProperty:stats forKey:@"conflictStats"]; [rows addObject:item];
        }
        if (!items.count) [rows addObject:CAConflictTextRow(@"暂未发现可排序的注入动态库")];
        _specifiers=[rows mutableCopy];
    }
    return _specifiers;
}
@end
