#import <Foundation/Foundation.h>
// Pure Foundation evidence model; no UIKit, no cause inference.
@interface CAPluginEvidence : NSObject
+ (NSArray *)summaryForReports:(NSArray *)reports limit:(NSUInteger)limit;
+ (NSString *)tierLabel:(NSString *)tier;
+ (NSArray *)validationStates;
+ (NSDictionary *)validationForPlugin:(NSString *)identity;
+ (BOOL)saveValidation:(NSDictionary *)record forPlugin:(NSString *)identity;
@end
