#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface VGHearingStatus : NSObject
@property (nonatomic, assign) BOOL bidirectionalSupported;
@property (nonatomic, assign) NSUInteger pairedEar;
@property (nonatomic, assign) NSUInteger streamingEar;
@property (nonatomic, copy) NSArray<NSString *> *pairedUUIDs;
@property (nonatomic, copy) NSString *summary;
+ (instancetype)current;
- (BOOL)leftPaired;
- (BOOL)rightPaired;
- (BOOL)leftStreaming;
- (BOOL)rightStreaming;
- (BOOL)anyConnected;
@end

NS_ASSUME_NONNULL_END
