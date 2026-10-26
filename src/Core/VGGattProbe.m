#import "VGGattProbe.h"
#import <objc/runtime.h>
#import "VGProbeSnapshot.h"
#import "VGGattProfile.h"
#import "VGProbeDevice.h"
#import "VGEarMap.h"

NSNotificationName const VGGattLogNotification     = @"VGGattLogNotification";
NSNotificationName const VGGattStateNotification   = @"VGGattStateNotification";
NSNotificationName const VGGattDevicesNotification = @"VGGattDevicesNotification";

static const uint16_t kVGCompany = 0x0295; // WS Audiology 661
static const NSTimeInterval kVGProbeTimeout = 45.0;
static const NSInteger kVGMaxDevices = 2;

// 仅自动读取这些 SIG 标准只读特征（16-bit UUID）
static NSSet<NSString *> *VGSafeReadUUIDs(void) {
    static NSSet *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [NSSet setWithArray:@[
            @"2A19", // Battery Level
            @"2A24", @"2A25", @"2A26", @"2A27", @"2A28", @"2A29", // Model/Serial/Firmware/Hardware/Software/Manufacturer
            @"2A23", @"2A50", // System ID / PnP ID
        ]];
    });
    return s;
}

static NSString *VGUUIDShort(CBUUID *uuid) {
    NSString *s = uuid.UUIDString.uppercaseString;
    // 16-bit 别名 UUID 基底
    NSString *base = @"-0000-1000-8000-00805F9B34FB";
    if (s.length == 36 && [s hasSuffix:base]) {
        return [s substringToIndex:8];
    }
    return s;
}

static NSString *VGProps(CBCharacteristicProperties p) {
    NSMutableArray *a = [NSMutableArray array];
    if (p & CBCharacteristicPropertyRead)    [a addObject:@"R"];
    if (p & CBCharacteristicPropertyWrite)   [a addObject:@"W"];
    if (p & CBCharacteristicPropertyWriteWithoutResponse) [a addObject:@"WW"];
    if (p & CBCharacteristicPropertyNotify)  [a addObject:@"N"];
    if (p & CBCharacteristicPropertyIndicate)[a addObject:@"I"];
    return [a componentsJoinedByString:@"/"];
}

// 把数据转成空格分隔的十六进制串，用于展示二进制特征（不可打印时）
static NSString *VGToHex(NSData *v) {
    if (v.length == 0) return @"";
    NSMutableString *s = [NSMutableString string];
    const uint8_t *b = v.bytes;
    for (NSUInteger i = 0; i < v.length; i++) {
        if (i) [s appendString:@" "];
        [s appendFormat:@"%02X", b[i]];
    }
    return s;
}

// 从广播厂商数据里推断耳别。
// 实测依据（本机 Vibe Go，序列号 JFA7311=右耳 / JFA5631=左耳，3 次独立抓包一致）：
// 23 字节负载中，下标 16 与下标 22 的 bit6（0x40）只在右耳置位——
//   右耳 … C1 … 70 … 40 ｜ 左耳 … 83 … 51 … 00
// 两个位置结论一致才给出推断，否则不猜（返回 nil）。
static NSString *VGMfrEarHint(NSData *mfr) {
    if (mfr.length < 23) return nil;
    const uint8_t *b = mfr.bytes;
    BOOL bit16 = (b[16] & 0x40) != 0;
    BOOL bit22 = (b[22] & 0x40) != 0;
    if (bit16 == bit22) return bit16 ? @"右耳" : @"左耳";
    return nil;
}

@interface VGGattProbe ()
@property (nonatomic, strong) CBCentralManager *central;
@property (nonatomic, strong) dispatch_queue_t q;
@property (nonatomic, strong) NSMutableArray<NSString *> *logLines;
@property (nonatomic, strong) NSMutableDictionary<NSUUID *, CBPeripheral *> *targets;
@property (nonatomic, strong) NSMutableDictionary<NSUUID *, VGProbeDevice *> *deviceMap;
@property (nonatomic, strong) NSMutableSet<NSUUID *> *done;
@property (nonatomic, strong) NSDate *startedAt;
@property (nonatomic, strong) NSTimer *timeout;
@property (nonatomic, readwrite) BOOL running;
@property (nonatomic, copy)   NSString *stateText;
@end

@implementation VGGattProbe

