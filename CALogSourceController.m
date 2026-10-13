#import "CAReportViewController.h"
#import <Preferences/PSSpecifier.h>
#import <sys/stat.h>
@implementation CAReportSourceController {
    UITextView *_text;
    UISearchBar *_find;
    UILabel *_status;
    NSString *_path;
    BOOL _complete;
    NSUInteger _findOffset;
}
@synthesize specifier=_specifier;
- (instancetype)initWithSpecifier:(PSSpecifier *)s { self=[super init]; if(self) self.specifier=s; return self; }
- (void)viewDidLoad {
    [super viewDidLoad]; _path=[[self.specifier propertyForKey:@"reportPath"] copy]; self.title=_path.lastPathComponent ?: @"原文";
    self.view.backgroundColor=UIColor.systemBackgroundColor;
    _find=[[UISearchBar alloc] init]; _find.placeholder=@"查找原文（搜索键跳到下一处）"; _find.delegate=self;
    _status=[[UILabel alloc] init]; _status.font=[UIFont preferredFontForTextStyle:UIFontTextStyleCaption1]; _status.numberOfLines=2; _status.text=@"正在后台读取（最多 4 MiB）…";
    _text=[[UITextView alloc] init]; _text.editable=NO; _text.selectable=YES; _text.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular]; _text.backgroundColor=UIColor.systemBackgroundColor;
    UIStackView *stack=[[[UIStackView alloc] initWithArrangedSubviews:@[_find,_status,_text]] autorelease]; stack.axis=UILayoutConstraintAxisVertical; stack.translatesAutoresizingMaskIntoConstraints=NO; [self.view addSubview:stack];
    UILayoutGuide *g=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:8],[stack.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-8],[stack.topAnchor constraintEqualToAnchor:g.topAnchor],[stack.bottomAnchor constraintEqualToAnchor:g.bottomAnchor]]];
    self.navigationItem.rightBarButtonItems=@[[[[UIBarButtonItem alloc] initWithTitle:@"分享" style:UIBarButtonItemStylePlain target:self action:@selector(share)] autorelease],[[[UIBarButtonItem alloc] initWithTitle:@"复制预览" style:UIBarButtonItemStylePlain target:self action:@selector(copyPreview)] autorelease]];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0),^{ @autoreleasepool {
        NSFileHandle *h=[NSFileHandle fileHandleForReadingAtPath:_path]; NSData *data=nil; NSString *error=nil; BOOL complete=NO;
        @try { if(h) { data=[h readDataOfLength:4*1024*1024+1]; complete=data.length<=4*1024*1024; if(!complete) data=[data subdataWithRange:NSMakeRange(0,4*1024*1024)]; } else error=@"读取失败：文件不存在或权限不足"; } @catch(NSException *e) { error=e.reason; } @finally { [h closeFile]; }
        NSString *body=data ? [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease] : nil;
        // A capped preview may end inside a UTF-8 scalar; remove only trailing bytes.
        if(!body && data && !complete) for(NSUInteger trim=1;trim<=3 && trim<data.length;trim++) { body=[[[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0,data.length-trim)] encoding:NSUTF8StringEncoding] autorelease]; if(body) break; }
        dispatch_async(dispatch_get_main_queue(),^{ _complete=complete && body!=nil; _text.text=body ?: @"无法解码 UTF-8 原文"; _status.text=error ?: (_complete?@"完整原文；可选择文字复制。原文可能含敏感信息。":@"仅前 4 MiB 预览或无法解码；分享为完整原文件。原文可能含敏感信息。"); });
    }});
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)s {
    [s resignFirstResponder]; NSString *q=s.text; NSString *body=_text.text; if(!q.length || !body.length) return;
    if(_findOffset>body.length) _findOffset=0;
    NSRange r=[body rangeOfString:q options:NSCaseInsensitiveSearch range:NSMakeRange(_findOffset,body.length-_findOffset)];
    if(r.location==NSNotFound) r=[body rangeOfString:q options:NSCaseInsensitiveSearch];
    if(r.location!=NSNotFound) { _text.selectedRange=r; [_text scrollRangeToVisible:r]; _findOffset=NSMaxRange(r); } else _status.text=@"当前预览中没有找到匹配；大文件只搜索已加载部分。";
}
- (void)searchBar:(UISearchBar *)s textDidChange:(NSString *)text { (void)s;(void)text; _findOffset=0; }
- (void)copyPreview { UIPasteboard.generalPasteboard.string=_text.text; _status.text=_complete?@"已复制完整原文（未脱敏）":@"已复制当前预览，不是完整文件（未脱敏）"; }
- (void)share {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"分享完整原文" message:@"原文件未经脱敏，可能包含路径、设备及应用标识。确认后后台复制完整文件。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"继续" style:UIAlertActionStyleDefault handler:^(id x){(void)x;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0),^{ @autoreleasepool {
            NSFileManager *fm=NSFileManager.defaultManager; NSString *dir=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
            [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL]; NSString *dst=[dir stringByAppendingPathComponent:_path.lastPathComponent ?: @"report.ips"]; NSError *error=nil; BOOL ok=[fm copyItemAtPath:_path toPath:dst error:&error];
            dispatch_async(dispatch_get_main_queue(),^{ if(!ok) { _status.text=error.localizedDescription ?: @"分享复制失败"; [fm removeItemAtPath:dir error:NULL]; return; }
                UIActivityViewController *v=[[[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:dst]] applicationActivities:nil] autorelease];
                v.completionWithItemsHandler=^(UIActivityType type,BOOL done,NSArray *items,NSError *e){(void)type;(void)done;(void)items;(void)e; [fm removeItemAtPath:dir error:NULL];};
                v.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItems.firstObject;
                [self presentViewController:v animated:YES completion:nil];
            });
        }});
    }]]; [self presentViewController:a animated:YES completion:nil];
}
- (void)dealloc { [_specifier release]; [_path release]; [_text release]; [_find release]; [_status release]; [super dealloc]; }
@end
