#import "CAEvidenceController.h"
#import "CAWorkbenchController.h"
@implementation CAEvidenceController {
    NSArray *_rows; NSArray *_filtered; NSUInteger _page;
}
- (instancetype)initWithRows:(NSArray *)rows title:(NSString *)title { if((self=[super initWithStyle:UITableViewStylePlain])) { _rows=[rows copy]; _filtered=[rows copy]; self.title=title; } return self; }
- (void)viewDidLoad { [super viewDidLoad]; UISearchBar *s=[[UISearchBar alloc] initWithFrame:CGRectMake(0,0,320,56)]; s.placeholder=@"搜索线程 / 模块 / 符号 / 路径"; s.delegate=self; self.tableView.tableHeaderView=s; [s release]; self.tableView.rowHeight=UITableViewAutomaticDimension; self.tableView.estimatedRowHeight=100; self.navigationItem.rightBarButtonItem=[[[UIBarButtonItem alloc] initWithTitle:@"下一页" style:UIBarButtonItemStylePlain target:self action:@selector(nextPage)] autorelease]; self.navigationItem.leftItemsSupplementBackButton=YES; self.navigationItem.leftBarButtonItem=[[[UIBarButtonItem alloc] initWithTitle:@"上一页" style:UIBarButtonItemStylePlain target:self action:@selector(previousPage)] autorelease]; [self updatePage]; }
- (void)updatePage { self.navigationItem.prompt=[NSString stringWithFormat:@"%lu 项 · 第 %lu / %lu 页（每页 100 项）",(unsigned long)_filtered.count,(unsigned long)_page+1,(unsigned long)MAX(1,(_filtered.count+99)/100)]; [self.tableView reloadData]; }
- (void)nextPage { if ((_page+1)*100<_filtered.count) { _page++; [self updatePage]; } }
- (void)previousPage { if (_page) { _page--; [self updatePage]; } }
- (void)searchBar:(UISearchBar *)bar textDidChange:(NSString *)text { NSMutableArray *a=[NSMutableArray array]; for(NSString *r in _rows) if(!text.length || [r rangeOfString:text options:NSCaseInsensitiveSearch].location!=NSNotFound) [a addObject:r]; [_filtered release]; _filtered=[a copy]; _page=0; [self updatePage]; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)section { NSUInteger start=_page*100; return start<_filtered.count?MIN(100,_filtered.count-start):0; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p { UITableViewCell *c=[t dequeueReusableCellWithIdentifier:@"evidence"]; if(!c)c=[[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"evidence"] autorelease]; c.textLabel.numberOfLines=0; c.textLabel.lineBreakMode=NSLineBreakByWordWrapping; c.textLabel.font=[UIFont systemFontOfSize:15]; c.textLabel.text=_filtered[_page*100+p.row]; return c; }
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p { [t deselectRowAtIndexPath:p animated:YES]; CAPresentText(self,@"完整证据",_filtered[_page*100+p.row]); }
- (void)dealloc { [_rows release]; [_filtered release]; [super dealloc]; }
@end
