//
//  HearingLink.m — jetAudio 12.0.0 × Vibe Go：播放压低麦克风音量，暂停恢复
//
//  v3.2（2026-10-25 12:20）—— 回到「固定值 + 强制标志字节」的稳定路线
//  ---------------------------------------------------------------
//  v3.1 真机日志（HearingLink(1).log）暴露的三个问题：
//    · 两只耳「连接时读到的原值」不一致：一只 09 01，另一只 06 00 / 07 00；
//      第二字节是 00 的那只，恢复写入四次全部「没生效」→ 麦克风回不来
//    · 音量不是一步到位，设备自己逐档渐变（00→02→07→08→09），
//      所以「连接瞬间读到的值」经常只是渐变过程的瞬时值，不可靠
//    · markReady 被服务发现回调触发多次 → 一次播放连写 4~5 遍
//
//  v3.2 做法（依据日志 + v3 当时稳定这一事实）：
//    · 报文 = [档位][01]，第二字节必须 01（写 00 那耳从未生效过）
//    · 档位 0 = 最低；档位 9 ≈ iOS 滑块的 60（设备档位实测 0~10+）
//    · 播放写 00 01、暂停写 09 01，固定值，不再靠捕获
//    · 写后回读校验一次，3.5s 内没到目标档位就补写一次（设备是渐变的，要给它时间）
//    · 只有音量特征做校验，别的特征（F3F594F9 之类状态字节）不再盯，日志干净
//
//  播放状态：只 hook JAudioPlayer init 取实例 + 0.25s 轮询 isPlaying，
//  绝不 swizzle play/pause（那些方法走消息转发，换实现会 SIGABRT）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <MediaPlayer/MediaPlayer.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <unistd.h>

#import "gatt_config.h"

#pragma mark - 对外接口（独立 App 复用同一套 GATT 逻辑时用）

#ifdef HL_STANDALONE_APP
static BOOL gHLJAudioHook = NO;      // 独立 App 里没有 JAudioPlayer，别去 hook
#else
static BOOL gHLJAudioHook = YES;
#endif
static BOOL (^gHLPlayingProvider)(void) = nil;
static BOOL gHLCallMode = NO;        // 通话中：用另一套档位

void HLSetCallMode(BOOL on) { gHLCallMode = on; }


static void HLLog(NSString *fmt, ...);

static void (^gHLLogSink)(NSString *line) = nil;
void HLSetLogSink(void (^sink)(NSString *line)) { gHLLogSink = sink; }

void HLSetPlayingProvider(BOOL (^p)(void)) { gHLPlayingProvider = p; }
void HLSetJAudioHookEnabled(BOOL on)       { gHLJAudioHook = on; }

void HLExternalLog(NSString *fmt, ...) __attribute__((format(__NSString__, 1, 2)));
void HLExternalLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *m = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    HLLog(@"%@", m);
}

#pragma mark - 日志

static NSFileHandle *HL_logHandle = nil;

static void HLLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n",
                      [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                    dateStyle:NSDateFormatterNoStyle
                                                    timeStyle:NSDateFormatterMediumStyle],
                      msg];
    fprintf(stderr, "%s", line.UTF8String);
    if (gHLLogSink) { NSString *l = line; @try { gHLLogSink(l); } @catch (NSException *e) {} }
    @try {
        @synchronized (HL_logHandle) {
            if (!HL_logHandle) {
                NSString *path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)
                                  .firstObject stringByAppendingPathComponent:@"HearingLink.log"];
                if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
                    [@"" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
                }
                HL_logHandle = [NSFileHandle fileHandleForWritingAtPath:path];
                [HL_logHandle seekToEndOfFile];
            }
            [HL_logHandle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            if ([HL_logHandle offsetInFile] > 256 * 1024) {
                [HL_logHandle truncateFileAtOffset:0];
                [HL_logHandle seekToEndOfFile];
            }
        }
    } @catch (NSException *e) {}
}

// ---- 联动总开关 ----
// 关掉之后**一个字节都不往外写**，但 BLE 连接和特征读取照常。
// 用途：做参数对比（改设置 → 找差异）时，否则我们自己写 1454E9D6 会在差异里
// 反复出现，把真正的变化盖住——三次「平衡测试」都看到音量在跳，就是这个干扰。
static BOOL gHLAutomation = YES;
void HLSetAutomation(BOOL on) {
    gHLAutomation = on;
    HLLog(@"联动写入 = %@", on ? @"恢复" : @"已暂停（只探测不写）");
}
BOOL HLGetAutomation(void) { return gHLAutomation; }

#pragma mark - 配置

static id HLPrefAny(NSString *key, id fallback) {
    @try {
        NSString *path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject
                          stringByAppendingPathComponent:@"hearinglink.plist"];
        NSDictionary *fileCfg = [NSDictionary dictionaryWithContentsOfFile:path];
        if (fileCfg[key]) return fileCfg[key];
    } @catch (NSException *e) {}
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return v ?: fallback;
}

static BOOL       HLEnabled(void)      { return [HLPrefAny(@"HLEnabled", @YES) boolValue]; }
static BOOL       HLVerbose(void)      { return [HLPrefAny(@"HLVerbose", @NO) boolValue]; }
static double     HLRestoreDelay(void) { return [HLPrefAny(@"HLRestoreDelay", @(HL_DEFAULT_RESTORE_DELAY)) doubleValue]; }
static double     HLReapplyDelay(void) { return [HLPrefAny(@"HLReapplyDelay", @2.0) doubleValue]; }
static NSString  *HLMicCharUUID(void)  { return HLPrefAny(@"HLMicCharUUID", HL_DEFAULT_MIC_CHAR_UUID); }
static NSInteger  HLLevelMax(void)     { return MAX(1, [HLPrefAny(@"HLLevelMax", @(HL_LEVEL_MAX)) integerValue]); }

// 百分比 -> 设备档位（默认满量程 15：60% -> 9）
static NSInteger HLPercentToLevel(NSInteger pct) {
    if (pct < 0) pct = 0;
    if (pct > 100) pct = 100;
    NSInteger mx = HLLevelMax();
    NSInteger lv = (NSInteger)llround(pct / 100.0 * (double)mx);
    return MIN(MAX(lv, 0), mx);
}

// 恢复音量：绝对档位(HLRestoreLevel) 优先 -> 分耳百分比 -> 全局百分比 -> 内置默认
// 内置默认：左耳 60%，右耳 0（右耳麦克风不恢复）
static NSInteger HLRestoreLevelForEar(NSString *ear) {
    id abs = HLPrefAny(@"HLRestoreLevel", nil);
    if (abs) return [abs integerValue];

    NSInteger dflt = HL_DEFAULT_RESTORE_PERCENT_LEFT;
    id perEar = nil;
    if ([ear isEqualToString:@"左耳"]) {
        perEar = HLPrefAny(@"HLRestorePercentLeft", nil);
        dflt = HL_DEFAULT_RESTORE_PERCENT_LEFT;
    } else if ([ear isEqualToString:@"右耳"]) {
        perEar = HLPrefAny(@"HLRestorePercentRight", nil);
        dflt = HL_DEFAULT_RESTORE_PERCENT_RIGHT;
    }
    if (perEar) return HLPercentToLevel([perEar integerValue]);
    return HLPercentToLevel([HLPrefAny(@"HLRestorePercent", @(dflt)) integerValue]);
}

static BOOL       HLCallModeEnabled(void) { return [HLPrefAny(@"HLCallModeEnable", @(HL_DEFAULT_CALL_ENABLE)) boolValue]; }

