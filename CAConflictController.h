#import <Foundation/Foundation.h>
#import <Preferences/PSListController.h>
@interface CAConflictController : PSListController
+ (NSArray *)summaryForReports:(NSArray *)reports limit:(NSUInteger)limit;
@end
