#import "VGBatteryMonitor.h"
#import "HLLink.h"

NSNotificationName const VGBatteryDidChangeNotification = @"VGBatteryDidChangeNotification";

static const uint16_t kVGCompany = 0x0295;        // WS Audiology = 661
static const NSInteger kVGMaxBatteryDevices = 2;
static const NSTimeInterval kVGPollInterval = 60.0;

@implementation VGBatteryDevice
@end

@interface VGBatteryMonitor () <CBCentralManagerDelegate, CBPeripheralDelegate>
@property (nonatomic, strong) CBCentralManager *central;
@property (nonatomic, strong) dispatch_queue_t q;
@property (nonatomic, strong) NSMutableDictionary<NSString *, VGBatteryDevice *> *items;
@property (nonatomic, strong) NSMutableDictionary<NSString *, CBPeripheral *> *peris;
@property (nonatomic, assign) NSTimeInterval lastPost;
@end

@implementation VGBatteryMonitor

+ (instancetype)shared {
    static VGBatteryMonitor *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [VGBatteryMonitor new]; });
    return m;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _items = [NSMutableDictionary dictionary];
        _peris = [NSMutableDictionary dictionary];
        _q = dispatch_queue_create("vg.battery", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)start {
    dispatch_async(self.q, ^{
        if (self.central) return;
        self.central = [[CBCentralManager alloc]
            initWithDelegate:self queue:self.q
                     options:@{ CBCentralManagerOptionShowPowerAlertKey: @NO }];
        [self startPollTimer];
    });
}

#pragma mark - Polling

- (void)startPollTimer {
    dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.q);
    uint64_t iv = (uint64_t)(kVGPollInterval * NSEC_PER_SEC);
    dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, iv), iv, (uint64_t)(5 * NSEC_PER_SEC));
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(t, ^{ [weakSelf pollOnce]; });
    dispatch_resume(t);
}

- (void)pollOnce {
    // ★ 先试 HLLink 已经连上的（避免重复 scan/connect）
    if ([HLLink shared].statusText.length > 0 && self.peris.count == 0) {
        @try {
            for (CBPeripheral *p in [[HLLink shared] connectedPeripherals]) {
                if (p.state == CBPeripheralStateConnected && !self.peris[p.identifier.UUIDString]) {
                    self.peris[p.identifier.UUIDString] = p;
                    VGBatteryDevice *d = [VGBatteryDevice new];
                    d.uuidString = p.identifier.UUIDString;
                    d.shortId = [d.uuidString substringFromIndex:d.uuidString.length - 6];
                    d.connected = YES;
                    d.name = p.name ?: @"Vibe";
                    d.updatedAt = [NSDate date];
                    self.items[p.identifier.UUIDString] = d;
                    p.delegate = self;
                }
            }
        } @catch (NSException *e) {
            NSLog(@"[VibeGo] HLLink fast path exception: %@", e);
        }
    }

    for (CBPeripheral *p in self.peris.allValues) {
        if (p.state != CBPeripheralStateConnected) continue;
        [p readRSSI];
        CBCharacteristic *batt = [self findCharacteristic:@"2A19" peripheral:p];
        if (batt) [p readValueForCharacteristic:batt];
        // 当前程序名（7BE94A55，可读）——只读，不写入
        CBCharacteristic *prog = [self findCharacteristic:@"7BE94A55-8D91-4592-BC0F-EA3664CCD3A9" peripheral:p];
        if (prog) [p readValueForCharacteristic:prog];
    }
}

- (CBCharacteristic *)findCharacteristic:(NSString *)shortUUID peripheral:(CBPeripheral *)p {
    // 统一比较「去基底的短名」：16-bit（如 2A19）与 128-bit 都能前缀匹配
    NSString *query = [shortUUID uppercaseString];
    for (CBService *svc in p.services) {
        for (CBCharacteristic *c in svc.characteristics) {
            NSString *base = [[c.UUID.UUIDString uppercaseString]
                stringByReplacingOccurrencesOfString:@"-0000-1000-8000-00805F9B34FB" withString:@""];
            if ([base hasPrefix:query]) return c;
        }
    }
    return nil;
}

#pragma mark - Notify

- (void)postChange {
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if (now - self.lastPost < 0.8) return;
    self.lastPost = now;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:VGBatteryDidChangeNotification object:nil];
    });
}

#pragma mark - Central

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    if (central.state != CBManagerStatePoweredOn) return;
    [central scanForPeripheralsWithServices:nil
                                    options:@{ CBCentralManagerScanOptionAllowDuplicatesKey: @NO }];
    // 已认识的设备（如 App 内 central 重建）直接尝试重连
    for (CBPeripheral *p in self.peris.allValues) {
        if (p.state == CBPeripheralStateDisconnected) [central connectPeripheral:p options:nil];
    }
}

