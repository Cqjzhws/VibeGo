#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 单次只读枚举得到的单只设备结构化档案（安全：仅来自 SIG 标准只读特征）
@interface VGProbeDevice : NSObject

@property (nonatomic, copy, nullable) NSString *peripheralID;   // 末尾 6 位
@property (nonatomic, copy, nullable) NSString *earKey;         // 完整 UUID（用于左右耳映射）
@property (nonatomic, copy, nullable) NSString *earLabel;       // @"左耳"/@"右耳"，未设定为空
@property (nonatomic, copy, nullable) NSString *advertisedName; // 广播名
@property (nonatomic, copy, nullable) NSString *manufacturer;
@property (nonatomic, copy, nullable) NSString *model;
@property (nonatomic, copy, nullable) NSString *serial;
@property (nonatomic, copy, nullable) NSString *hwRev;
@property (nonatomic, copy, nullable) NSString *fwRev;
@property (nonatomic, copy, nullable) NSString *swRev;
@property (nonatomic, copy, nullable) NSString *battery;        // 如 "100%"
@property (nonatomic, assign) NSInteger charCount;             // 发现特征数
/// 厂商信息/状态/配置等可读特征的解码结果：shortUUID -> 展示串（纯只读获取）
@property (nonatomic, strong, nullable) NSMutableDictionary<NSString *, NSString *> *rawValues;

/// 广播厂商数据（hex，用于连接前识别；也为侧别推断提供依据）
@property (nonatomic, copy, nullable) NSString *mfrHex;
/// 由广播厂商数据推断的耳别（@"左耳"/@"右耳"，依据不足则为 nil）
@property (nonatomic, copy, nullable) NSString *mfrEarHint;

/// 本次探测相对上次快照的变化（每行如「当前程序名：A → B」）；无基线则 nil
@property (nonatomic, strong, nullable) NSArray<NSString *> *changes;
/// 是否存在可用的上次基线快照
@property (nonatomic, assign) BOOL hasBaseline;
/// 上次快照的时间描述（如「10-16 12:29」）
@property (nonatomic, copy, nullable) NSString *baselineDateText;
/// 用于持久化比对的键（序列号优先）
@property (nonatomic, copy, nullable) NSString *snapshotKey;

/// 显示名，如「Vibe Go ·5631」（型号 + 序列号末 4 位）
- (NSString *)displayName;

/// 多行摘要，便于直接展示/分享
- (NSString *)summary;

/// 当前助听程序名（来自当前程序名特征，无则 nil）
- (nullable NSString *)currentProgramName;

/// 用户自定义耳别显示名（如「左耳 · 客厅」），无则 nil
- (nullable NSString *)earDisplayName;

/// 综合推断耳别：广播侧别字节 + 配对 ID + 侧别标志位 交叉验证；
/// 返回如「右耳（3 项依据一致：广播侧别字节 + 配对 ID + 侧别标志）」，无法推断则 nil
- (nullable NSString *)inferredEarText;

/// 配对标识（信息特征 2 的值，如 2FF351 / 2FCDA8），无则 nil
- (nullable NSString *)pairingID;

/// 与另一只耳朵的配对标识是否一致（用于判断是否配套）
- (BOOL)isPairedWith:(VGProbeDevice *)other;

/// 可持久化的「特征 → 值」快照（排除空值）
- (NSDictionary<NSString *, NSString *> *)snapshotValues;

@end

NS_ASSUME_NONNULL_END
