#import <UIKit/UIKit.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import "VGProbeDevice.h"

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const VGGattLogNotification;     // 新增一行日志
extern NSNotificationName const VGGattStateNotification;   // 运行状态变化
extern NSNotificationName const VGGattDevicesNotification; // 结构化设备档案更新

/// 只读 GATT 枚举器（安全红线）：
///  - 仅 discover 服务/特征；只读取「带 Read 属性」的特征（含厂商私有特征，均为只读取值）
///  - 绝不调用鉴权/握手；绝不写入任何特征；绝不订阅通知（不写 CCCD）
///  - 结果在本机留存基线快照，用于跨次比对「哪些特征发生了变化」（纯本地，不联网、不上传）
@interface VGGattProbe : NSObject <CBCentralManagerDelegate, CBPeripheralDelegate>
+ (instancetype)shared;
@property (nonatomic, readonly) BOOL running;
@property (nonatomic, readonly) NSString *stateText;
- (void)start;
- (NSArray<NSString *> *)lines;
- (NSArray<VGProbeDevice *> *)devices;
- (NSURL *)exportFile;
@end

NS_ASSUME_NONNULL_END