+ (instancetype)shared {
    static VGGattProbe *m; static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [VGGattProbe new]; });
    return m;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _logLines = [NSMutableArray array];
        _targets = [NSMutableDictionary dictionary];
        _deviceMap = [NSMutableDictionary dictionary];
        _done = [NSMutableSet set];
        _q = dispatch_queue_create("vg.gatt", DISPATCH_QUEUE_SERIAL);
        _stateText = @"空闲";
    }
    return self;
}

- (NSArray<NSString *> *)lines {
    @synchronized (self.logLines) { return [self.logLines copy]; }
}

- (void)postLog:(NSString *)line {
    @synchronized (self.logLines) { [self.logLines addObject:line]; }
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:VGGattLogNotification object:nil];
    });
}

- (void)setState:(NSString *)s {
    self.stateText = s;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:VGGattStateNotification object:nil];
    });
}

- (void)start {
    if (self.running) return;
    self.running = YES;
    self.startedAt = [NSDate date];
    @synchronized (self.logLines) { [self.logLines removeAllObjects]; }
    [self.targets removeAllObjects]; [self.done removeAllObjects]; [self.deviceMap removeAllObjects];

    [self postLog:@"================ Vibe Go GATT 只读枚举 ================"];
    [self postLog:@"安全模式：枚举全部服务/特征，仅读取带 Read 属性者；不鉴权、不写入、不订阅通知"];
    [self postLog:@"比对模式：结束时会与「上次探测」自动比对，列出发生变化的特征（基线只存本机，不上传）"];
    [self setState:@"初始化蓝牙…"];
    self.central = [[CBCentralManager alloc] initWithDelegate:self queue:self.q
                                                     options:@{ CBCentralManagerOptionShowPowerAlertKey: @NO }];
    self.timeout = [NSTimer scheduledTimerWithTimeInterval:kVGProbeTimeout target:self
                                                  selector:@selector(finishTimeout) userInfo:nil repeats:NO];
}

- (void)finishTimeout {
    [self postLog:@"— 到达 45 秒探测时限，结束 —"];
    [self finish];
}

- (void)finish {
    if (!self.running) return;
    self.running = NO;
    [self.timeout invalidate]; self.timeout = nil;
    @try {
        for (CBPeripheral *p in self.targets.allValues) {
            if (p.state != CBPeripheralStateDisconnected) [self.central cancelPeripheralConnection:p];
        }
        [self.central stopScan];
    } @catch (NSException *e) { [self postLog:[NSString stringWithFormat:@"清理异常: %@", e]]; }
    [self postLog:@"================ 枚举结束 ================"];
    [self snapshotCompareAll];
    [self setState:@"完成，可分享日志"];
    [self postDevices];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:VGGattLogNotification object:nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:VGGattStateNotification object:nil];
    });
}

- (void)postDevices {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:VGGattDevicesNotification object:nil];
    });
}

- (NSArray<VGProbeDevice *> *)devices {
    @synchronized (self.deviceMap) { return [self.deviceMap.allValues copy]; }
}

#pragma mark - 快照比对（找出「会变的特征」）

// 每次探测结束都把本次取值存为基线；下次探测自动列出差异。
// 这样用户只要在手机上操作一下（切程序 / 调音量 / 换场景），再跑一次探测，
// 就能从差异清单里直接看出「哪个特征对应哪个功能」——全程只读，不写设备。
- (void)snapshotCompareAll {
    NSArray<VGProbeDevice *> *devs;
    @synchronized (self.deviceMap) { devs = [self.deviceMap.allValues copy]; }
    for (VGProbeDevice *d in devs) {
        if (d.rawValues.count == 0) continue;
        NSString *key = [VGProbeSnapshot deviceKeyWithSerial:d.serial fallback:d.peripheralID];
        NSDictionary *old = [VGProbeSnapshot loadForDeviceKey:key];
        NSDictionary *now = [d snapshotValues];
        d.snapshotKey = key;
        d.hasBaseline = (old.count > 0);
        d.baselineDateText = [VGProbeSnapshot savedDateTextForDeviceKey:key];
        NSArray<NSString *> *ch = [VGProbeSnapshot changesFromOld:old toNew:now];
        d.changes = ch;

        [self postLog:[NSString stringWithFormat:@"[快照] …%@  基线键=%@",
                       d.peripheralID ?: @"??????", key]];
        if (!d.hasBaseline) {
            [self postLog:@"      首次记录基线，已保存；下次探测会自动列出变化项"];
        } else if (ch.count == 0) {
            [self postLog:[NSString stringWithFormat:@"      与上次（%@）完全一致：0 项变化",
                           d.baselineDateText ?: @"上次"]];
        } else {
            [self postLog:[NSString stringWithFormat:@"      ⚠️ 较上次（%@）共 %lu 项变化：",
                           d.baselineDateText ?: @"上次", (unsigned long)ch.count]];
            for (NSString *c in ch) [self postLog:[NSString stringWithFormat:@"        · %@", c]];
        }
        [VGProbeSnapshot saveValues:now forDeviceKey:key];
    }
}

