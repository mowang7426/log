#import <Foundation/Foundation.h>
FOUNDATION_EXPORT NSDate *CAReportDate(NSDictionary *report, NSDate *fallback);
FOUNDATION_EXPORT BOOL CAReportMatches(NSDictionary *report, NSString *query);
FOUNDATION_EXPORT NSString *CAProcessName(NSDictionary *report);
FOUNDATION_EXPORT NSArray *CASpecialEvidence(NSDictionary *report);
