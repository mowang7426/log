#import <Foundation/Foundation.h>

@interface CALogStore : NSObject
+ (instancetype)sharedStore;
- (NSArray<NSDictionary *> *)reports;
- (NSDictionary *)reportAtPath:(NSString *)path;
- (NSArray<NSDictionary *> *)reportsForCategory:(NSString *)category;
- (NSDictionary *)scanDiagnostics;
- (NSString *)categoryForReport:(NSDictionary *)report;
- (NSString *)diagnosisForReport:(NSDictionary *)report;
@end
