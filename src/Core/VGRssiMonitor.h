#import <UIKit/UIKit.h>
#import <CoreBluetooth/CoreBluetooth.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const VGRssiDidChangeNotification;

@interface VGRssiReading : NSObject
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *localName;
@property (nonatomic, assign) NSInteger lastRSSI;
@property (nonatomic, assign) double avgRSSI;
@property (nonatomic, strong) NSDate *updatedAt;
@property (nonatomic, assign) NSUInteger samples;
@end

@interface VGRssiMonitor : NSObject <CBCentralManagerDelegate>
+ (instancetype)shared;
- (void)start;
- (NSArray<VGRssiReading *> *)readings;
/// 20 秒内仍在广播的 Vibe 设备数量（1 或 2 表示单耳/双耳在场）
- (NSUInteger)freshDeviceCount;
// 针对锌空电池低功率 BLE 校准：>= -85 优；-85~-95 正常；-95~-102 偏弱；< -102 弱
+ (NSString *)qualityLabel:(double)rssi;
+ (UIColor *)qualityColor:(double)rssi;
+ (NSInteger)signalBars:(double)rssi; // 1~4
@end

NS_ASSUME_NONNULL_END
