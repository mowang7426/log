#import <Preferences/PSListController.h>
@class PSSpecifier;
@interface CAAIConfigController : PSListController
@end
@interface CAAIModelPickerController : PSListController
@end

@interface CAAIService : NSObject <NSURLSessionTaskDelegate>
- (NSDictionary *)prepareReport:(NSDictionary *)report includeSource:(BOOL)includeSource error:(NSError **)error;
- (void)runPrepared:(NSDictionary *)prepared report:(NSDictionary *)report fresh:(BOOL)fresh completion:(void (^)(NSString *result, NSError *error))completion;
- (void)cancelAnalysis;
- (NSArray *)history;
- (NSArray *)historyForReport:(NSDictionary *)report;
+ (instancetype)shared;
- (void)testConnection:(void (^)(BOOL ok, NSString *message))completion;
- (void)fetchModels:(void (^)(NSArray *models, NSString *error))completion;
- (void)analyzeReport:(NSDictionary *)report includeSource:(BOOL)includeSource completion:(void (^)(NSString *result, NSError *error))completion;
- (BOOL)deleteHistoryEntry:(NSDictionary *)entry;
- (NSUInteger)deleteAllHistory;
- (NSUInteger)historyStorageBytes;
@end
