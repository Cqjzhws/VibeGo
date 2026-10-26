#import <UIKit/UIKit.h>
#import <CoreBluetooth/CoreBluetooth.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const VGBatteryDidChangeNotification;

/// 单只助听器的只读信息（来自标准 GATT：电池 0x180F/2A19、设备信息 0x180A/*）
@interface VGBatteryDevice : NSObject
@property (nonatomic, copy) NSString *uuidString;
@property (nonatomic, copy) NSString *shortId;        // UUID 末 6 位
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) BOOL connected;
@property (nonatomic, strong, nullable) NSNumber *battery; // 0~100，nil=尚未读到
@property (nonatomic, strong, nullable) NSNumber *rssi;    // 连接态实测
@property (nonatomic, copy) NSString *currentProgram;     // 当前助听程序名（7BE94A55）
@property (nonatomic, copy) NSString *pairingIDA;         // 验配/配对标识之一（C97D21D3）
@property (nonatomic, copy) NSString *pairingIDB;         // 验配/配对标识之二（497EEB9E）
@property (nonatomic, copy) NSString *manufacturer;  // 2A29
@property (nonatomic, copy) NSString *model;         // 2A24
@property (nonatomic, copy) NSString *serial;        // 2A25
@property (nonatomic, copy) NSString *hardware;      // 2A27
@property (nonatomic, copy) NSString *firmware;      // 2A26
@property (nonatomic, copy) NSString *software;      // 2A28
@property (nonatomic, strong) NSDate *updatedAt;

// ---- 电池健康（0.8.0 新增）----
/// 电量历史：最近 48 次读数 @{@"level": @(0-100), @"time": NSDate}
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *batteryHistory;
/// 首次观测到的电量（用于估算衰减）
@property (nonatomic, strong, nullable) NSNumber *firstSeenBattery;
/// 电池健康度 0~100：基于首次满电到当前的衰减估算
- (NSInteger)batteryHealth;
/// 预计剩余使用分钟数（基于最近 10 分钟的放电速率）；数据不足返回 -1
- (NSInteger)estimatedMinutesRemaining;
/// 放电速率：百分比/小时（基于最近 30 分钟数据）；数据不足返回 0
- (double)drainRatePerHour;
@end

/// 持续在后台（App 生命周期内）扫描 company=661 的 Vibe Go，
/// 自动连接最多 2 只，只读标准电池/设备信息，60 秒轮询，断开自动重连。
/// 安全红线：不 setNotifyValue（不写 CCCD）、不写任何特征、不做鉴权。
@interface VGBatteryMonitor : NSObject
+ (instancetype)shared;
- (void)start;
/// 本次启动以来见过的设备（按 UUID 字符串排序，最多 2 只）
- (NSArray<VGBatteryDevice *> *)devices;
/// 当前助听程序名（由后台轮询读取，如 "Program Et -- Einstellung Eins"）；未读到返回 @""
- (NSString *)currentProgramName;
@end

NS_ASSUME_NONNULL_END