- (void)centralManager:(CBCentralManager *)central
    didDiscoverPeripheral:(CBPeripheral *)peripheral
        advertisementData:(NSDictionary *)adv RSSI:(NSNumber *)RSSI {
    NSData *mfr = adv[CBAdvertisementDataManufacturerDataKey];
    if (mfr.length < 2) return;
    const uint8_t *b = mfr.bytes;
    if ((b[0] | (b[1] << 8)) != kVGCompany) return;

    NSString *key = peripheral.identifier.UUIDString;
    VGBatteryDevice *d = self.items[key];
    if (!d) {
        if (self.items.count >= kVGMaxBatteryDevices) return;
        d = [VGBatteryDevice new];
        d.uuidString = key;
        d.shortId = [key substringFromIndex:key.length - 6];
        d.connected = NO;
        self.items[key] = d;
        self.peris[key] = peripheral;
    } else {
        self.peris[key] = peripheral;
    }
    d.name = adv[CBAdvertisementDataLocalNameKey] ?: (peripheral.name ?: @"Vibe");
    d.updatedAt = [NSDate date];

    if (peripheral.state == CBPeripheralStateDisconnected) {
        peripheral.delegate = self;
        [central connectPeripheral:peripheral options:nil];
    }
    [self postChange];
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    VGBatteryDevice *d = self.items[peripheral.identifier.UUIDString];
    d.connected = YES;
    d.updatedAt = [NSDate date];
    peripheral.delegate = self;
    [peripheral readRSSI];
    // 只发现标准 SIG 服务：电池 + 设备信息；厂商私有服务一律不碰
    [peripheral discoverServices:@[
        [CBUUID UUIDWithString:@"180F"],
        [CBUUID UUIDWithString:@"180A"],
    ]];
    [self postChange];
}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    VGBatteryDevice *d = self.items[peripheral.identifier.UUIDString];
    d.connected = NO;
    d.updatedAt = [NSDate date];
    // 2 秒后重试
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), self.q, ^{
        if (self.central.state == CBManagerStatePoweredOn &&
            peripheral.state == CBPeripheralStateDisconnected) {
            [self.central connectPeripheral:peripheral options:nil];
        }
    });
    [self postChange];
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    VGBatteryDevice *d = self.items[peripheral.identifier.UUIDString];
    d.connected = NO;
    d.updatedAt = [NSDate date];
    // 立即挂起重连（设备再次广播时系统自动连上）
    if (error) {
        NSLog(@"[VibeGo] battery disconnect: %@", error.localizedDescription);
    }
    [central connectPeripheral:peripheral options:nil];
    [self postChange];
}

#pragma mark - Peripheral

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
    if (error) {
        NSLog(@"[VibeGo] discover services error: %@", error.localizedDescription);
        return;
    }
    for (CBService *svc in peripheral.services) {
        [peripheral discoverCharacteristics:nil forService:svc];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    if (error) {
        NSLog(@"[VibeGo] discover chars error (%@): %@", service.UUID.UUIDString, error.localizedDescription);
        return;
    }
    for (CBCharacteristic *c in service.characteristics) {
        if (!(c.properties & CBCharacteristicPropertyRead)) continue;
        NSString *u = c.UUID.UUIDString.uppercaseString;
        // 只自动读取标准电池 + DIS 只读项 + 当前程序名/配对标识；绝不 setNotify、绝不写入
        if ([u hasPrefix:@"2A19"] || [u hasPrefix:@"2A24"] || [u hasPrefix:@"2A25"] ||
            [u hasPrefix:@"2A26"] || [u hasPrefix:@"2A27"] || [u hasPrefix:@"2A28"] ||
            [u hasPrefix:@"2A29"] || [u hasPrefix:@"7BE94A55"] ||
            [u hasPrefix:@"C97D21D3"] || [u hasPrefix:@"497EEB9E"]) {
            [peripheral readValueForCharacteristic:c];
        }
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)c error:(NSError *)error {
    VGBatteryDevice *d = self.items[peripheral.identifier.UUIDString];
    if (!d || error) return; // 加密错误等：忽略，不触发任何配对动作
    NSData *v = c.value;
    if (v.length == 0) return;
    NSString *u = c.UUID.UUIDString.uppercaseString;

    if ([u hasPrefix:@"2A19"]) {
        uint8_t pct = ((const uint8_t *)v.bytes)[0];
        if (pct <= 100) d.battery = @(pct);
    } else {
        NSString *s = [[NSString alloc] initWithData:v encoding:NSUTF8StringEncoding];
        if (s.length == 0) return;
        if ([u hasPrefix:@"2A29"]) d.manufacturer = s;
        else if ([u hasPrefix:@"2A24"]) d.model = s;
        else if ([u hasPrefix:@"2A25"]) d.serial = s;
        else if ([u hasPrefix:@"2A27"]) d.hardware = s;
        else if ([u hasPrefix:@"2A26"]) d.firmware = s;
        else if ([u hasPrefix:@"2A28"]) d.software = s;
        else if ([u hasPrefix:@"7BE94A55"]) d.currentProgram = s;
        else if ([u hasPrefix:@"C97D21D3"]) d.pairingIDA = s;
        else if ([u hasPrefix:@"497EEB9E"]) d.pairingIDB = s;
    }
    d.updatedAt = [NSDate date];
    [self postChange];
}

- (NSString *)currentProgramName {
    __block NSString *out = @"";
    dispatch_sync(self.q, ^{
        for (VGBatteryDevice *d in self.items.allValues) {
            if (d.currentProgram.length) { out = d.currentProgram; return; }
        }
    });
    return out;
}

- (void)peripheral:(CBPeripheral *)peripheral didReadRSSI:(NSNumber *)RSSI error:(NSError *)error {
    if (error) return;
    VGBatteryDevice *d = self.items[peripheral.identifier.UUIDString];
    if (!d) return;
    d.rssi = RSSI;
    d.updatedAt = [NSDate date];
    [self postChange];
}

#pragma mark - Snapshot

- (NSArray<VGBatteryDevice *> *)devices {
    __block NSArray *out = @[];
    dispatch_sync(self.q, ^{
        out = [self.items.allValues sortedArrayUsingComparator:
               ^NSComparisonResult(VGBatteryDevice *a, VGBatteryDevice *b) {
            return [a.uuidString compare:b.uuidString];
        }];
    });
    return out;
}

@end
