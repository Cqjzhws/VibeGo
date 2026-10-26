#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>

NS_ASSUME_NONNULL_BEGIN

/// 设备信息/电池/私有特征的行为分类（含义推测，仅按 GATT 属性推断）
typedef NS_ENUM(NSInteger, VGCharCategory) {
    VGCharCategoryUnknown      = 0,
    VGCharCategoryDeviceInfo   = 1,  // SIG DIS：厂商/型号/序列号/版本
    VGCharCategoryBattery      = 2,  // 标准电量
    VGCharCategoryInfo         = 3,  // 只读信息类（推测）
    VGCharCategoryConfig       = 4,  // 可读写配置类（推测）
    VGCharCategoryStatus       = 5,  // 状态/事件（R/N，推测）
    VGCharCategoryCommand      = 6,  // 命令/写（W/WW，推测）
    VGCharCategoryAudioUp      = 7,  // 音频上行（N，推测）
    VGCharCategoryAudioDown    = 8,  // 音频下行（推测）
    VGCharCategoryVendorStream = 9,  // 厂商流通道 C8F7xxxx（推测）
};

/// Vibe Go 实测 GATT 协议档案：固化只读枚举日志中的真实 UUID，并提供友好名/分类。
/// 数据来自 vg_gatt_20261016_081043.log；私有特征含义为推测，改动协议前须抓包确认。
@interface VGGattProfile : NSObject

/// 任意 UUID（16-bit 短名或 128-bit 全名，大小写不敏感）-> 友好中文名
+ (NSString *)friendlyNameForUUID:(NSString *)uuid;

/// 分类
+ (VGCharCategory)categoryForUUID:(NSString *)uuid;

/// 分类中文名
+ (NSString *)categoryName:(VGCharCategory)category;

/// 已推断的语义提示（基于多份只读抓包的观察，纯假设，改动协议前须再抓包确认）。无推断返回 nil。
+ (NSString *)hintForUUID:(NSString *)uuid;

/// 6 个私有服务 UUID（探测时应重点记录）
+ (NSArray<CBUUID *> *)vendorServiceUUIDs;

/// 8 个厂商流通道特征（C8F7xxxx，订阅/写入可抓真实音频或事件流）
+ (NSArray<CBUUID *> *)vendorStreamCharacteristicUUIDs;

/// 已知特征总数（含 SIG 标准与私有）
+ (NSInteger)knownCharacteristicCount;

@end

NS_ASSUME_NONNULL_END
