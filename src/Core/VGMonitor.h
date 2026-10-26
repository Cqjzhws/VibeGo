#import <Foundation/Foundation.h>
#import "VGHearingDevice.h"

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const VGStatusDidChangeNotification;

@interface VGMonitor : NSObject
@property (nonatomic, strong, readonly) VGHearingStatus *latest;
+ (instancetype)shared;
- (void)start;
- (void)refresh;
@end

NS_ASSUME_NONNULL_END
