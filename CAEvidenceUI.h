#import <Preferences/PSTableCell.h>
#import <Preferences/PSSpecifier.h>
@interface CAEvidenceWrappingCell : PSTableCell
@end
FOUNDATION_EXPORT CGFloat CAEvidenceRowHeight(UITableView *table, PSSpecifier *specifier);
FOUNDATION_EXPORT void CAWrapEvidenceRow(PSSpecifier *specifier);