static NSInteger HLMuteLevelForEar(NSString *ear) {
    id abs = HLPrefAny(@"HLMuteLevel", nil);
    if (abs) return [abs integerValue];      // 绝对档位优先，通话模式也让位

    if (gHLCallMode && HLCallModeEnabled()) {
        id per = nil;
        if ([ear isEqualToString:@"左耳"])      per = HLPrefAny(@"HLCallMutePercentLeft", nil);
        else if ([ear isEqualToString:@"右耳"]) per = HLPrefAny(@"HLCallMutePercentRight", nil);
        if (!per) per = HLPrefAny(@"HLCallMutePercent", nil);
        if (per) return HLPercentToLevel([per integerValue]);
        return HLPercentToLevel([ear isEqualToString:@"左耳"] ? HL_DEFAULT_CALL_LEFT : HL_DEFAULT_CALL_RIGHT);
    }
    return HLPercentToLevel([HLPrefAny(@"HLMutePercent", @0) integerValue]);
}

// ---- 右耳锁定 ----
static BOOL       HLLockEnabled(void)  { return [HLPrefAny(@"HLLockRightEar", @(HL_DEFAULT_LOCK_ENABLED)) boolValue]; }
static NSInteger  HLLockLevel(void)    { return [HLPrefAny(@"HLLockEarLevel", @(HL_DEFAULT_LOCK_LEVEL)) integerValue]; }
static double     HLLockInterval(void) {
    double d = [HLPrefAny(@"HLLockInterval", @(HL_DEFAULT_LOCK_INTERVAL)) doubleValue];
    return d < 1.0 ? 1.0 : d;          // 低于 1s 没意义，还会耗电
}
static BOOL       HLNotifyOn(void)     { return [HLPrefAny(@"HLNotify", @(HL_DEFAULT_NOTIFY)) boolValue]; }

// 播放中保持：iOS 音量键会抢写同一个音量特征，必须按住
static BOOL       HLHoldWhilePlaying(void) {
    return [HLPrefAny(@"HLHoldWhilePlaying", @(HL_DEFAULT_HOLD_WHILE_PLAYING)) boolValue];
}

// 哪些耳朵要被锁（HLLockEars，逗号分隔）
static BOOL HLEarIsLocked(NSString *ear) {
    if (!ear.length) return NO;
    NSString *list = HLPrefAny(@"HLLockEars", HL_DEFAULT_LOCK_EARS);
    if (![list isKindOfClass:[NSString class]] || !list.length) return NO;
    for (NSString *x in [list componentsSeparatedByString:@","]) {
        if ([x stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length &&
            [[x stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] isEqualToString:ear]) return YES;
    }
    return NO;
}

static NSInteger HLMicLevelByte(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"HLMicLevelByte"];
    return v ? [v integerValue] : HL_DEFAULT_LEVEL_BYTE;
}

#pragma mark - 小工具

static NSString *HLHex(NSData *d) {
    if (!d.length) return @"";
    const uint8_t *b = d.bytes;
    NSMutableString *s = [NSMutableString stringWithCapacity:d.length * 3];
    for (NSUInteger i = 0; i < d.length; i++) [s appendFormat:(i ? @" %02X" : @"%02X"), b[i]];
    return s;
}

static void HLAfter(NSTimeInterval sec, dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(sec * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), block);
}

static BOOL HLContainsUUID(NSArray *list, CBUUID *u) {
    for (NSString *s in list) {
        if ([u.UUIDString caseInsensitiveCompare:s] == NSOrderedSame) return YES;
    }
    return NO;
}