#pragma mark - Central

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    if (central.state == CBManagerStatePoweredOn) {
        [self setState:@"正在扫描 company=661 设备…"];
        [self postLog:@"[扫描] 开始监听广播（最多连接 2 只）"];
        [central scanForPeripheralsWithServices:nil
                                        options:@{ CBCentralManagerScanOptionAllowDuplicatesKey: @NO }];
    } else {
        [self postLog:[NSString stringWithFormat:@"蓝牙状态异常: %ld", (long)central.state]];
    }
}

- (void)centralManager:(CBCentralManager *)central
    didDiscoverPeripheral:(CBPeripheral *)peripheral
        advertisementData:(NSDictionary *)adv RSSI:(NSNumber *)RSSI {
    NSData *mfr = adv[CBAdvertisementDataManufacturerDataKey];
    if (mfr.length < 2) return;
    const uint8_t *b = mfr.bytes;
    if ((b[0] | (b[1] << 8)) != kVGCompany) return;

    NSUUID *pid = peripheral.identifier;
    if (self.targets[pid] || self.targets.count >= kVGMaxDevices) return;

    NSString *name = adv[CBAdvertisementDataLocalNameKey] ?: peripheral.name ?: @"(无名)";
    self.targets[pid] = peripheral;
    VGProbeDevice *dev = [VGProbeDevice new];
    dev.peripheralID = [pid.UUIDString substringFromIndex:pid.UUIDString.length - 6];
    dev.earKey = pid.UUIDString;
    dev.earLabel = [VGEarMap earLabelForKey:pid.UUIDString];
    dev.advertisedName = name;
    dev.mfrHex = VGToHex(mfr);
    dev.mfrEarHint = VGMfrEarHint(mfr);
    self.deviceMap[pid] = dev;
    [self postLog:[NSString stringWithFormat:@"[发现] %@  id=…%@  RSSI=%@ dBm", name,
                   [pid.UUIDString substringFromIndex:pid.UUIDString.length - 6], RSSI]];
    [self postLog:[NSString stringWithFormat:@"      广播厂商数据(%luB) = %@%@",
                   (unsigned long)mfr.length, dev.mfrHex,
                   dev.mfrEarHint.length ? [NSString stringWithFormat:@"   侧别推断=%@", dev.mfrEarHint] : @""]];
    peripheral.delegate = self;
    [central connectPeripheral:peripheral options:nil];
    [self setState:[NSString stringWithFormat:@"已发现 %lu 只，正在连接…", (unsigned long)self.targets.count]];
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    [self postLog:[NSString stringWithFormat:@"[连接] 成功 …%@，发现服务中",
                   [peripheral.identifier.UUIDString substringFromIndex:peripheral.identifier.UUIDString.length - 6]]];
    objc_setAssociatedObject(peripheral, @selector(start), [NSMutableArray array],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC); // 待枚举服务
    [peripheral readRSSI];
    [peripheral discoverServices:nil];
}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    [self postLog:[NSString stringWithFormat:@"[连接失败] %@", error.localizedDescription]];
    [self.done addObject:peripheral.identifier];
    [self maybeFinish];
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    [self.done addObject:peripheral.identifier];
    [self maybeFinish];
}

