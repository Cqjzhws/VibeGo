#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 只读探测的「上次快照」存取与差异比对。
///
/// 用途：助听器的私有特征里有些是**会变的**（程序名、状态标志、计数器）。
/// 单次探测只能看到「当前值」，看不出它是否会动。本类把每次探测的结果存到
/// 本地 UserDefaults，下次探测时自动比对，把「哪些特征变了、从什么变成什么」
/// 直接列出来——这样用户只要在手机上操作一下（切程序/调音量/开关），
/// 再跑一次探测，就能定位到到底哪个特征对应该功能。
///
/// 安全边界：纯本地读写 + 纯字符串比对，不碰蓝牙、不写入设备任何特征。
@interface VGProbeSnapshot : NSObject

/// 生成设备存储键：优先序列号（换手机也认得同一只耳），否则用 UUID 末 6 位
+ (NSString *)deviceKeyWithSerial:(nullable NSString *)serial fallback:(nullable NSString *)fallback;

/// 取上次快照（shortUUID -> 展示串）；没有则返回空字典
+ (NSDictionary<NSString *, NSString *> *)loadForDeviceKey:(NSString *)key;

/// 存本次快照
+ (void)saveValues:(NSDictionary<NSString *, NSString *> *)values forDeviceKey:(NSString *)key;

/// 首次快照时间描述（如「今天 12:29」），无则 nil
+ (nullable NSString *)savedDateTextForDeviceKey:(NSString *)key;

/// 计算变化行，每行形如：
///   「当前程序名：Program Et -- Einstellung Eins → Universal」
+ (NSArray<NSString *> *)changesFromOld:(nullable NSDictionary<NSString *, NSString *> *)old
                                 toNew:(NSDictionary<NSString *, NSString *> *)now;

/// 清空全部快照（用户主动重置基线用）
+ (void)resetAll;

@end

NS_ASSUME_NONNULL_END