// "09 01" / "0901" -> NSData；非法返回 nil
static NSData *HLDataFromHex(NSString *hex) {
    if (![hex isKindOfClass:[NSString class]]) return nil;
    NSString *clean = [[hex uppercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
    clean = [clean stringByReplacingOccurrencesOfString:@"0x" withString:@""];
    clean = [clean stringByReplacingOccurrencesOfString:@"," withString:@""];
    if (clean.length == 0 || clean.length % 2) return nil;
    NSMutableData *d = [NSMutableData dataWithCapacity:clean.length / 2];
    for (NSUInteger i = 0; i < clean.length; i += 2) {
        unsigned int v = 0;
        NSString *byteStr = [clean substringWithRange:NSMakeRange(i, 2)];
        if (![[NSScanner scannerWithString:byteStr] scanHexInt:&v]) return nil;
        uint8_t b = (uint8_t)v;
        [d appendBytes:&b length:1];
    }
    return d;
}

// 统一成「短标识」：
//   标准 16-bit（00002A29-0000-1000-8000-00805F9B34FB）→ "2A29"
//   自定义 128-bit（1454E9D6-F658-4190-8589-22AA9E3021EB）→ "1454E9D6"
// 注解表和快照 key 都靠这个对齐，否则自定义 UUID 永远匹配不上。
static NSString *HLShortUUID(NSString *u) {
    if (!u.length) return @"";
    NSString *U = [[u uppercaseString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
    if (U.length == 32 && [U hasPrefix:@"0000"] && [U hasSuffix:@"00001000800000805F9B34FB"])
        return [U substringWithRange:NSMakeRange(4, 4)];
    if (U.length >= 8) return [U substringToIndex:8];
    return [u uppercaseString];
}

static CBCharacteristicWriteType HLWriteTypeFor(CBCharacteristic *c) {
    if (c.properties & CBCharacteristicPropertyWrite) return CBCharacteristicWriteWithResponse;
    return CBCharacteristicWriteWithoutResponse;
}

#pragma mark - 设备控制器

@protocol HLLinkDelegate <NSObject>
- (void)linkDidBecomeReady;
@end

@interface HLLink : NSObject <CBCentralManagerDelegate, CBPeripheralDelegate>
+ (instancetype)shared;
- (void)start;
- (BOOL)applyMute:(BOOL)mute;    // YES=已处理，NO=没条件（未连接 / 未认到特征）
- (void)enforceLock;             // 右耳锁定看门狗一拍
- (BOOL)holdActive;              // 播放/通话中是否在「按住档位」
- (NSString *)statusText;        // 「左耳✓ 右耳✗」
- (void)readAllChars;
- (void)runReadJobs:(NSArray *)jobs from:(NSUInteger)idx;
- (void)readDeviceInfoChars;
- (NSString *)valueForShort:(NSString *)shortUUID ear:(NSString *)ear;
- (BOOL)writeUUID:(NSString *)uuid hex:(NSString *)hex ear:(NSString *)ear;
- (NSDictionary *)deviceInfo;
- (NSArray<NSDictionary *> *)capabilityReport;
- (NSString *)micLiveText;
- (NSArray<CBPeripheral *> *)connectedPeripherals;  // ★ Bug #1: 暴露已连接外设给其他 Monitor 复用
@property (nonatomic, weak) id<HLLinkDelegate> delegate;
@end

@implementation HLLink {
    CBCentralManager *_cm;
    NSMutableArray<CBPeripheral *> *_periphs;
    NSMutableDictionary<NSString *, NSMutableArray *> *_chars;   // periphUUID -> [CBCharacteristic]
    NSMutableDictionary<NSString *, NSDictionary *> *_verify;    // key -> 校验任务
    NSMutableDictionary<NSString *, NSString *> *_ear;           // periphUUID -> 左耳/右耳
    NSMutableDictionary<NSString *, NSNumber *> *_lockAt;        // key -> 上次锁写时间（防死循环）
    NSMutableDictionary<NSString *, NSNumber *> *_retry;         // periphUUID -> 重连次数
    NSMutableDictionary<NSString *, NSData *> *_values;          // "periphUUID/shortUUID" -> 最近值
    NSMutableDictionary<NSString *, NSNumber *> *_earLock;        // periphUUID -> 侧别已由 8D17AC2F 确认

    NSTimeInterval _lastReadyAt;
    NSInteger _reapplyGen;
    BOOL _lastMute;
    BOOL _ready;
}

+ (instancetype)shared {
    static HLLink *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [HLLink new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _periphs = [NSMutableArray array];
        _chars = [NSMutableDictionary dictionary];
        _verify = [NSMutableDictionary dictionary];
        _ear = [NSMutableDictionary dictionary];
        _lockAt = [NSMutableDictionary dictionary];
        _retry = [NSMutableDictionary dictionary];
        _values = [NSMutableDictionary dictionary];
        _earLock = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark 启动 / 连接

- (void)start {
    if (!HLEnabled()) { HLLog(@"已禁用（HLEnabled=false）"); return; }
    HLAfter(2.0, ^{ [self startCentralWithRetry:0]; });
    HLLog(@"v3.5.2 启动：特征=%@ 档位=第 %ld 字节 | 播放→%ld档 | 暂停→左耳%ld档 / 右耳%ld档（满量程 %ld）",
          HLMicCharUUID(), (long)HLMicLevelByte() + 1,
          (long)HLMuteLevelForEar(nil),
          (long)HLRestoreLevelForEar(@"左耳"), (long)HLRestoreLevelForEar(@"右耳"),
          (long)HLLevelMax());
    HLLog(@"通话模式=%@（左%ld%% / 右%ld%%）",
          HLCallModeEnabled() ? @"开" : @"关",
          (long)[HLPrefAny(@"HLCallMutePercentLeft", @(HL_DEFAULT_CALL_LEFT)) integerValue],
          (long)[HLPrefAny(@"HLCallMutePercentRight", @(HL_DEFAULT_CALL_RIGHT)) integerValue]);
    HLLog(@"锁定右耳=%@ 目标档位=%ld 每 %.1fs 检查一次 | 通知订阅=%@",
          HLLockEnabled() ? @"开" : @"关", (long)HLLockLevel(), HLLockInterval(),
          HLNotifyOn() ? @"开" : @"关");
}

- (void)startCentralWithRetry:(NSInteger)try {
    if (_cm.state == CBManagerStatePoweredOn) return;
    if (try > 0) { _cm = nil; [_periphs removeAllObjects]; [_chars removeAllObjects]; }
    _cm = [[CBCentralManager alloc] initWithDelegate:self
                                               queue:dispatch_get_main_queue()
                                             options:@{CBCentralManagerOptionShowPowerAlertKey: @NO}];
    if (try >= 3) return;
    HLAfter(3.0, ^{
        if (self->_cm.state == CBManagerStateUnknown) [self startCentralWithRetry:try + 1];
    });
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    HLLog(@"CB state = %ld", (long)central.state);
    if (central.state == CBManagerStatePoweredOn) {
        [self reconnectKnown];
        [self scan];
    } else if (central.state == CBManagerStatePoweredOff) {
        [_periphs removeAllObjects];
        [_chars removeAllObjects];
    }
}

- (void)reconnectKnown {
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:@"HLSavedPeriphs"];
    if (!saved.count) return;
    NSMutableArray *ids = [NSMutableArray array];
    for (NSString *s in saved) {
        NSUUID *u = [[NSUUID alloc] initWithUUIDString:s];
        if (u) [ids addObject:u];
    }
    for (CBPeripheral *p in [_cm retrievePeripheralsWithIdentifiers:ids]) {
        [self attachPeripheral:p];
        // retrieve 回来的外设如果系统层面已经是 connected，connectPeripheral 不会再回调 didConnect，
        // 这时直接重新发现服务，把它拉回工作状态
        if (p.state == CBPeripheralStateConnected) {
            p.delegate = self;
            [p discoverServices:nil];
        }
    }
    HLLog(@"已知外设召回 %lu 个", (unsigned long)ids.count);
}

// 断线重连：每次失败往后推（3s → 5s → 7s …最长 12s）
- (void)scheduleReconnect:(CBPeripheral *)p {
    NSInteger n = [_retry[p.identifier.UUIDString] integerValue];
    double delay = MIN(3.0 + n * 2.0, 12.0);
    _retry[p.identifier.UUIDString] = @(n + 1);
    HLAfter(delay, ^{
        if (p.state == CBPeripheralStateConnected) { [p discoverServices:nil]; return; }
        HLLog(@"重连 %@（第 %ld 次）", [self earName:p], (long)(n + 1));
        [self->_cm connectPeripheral:p
                             options:@{CBConnectPeripheralOptionNotifyOnDisconnectionKey: @YES}];
    });
    // 兜底：如果一直连不上，扫一轮广播重新发现（scan 里会走 attachPeripheral）
    HLAfter(delay + 6.0, ^{
        if (p.state == CBPeripheralStateConnected) return;
        if (self->_periphs.count < HL_MAX_PERIPHERALS) [self scan];
    });
}

- (void)scan {
    NSMutableArray *cb = [NSMutableArray array];
    for (NSString *s in HL_VENDOR_SERVICE_UUIDS) [cb addObject:[CBUUID UUIDWithString:s]];
    [_cm scanForPeripheralsWithServices:cb options:@{CBCentralManagerScanOptionAllowDuplicatesKey: @NO}];
    HLAfter(8.0, ^{
        if (self->_periphs.count >= HL_MAX_PERIPHERALS) { [self->_cm stopScan]; return; }
        [self->_cm stopScan];
        [self->_cm scanForPeripheralsWithServices:nil options:nil];
        HLAfter(8.0, ^{ [self->_cm stopScan]; });
    });
}

- (BOOL)looksLikeHearingAid:(CBPeripheral *)p adv:(NSDictionary *)adv {
    NSMutableString *hay = [NSMutableString string];
    if (p.name.length) [hay appendString:p.name];
    id ln = adv[CBAdvertisementDataLocalNameKey];
    if ([ln isKindOfClass:[NSString class]]) [hay appendString:ln];
    NSString *lower = hay.lowercaseString;
    for (NSString *k in HL_DEVICE_NAME_KEYS) {
        if (lower.length && [lower containsString:k.lowercaseString]) return YES;
    }
    for (CBUUID *u in adv[CBAdvertisementDataServiceUUIDsKey]) {
        if (HLContainsUUID(HL_VENDOR_SERVICE_UUIDS, u)) return YES;
    }
    return NO;
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral
     advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI {
    if (_periphs.count >= HL_MAX_PERIPHERALS) return;
    for (CBPeripheral *p in _periphs) if ([p.identifier isEqual:peripheral.identifier]) return;
    if (![self looksLikeHearingAid:peripheral adv:advertisementData]) return;
    HLLog(@"发现 %@ (%@)", peripheral.name ?: @"?", peripheral.identifier.UUIDString);
    [self attachPeripheral:peripheral];

    // ★ Bug #1: 广播转发——让 VGRssiMonitor 复用 HLLink 的 scan 结果，避免自己开 scan 争用
    [[NSNotificationCenter defaultCenter] postNotificationName:@"HLLinkDidDiscover"
                                                        object:nil
                                                      userInfo:@{
        @"peripheral": peripheral,
        @"advertisementData": advertisementData ?: @{},
        @"RSSI": RSSI ?: @0
    }];
}

- (void)attachPeripheral:(CBPeripheral *)p {
    for (CBPeripheral *x in _periphs) if ([x.identifier isEqual:p.identifier]) return;
    p.delegate = self;
    [_periphs addObject:p];
    NSArray *old = [[NSUserDefaults standardUserDefaults] arrayForKey:@"HLSavedPeriphs"] ?: @[];
    NSMutableArray *saved = [NSMutableArray arrayWithArray:old];
    if (![saved containsObject:p.identifier.UUIDString]) [saved addObject:p.identifier.UUIDString];
    while (saved.count > HL_MAX_PERIPHERALS) [saved removeObjectAtIndex:0];
    [[NSUserDefaults standardUserDefaults] setObject:saved forKey:@"HLSavedPeriphs"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [_cm connectPeripheral:p options:@{CBConnectPeripheralOptionNotifyOnDisconnectionKey: @YES}];
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    HLLog(@"已连接 %@", [self earName:peripheral]);
    _retry[peripheral.identifier.UUIDString] = @0;
    [peripheral discoverServices:nil];
    HLAfter(6.0, ^{ [self markReady]; });
}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    HLLog(@"连接失败 %@: %@", [self earName:peripheral], error.localizedDescription);
    // 摘掉再排重连，否则 attachPeripheral 的去重会让它再也连不上
    [_periphs removeObject:peripheral];
    [self scheduleReconnect:peripheral];
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    HLLog(@"断开 %@ %@，稍后自动重连", [self earName:peripheral], error ? error.localizedDescription : @"");
    [_chars removeObjectForKey:peripheral.identifier.UUIDString];
    [_earLock removeObjectForKey:peripheral.identifier.UUIDString];
    _ready = NO;

    // ★ v3.5 关键修复：必须把它从 _periphs 摘掉。
    // v3.4 只清了 _chars，peripheral 还留在 _periphs 里，于是 3s 后 reconnectKnown →
    // attachPeripheral 的「已在列表就 return」去重判断直接返回，connectPeripheral 永远不再调用。
    // 日志表现就是「已知外设召回 2 个」之后再没有任何「已连接」，直到 App 重启才恢复。
    [_periphs removeObject:peripheral];
    [self scheduleReconnect:peripheral];
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
    if (error) { HLLog(@"发现服务失败: %@", error.localizedDescription); return; }
    for (CBService *s in peripheral.services) [peripheral discoverCharacteristics:nil forService:s];
}

- (BOOL)allCharacteristicsDiscovered {
    for (CBPeripheral *p in _periphs) {
        if (p.state != CBPeripheralStateConnected) continue;
        for (CBService *s in p.services) if (!s.characteristics) return NO;
    }
    return _chars.count > 0;
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    if (error) { HLLog(@"发现特征失败 %@: %@", service.UUID.UUIDString, error.localizedDescription); return; }
    NSString *key = peripheral.identifier.UUIDString;
    NSMutableArray *list = _chars[key];
    if (!list) { list = [NSMutableArray array]; _chars[key] = list; }
    for (CBCharacteristic *c in service.characteristics) {
        if (![list containsObject:c]) [list addObject:c];
        // 顺便读一下配对 ID / 侧别标志，日志里就能直接写「左耳 / 右耳」
        if (([c.UUID.UUIDString caseInsensitiveCompare:HL_EAR_ID_CHAR_UUID] == NSOrderedSame ||
             [c.UUID.UUIDString caseInsensitiveCompare:HL_EAR_FLAG_CHAR_UUID] == NSOrderedSame) &&
            (c.properties & CBCharacteristicPropertyRead)) {
            [peripheral readValueForCharacteristic:c];
        }
        // 麦克风特征支持 Notify：订阅之后设备自己改动（或被 iOS 改回）能立刻收到，比 3s 轮询快
        if (HLNotifyOn() && HLMicCharUUID().length &&
            [c.UUID.UUIDString caseInsensitiveCompare:HLMicCharUUID()] == NSOrderedSame &&
            (c.properties & CBCharacteristicPropertyNotify) && !c.isNotifying) {
            [peripheral setNotifyValue:YES forCharacteristic:c];
            HLLog(@"订阅 %@ 音量通知", [self earName:peripheral]);
        }
    }
    if (![self allCharacteristicsDiscovered]) return;
    [self markReady];
}

- (void)markReady {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    BOOL first = !_ready;
    _ready = YES;
    if (first) {
        NSUInteger total = 0;
        for (NSString *k in _chars) total += [_chars[k] count];
        HLLog(@"就绪：%lu 只耳 / %lu 个特征", (unsigned long)_chars.count, (unsigned long)total);
        [self readDeviceInfoChars];      // 型号/序列号/固件/程序名/电量，装好就能显示
    }
    // 服务发现回调会来好几次，5s 内不重复对齐（v3.1 一次播放被写 4 遍就是这个原因）
    if (!first && (now - _lastReadyAt) < 5.0) return;
    _lastReadyAt = now;
    if ([self.delegate respondsToSelector:@selector(linkDidBecomeReady)]) {
        [self.delegate linkDidBecomeReady];
    }
}

- (NSString *)statusText {
    if (!_periphs.count) return @"未连接";
    NSMutableArray *a = [NSMutableArray array];
    for (CBPeripheral *p in _periphs) {
        NSString *ear = [self earName:p];
        BOOL ok = (p.state == CBPeripheralStateConnected);
        [a addObject:[NSString stringWithFormat:@"%@%@", ear, ok ? @"✓" : @"✗"]];
    }
    return [a componentsJoinedByString:@"  "];
}

NSString *HLStatusText(void) { return [[HLLink shared] statusText]; }

// ---- 深度探测：能力矩阵 ----

- (NSString *)propsTextFor:(CBCharacteristicProperties)p {
    NSMutableArray *a = [NSMutableArray array];
    if (p & CBCharacteristicPropertyRead)                  [a addObject:@"R"];
    if (p & CBCharacteristicPropertyWrite)                 [a addObject:@"W"];
    if (p & CBCharacteristicPropertyWriteWithoutResponse)  [a addObject:@"WW"];
    if (p & CBCharacteristicPropertyNotify)                [a addObject:@"N"];
    if (p & CBCharacteristicPropertyIndicate)              [a addObject:@"I"];
    if (p & CBCharacteristicPropertyBroadcast)             [a addObject:@"B"];
    return a.count ? [a componentsJoinedByString:@"/"] : @"-";
}

// 所有可读特征读一遍（只读，不写不订阅）
// ⚠️ 必须分批：两耳加起来 90+ 个可读特征，一次性全发会让设备 GATT 队列溢出，
//    表现就是「连接超时断开」，然后整份快照变空 —— 0.6.0 的对比就是这么翻车的。
- (void)readAllChars {
    NSMutableArray *jobs = [NSMutableArray array];
    for (CBPeripheral *p in _periphs) {
        if (p.state != CBPeripheralStateConnected) continue;
        for (CBCharacteristic *c in _chars[p.identifier.UUIDString]) {
            if (c.properties & CBCharacteristicPropertyRead) [jobs addObject:@[p, c]];
        }
    }
    if (jobs.count) HLLog(@"全量读取：%lu 个特征，分 %lu 批",
                          (unsigned long)jobs.count, (unsigned long)((jobs.count + 5) / 6));
    [self runReadJobs:jobs from:0];
}

- (void)runReadJobs:(NSArray *)jobs from:(NSUInteger)idx {
    NSUInteger batch = 0;
    while (idx < jobs.count && batch < 6) {
        CBPeripheral *p = jobs[idx][0];
        CBCharacteristic *c = jobs[idx][1];
        if (p.state == CBPeripheralStateConnected) [p readValueForCharacteristic:c];
        idx++; batch++;
    }
    if (idx >= jobs.count) return;
    __weak typeof(self) ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.06 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [ws runReadJobs:jobs from:idx]; });
}

// 读一次设备信息类特征（标准 Device Info 服务 + 程序名）
- (void)readDeviceInfoChars {
    NSArray *wanted = @[@"2A29", @"2A24", @"2A25", @"2A26", @"2A27", @"2A28", @"2A19",
                        @"7BE94A55", @"8D17AC2F"];
    for (CBPeripheral *p in _periphs) {
        if (p.state != CBPeripheralStateConnected) continue;
        for (CBCharacteristic *c in _chars[p.identifier.UUIDString]) {
            NSString *sid = HLShortUUID(c.UUID.UUIDString);
            if ([wanted containsObject:sid] && (c.properties & CBCharacteristicPropertyRead)) {
                [p readValueForCharacteristic:c];
            }
        }
    }
}

// 在缓存里按短 UUID 找某只耳最近一次读到的值（十六进制串）
- (NSString *)valueForShort:(NSString *)shortUUID ear:(NSString *)ear {
    NSString *want = [shortUUID uppercaseString];
    for (CBPeripheral *p in _periphs) {
        if (ear.length && ![[self earName:p] isEqualToString:ear]) continue;
        NSString *periph = p.identifier.UUIDString;
        for (CBCharacteristic *c in _chars[periph]) {
            if (![HLShortUUID(c.UUID.UUIDString) isEqualToString:want]) continue;
            NSData *v = _values[[NSString stringWithFormat:@"%@/%@", periph, c.UUID.UUIDString]];
            return v ? HLHex(v) : @"";
        }
    }
    return @"";
}

// 对任意可写特征写一段十六进制（实验台用）。ear 为空表示两耳都写。
- (BOOL)writeUUID:(NSString *)uuid hex:(NSString *)hex ear:(NSString *)ear {
    CBUUID *want = [CBUUID UUIDWithString:uuid];
    NSData *payload = HLDataFromHex(hex);
    if (!want || !payload.length) return NO;

    BOOL wrote = NO;
    for (CBPeripheral *p in _periphs) {
        if (p.state != CBPeripheralStateConnected) continue;
        NSString *en = [self earName:p];
        if (ear.length && ![en isEqualToString:ear]) continue;
        for (CBCharacteristic *c in _chars[p.identifier.UUIDString]) {
            if (![c.UUID isEqual:want]) continue;
            if (!(c.properties & CBCharacteristicPropertyWrite) &&
                !(c.properties & CBCharacteristicPropertyWriteWithoutResponse)) continue;

            NSString *before = [self valueForShort:HLShortUUID(c.UUID.UUIDString) ear:en];
            [p writeValue:payload forCharacteristic:c type:HLWriteTypeFor(c)];
            HLLog(@"🧪 实验写入 %@ %@ : %@ → %@",
                  en, HLShortUUID(c.UUID.UUIDString),
                  before.length ? before : @"(无)", HLHex(payload));
            wrote = YES;

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (c.properties & CBCharacteristicPropertyRead) [p readValueForCharacteristic:c];
            });
            break;
        }
    }
    if (!wrote) HLLog(@"🧪 写入失败：没有匹配的可写特征（%@ / %@）", ear.length ? ear : @"双耳", uuid);
    return wrote;
}

// 打包成便于界面展示的有序数组
- (NSDictionary *)deviceInfo {
    // 优先左耳；两耳序列号其实不同（实测左 JFA5631 / 右 JFA7311），所以不能随便取第一只
    NSString *ear = @"";
    for (CBPeripheral *p in _periphs) {
        if ([[self earName:p] isEqualToString:@"左耳"]) { ear = @"左耳"; break; }
    }
    NSString *prog = [self valueForShort:@"7BE94A55" ear:ear];
    NSString *progText = @"";
    if (prog.length) {
        NSData *d = HLDataFromHex(prog);
        NSString *ascii = d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : nil;
        progText = ascii.length ? ascii : prog;
    }
    return @{
        @"制造商":  [self valueForShort:@"2A29" ear:ear] ?: @"",
        @"型号":    [self valueForShort:@"2A24" ear:ear] ?: @"",
        @"序列号":  [self valueForShort:@"2A25" ear:ear] ?: @"",
        @"硬件":    [self valueForShort:@"2A27" ear:ear] ?: @"",
        @"固件":    [self valueForShort:@"2A26" ear:ear] ?: @"",
        @"软件":    [self valueForShort:@"2A28" ear:ear] ?: @"",
        @"电量":    [self valueForShort:@"2A19" ear:ear] ?: @"",
        @"程序名":  progText,
        @"程序原值": prog ?: @"",
    };
}

- (NSArray<NSDictionary *> *)capabilityReport {
    NSMutableArray *out = [NSMutableArray array];
    for (CBPeripheral *p in _periphs) {
        NSString *ear = [_ear[p.identifier.UUIDString] copy] ?: (p.name ?: @"?");
        BOOL connected = (p.state == CBPeripheralStateConnected);
        NSString *periph = p.identifier.UUIDString;
        for (CBCharacteristic *c in _chars[periph]) {
            NSString *vk = [NSString stringWithFormat:@"%@/%@", periph, c.UUID.UUIDString];
            NSData *v = _values[vk];
            [out addObject:@{
                @"ear": ear,
                @"connected": @(connected),
                @"service": c.service.UUID.UUIDString ?: @"?",
                @"uuid": c.UUID.UUIDString,
                @"props": [self propsTextFor:c.properties],
                @"writable": @((c.properties & CBCharacteristicPropertyWrite) ||
                               (c.properties & CBCharacteristicPropertyWriteWithoutResponse)),
                @"notify": @((c.properties & CBCharacteristicPropertyNotify) != 0),
                @"isMic": @(HLMicCharUUID().length &&
                            [c.UUID.UUIDString caseInsensitiveCompare:HLMicCharUUID()] == NSOrderedSame),
                @"note": HLNoteForUUID(c.UUID.UUIDString),
                @"writeOnly": @(HLIsWriteOnly(c.properties)),
                @"len": @(v.length),
                @"value": v ? HLHex(v) : @""
            }];
        }
    }
    return out;
}

- (NSString *)micLiveText {
    NSInteger idx = HLMicLevelByte();
    NSMutableArray *parts = [NSMutableArray array];
    for (CBPeripheral *p in _periphs) {
        NSString *ear = [_ear[p.identifier.UUIDString] copy] ?: @"?";
        for (CBCharacteristic *c in _chars[p.identifier.UUIDString]) {
            if (HLMicCharUUID().length &&
                [c.UUID.UUIDString caseInsensitiveCompare:HLMicCharUUID()] == NSOrderedSame) {
                NSData *v = _values[[NSString stringWithFormat:@"%@/%@", p.identifier.UUIDString, c.UUID.UUIDString]];
                NSInteger lv = (idx >= 0 && v.length > (NSUInteger)idx) ? ((const uint8_t *)v.bytes)[idx] : -1;
                [parts addObject:[NSString stringWithFormat:@"%@ 档位=%ld 值=%@",
                                  ear, (long)lv, v ? HLHex(v) : @"(未读)"]];
                break;
            }
        }
    }
    return parts.count ? [parts componentsJoinedByString:@"  |  "] : @"未连接";
}

// ★ Bug #1: 暴露已连接的外设给 VGBatteryMonitor / VGRssiMonitor 复用
- (NSArray<CBPeripheral *> *)connectedPeripherals {
    NSMutableArray *out = [NSMutableArray array];
    for (CBPeripheral *p in _periphs) {
        if (p.state == CBPeripheralStateConnected) [out addObject:p];
    }
    return out;
}

#pragma mark 特征语义注解

// 依据 2026-10-25 导出的能力矩阵（116 条特征）人工判读。
// 只做“显示用”的注解，不参与任何写入决策——写错注解也不会影响功能。
static NSString *HLNoteForUUID(NSString *uuid) {
    static NSDictionary *m = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        m = @{
            // —— 标准服务 ——
            @"2A29": @"制造商",
            @"2A24": @"型号",
            @"2A25": @"序列号",
            @"2A26": @"固件版本",
            @"2A27": @"硬件版本",
            @"2A28": @"软件版本",
            @"2A19": @"电池电量",
            // —— 已确认 ——
            @"1454E9D6": @"⭐麦克风音量 [档位][01]",
            @"8D17AC2F": @"左右侧别 00左/01右",
            @"C97D21D3": @"本机配对ID",
            @"5F35C43D": @"本机配对ID",
            @"497EEB9E": @"对侧配对ID",
            @"353ECC73": @"对侧配对ID",
            @"7BE94A55": @"⭐当前程序名(ASCII)",
            @"42E940EF": @"实时输入电平",
            @"ADC3023D": @"实时输入电平",
            @"F3F594F9": @"状态字节(跟随写入跳动)",
            // —— 高度疑似：音量类（都是 [档位][尾] 结构）——
            @"8B820C6D": @"？疑似总音量 [档位][01]",
            @"9215A295": @"？疑似音量 [档位][00]",
            @"50632720": @"？疑似音量 [档位][00]",
            // —— 疑似：程序 / 开关（1 字节 R/W）——
            @"A28B6BE1": @"？疑似程序索引",
            @"9C12A3DB": @"？疑似程序索引",
            @"21FF4275": @"？疑似程序索引",
            @"535442F7": @"？未知开关(可写)",
            @"51939BB6": @"？未知开关(可写)",
            @"6AC46200": @"？未知开关(可写)",
            @"A391C6F1": @"？未知开关(可写)",
            @"4656D3AC": @"？未知开关(可写)",
            @"EBEE6F69": @"？未知开关(可写)",
            @"68BFA64E": @"？未知(FF)",
            // —— 只写命令通道（无初值，日志里从没读到过值）——
            @"6D5758A1": @"命令通道(只写)",
            @"786FF607": @"命令通道(只写)",
            @"6EFAB52E": @"命令通道(只写)",
            @"62DCC92F": @"命令通道(只写)",
            @"8B8276E8": @"命令通道(只写)",
            // —— 统计 / 状态 ——
            @"C8F7FAC0": @"统计块 20B",
            @"BC6829C4": @"计数器 8B",
            @"58BBCCC5": @"状态 6B",
            @"D01AB591": @"状态 3B",
            @"16438C66": @"状态 4B",
            @"DCBE7A3E": @"状态 1B",
            @"E24FAC83": @"状态 1B",
            @"D28617FE": @"侧别相关 00/01",
            @"BBA1C7F1": @"状态 1B",
            @"76B3DB1F": @"状态 0x11",
            @"98924A39": @"状态 1B",
            @"24E1DFF3": @"状态 1B",
            @"C8F714D6": @"未知(空值)",
            @"34DFC7CB": @"通知通道",
            @"C8F73DC3": @"通知通道",
            @"C8F7A68A": @"通知通道",
            @"C8F723DA": @"命令通道(只写)",
            @"C8F79C9A": @"命令通道(只写)",
            @"C8F7A8E4": @"命令通道(只写)",
            @"C8F7690C": @"状态(空)",
            @"60415E72": @"空通道",
            @"6E557876": @"空通道",
            @"E5892EBE": @"空通道",
        };
    });
    return m[HLShortUUID(uuid)] ?: @"";
}

