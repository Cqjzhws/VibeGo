//
//  VGStabilityLog.m
//

#import "VGStabilityLog.h"

static NSString *const kVGStabilityKey = @"vg_stability_events_v1";
static const NSUInteger kVGMaxEvents = 500;

@implementation VGStabilityLog

+ (instancetype)shared {
    static VGStabilityLog *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [VGStabilityLog new]; });
    return s;
}

- (NSArray<NSDictionary *> *)events {
    NSArray *a = [[NSUserDefaults standardUserDefaults] arrayForKey:kVGStabilityKey];
    return a ?: @[];
}

- (void)recordConnected:(BOOL)connected ear:(NSUInteger)ear summary:(NSString *)summary {
    NSArray *old = self.events;
    // 状态没变就不重复记
    if (old.count) {
        NSString *lastState = old.firstObject[@"state"];
        BOOL lastConnected = [lastState isEqualToString:@"connected"];
        if (lastConnected == connected) return;
    }

    NSDictionary *e = @{
        @"ts": @([[NSDate date] timeIntervalSince1970]),
        @"state": connected ? @"connected" : @"disconnected",
        @"summary": summary ?: @"",
        @"ear": @(ear)
    };
    NSMutableArray *list = [NSMutableArray arrayWithObject:e];
    [list addObjectsFromArray:old];
    while (list.count > kVGMaxEvents) [list removeLastObject];

    [[NSUserDefaults standardUserDefaults] setObject:list forKey:kVGStabilityKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString *)statisticsText {
    NSArray *events = self.events;
    if (!events.count) return @"还没有记录到连接事件。";

    NSDate *dayAgo = [NSDate dateWithTimeIntervalSinceNow:-24 * 3600];
    NSUInteger disc = 0, conn = 0;
    NSTimeInterval down = 0;
    NSDate *downSince = nil;

    for (NSDictionary *e in [[events reverseObjectEnumerator] allObjects]) {
        NSDate *ts = [NSDate dateWithTimeIntervalSince1970:[e[@"ts"] doubleValue]];
        if ([ts compare:dayAgo] == NSOrderedAscending) continue;
        if ([e[@"state"] isEqualToString:@"disconnected"]) {
            disc++;
            if (!downSince) downSince = ts;
        } else {
            conn++;
            if (downSince) { down += [ts timeIntervalSinceDate:downSince]; downSince = nil; }
        }
    }
    if (downSince) down += [[NSDate date] timeIntervalSinceDate:downSince];

    NSUInteger total = disc + conn;
    double availability = total ? (double)conn / (double)total * 100.0 : 100.0;

    return [NSString stringWithFormat:
            @"近 24 小时\n"
             "  断开次数：%lu\n"
             "  累计离线：%ld 分\n"
             "  连接事件：%lu（在线占比 %.0f%%）\n"
             "  总计记录：%lu 条（上限 500）",
            (unsigned long)disc,
            (long)(down / 60),
            (unsigned long)conn, availability,
            (unsigned long)events.count];
}

- (NSURL *)exportFile {
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"yyyy-MM-dd HH:mm:ss";

    NSMutableString *csv = [NSMutableString stringWithString:@"时间,状态,概要\n"];
    for (NSDictionary *e in [[self.events reverseObjectEnumerator] allObjects]) {
        NSDate *ts = [NSDate dateWithTimeIntervalSince1970:[e[@"ts"] doubleValue]];
        NSString *state = [e[@"state"] isEqualToString:@"connected"] ? @"已连接" : @"已断开";
        NSString *summary = [e[@"summary"] ?: @"" stringByReplacingOccurrencesOfString:@"," withString:@"，"];
        [csv appendFormat:@"%@,%@,%@\n", [f stringFromDate:ts], state, summary];
    }

    NSString *path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)
                      .firstObject stringByAppendingPathComponent:@"VibeGo-稳定性.csv"];
    NSError *err = nil;
    [csv writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if (err) NSLog(@"[VibeGo] 导出失败 %@", err);
    return [NSURL fileURLWithPath:path];
}

@end
