#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const VGEarMapDidChangeNotification;

/// 持久化「设备 ↔ 左右耳」映射。
/// 系统 API（AXMFiHearingDevice*）只提供配对/出声状态，不给 UUID 与耳别的对应，
/// 因此由用户在 GATT 页对每只设备指定一次（设为左耳/右耳），本类负责持久存储，
/// 主页电量卡、RSSI 卡、GATT 档案卡全局复用。
///
/// 0.8.0 新增「自动耳别」：
///   Vibe Go 设备有 8D17AC2F 特征，值 01=右 00=左，连接后只读一次即可知道耳别。
///   VGBatteryMonitor 读到后调用 setAutoEar:forKey: 存入自动映射。
///   earLabelForKey: 优先返回自动耳别，找不到再回退到用户手动映射。
///
/// 存储：
///   NSUserDefaults 键 vg_ear_map       → 手动映射 { 完整UUID : @"L" / @"R" }
///   NSUserDefaults 键 vg_ear_auto_map  → 自动映射 { 完整UUID或尾巴 : @"L" / @"R" }
/// 查询：支持任意长度的 UUID 尾巴匹配（电量监视用完整 UUID，RSSI 用尾 8 位）。
@interface VGEarMap : NSObject

/// 按任意长度的 UUID（或其尾巴）查询耳别标签；自动优先，回退手动；未设定返回 @""。
+ (NSString *)earLabelForKey:(nullable NSString *)uuidOrTail;

/// 设定某完整 UUID 的耳别（earLabel 只接受 @"左耳" / @"右耳"）——手动映射。
+ (void)setEar:(NSString *)earLabel forFullUUID:(NSString *)fullUUID;

/// 清除某完整 UUID 的手动设定。
+ (void)clearForFullUUID:(NSString *)fullUUID;

/// 设备自报耳别（来自 8D17AC2F）——自动映射，优先级高于手动。
/// key 可为完整 UUID 或其尾巴；earLabel 接受 @"左耳"/@"右耳" 或 @"L"/@"R"。
+ (void)setAutoEar:(NSString *)earLabel forKey:(NSString *)key;

/// 清除某 key 的自动耳别。
+ (void)clearAutoEarForKey:(NSString *)key;

/// 已设定的手动映射快照 { 完整UUID : @"L"/@"R" }，仅供展示。
+ (NSDictionary<NSString *, NSString *> *)snapshot;

/// 已设定的自动映射快照，仅供展示。
+ (NSDictionary<NSString *, NSString *> *)autoSnapshot;

@end

NS_ASSUME_NONNULL_END
