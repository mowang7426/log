#import "CAReportViewController.h"
#import "CALogStore.h"
#import "CALogExperience.h"
#import <Preferences/PSSpecifier.h>

@implementation CAReportViewController {
    UISearchController *_search;
    NSArray *_groups;
    NSArray *_names;
    NSMutableSet *_selectedPaths;
    BOOL _grouped;
}
@synthesize specifier=_specifier;
- (instancetype)initWithSpecifier:(PSSpecifier *)s { self=[super initWithSpecifier:s]; if(self) self.specifier=s; return self; }
- (NSString *)reportCategory { return nil; }
- (void)viewDidLoad {
    [super viewDidLoad]; _grouped=YES; _selectedPaths=[NSMutableSet new];
    _search=[[UISearchController alloc] initWithSearchResultsController:nil]; _search.obscuresBackgroundDuringPresentation=NO; _search.searchResultsUpdater=self; _search.searchBar.placeholder=@"进程 / 包名 / 异常 / 文件";
    self.navigationItem.searchController=_search; self.definesPresentationContext=YES;
    self.tableView.allowsMultipleSelectionDuringEditing=YES;
    self.navigationItem.rightBarButtonItem=self.editButtonItem;
    self.navigationItem.leftItemsSupplementBackButton=YES;
    self.navigationItem.leftBarButtonItem=[[[UIBarButtonItem alloc] initWithTitle:@"分组" style:UIBarButtonItemStylePlain target:self action:@selector(toggleGroups)] autorelease];
    self.toolbarItems=@[[[[UIBarButtonItem alloc] initWithTitle:@"删除所选" style:UIBarButtonItemStylePlain target:self action:@selector(deleteSelected)] autorelease]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(scanUpdated:) name:CALogStoreDidRefreshNotification object:CALogStore.sharedStore];
    [self rebuild];
}
- (void)viewWillAppear:(BOOL)a { [super viewWillAppear:a]; [self.navigationController setToolbarHidden:!self.editing animated:a]; [CALogStore.sharedStore refreshReports]; }
- (void)viewWillDisappear:(BOOL)a { [super viewWillDisappear:a]; [self.navigationController setToolbarHidden:YES animated:a]; }
- (void)setEditing:(BOOL)e animated:(BOOL)a { [super setEditing:e animated:a]; if(!e) [_selectedPaths removeAllObjects]; [self.navigationController setToolbarHidden:!e animated:a]; [self.tableView reloadData]; }
- (void)toggleGroups { _grouped=!_grouped; self.navigationItem.leftBarButtonItem.title=_grouped?@"分组":@"时间"; [self rebuild]; }
- (void)updateSearchResultsForSearchController:(UISearchController *)c { (void)c; [self rebuild]; }
- (void)scanUpdated:(NSNotification *)n { (void)n; [self rebuild]; }
- (void)rebuild {
    NSArray *all=[self reportCategory].length ? [CALogStore.sharedStore reportsForCategory:[self reportCategory]] : CALogStore.sharedStore.reports;
    NSMutableDictionary *map=[NSMutableDictionary dictionary]; NSMutableArray *order=[NSMutableArray array]; NSUInteger count=0;
    for (NSDictionary *r in all) {
        if(!CAReportMatches(r,_search.searchBar.text)) continue;
        NSString *key=_grouped?CAProcessName(r):@"按时间倒序";
        if(!map[key]) { map[key]=[NSMutableArray array]; [order addObject:key]; }
        [map[key] addObject:r]; count++;
    }
    NSMutableArray *groups=[NSMutableArray array]; for(NSString *name in order) [groups addObject:map[name]];
    [_groups release]; _groups=[groups copy]; [_names release]; _names=[order copy];
    self.title=[NSString stringWithFormat:@"%@ · %lu",[self reportCategory] ?: @"日志",(unsigned long)count];
    self.tableView.backgroundView=nil;
    if(!count) { UILabel *empty=[[[UILabel alloc] init] autorelease]; empty.numberOfLines=0; empty.textAlignment=NSTextAlignmentCenter; NSDictionary *d=CALogStore.sharedStore.scanDiagnostics; empty.text=CALogStore.sharedStore.scanInProgress?@"正在后台扫描…":([d[@"error"] length]?d[@"error"]:(![d[@"exists"] boolValue]?@"日志目录不存在或不可访问":@"没有匹配的日志")); self.tableView.backgroundView=empty; }
    [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { (void)t; return _groups.count; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { (void)t; return [_groups[s] count]; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s { (void)t; return [NSString stringWithFormat:@"%@ · %lu 条",_names[s],(unsigned long)[_groups[s] count]]; }
- (NSDictionary *)report:(NSIndexPath *)i { return _groups[i.section][i.row]; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)i {
    UITableViewCell *c=[t dequeueReusableCellWithIdentifier:@"log"];
    if(!c) c=[[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"log"] autorelease];
    NSDictionary *r=[self report:i]; c.textLabel.text=r[@"fileName"]; c.textLabel.numberOfLines=2; c.detailTextLabel.numberOfLines=3;
    c.detailTextLabel.text=[NSString stringWithFormat:@"%@ · %@\n%@%@",r[@"category"],r[@"timestamp"] ?: [r[@"sortDate"] description] ?: @"时间未知",r[@"dateSource"] ?: @"",[r[@"parsePartial"] boolValue]?@" · 正文不完整":@""];
    c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    if(self.editing && [_selectedPaths containsObject:r[@"path"]]) [t selectRowAtIndexPath:i animated:NO scrollPosition:UITableViewScrollPositionNone];
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)i {
    NSDictionary *r=[self report:i]; if(self.editing) { [_selectedPaths addObject:r[@"path"]]; return; }
    [t deselectRowAtIndexPath:i animated:YES]; PSSpecifier *s=[PSSpecifier preferenceSpecifierNamed:r[@"fileName"] target:nil set:nil get:nil detail:nil cell:PSLinkCell edit:nil];
    [s setProperty:r forKey:@"reportSnapshot"]; [s setProperty:r[@"path"] forKey:@"reportPath"];
    CAReportDetailController *detail=[[[CAReportDetailController alloc] initWithSpecifier:s] autorelease]; [self.navigationController pushViewController:detail animated:YES];
}
- (void)tableView:(UITableView *)t didDeselectRowAtIndexPath:(NSIndexPath *)i { (void)t; if(self.editing) [_selectedPaths removeObject:[self report:i][@"path"]]; }
- (void)confirmPaths:(NSArray *)requested {
    // Snapshot path membership before presenting. Later arrivals never join it.
    NSSet *valid=[NSSet setWithArray:[CALogStore.sharedStore deletableReportPaths]];
    NSMutableArray *snapshot=[NSMutableArray array]; for(NSString *p in [NSSet setWithArray:requested]) if([valid containsObject:p]) [snapshot addObject:p];
    NSArray *paths=[[snapshot copy] autorelease]; NSUInteger count=paths.count;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"删除原始日志" message:[NSString stringWithFormat:@"确认删除 %lu 个普通日志文件？仅删除此时冻结的路径集合，新增日志不包含。AI 历史和案例保留。",(unsigned long)count] preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    if(count) [a addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x){ (void)x; NSUInteger deleted=[CALogStore.sharedStore deleteReportsAtPaths:paths]; [_selectedPaths minusSet:[NSSet setWithArray:paths]]; UIAlertController *result=[UIAlertController alertControllerWithTitle:@"删除结果" message:[NSString stringWithFormat:@"确认 %lu，已删除 %lu，未删除 %lu（文件变化或权限不足）。",(unsigned long)count,(unsigned long)deleted,(unsigned long)(count-deleted)] preferredStyle:UIAlertControllerStyleAlert]; [result addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:result animated:YES completion:nil]; }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)deleteSelected { [self confirmPaths:[_selectedPaths allObjects]]; }
- (UISwipeActionsConfiguration *)tableView:(UITableView *)t trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)i {
    (void)t; NSString *path=[self report:i][@"path"];
    UIContextualAction *action=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(UIContextualAction *a,UIView *v,void (^done)(BOOL)){ (void)a;(void)v; [self confirmPaths:@[path]]; done(YES); }];
    UISwipeActionsConfiguration *c=[UISwipeActionsConfiguration configurationWithActions:@[action]]; c.performsFirstActionWithFullSwipe=NO; return c;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; [_specifier release]; [_search release]; [_groups release]; [_names release]; [_selectedPaths release]; [super dealloc]; }
@end
