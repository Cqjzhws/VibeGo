#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const VGEarMapDidChangeNotification;

/// 持久化「设备 ↔ 左右耳」映射。
/// 系统 API（AXMFiHearingDevice*）只提供配对/出声状态，不给 UUID 与耳别的对应，
/// 因此由用户在 GATT 页对每只设备指定一次（设为左耳/右耳），本类负责持久存储，
/// 主页电量卡、RSSI 卡、GATT 档案卡全局复用。
/// 存储：NSUserDefaults 键 vg_ear_map，结构 { 完整UUID : @"L" / @"R" }。
/// 查询：支持任意长度的 UUID 尾巴匹配（电量监视用完整 UUID，RSSI 用尾 8 位）。
@interface VGEarMap : NSObject

/// 按任意长度的 UUID（或其尾巴）查询耳别标签；未设定返回 @""。
+ (NSString *)earLabelForKey:(nullable NSString *)uuidOrTail;

/// 设定某完整 UUID 的耳别（earLabel 只接受 @"左耳" / @"右耳"）。
+ (void)setEar:(NSString *)earLabel forFullUUID:(NSString *)fullUUID;

/// 清除某完整 UUID 的设定。
+ (void)clearForFullUUID:(NSString *)fullUUID;

/// 已设定的映射快照 { 完整UUID : @"L"/@"R" }，仅供展示。
+ (NSDictionary<NSString *, NSString *> *)snapshot;

@end

NS_ASSUME_NONNULL_END
