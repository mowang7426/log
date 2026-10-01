#import <Foundation/Foundation.h>

// Local retrieval of AI references, never model training or verified root causes.
@interface CACaseStore : NSObject
@property(nonatomic, copy) NSString *directory;
+ (instancetype)sharedStore;
+ (NSDictionary *)evidenceForReport:(NSDictionary *)report; // nil means not matchable
- (instancetype)initWithDirectory:(NSString *)directory; // isolated production-code tests
- (NSArray *)allCases;
- (NSDictionary *)matchingCaseForReport:(NSDictionary *)report;
- (BOOL)saveUnverifiedAnswer:(NSString *)answer forReport:(NSDictionary *)report;
- (BOOL)recordTestNote:(NSString *)note forCase:(NSDictionary *)entry;
- (BOOL)rejectCase:(NSDictionary *)entry;
@end