#pragma mark - Peripheral

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
    if (error) { [self postLog:[NSString stringWithFormat:@"[服务错误] %@", error.localizedDescription]]; }
    NSMutableArray *pending = objc_getAssociatedObject(peripheral, @selector(start));
    NSArray *services = peripheral.services ?: @[];
    [pending addObjectsFromArray:services];
    for (CBService *svc in services) {
        [self postLog:[NSString stringWithFormat:@"  服务 %@", VGUUIDShort(svc.UUID)]];
        [peripheral discoverCharacteristics:nil forService:svc];
    }
    if (pending.count == 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), self.q, ^{
            [self markDone:peripheral];
        });
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    if (error) [self postLog:[NSString stringWithFormat:@"[特征错误 svc %@] %@",
                              VGUUIDShort(service.UUID), error.localizedDescription]];

    NSMutableArray<CBCharacteristic *> *toRead = [NSMutableArray array];
    for (CBCharacteristic *c in service.characteristics ?: @[]) {
        NSString *shortUUID = VGUUIDShort(c.UUID);
        NSString *fn = [VGGattProfile friendlyNameForUUID:shortUUID];
        VGCharCategory cat = [VGGattProfile categoryForUUID:shortUUID];
        NSString *tag = fn ? [NSString stringWithFormat:@"%@ · %@", fn, [VGGattProfile categoryName:cat]]
                           : [VGGattProfile categoryName:cat];
        [self postLog:[NSString stringWithFormat:@"    特征 %@  [%@]  %@", shortUUID, VGProps(c.properties), tag]];
        VGProbeDevice *dev = self.deviceMap[peripheral.identifier];
        if (dev) dev.charCount += 1;
        // 安全原则：只读取带 Read 属性、且非写/写无响应专属的特征（命令特征 [W]/[WW] 自动排除）。
        // 不订阅任何通知（不写 CCCD）、不写入任何特征、不做鉴权。
        BOOL readable = (c.properties & CBCharacteristicPropertyRead) != 0;
        if (readable) [toRead addObject:c];
    }
    // 逐个读标准只读项
    for (CBCharacteristic *c in toRead) [peripheral readValueForCharacteristic:c];

    // 该服务枚举完成，从待处理移除；全部完成后留 3 秒等读取回调，再结束此设备
    NSMutableArray *pending = objc_getAssociatedObject(peripheral, @selector(start));
    [pending removeObject:service];
    if (pending.count == 0) {
        [self postLog:[NSString stringWithFormat:@"  …%@ 服务/特征枚举完毕，等待只读返回",
                       [peripheral.identifier.UUIDString substringFromIndex:peripheral.identifier.UUIDString.length - 6]]];
        CBPeripheral *weakP = peripheral;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), self.q, ^{
            [self markDone:weakP];
        });
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)c error:(NSError *)error {    NSString *u = VGUUIDShort(c.UUID);
    if (error) {
        // 加密错误也记录（它本身就是结论），但不触发任何配对动作
        [self postLog:[NSString stringWithFormat:@"      读取 %@ => 错误 %ld %@（可能需加密，已停止）",
                       u, (long)error.code, error.localizedDescription]];
        return;
    }
    NSData *v = c.value;
    NSString *hex = [v base64EncodedStringWithOptions:0];
    NSMutableString *ascii = [NSMutableString string];
    // 只有「全部字节都可打印」才按文本展示；只要出现一个控制字节/NUL 就按二进制走 hex。
    // （此前是「任一字节可打印就算文本」，导致 20 字节流数据被显示成满屏「.」）
    BOOL allPrintable = (v.length > 0);
    for (NSUInteger i = 0; i < v.length; i++) {
        uint8_t x = ((const uint8_t *)v.bytes)[i];
        BOOL ok = (x >= 32 && x < 127);
        if (!ok) allPrintable = NO;
        [ascii appendString:ok ? [NSString stringWithFormat:@"%c", x] : @"."];
    }
    // 二进制（不可打印）统一用十六进制展示，避免满屏「.」
    NSString *decoded = allPrintable ? [ascii copy] : VGToHex(v);
    [self postLog:[NSString stringWithFormat:@"      ✅读取 %@ = %@  ascii=\"%@\"", u, hex, ascii]];

    // 结构化写回设备档案（仅来自 SIG 标准只读特征）
    VGProbeDevice *dev = self.deviceMap[peripheral.identifier];
    if (dev) {
        if      ([u isEqualToString:@"2A29"]) dev.manufacturer = [ascii copy];
        else if ([u isEqualToString:@"2A24"]) dev.model = [ascii copy];
        else if ([u isEqualToString:@"2A25"]) dev.serial = [ascii copy];
        else if ([u isEqualToString:@"2A27"]) dev.hwRev = [ascii copy];
        else if ([u isEqualToString:@"2A26"]) dev.fwRev = [ascii copy];
        else if ([u isEqualToString:@"2A28"]) dev.swRev = [ascii copy];
    }

    // 电量特别解读
    if ([u isEqualToString:@"2A19"] && v.length >= 1) {
        uint8_t pct = ((const uint8_t *)v.bytes)[0];
        [self postLog:[NSString stringWithFormat:@"      🔋 标准电池服务电量 = %u%%", pct]];
        dev.battery = [NSString stringWithFormat:@"%u%%", pct];
    } else {
        // 其余可读特征（厂商信息/状态/配置等）纳入结构化遥测，按 UUID 存解码串
        NSSet *dis = [NSSet setWithObjects:@"2A29",@"2A24",@"2A25",@"2A27",@"2A26",@"2A28",nil];
        if (dev && ![dis containsObject:u]) {
            if (!dev.rawValues) dev.rawValues = [NSMutableDictionary dictionary];
            dev.rawValues[u] = decoded;
            NSString *fn = [VGGattProfile friendlyNameForUUID:u];
            if (fn.length) {
                [self postLog:[NSString stringWithFormat:@"      📦 %@ = %@", fn, decoded]];
            }
        }
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didReadRSSI:(NSNumber *)RSSI error:(NSError *)error {
    if (!error) {
        [self postLog:[NSString stringWithFormat:@"[链路RSSI] %ld dBm（连接态实测）", (long)RSSI.integerValue]];
    }
}

- (void)peripheralDidUpdateName:(CBPeripheral *)peripheral {}

// 服务/特征发现是异步批量的，采用延时收尾：无新活动 2 秒后断开
- (void)markDone:(CBPeripheral *)peripheral {
    [self.done addObject:peripheral.identifier];
    [self postDevices];
    [self maybeFinish];
}

- (void)maybeFinish {
    if (self.targets.count == 0) return;
    NSTimeInterval elapsed = -[self.startedAt timeIntervalSinceNow];
    BOOL scanWindowOK = (self.targets.count >= kVGMaxDevices) || (elapsed >= 12.0);
    if (scanWindowOK && self.done.count >= self.targets.count) {
        [self.central stopScan];
        [self finish];
    }
}

- (NSURL *)exportFile {
    NSString *text = [[self lines] componentsJoinedByString:@"\n"];

    // 在文本日志后附加结构化 JSON（便于跨次抓包对比分析）
    NSMutableArray *devs = [NSMutableArray array];
    for (VGProbeDevice *d in self.deviceMap.allValues) {
        NSMutableDictionary *o = [NSMutableDictionary dictionary];
        if (d.peripheralID) o[@"id"] = d.peripheralID;
        if (d.earLabel)     o[@"ear"] = d.earLabel;
        if (d.inferredEarText) o[@"earInferred"] = [d inferredEarText];
        if (d.pairingID)    o[@"pairingID"] = [d pairingID];
        if (d.mfrHex)       o[@"advertMfrHex"] = d.mfrHex;
        if (d.advertisedName) o[@"name"] = d.advertisedName;
        if (d.manufacturer) o[@"manufacturer"] = d.manufacturer;
        if (d.model)        o[@"model"] = d.model;
        if (d.serial)       o[@"serial"] = d.serial;
        if (d.hwRev)        o[@"hardware"] = d.hwRev;
        if (d.fwRev)        o[@"firmware"] = d.fwRev;
        if (d.swRev)        o[@"software"] = d.swRev;
        if (d.battery)      o[@"battery"] = d.battery;
        o[@"charCount"] = @(d.charCount);
        if (d.rawValues.count) o[@"telemetry"] = d.rawValues;
        if (d.hasBaseline) {
            o[@"baselineAt"] = d.baselineDateText ?: @"上次";
            o[@"changesVsLastRun"] = d.changes ?: @[];
        }
        [devs addObject:o];
    }
    NSError *jerr;
    NSData *jdata = [NSJSONSerialization dataWithJSONObject:@{@"devices": devs} options:NSJSONWritingPrettyPrinted error:&jerr];
    NSString *json = jerr ? @"" : [[NSString alloc] initWithData:jdata encoding:NSUTF8StringEncoding];
    NSString *full = [text stringByAppendingFormat:@"\n\n======== 结构化 JSON ========\n%@\n", json];

    NSURL *dir = [[NSFileManager defaultManager] URLForDirectory:NSDocumentDirectory
                                                        inDomain:NSUserDomainMask appropriateForURL:nil
                                                          create:YES error:nil];
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"yyyyMMdd_HHmmss";
    NSURL *url = [dir URLByAppendingPathComponent:
                  [NSString stringWithFormat:@"vg_gatt_%@.log", [f stringFromDate:NSDate.date]]];
    [full writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return url;
}

@end
