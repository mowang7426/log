#import <Foundation/Foundation.h>

@interface CALogStore : NSObject
+ (instancetype)sharedStore;
- (NSArray<NSDictionary *> *)reports;
- (NSArray<NSDictionary *> *)reportsForCategory:(NSString *)category;
- (NSString *)categoryForReport:(NSDictionary *)report;
- (NSString *)diagnosisForReport:(NSDictionary *)report;
@end