static BOOL HLIsWriteOnly(CBCharacteristicProperties p) {
    return !(p & CBCharacteristicPropertyRead) &&
           ((p & CBCharacteristicPropertyWrite) || (p & CBCharacteristicPropertyWriteWithoutResponse));
}

#pragma mark 左右耳识别

- (NSString *)earName:(CBPeripheral *)p {
    NSString *e = _ear[p.identifier.UUIDString];
    if (e) return e;
    return p.name.length ? p.name : @"?";
}

- (void)detectEar:(CBPeripheral *)p char:(CBCharacteristic *)c {
    // 侧别来源只有两个，且**必须分主次**（2026-10-25 能力矩阵实证）：
    //
    //   主：8D17AC2F —— 1 字节纯侧别，00=左 / 01=右。读到就上锁，不再被任何东西改。
    //   次：C97D21D3 —— 6 字节 ASCII，**本机**配对 ID（左 2FCDA8 / 右 2FF351）。
    //       只在还没上锁时用。
    //
    // ⚠️ 同一只耳上还会读到 497EEB9E / 353ECC73 / 5F35C43D，那是**对侧**的 ID
    //    （左耳上读出来是 2FF351，右耳上读出来是 2FCDA8）。拿它判侧别会让左右耳
    //    完全反过来 —— 左耳按右耳档位写、右耳按左耳写，功能直接坏掉。
    //    所以这里只认 C97D21D3 一个，其余一律忽略。
    NSString *key  = p.identifier.UUIDString;
    BOOL locked    = [_earLock[key] boolValue];
    BOOL isSide    = ([c.UUID.UUIDString caseInsensitiveCompare:HL_EAR_FLAG_CHAR_UUID] == NSOrderedSame);
    BOOL isSelfId  = ([c.UUID.UUIDString caseInsensitiveCompare:HL_EAR_ID_CHAR_UUID] == NSOrderedSame);

    if (!isSide && !isSelfId) return;
    if (isSelfId && locked)   return;      // 侧别已确认，配对 ID 无权推翻

    NSString *ear = nil;
    NSString *how = @"";

    if (isSide && c.value.length == 1) {
        ear = (((const uint8_t *)c.value.bytes)[0] == 0) ? @"左耳" : @"右耳";
        how = @"侧别特征";
        _earLock[key] = @YES;
    } else if (isSelfId) {
        NSString *ascii = [[NSString alloc] initWithData:c.value encoding:NSUTF8StringEncoding];
        NSString *text = [[ascii stringByReplacingOccurrencesOfString:@" " withString:@""] uppercaseString];
        if ([text isEqualToString:HL_EAR_PAIR_LEFT])       { ear = @"左耳"; how = @"本机配对ID"; }
        else if ([text isEqualToString:HL_EAR_PAIR_RIGHT]) { ear = @"右耳"; how = @"本机配对ID"; }
    }

    if (!ear) return;
    if ([_ear[key] isEqualToString:ear]) return;
    _ear[key] = ear;
    HLLog(@"识别：%@ = %@（%@ %@）", key, ear, how, HLHex(c.value));
}

