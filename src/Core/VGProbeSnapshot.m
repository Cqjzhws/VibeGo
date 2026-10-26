#import "VGProbeSnapshot.h"
#import "VGGattProfile.h"

static NSString * const kVGProbeSnapshotStoreKey = @"VGProbeSnapshotStore_v1";

@implementation VGProbeSnapshot

+ (NSMutableDictionary *)store {
    NSDictionary *d = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kVGProbeSnapshotStoreKey];
    return d ? [d mutableCopy] : [NSMutableDictionary dictionary];
}

+ (void)writeStore:(NSDictionary *)store {
    [[NSUserDefaults standardUserDefaults] setObject:store forKey:kVGProbeSnapshotStoreKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (NSString *)deviceKeyWithSerial:(NSString *)serial fallback:(NSString *)fallback {
    if (serial.length) return [NSString stringWithFormat:@"SN:%@", serial];
    if (fallback.length) return [NSString stringWithFormat:@"ID:%@", fallback];
    return @"UNKNOWN";
}

+ (NSDictionary<NSString *, NSString *> *)loadForDeviceKey:(NSString *)key {
    if (key.length == 0) return @{};
    NSDictionary *entry = [self store][key];
    NSDictionary *vals = entry[@"values"];
    return [vals isKindOfClass:[NSDictionary class]] ? vals : @{};
}

+ (NSString *)savedDateTextForDeviceKey:(NSString *)key {
    if (key.length == 0) return nil;
    NSNumber *ts = [self store][key][@"at"];
    if (![ts isKindOfClass:[NSNumber class]]) return nil;
    NSDate *d = [NSDate dateWithTimeIntervalSince1970:ts.doubleValue];
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"MM-dd HH:mm";
    return [f stringFromDate:d];
}

+ (void)saveValues:(NSDictionary<NSString *, NSString *> *)values forDeviceKey:(NSString *)key {
    if (key.length == 0) return;
    NSMutableDictionary *store = [self store];
    store[key] = @{ @"at": @([[NSDate date] timeIntervalSince1970]),
                    @"values": values ?: @{} };
    [self writeStore:store];
}

+ (NSArray<NSString *> *)changesFromOld:(NSDictionary<NSString *, NSString *> *)old
                                  toNew:(NSDictionary<NSString *, NSString *> *)now {
    NSMutableArray *out = [NSMutableArray array];
    if (old.count == 0) return out;
    NSMutableSet *allKeys = [NSMutableSet setWithArray:old.allKeys];
    [allKeys addObjectsFromArray:now.allKeys];
    NSArray *sorted = [[allKeys allObjects] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *u in sorted) {
        NSString *a = old[u] ?: @"";
        NSString *b = now[u] ?: @"";
        if ([a isEqualToString:b]) continue;
        NSString *fn = [VGGattProfile friendlyNameForUUID:u];
        NSString *label = fn.length ? fn : u;
        [out addObject:[NSString stringWithFormat:@"%@：%@ → %@",
                        label, a.length ? a : @"(空)", b.length ? b : @"(空)"]];
    }
    return out;
}

+ (void)resetAll {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kVGProbeSnapshotStoreKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end
