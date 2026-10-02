#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
@interface CAEvidenceWrappingCell : PSTableCell
@end
FOUNDATION_EXPORT CGFloat CAEvidenceRowHeight(UITableView *table, PSSpecifier *specifier);
FOUNDATION_EXPORT void CAWrapEvidenceRow(PSSpecifier *specifier);