#pragma mark 右耳锁定

// 按档位构造报文并写入（尾字节固定 01），同时挂一个回读校验
- (void)writeLevel:(NSInteger)level to:(CBPeripheral *)peripheral char:(CBCharacteristic *)c {
    NSInteger idx = HLMicLevelByte();
    if (idx < 0) return;
    NSUInteger len = (NSUInteger)MAX(idx + 1, 2);
    NSMutableData *payload = [NSMutableData dataWithLength:len];
    uint8_t *b = payload.mutableBytes;
    memset(b, 0, len);
    b[idx] = (uint8_t)level;
    b[len - 1] = HL_FRAME_TRAILER;
    [peripheral writeValue:payload forCharacteristic:c type:HLWriteTypeFor(c)];

    NSString *key = [NSString stringWithFormat:@"%@/%@", peripheral.identifier.UUIDString, c.UUID.UUIDString];
    _verify[key] = @{@"level": @(level), @"retried": @NO,
                     @"deadline": @([[NSDate date] timeIntervalSince1970] + 3.5),
                     @"payload": payload, @"ear": [self earName:peripheral]};
}

// 这一只耳此刻「应该」是多少档？ -1 = 不用管
//   被显式锁住的耳（默认右耳）→ 锁到 HLLockLevel
//   播放 / 通话中且开了「播放中保持」→ 按当前场景的压低档位按住（左耳默认 0~50%，右耳 0）
- (NSInteger)targetLevelForEar:(NSString *)ear {
    if (!ear.length) return -1;
    if (HLEarIsLocked(ear)) return HLLockLevel();
    if (HLHoldWhilePlaying() && _lastMute) return HLMuteLevelForEar(ear);
    return -1;
}

