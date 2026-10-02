#import "CAEvidenceUI.h"
@implementation CAEvidenceWrappingCell
- (void)layoutSubviews {
    [super layoutSubviews];
    UILabel *label = self.titleLabel ?: self.textLabel;
    label.numberOfLines = 0;
    label.lineBreakMode = NSLineBreakByCharWrapping;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = UIColor.labelColor;
    label.frame = CGRectMake(16, 10, MAX(1, self.contentView.bounds.size.width - 48),
                             MAX(1, self.contentView.bounds.size.height - 20));
}
@end
void CAWrapEvidenceRow(PSSpecifier *s) { [s setProperty:[CAEvidenceWrappingCell class] forKey:@"cellClass"]; }
CGFloat CAEvidenceRowHeight(UITableView *table, PSSpecifier *s) {
    NSMutableParagraphStyle *paragraph = [[[NSMutableParagraphStyle alloc] init] autorelease];
    paragraph.lineBreakMode = NSLineBreakByCharWrapping;
    CGRect box =
        [[s name] boundingRectWithSize:CGSizeMake(MAX(1, table.bounds.size.width - 80), CGFLOAT_MAX)
                               options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                            attributes:@{
                                NSFontAttributeName : [UIFont preferredFontForTextStyle:UIFontTextStyleBody],
                                NSParagraphStyleAttributeName : paragraph
                            }
                               context:nil];
    return MAX(52, ceil(box.size.height) + 28);
}
