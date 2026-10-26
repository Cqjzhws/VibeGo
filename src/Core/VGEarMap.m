#import "VGEarMap.h"

NSNotificationName const VGEarMapDidChangeNotification = @"VGEarMapDidChangeNotification";

static NSString *const kVGStoreKey = @"vg_ear_map";
static NSString *const kVGAutoKey  = @"vg_ear_auto_map";

@implementation VGEarMap

+ (NSMutableDictionary<NSString *, NSString *> *)store {
    NSDictionary *raw = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kVGStoreKey];
    return [NSMutableDictionary dictionaryWithDictionary:raw ?: @{}];
}

+ (NSMutableDictionary<NSString *, NSString *> *)autoStore {
    NSDictionary *raw = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kVGAutoKey];
    return [NSMutableDictionary dictionaryWithDictionary:raw ?: @{}];
}

+ (void)save:(NSDictionary<NSString *, NSString *> *)store {
    [[NSUserDefaults standardUserDefaults] setObject:store forKey:kVGStoreKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self postChange];
}

+ (void)saveAuto:(NSDictionary<NSString *, NSString *> *)store {
    [[NSUserDefaults standardUserDefaults] setObject:store forKey:kVGAutoKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self postChange];
}

+ (void)postChange {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:VGEarMapDidChangeNotification object:nil];
    });
}

+ (NSString *)normalizeEar:(NSString *)earLabel {
    if ([earLabel isEqualToString:@"左耳"] || [earLabel isEqualToString:@"L"]) return @"L";
    if ([earLabel isEqualToString:@"右耳"] || [earLabel isEqualToString:@"R"]) return @"R";
    return nil;
}

+ (NSString *)displayEar:(NSString *)v {
    if ([v isEqualToString:@"L"]) return @"左耳";
    if ([v isEqualToString:@"R"]) return @"右耳";
    return @"";
}

+ (NSString *)earLabelForKey:(NSString *)uuidOrTail {
    if (uuidOrTail.length == 0) return @"";
    // 1) 自动映射优先（设备自报，可信）
    NSDictionary *auto = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kVGAutoKey];
    for (NSString *k in auto) {
        if ([k isEqualToString:uuidOrTail] || [k hasSuffix:uuidOrTail] ||
            [uuidOrTail hasSuffix:k]) {
            return [self displayEar:auto[k]];
        }
    }
    // 2) 回退手动映射
    NSDictionary *raw = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kVGStoreKey];
    for (NSString *full in raw) {
        if ([full isEqualToString:uuidOrTail] || [full hasSuffix:uuidOrTail]) {
            return [self displayEar:raw[full]];
        }
    }
    return @"";
}

+ (void)setEar:(NSString *)earLabel forFullUUID:(NSString *)fullUUID {
    NSString *v = [self normalizeEar:earLabel];
    if (!v || fullUUID.length == 0) return;
    NSMutableDictionary *store = [self store];
    store[fullUUID] = v;
    [self save:store];
}

+ (void)clearForFullUUID:(NSString *)fullUUID {
    if (fullUUID.length == 0) return;
    NSMutableDictionary *store = [self store];
    [store removeObjectForKey:fullUUID];
    [self save:store];
}

+ (void)setAutoEar:(NSString *)earLabel forKey:(NSString *)key {
    NSString *v = [self normalizeEar:earLabel];
    if (!v || key.length == 0) return;
    NSMutableDictionary *store = [self autoStore];
    store[key] = v;
    [self saveAuto:store];
}

+ (void)clearAutoEarForKey:(NSString *)key {
    if (key.length == 0) return;
    NSMutableDictionary *store = [self autoStore];
    [store removeObjectForKey:key];
    [self saveAuto:store];
}

+ (NSDictionary<NSString *, NSString *> *)snapshot {
    return [self store];
}

+ (NSDictionary<NSString *, NSString *> *)autoSnapshot {
    return [self autoStore];
}

@end