// 播放中保持是否生效（决定看门狗跑多快）
- (BOOL)holdActive {
    if (!HLEnabled() || !gHLAutomation) return NO;
    if (!HLHoldWhilePlaying() || !_lastMute) return NO;
    return YES;
}

// 看门狗一拍：把被锁耳朵的当前档位读回来（值在 didUpdateValue 里核对）
- (void)enforceLock {
    if (!HLEnabled()) return;
    if (!gHLAutomation) return;             // 总开关关着：不再按任何耳
    BOOL holdPlaying = [self holdActive];
    if (!HLLockEnabled() && !holdPlaying) return;
    NSString *uuidStr = HLMicCharUUID();
    if (!uuidStr.length || HLMicLevelByte() < 0) return;
    CBUUID *want = [CBUUID UUIDWithString:uuidStr];

    for (CBPeripheral *p in _periphs) {
        if (p.state != CBPeripheralStateConnected) continue;
        NSString *ear = [self earName:p];
        if ([self targetLevelForEar:ear] < 0) continue;
        for (CBCharacteristic *c in _chars[p.identifier.UUIDString]) {
            if (![c.UUID isEqual:want]) continue;
            if (!(c.properties & CBCharacteristicPropertyRead)) break;
            [p readValueForCharacteristic:c];    // 值回来后在 didUpdateValue 里核对
            break;
        }
    }
}

