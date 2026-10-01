#import <Foundation/Foundation.h>
// Foundation-only production helpers; usable under ARC and MRC.
@interface CAWorkbench : NSObject
+ (NSArray *)evidence:(NSDictionary *)report mode:(NSString *)mode;
+ (NSArray *)filterCases:(NSArray *)cases query:(NSString *)query status:(NSString *)status;
+ (NSString *)responseText:(NSData *)data status:(NSInteger)status error:(NSError **)error;
+ (NSDictionary *)payload:(NSDictionary *)report source:(NSString *)source model:(NSString *)model prompt:(NSString *)prompt;
+ (NSString *)cacheKeyForBody:(NSData *)body endpoint:(NSString *)endpoint;
+ (NSArray *)historyAtPath:(NSString *)path;
+ (BOOL)saveAnswer:(NSString *)answer key:(NSString *)key model:(NSString *)model scope:(NSString *)scope path:(NSString *)path;
+ (NSString *)exportReport:(NSDictionary *)report local:(NSDictionary *)local historical:(NSDictionary *)historical history:(NSArray *)history;
+ (NSURL *)writeExport:(NSString *)text extension:(NSString *)extension error:(NSError **)error;
@end
