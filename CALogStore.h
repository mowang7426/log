#import <Foundation/Foundation.h>

@interface CALogStore : NSObject
+ (instancetype)sharedStore;
- (NSArray<NSDictionary *> *)reports;
- (NSDictionary *)reportAtPath:(NSString *)path;
- (NSArray<NSDictionary *> *)reportsForCategory:(NSString *)category;
- (NSDictionary *)scanDiagnostics;
- (NSString *)categoryForReport:(NSDictionary *)report;
// Stable SHA-256 incident signature (not a hash of the source file).
- (NSString *)fingerprintForReport:(NSDictionary *)report;
// JSON-compatible dictionary: facts, recommendations, summary, rootCause, confirmed.
- (NSDictionary *)localAnalysisForReport:(NSDictionary *)report;
// Returns nil on a cache miss, malformed data, or unavailable storage.
- (NSDictionary *)analysisCacheForFingerprint:(NSString *)fingerprint;
// Merges supplied fields with an existing entry; returns NO on validation/I/O failure.
// localDiagnosis is a localAnalysis dictionary; aiDiagnosis/rootCause are strings,
// confirmed is a boolean, recommendations is an array of strings, createdAt is UTC ISO-8601.
- (BOOL)saveAnalysisCache:(NSDictionary *)cache forFingerprint:(NSString *)fingerprint;
- (NSString *)diagnosisForReport:(NSDictionary *)report;
@end