#pragma mark 回读校验

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    if (error || !characteristic.value) return;

    // 顺手留一份值，给「深度探测」用（不改任何行为）
    {
        NSString *vk = [NSString stringWithFormat:@"%@/%@", peripheral.identifier.UUIDString, characteristic.UUID.UUIDString];
        _values[vk] = characteristic.value;
    }

    if ([characteristic.UUID.UUIDString caseInsensitiveCompare:HL_EAR_ID_CHAR_UUID] == NSOrderedSame ||
        [characteristic.UUID.UUIDString caseInsensitiveCompare:HL_EAR_FLAG_CHAR_UUID] == NSOrderedSame) {
        [self detectEar:peripheral char:characteristic];
        return;
    }

    NSString *key = [NSString stringWithFormat:@"%@/%@", peripheral.identifier.UUIDString, characteristic.UUID.UUIDString];

    // 档位核对：不管这个值是「我们读回来的」还是「设备主动通知的」，只要是音量特征
    // 且这只耳有目标档位（被锁 / 播放中保持），就核对一次——不是目标值立刻按回去。
    // 0.6.5 起这里覆盖了「iOS 音量键抢写」：按音量键改了档位，1.5 秒内被按回。
    if (HLMicCharUUID().length && (HLLockEnabled() || (HLHoldWhilePlaying() && _lastMute)) &&
        [characteristic.UUID.UUIDString caseInsensitiveCompare:HLMicCharUUID()] == NSOrderedSame) {
        NSString *ear = [self earName:peripheral];
        NSInteger target = [self targetLevelForEar:ear];
        if (target >= 0) {
            if (!_verify[key]) {                // 有校验任务在跑就交给校验，别抢
                NSInteger idx0 = HLMicLevelByte();
                NSData *d0 = characteristic.value;
                NSInteger got0 = (idx0 >= 0 && idx0 < (NSInteger)d0.length) ? ((const uint8_t *)d0.bytes)[idx0] : -1;
                if (got0 >= 0 && got0 != target) {
                    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
                    // 防止设备顶着写导致死循环：显式锁 1.5s 内不重复按；播放中保持 0.8s
                    double guard = HLEarIsLocked(ear) ? 1.5 : 0.8;
                    if (now - [_lockAt[key] doubleValue] > guard) {
                        _lockAt[key] = @(now);
                        HLLog(@"🔒 %@ 档位跳到 %ld，%@ %ld", ear, (long)got0,
                              HLEarIsLocked(ear) ? @"锁回" : @"按回", (long)target);
                        [self writeLevel:target to:peripheral char:characteristic];
                    }
                }
                return;
            }
        }
    }

    NSDictionary *v = _verify[key];
    if (!v) {
        if (HLVerbose()) HLLog(@"[读] %@ = %@", characteristic.UUID.UUIDString, HLHex(characteristic.value));
        return;
    }

    NSInteger idx = HLMicLevelByte();
    NSData *d = characteristic.value;
    NSInteger want = [v[@"level"] integerValue];
    NSInteger got = (idx >= 0 && idx < (NSInteger)d.length) ? ((const uint8_t *)d.bytes)[idx] : -1;

    if (got == want) {
        HLLog(@"✓ %@ 档位=%ld 已生效", v[@"ear"] ?: (peripheral.name ?: @"?"), (long)got);
        [_verify removeObjectForKey:key];
        return;
    }
    if ([[NSDate date] timeIntervalSince1970] < [v[@"deadline"] doubleValue]) return;  // 设备在渐变，等它

    if (![v[@"retried"] boolValue]) {
        _verify[key] = @{@"level": @(want), @"retried": @YES, @"ear": v[@"ear"] ?: @"?",
                         @"deadline": @([[NSDate date] timeIntervalSince1970] + 3.0),
                         @"payload": v[@"payload"]};
        HLLog(@"%@ 档位还是 %ld（目标 %ld），补写一次", v[@"ear"] ?: (peripheral.name ?: @"?"), (long)got, (long)want);
        [peripheral writeValue:v[@"payload"] forCharacteristic:characteristic type:HLWriteTypeFor(characteristic)];
    } else {
        HLLog(@"%@ 补写后仍停在 %ld（目标 %ld）", v[@"ear"] ?: (peripheral.name ?: @"?"), (long)got, (long)want);
        [_verify removeObjectForKey:key];
    }
}

#pragma mark 写入

- (BOOL)applyMute:(BOOL)mute { return [self applyMute:mute reapply:NO]; }

- (BOOL)applyMute:(BOOL)mute reapply:(BOOL)reapply {
    if (!HLEnabled()) return NO;
    if (!gHLAutomation) return NO;          // 总开关关着：只探测不写

    NSString *uuidStr = HLMicCharUUID();
    NSInteger idx = HLMicLevelByte();
    if (!uuidStr.length || idx < 0) { HLLog(@"没认到音量特征，跳过"); return NO; }

    CBUUID *want = [CBUUID UUIDWithString:uuidStr];
    NSUInteger len = (NSUInteger)MAX(idx + 1, 2);
    BOOL wrote = NO;

    for (CBPeripheral *p in _periphs) {
        if (p.state != CBPeripheralStateConnected) continue;
        for (CBCharacteristic *c in _chars[p.identifier.UUIDString]) {
            if (![c.UUID isEqual:want]) continue;

            NSString *ear = [self earName:p];
            NSInteger level = mute ? HLMuteLevelForEar(ear) : HLRestoreLevelForEar(ear);

            NSMutableData *payload = [NSMutableData dataWithLength:len];
            uint8_t *b = payload.mutableBytes;
            memset(b, 0, len);
            b[idx] = (uint8_t)level;
            b[len - 1] = HL_FRAME_TRAILER;      // 关键：第二字节必须是 01

            [p writeValue:payload forCharacteristic:c type:HLWriteTypeFor(c)];
            HLLog(@"%@ 写入 %@ : 档位=%ld (%ld%%)  报文=%@", mute ? @"播放" : @"暂停", ear,
                  (long)level, (long)llround(level * 100.0 / HLLevelMax()), HLHex(payload));

            NSString *key = [NSString stringWithFormat:@"%@/%@", p.identifier.UUIDString, c.UUID.UUIDString];
            _verify[key] = @{@"level": @(level), @"retried": @NO,
                             @"deadline": @([[NSDate date] timeIntervalSince1970] + 3.5),
                             @"payload": payload, @"ear": ear};
            wrote = YES;
            break;
        }
    }
    if (!wrote) { HLLog(@"没有已连接的耳，跳过"); return NO; }

    _lastMute = mute;
    [[NSUserDefaults standardUserDefaults] setBool:mute forKey:@"HLWasMuted"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    HLAfter(0.6, ^{ [self readMicChar]; });          // 先看一眼，校验逻辑接着盯 3.5s

    if (mute && !reapply) {                            // 播放中补写一次（开流常把档位重置）
        double d = HLReapplyDelay();
        if (d > 0) {
            NSInteger gen = ++_reapplyGen;
            HLAfter(d, ^{
                if (gen == self->_reapplyGen && self->_lastMute) [self applyMute:YES reapply:YES];
            });
        }
    } else if (!mute) {
        _reapplyGen++;
    }
    return YES;
}

- (void)readMicChar {
    CBUUID *want = [CBUUID UUIDWithString:HLMicCharUUID()];
    for (CBPeripheral *p in _periphs) {
        if (p.state != CBPeripheralStateConnected) continue;
        for (CBCharacteristic *c in _chars[p.identifier.UUIDString]) {
            if ([c.UUID isEqual:want] && (c.properties & CBCharacteristicPropertyRead)) {
                [p readValueForCharacteristic:c];
            }
        }
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    if (error) HLLog(@"写入失败 %@: %@", characteristic.UUID.UUIDString, error.localizedDescription);
}

@end

#pragma mark - 播放状态监听

@interface HLPlayMonitor : NSObject
+ (instancetype)shared;
- (void)start;
@end

@interface HLPlayMonitor () <HLLinkDelegate>
@end

@implementation HLPlayMonitor {
    NSTimer *_poll;
    BOOL _last;
    BOOL _hasLast;
    NSInteger _restoreGen;
    NSTimeInterval _lastLockAt;
    BOOL _everMuted;          // 启动后是否真的压过麦克风
}

+ (instancetype)shared {
    static HLPlayMonitor *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [HLPlayMonitor new]; });
    return s;
}

