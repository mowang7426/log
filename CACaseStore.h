#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString * const CAAutoSaveCases;
FOUNDATION_EXPORT NSString * const CAUseHistoricalCases;
FOUNDATION_EXPORT NSString * const CAOnlyValidatedCases;

// Retrieval of local AI references, never model training or guaranteed root causes.
@interface CACaseStore : NSObject
@property(nonatomic, copy) NSString *directory;
@property(nonatomic, retain) NSUserDefaults *defaults;
+ (instancetype)sharedStore;
+ (NSDictionary *)evidenceForReport:(NSDictionary *)report;
- (instancetype)initWithDirectory:(NSString *)directory;
- (BOOL)settingEnabled:(NSString *)key; // all three default to YES
- (NSArray *)allCases; // includes unverified and rejected references
- (NSDictionary *)summary; // total, unverified, validated, rejected
- (NSDictionary *)caseWithID:(NSString *)caseID;
- (NSDictionary *)matchingCaseForReport:(NSDictionary *)report;
- (BOOL)saveUnverifiedAnswer:(NSString *)answer forReport:(NSDictionary *)report;
- (BOOL)recordTestNote:(NSString *)note forCase:(NSDictionary *)entry;
- (BOOL)rejectCase:(NSDictionary *)entry;
- (BOOL)deleteCaseWithID:(NSString *)caseID;
@end
