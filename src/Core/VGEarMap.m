#import "VGEarMap.h"

NSNotificationName const VGEarMapDidChangeNotification = @"VGEarMapDidChangeNotification";

static NSString *const kVGStoreKey = @"vg_ear_map";

@implementation VGEarMap

+ (NSMutableDictionary<NSString *, NSString *> *)store {
    NSDictionary *raw = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kVGStoreKey];
    return [NSMutableDictionary dictionaryWithDictionary:raw ?: @{}];
}

+ (void)save:(NSDictionary<NSString *, NSString *> *)store {
    [[NSUserDefaults standardUserDefaults] setObject:store forKey:kVGStoreKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:VGEarMapDidChangeNotification object:nil];
    });
}

+ (NSString *)earLabelForKey:(NSString *)uuidOrTail {
    if (uuidOrTail.length == 0) return @"";
    NSDictionary *raw = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kVGStoreKey];
    for (NSString *full in raw) {
        if ([full isEqualToString:uuidOrTail] || [full hasSuffix:uuidOrTail]) {
            return [raw[full] isEqualToString:@"L"] ? @"左耳" : @"右耳";
        }
    }
    return @"";
}

+ (void)setEar:(NSString *)earLabel forFullUUID:(NSString *)fullUUID {
    if (earLabel.length == 0 || fullUUID.length == 0) return;
    NSMutableDictionary *store = [self store];
    store[fullUUID] = [earLabel isEqualToString:@"左耳"] ? @"L" : @"R";
    [self save:store];
}

+ (void)clearForFullUUID:(NSString *)fullUUID {
    if (fullUUID.length == 0) return;
    NSMutableDictionary *store = [self store];
    [store removeObjectForKey:fullUUID];
    [self save:store];
}

+ (NSDictionary<NSString *, NSString *> *)snapshot {
    return [self store];
}

@end