- (void)start {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gHLJAudioHook) [self installInstanceHook];
        _poll = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self
                                               selector:@selector(poll) userInfo:nil repeats:YES];
        [HLLink shared].delegate = self;
        [[HLLink shared] start];
        HLLog(@"HearingLink v3.5.2 已加载 pid=%d", (int)getpid());
    });
}

- (void)installInstanceHook {
    Class cls = NSClassFromString(@"JAudioPlayer");
    if (!cls) { HLAfter(1.0, ^{ [self installInstanceHook]; }); return; }

    // 只 hook 本类自己声明的 init，仅用于拿实例读 isPlaying。
    // 绝不 swizzle play/pause：那些方法内部走消息转发，交换实现后转发链断裂会 SIGABRT。
    unsigned int mcount = 0;
    Method *mlist = class_copyMethodList(cls, &mcount);
    BOOL ownInit = NO;
    for (unsigned int i = 0; i < mcount; i++) {
        if (method_getName(mlist[i]) == @selector(init)) { ownInit = YES; break; }
    }
    free(mlist);
    if (!ownInit) return;

    SEL repl = NSSelectorFromString(@"hl_init");
    Method m = class_getInstanceMethod([HLPlayMonitor class], repl);
    if (!m) return;
    class_addMethod(cls, repl, method_getImplementation(m), method_getTypeEncoding(m));
    @try {
        method_exchangeImplementations(class_getInstanceMethod(cls, @selector(init)),
                                       class_getInstanceMethod(cls, repl));
    } @catch (NSException *e) { HLLog(@"init hook 失败: %@", e.reason); }
}

- (id)hl_init {
    id obj = nil;
    @try { obj = [self hl_init]; }
    @catch (NSException *e) { return nil; }
    if (obj) {
        NSMutableArray *insts = objc_getAssociatedObject([HLPlayMonitor class], @"jplayers");
        if (!insts) {
            insts = [NSMutableArray array];
            objc_setAssociatedObject([HLPlayMonitor class], @"jplayers", insts, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        @synchronized (insts) { if (![insts containsObject:obj]) [insts addObject:obj]; }
    }
    return obj;
}

- (BOOL)isPlaying {
    if (gHLPlayingProvider) {
        @try { return gHLPlayingProvider(); } @catch (NSException *e) { return NO; }
    }
    NSArray *insts = objc_getAssociatedObject([HLPlayMonitor class], @"jplayers");
    for (id inst in insts) {
        @try {
            if ([inst respondsToSelector:@selector(isPlaying)] &&
                ((BOOL(*)(id, SEL))objc_msgSend)(inst, @selector(isPlaying))) return YES;
        } @catch (NSException *e) {}
    }
    if (insts.count) return NO;
    @try {
        NSNumber *rate = [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate];
        if (rate && rate.doubleValue > 0.01) return YES;
    } @catch (NSException *e) {}
    return NO;
}

- (void)poll {
    if (!HLEnabled()) return;

    // 右耳锁定看门狗：不管在播放还是暂停，每 N 秒查一次被锁的耳朵
    // 0.6.5：播放中保持时提速到 1 秒一拍，否则按音量键被改的档位要 3 秒才按得回来
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    BOOL holdOn = [[HLLink shared] holdActive];
    NSTimeInterval lockIv = holdOn ? HL_HOLD_INTERVAL : HLLockInterval();
    if (now - _lastLockAt >= lockIv) {
        _lastLockAt = now;
        @try { [[HLLink shared] enforceLock]; } @catch (NSException *e) {}
    }

    @try {
        BOOL playing = [self isPlaying];
        if (_hasLast && playing == _last) return;
        _hasLast = YES;
        _last = playing;
        HLLog(@"状态 → %@", playing ? @"播放中" : @"暂停/停止");
        if (playing) {
            _everMuted = YES;
            NSInteger gen = ++_restoreGen;
            [self applyMute:YES gen:gen attempt:0];
        } else {
            // 启动后第一次就是「没在放」：只记状态，不写。
            // v3.5 在 App 刚起来时会把左耳强推到 60%，覆盖掉你在 iOS 里手调的音量
            if (!_everMuted) {
                HLLog(@"启动待命：没在放声音，不动音量");
                return;
            }
            NSInteger gen = ++_restoreGen;
            HLAfter(HLRestoreDelay(), ^{
                if (gen != self->_restoreGen) return;
                [self applyMute:NO gen:gen attempt:0];
            });
        }
    } @catch (NSException *e) { HLLog(@"poll 异常: %@", e.reason); }
}

// 写入失败（耳朵还没连上 / 刚断线）时自动补：2s、3s、4s…最多 8 次
// v3.4 的「偶尔暂停左耳没恢复」就是断线窗口里写不进去、之后没人再补
- (void)applyMute:(BOOL)mute gen:(NSInteger)gen attempt:(NSInteger)attempt {
    if (gen != _restoreGen) return;
    if ([[HLLink shared] applyMute:mute]) return;
    if (attempt >= 8) { HLLog(@"%@：重试 %ld 次仍没连上，放弃这一轮", mute ? @"播放" : @"暂停", (long)attempt); return; }
    HLAfter(2.0 + attempt, ^{
        [self applyMute:mute gen:gen attempt:attempt + 1];
    });
}

- (void)linkDidBecomeReady {
    // 刚连上（含断线重连）先锁一次右耳，不用等 3s 心跳
    HLAfter(1.0, ^{ [[HLLink shared] enforceLock]; });
    _lastLockAt = [[NSDate date] timeIntervalSince1970];

    BOOL playing = [self isPlaying];
    if (playing) {
        HLLog(@"就绪 → 正在播放，压低");
        [[HLLink shared] applyMute:YES];
        return;
    }
    // 没在播放：只在「上次停在静音」时恢复，免得每次启动都覆盖你手动设的音量
    if ([HLPrefAny(@"HLWasMuted", @NO) boolValue]) {
        HLLog(@"就绪 → 上次停在静音，恢复");
        [[HLLink shared] applyMute:NO];
    } else {
        HLLog(@"就绪 → 待命（未播放，不动音量）");
    }
}

@end

#pragma mark - 深度探测对外接口

void HLReadAllChars(void)        { [[HLLink shared] readAllChars]; }
NSArray<NSDictionary *> *HLCapabilityReport(void) { return [[HLLink shared] capabilityReport]; }
NSString *HLMicLiveText(void)    { return [[HLLink shared] micLiveText]; }

// ---- 实验台 / 快照 对外接口 ----

NSInteger HLGetLevelMax(void)    { return HLLevelMax(); }

// 当前所有特征的快照：key = "左耳|1454E9D6"，value = "00 01"
NSDictionary<NSString *, NSString *> *HLSnapshotValues(void) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSDictionary *r in HLCapabilityReport()) {
        NSString *k = [NSString stringWithFormat:@"%@|%@",
                       r[@"ear"], HLShortUUID(r[@"uuid"])];
        out[k] = r[@"value"] ?: @"";
    }
    return out;
}

BOOL HLWriteCharHex(NSString *ear, NSString *uuid, NSString *hex) {
    return [[HLLink shared] writeUUID:uuid hex:hex ear:ear];
}

NSDictionary *HLDeviceInfo(void)  { return [[HLLink shared] deviceInfo]; }
void HLReadDeviceInfo(void)       { [[HLLink shared] readDeviceInfoChars]; }

#pragma mark - 入口

// 立刻按当前播放状态重写一次（切通话模式后调用，否则档位要等下一次播放/暂停才更新）
void HLReapplyNow(void) {
    BOOL playing = gHLPlayingProvider ? gHLPlayingProvider() : NO;
    [[HLLink shared] applyMute:playing];
}

__attribute__((constructor))
static void HLBootstrap(void) {
    @try {
        [[HLPlayMonitor shared] start];
    } @catch (NSException *e) {
        HLLog(@"bootstrap 异常: %@", e.reason);
    }
}
