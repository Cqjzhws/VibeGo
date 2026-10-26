#import "VGProbeDevice.h"
#import "VGGattProfile.h"

/// 配对标识 → 耳别。实测于本机 Vibe Go（序列号 JFA7311/JFA5631）：
/// 右耳信息特征 2 = 2FF351、左耳 = 2FCDA8，跨 3 次独立抓包稳定；
/// 换设备/换机器可能不同，故仅作「参考推断」，用户手动设定优先。
static NSDictionary<NSString *, NSString *> *VGPairingIDEarMap(void) {
    static NSDictionary *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ m = @{ @"2FF351": @"右耳", @"2FCDA8": @"左耳" }; });
    return m;
}

@implementation VGProbeDevice

- (NSString *)telemetrySummary {
    if (self.rawValues.count == 0) return @"";
    NSMutableArray *lines = [NSMutableArray array];
    [lines addObject:@"  厂商遥测（只读解码）："];
    NSArray *keys = [[self.rawValues allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *u in keys) {
        NSString *fn = [VGGattProfile friendlyNameForUUID:u];
        NSString *label = fn.length ? fn : u;
        [lines addObject:[NSString stringWithFormat:@"    - %@: %@", label, self.rawValues[u]]];
        NSString *hint = [VGGattProfile hintForUUID:u];
        if (hint.length) [lines addObject:[NSString stringWithFormat:@"       ↳ 推断：%@", hint]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

- (NSString *)displayName {
    NSString *m = self.model.length ? self.model : (self.advertisedName.length ? self.advertisedName : @"Vibe Go");
    NSString *tail = @"";
    if (self.serial.length >= 4) tail = [self.serial substringFromIndex:self.serial.length - 4];
    else if (self.serial.length) tail = self.serial;
    if (tail.length) return [NSString stringWithFormat:@"%@ ·%@", m, tail];
    return m;
}

- (NSString *)currentProgramName {
    NSString *v = self.rawValues[@"7BE94A55-8D91-4592-BC0F-EA3664CCD3A9"];
    if (v.length == 0) return nil;
    return v;
}

- (NSString *)earDisplayName {
    if (self.earLabel.length == 0) return nil;
    // 若用户自定义了备注（VGEarMap 侧以「左耳 · 备注」形式存储），取备注部分
    NSRange r = [self.earLabel rangeOfString:@" · "];
    if (r.location != NSNotFound) {
        NSString *tail = [self.earLabel substringFromIndex:r.location + r.length];
        if (tail.length) return tail;
    }
    return nil;
}

- (NSString *)pairingID {
    NSString *v = self.rawValues[@"C97D21D3-D79D-4DF8-9230-BB33FA805F4E"];
    return v.length ? v : nil;
}

- (NSString *)inferredEarText {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    NSMutableArray<NSString *> *sources = [NSMutableArray array];

    // 依据 1：配对 ID（信息特征 2）
    NSString *byPair = VGPairingIDEarMap()[self.pairingID ?: @""];
    if (byPair.length) { [names addObject:byPair]; [sources addObject:@"配对 ID"]; }

    // 依据 2：广播厂商数据里的侧别字节
    if (self.mfrEarHint.length) { [names addObject:self.mfrEarHint]; [sources addObject:@"广播侧别字节"]; }

    // 依据 3：侧别标志位（信息特征 1：右耳 01 / 左耳 00）
    NSString *flag = self.rawValues[@"8D17AC2F-1D54-4742-A49A-EF4B20784EB3"];
    NSString *byFlag = nil;
    if ([flag isEqualToString:@"01"])      byFlag = @"右耳";
    else if ([flag isEqualToString:@"00"]) byFlag = @"左耳";
    if (byFlag.length) { [names addObject:byFlag]; [sources addObject:@"侧别标志"]; }

    if (names.count == 0) return nil;

    BOOL allSame = YES;
    for (NSString *n in names) {
        if (![n isEqualToString:names[0]]) { allSame = NO; break; }
    }
    if (allSame) {
        return [NSString stringWithFormat:@"%@（%lu 项依据一致：%@）",
                names[0], (unsigned long)names.count,
                [sources componentsJoinedByString:@" + "]];
    }
    return [NSString stringWithFormat:@"依据冲突（%@），请以手动设定为准",
            [sources componentsJoinedByString:@" / "]];
}

- (NSDictionary<NSString *, NSString *> *)snapshotValues {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSString *k in self.rawValues) {
        NSString *v = self.rawValues[k];
        if (v.length == 0) continue;
        out[k] = v;
    }
    return [out copy];
}

- (BOOL)isPairedWith:(VGProbeDevice *)other {
    if (!other) return NO;
    // 验配/配对标识：信息特征 2 与 3 各一份，两耳取值互换即视为配套
    NSString *a2 = self.rawValues[@"C97D21D3-D79D-4DF8-9230-BB33FA805F4E"];
    NSString *b2 = other.rawValues[@"C97D21D3-D79D-4DF8-9230-BB33FA805F4E"];
    NSString *a3 = self.rawValues[@"497EEB9E-B194-4F35-BC82-36FD300482A6"];
    NSString *b3 = other.rawValues[@"497EEB9E-B194-4F35-BC82-36FD300482A6"];
    if (a2.length == 0 || b2.length == 0) return NO;
    // 若两只耳读到完全相同的配对 ID，则不是配套（应是左右各一）
    if ([a2 isEqualToString:b2] && [a3 isEqualToString:b3]) return NO;
    return YES;
}

- (NSString *)summary {
    NSMutableArray *lines = [NSMutableArray array];
    NSString *ear = self.earLabel.length ? [NSString stringWithFormat:@"%@ ", self.earLabel] : @"";
    [lines addObject:[NSString stringWithFormat:@"设备：%@%@（…%@）", ear, self.displayName, self.peripheralID ?: @"??????"]];

    // 侧别推断：手动未设定时才提示，避免干扰用户自己的标注
    if (self.earLabel.length == 0) {
        NSString *inf = [self inferredEarText];
        if (inf.length) [lines addObject:[NSString stringWithFormat:@"  推断耳别：%@", inf]];
    }
    if (self.pairingID.length) {
        NSString *matched = VGPairingIDEarMap()[self.pairingID];
        [lines addObject:[NSString stringWithFormat:@"  配对 ID：%@%@", self.pairingID,
                          matched.length ? [NSString stringWithFormat:@"（已知映射 → %@）", matched] : @"（未收录，本次自动记录）"]];
    }

    if (self.mfrHex.length) {
        [lines addObject:[NSString stringWithFormat:@"  广播数据：%@", self.mfrHex]];
    }

    // —— 与上次探测的差异：定位「哪个特征会动」的核心工具 ——
    if (self.hasBaseline) {
        if (self.changes.count == 0) {
            [lines addObject:[NSString stringWithFormat:@"  ✅ 较上次探测（%@）完全一致：0 项变化", self.baselineDateText ?: @"上次"]];
        } else {
            [lines addObject:[NSString stringWithFormat:@"  ⚠️ 较上次探测（%@）有 %lu 项变化：",
                              self.baselineDateText ?: @"上次", (unsigned long)self.changes.count]];
            for (NSString *c in self.changes) [lines addObject:[NSString stringWithFormat:@"      · %@", c]];
        }
    } else {
        [lines addObject:@"  ℹ️ 已记录本次为基线；下次探测会自动列出「哪些特征变了」"];
    }

    if (self.manufacturer) [lines addObject:[NSString stringWithFormat:@"  厂商：%@", self.manufacturer]];
    if (self.model)        [lines addObject:[NSString stringWithFormat:@"  型号：%@", self.model]];
    if (self.serial)       [lines addObject:[NSString stringWithFormat:@"  序列号：%@", self.serial]];
    if (self.hwRev)        [lines addObject:[NSString stringWithFormat:@"  硬件：%@", self.hwRev]];
    if (self.fwRev)        [lines addObject:[NSString stringWithFormat:@"  固件：%@", self.fwRev]];
    if (self.swRev)        [lines addObject:[NSString stringWithFormat:@"  软件：%@", self.swRev]];
    if (self.battery)      [lines addObject:[NSString stringWithFormat:@"  电量：%@", self.battery]];
    NSString *prog = [self currentProgramName];
    if (prog.length)      [lines addObject:[NSString stringWithFormat:@"  当前程序：%@", prog]];
    [lines addObject:[NSString stringWithFormat:@"  特征数：%ld", (long)self.charCount]];
    NSString *tele = [self telemetrySummary];
    if (tele.length) [lines addObject:tele];
    return [lines componentsJoinedByString:@"\n"];
}

@end
