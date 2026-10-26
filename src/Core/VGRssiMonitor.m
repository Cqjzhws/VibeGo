#import "VGRssiMonitor.h"

NSNotificationName const VGRssiDidChangeNotification = @"VGRssiDidChangeNotification";

static const uint16_t kVGWSACompanyID = 0x0295; // WS Audiology = 661
static const NSTimeInterval kVGFreshSeconds = 20.0;

@implementation VGRssiReading
@end

@interface VGRssiMonitor () <CBCentralManagerDelegate>
@property (nonatomic, strong) CBCentralManager *central;
@property (nonatomic, strong) NSMutableDictionary<NSString *, VGRssiReading *> *items;
@property (nonatomic, strong) dispatch_queue_t dataQueue;
@property (nonatomic, strong) dispatch_queue_t btQueue;
@property (nonatomic, assign) NSTimeInterval lastNotify;
@end

@implementation VGRssiMonitor

+ (instancetype)shared {
    static VGRssiMonitor *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [VGRssiMonitor new]; });
    return m;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _items = [NSMutableDictionary dictionary];
        _dataQueue = dispatch_queue_create("vg.rssi.data", DISPATCH_QUEUE_SERIAL);
        _btQueue = dispatch_queue_create("vg.rssi.bt", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)start {
    // ★ Bug #1: 优先订阅 HLLink 的广播转发，避免自己开 scan 争用
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(hlDidDiscover:)
                                                 name:@"HLLinkDidDiscover" object:nil];
    if (self.central) return;
    NSDictionary *opts = @{ CBCentralManagerOptionShowPowerAlertKey: @NO };
    self.central = [[CBCentralManager alloc] initWithDelegate:self
                                                       queue:self.btQueue
                                                     options:opts];
}

- (void)safeScan {
    if (self.central.state != CBManagerStatePoweredOn) return;
    [self.central scanForPeripheralsWithServices:nil
                                        options:@{ CBCentralManagerScanOptionAllowDuplicatesKey: @YES }];
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    if (central.state == CBManagerStatePoweredOn) [self safeScan];
}

- (void)centralManager:(CBCentralManager *)central
    didDiscoverPeripheral:(CBPeripheral *)peripheral
        advertisementData:(NSDictionary<NSString *, id> *)advertisementData
                     RSSI:(NSNumber *)RSSI {
    NSData *mfr = advertisementData[CBAdvertisementDataManufacturerDataKey];
    if (mfr.length < 2) return;
    const uint8_t *b = mfr.bytes;
    uint16_t company = b[0] | (b[1] << 8);
    if (company != kVGWSACompanyID) return;

    NSInteger rssi = RSSI.integerValue;
    if (rssi == 127 || rssi > 0) return;

    NSString *key = peripheral.identifier.UUIDString ?: @"";
    if (key.length == 0) return;
    NSString *localName = advertisementData[CBAdvertisementDataLocalNameKey]
        ?: (peripheral.name ?: @"Vibe");
    NSString *shortKey = key.length > 8 ? [key substringFromIndex:key.length - 8] : key;

    dispatch_sync(self.dataQueue, ^{
        VGRssiReading *r = self.items[key];
        if (!r) {
            r = [VGRssiReading new];
            r.key = shortKey;
            r.avgRSSI = rssi;
            r.samples = 0;
            self.items[key] = r;
        }
        r.localName = localName;
        r.lastRSSI = rssi;
        r.avgRSSI = r.samples == 0 ? rssi : (r.avgRSSI * 0.7 + rssi * 0.3);
        r.samples += 1;
        r.updatedAt = [NSDate date];
    });

    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if (now - self.lastNotify > 2.0) {
        self.lastNotify = now;
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                [[NSNotificationCenter defaultCenter]
                    postNotificationName:VGRssiDidChangeNotification object:nil];
            } @catch (NSException *e) {
                NSLog(@"[VibeGo] notify exception: %@", e);
            }
        });
    }
}

// ★ Bug #1: 订阅 HLLink 广播转发，避免重复 scan
- (void)hlDidDiscover:(NSNotification *)note {
    NSDictionary *info = note.userInfo;
    CBPeripheral *peripheral = info[@"peripheral"];
    NSDictionary *advertisementData = info[@"advertisementData"] ?: @{};
    NSNumber *RSSI = info[@"RSSI"] ?: @0;
    if (!peripheral) return;
    [self centralManager:nil
   didDiscoverPeripheral:peripheral
       advertisementData:advertisementData
                    RSSI:RSSI];
}

- (NSArray<VGRssiReading *> *)readings {
    __block NSArray *out = @[];
    dispatch_sync(self.dataQueue, ^{
        out = [self.items.allValues sortedArrayUsingComparator:
               ^NSComparisonResult(VGRssiReading *a, VGRssiReading *b) {
            return a.avgRSSI < b.avgRSSI ? NSOrderedDescending : NSOrderedAscending;
        }];
    });
    return out;
}

- (NSUInteger)freshDeviceCount {
    __block NSUInteger n = 0;
    dispatch_sync(self.dataQueue, ^{
        NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-kVGFreshSeconds];
        for (VGRssiReading *r in self.items.allValues) {
            if ([r.updatedAt compare:cutoff] == NSOrderedDescending) n++;
        }
    });
    return n;
}

+ (NSString *)qualityLabel:(double)rssi {
    if (rssi >= -85) return @"优";
    if (rssi >= -95) return @"正常·低功耗";
    if (rssi >= -102) return @"偏弱";
    return @"弱·警惕";
}

+ (UIColor *)qualityColor:(double)rssi {
    if (rssi >= -85) return [UIColor colorWithRed:0.30 green:0.85 blue:0.60 alpha:1];
    if (rssi >= -95) return [UIColor colorWithRed:0.30 green:0.80 blue:0.85 alpha:1];
    if (rssi >= -102) return [UIColor colorWithRed:0.98 green:0.72 blue:0.30 alpha:1];
    return [UIColor colorWithRed:0.98 green:0.42 blue:0.36 alpha:1];
}

+ (NSInteger)signalBars:(double)rssi {
    if (rssi >= -85) return 4;
    if (rssi >= -95) return 3;
    if (rssi >= -102) return 2;
    return 1;
}

@end
