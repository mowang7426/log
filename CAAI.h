#import <Preferences/PSListController.h>
@class PSSpecifier;
@interface CAAIConfigController : PSListController
@end

@interface CAAIService : NSObject
+ (instancetype)shared;
- (void)testConnection:(void (^)(BOOL ok, NSString *message))completion;
- (void)fetchModels:(void (^)(NSArray *models, NSString *error))completion;
- (void)analyzeReport:(NSDictionary *)report includeSource:(BOOL)includeSource completion:(void (^)(NSString *result, NSError *error))completion;
@end
