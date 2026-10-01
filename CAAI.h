#import <Preferences/PSListController.h>
@class PSSpecifier;
@interface CAAIConfigController : PSListController
@end

@interface CAAIService : NSObject
+ (instancetype)shared;
- (void)analyzeReport:(NSDictionary *)report includeSource:(BOOL)includeSource completion:(void (^)(NSString *result, NSError *error))completion;
@end
