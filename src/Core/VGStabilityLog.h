//
//  VGStabilityLog.h — 连接稳定性记录（原工程里缺这个文件，按调用点补齐）
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface VGStabilityLog : NSObject

/// 事件列表，**新的在前**，每条是 @{@"ts": NSNumber(秒), @"state": @"connected"/@"disconnected", @"summary": NSString}
@property (nonatomic, strong, readonly) NSArray<NSDictionary *> *events;

+ (instancetype)shared;

- (void)recordConnected:(BOOL)connected ear:(NSUInteger)ear summary:(NSString *)summary;

/// 最近 24 小时的统计文本
- (NSString *)statisticsText;

/// 导出 CSV 到 Documents，返回文件 URL
- (NSURL *)exportFile;

@end

NS_ASSUME_NONNULL_END
