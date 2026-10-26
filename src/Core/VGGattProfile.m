#import "VGGattProfile.h"

@implementation VGGattProfile

// 单条档案：@[@"UUID", @"友好名", @(category)]
static NSArray<NSArray *> *VGProfileRows(void) {
    static NSArray *rows;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        rows = @[
            // —— SIG 设备信息 (0x180A) ——
            @[@"2A29", @"厂商名 Manufacturer", @(VGCharCategoryDeviceInfo)],
            @[@"2A24", @"型号 Model",          @(VGCharCategoryDeviceInfo)],
            @[@"2A25", @"序列号 Serial",       @(VGCharCategoryDeviceInfo)],
            @[@"2A27", @"硬件版本 HW Rev",     @(VGCharCategoryDeviceInfo)],
            @[@"2A26", @"固件版本 FW Rev",     @(VGCharCategoryDeviceInfo)],
            @[@"2A28", @"软件版本 SW Rev",     @(VGCharCategoryDeviceInfo)],
            @[@"2A23", @"System ID",          @(VGCharCategoryDeviceInfo)],
            @[@"2A50", @"PnP ID",             @(VGCharCategoryDeviceInfo)],
            // —— SIG 电量 (0x180F) ——
            @[@"2A19", @"电量 Battery",        @(VGCharCategoryBattery)],

            // —— 私有·信息类 (17, 推测只读) ——
            @[@"8D17AC2F-1D54-4742-A49A-EF4B20784EB3", @"信息特征 1",  @(VGCharCategoryInfo)],
            @[@"C97D21D3-D79D-4DF8-9230-BB33FA805F4E", @"信息特征 2",  @(VGCharCategoryInfo)],
            @[@"497EEB9E-B194-4F35-BC82-36FD300482A6", @"信息特征 3",  @(VGCharCategoryInfo)],
            @[@"21FF4275-C41D-4486-A0E3-DC11138BCDE6", @"信息特征 4",  @(VGCharCategoryInfo)],
            @[@"16438C66-E95A-4C6F-8117-A6B745BD86FC", @"信息特征 5",  @(VGCharCategoryInfo)],
            @[@"76B3DB1F-44C4-46CC-A7B5-E9CE7DFBEF50", @"信息特征 6",  @(VGCharCategoryInfo)],
            @[@"98924A39-6559-40A8-B302-3C8E40DBF834", @"信息特征 7",  @(VGCharCategoryInfo)],
            @[@"E24FAC83-B5A8-4B9B-8FDA-803FFFB0C21C", @"信息特征 8",  @(VGCharCategoryInfo)],
            @[@"D28617FE-0AD5-40C5-A04A-BC89051FF755", @"信息特征 9",  @(VGCharCategoryInfo)],
            @[@"5F35C43D-E0F4-4DA9-87E6-9719982CD25E", @"信息特征 10", @(VGCharCategoryInfo)],
            @[@"353ECC73-4D2C-421B-AC1C-8DCB35CD4477", @"信息特征 11", @(VGCharCategoryInfo)],
            @[@"DCBE7A3E-A742-4527-AEB5-CD8DEE63167F", @"信息特征 12", @(VGCharCategoryInfo)],
            @[@"BBA1C7F1-B445-4657-90C3-8DBD97361A0C", @"信息特征 13", @(VGCharCategoryInfo)],
            @[@"E5892EBE-97D0-4F97-8F8E-CB85D16A4CC1", @"信息特征 14", @(VGCharCategoryInfo)],
            @[@"60415E72-C345-417A-BB2B-BBBA95B2C9A3", @"信息特征 15", @(VGCharCategoryInfo)],
            @[@"6E557876-CCC4-40E0-8C2D-651542C5AD3D", @"信息特征 16", @(VGCharCategoryInfo)],
            @[@"BC6829C4-B750-48E6-B6F4-48EC866A1EFB", @"信息特征 17", @(VGCharCategoryInfo)],

            // —— 私有·配置类 (15, 推测 R/W) ——
            @[@"F3F594F9-E210-48F3-85E2-4B0CF235A9D3", @"配置特征 1",  @(VGCharCategoryConfig)],
            @[@"6AC46200-24EA-46D8-A136-81133C65840A", @"配置特征 2",  @(VGCharCategoryConfig)],
            @[@"A391C6F1-20BB-495A-ABBF-2017098FBC61", @"配置特征 3",  @(VGCharCategoryConfig)],
            @[@"A28B6BE1-2FA4-42F8-AEB2-B15A1DBD837A", @"配置特征 4",  @(VGCharCategoryConfig)],
            @[@"7BE94A55-8D91-4592-BC0F-EA3664CCD3A9", @"当前程序名", @(VGCharCategoryConfig)],
            @[@"9C12A3DB-9CE8-4865-A217-D394B3BC9311", @"配置特征 6",  @(VGCharCategoryConfig)],
            @[@"4656D3AC-C2DF-4096-96E7-713580B69CCD", @"配置特征 7",  @(VGCharCategoryConfig)],
            @[@"68BFA64E-3209-4172-B117-F7EAFCE17414", @"配置特征 8",  @(VGCharCategoryConfig)],
            @[@"535442F7-0FF7-4FEC-9780-742F3EB00EDA", @"配置特征 9",  @(VGCharCategoryConfig)],
            @[@"1454E9D6-F658-4190-8589-22AA9E3021EB", @"配置特征 10", @(VGCharCategoryConfig)],
            @[@"9215A295-B813-483F-9F85-B700D0B7BC75", @"配置特征 11", @(VGCharCategoryConfig)],
            @[@"50632720-4C0F-4BC4-960A-2404BDFDFBCA", @"配置特征 12", @(VGCharCategoryConfig)],
            @[@"51939BB6-A635-4B1E-903B-76CD9DFF3FAC", @"配置特征 13", @(VGCharCategoryConfig)],
            @[@"EBEE6F69-70B6-4BB9-B13B-9BA84953C233", @"配置特征 14", @(VGCharCategoryConfig)],
            @[@"8B820C6D-0F0C-40BB-B422-3770FA72A864", @"配置特征 15", @(VGCharCategoryConfig)],

            // —— 私有·状态/事件 (5, 推测 R/N) ——
            @[@"24E1DFF3-AE90-41BF-BFBD-2CF8DF42BF87", @"状态/事件 1", @(VGCharCategoryStatus)],
            @[@"ADC3023D-BFD2-43FD-86F6-7AE05A619092", @"状态/事件 2", @(VGCharCategoryStatus)],
            @[@"42E940EF-98C8-4CCD-A557-30425295AF89", @"状态/事件 3", @(VGCharCategoryStatus)],
            @[@"58BBCCC5-5A57-4E00-98D5-18C6A0408DFD", @"状态/事件 4", @(VGCharCategoryStatus)],
            @[@"D01AB591-D282-4EF5-B83B-538E0BF32D85", @"状态/事件 5", @(VGCharCategoryStatus)],

            // —— 私有·命令 (5, 推测 W/WW) ——
            @[@"6D5758A1-D4AF-4B32-B95E-1E6992454F4F", @"命令特征 1",  @(VGCharCategoryCommand)],
            @[@"786FF607-774D-49D6-80A5-A17E08823D91", @"命令特征 2",  @(VGCharCategoryCommand)],
            @[@"6EFAB52E-3002-4764-9430-016CEF4DFC87", @"命令特征 3",  @(VGCharCategoryCommand)],
            @[@"62DCC92F-59C2-4228-9A11-C85F18773530", @"命令特征 4",  @(VGCharCategoryCommand)],
            @[@"8B8276E8-0F0C-40BB-B422-3770FA72A864", @"命令特征 5",  @(VGCharCategoryCommand)],

            // —— 私有·音频上行 (1, 推测 N) ——
            @[@"34DFC7CB-5252-430B-BA6D-DF2FE87914E7", @"音频上行",    @(VGCharCategoryAudioUp)],

            // —— 私有·厂商流通道 (8, C8F7xxxx, 推测流媒体) ——
            @[@"C8F7FAC0-21B2-45B8-87F8-BD49A13EFF49", @"流通道 1",   @(VGCharCategoryVendorStream)],
            @[@"C8F714D6-21B2-45B8-87F8-BD49A13EFF49", @"流通道 2",   @(VGCharCategoryVendorStream)],
            @[@"C8F79C9A-21B2-45B8-87F8-BD49A13EFF49", @"流通道 3",   @(VGCharCategoryVendorStream)],
            @[@"C8F73DC3-21B2-45B8-87F8-BD49A13EFF49", @"流通道 4",   @(VGCharCategoryVendorStream)],
            @[@"C8F7A8E4-21B2-45B8-87F8-BD49A13EFF49", @"流通道 5",   @(VGCharCategoryVendorStream)],
            @[@"C8F7A68A-21B2-45B8-87F8-BD49A13EFF49", @"流通道 6",   @(VGCharCategoryVendorStream)],
            @[@"C8F723DA-21B2-45B8-87F8-BD49A13EFF49", @"流通道 7",   @(VGCharCategoryVendorStream)],
            @[@"C8F7690C-21B2-45B8-87F8-BD49A13EFF49", @"流通道 8",   @(VGCharCategoryVendorStream)],
        ];
    });
    return rows;
}

static NSDictionary<NSString *, NSArray<NSNumber *> *> *VGProfileMap(void) {
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *m = [NSMutableDictionary dictionary];
        for (NSArray *row in VGProfileRows()) {
            [m setObject:@[row[1], row[2]] forKey:[row[0] uppercaseString]];
        }
        map = [m copy];
    });
    return map;
}

// 基于多份只读抓包（vg_gatt_20261016_12xxxx / 140322）的语义推断——纯假设，改动协议前须再抓包确认
// （历史遗留的重复表 VGHints() 已移除，语义推断统一以本表 VGHintMap() 为准）

+ (NSString *)friendlyNameForUUID:(NSString *)uuid {
    if (!uuid) return nil;
    NSArray *v = VGProfileMap()[[uuid uppercaseString]];
    return v ? v[0] : nil;
}

+ (VGCharCategory)categoryForUUID:(NSString *)uuid {
    if (!uuid) return VGCharCategoryUnknown;
    NSArray *v = VGProfileMap()[[uuid uppercaseString]];
    return v ? (VGCharCategory)[v[1] integerValue] : VGCharCategoryUnknown;
}

+ (NSString *)categoryName:(VGCharCategory)category {
    switch (category) {
        case VGCharCategoryDeviceInfo:   return @"设备信息";
        case VGCharCategoryBattery:      return @"电量";
        case VGCharCategoryInfo:         return @"信息";
        case VGCharCategoryConfig:       return @"配置";
        case VGCharCategoryStatus:       return @"状态/事件";
        case VGCharCategoryCommand:      return @"命令";
        case VGCharCategoryAudioUp:      return @"音频上行";
        case VGCharCategoryAudioDown:    return @"音频下行";
        case VGCharCategoryVendorStream: return @"厂商流通道";
        default:                         return @"未知";
    }
}

// 语义推断表：来自 2026-10-16 多次只读抓包的交叉观察，全部为「推测」，未经写入验证。
// 依据：同一只耳朵多次读数稳定；左右耳的差异集中在特定字节；可打印字符串直接泄露语义。
static NSDictionary<NSString *, NSString *> *VGHintMap(void) {
    static NSDictionary *h;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        h = @{
            @"7BE94A55-8D91-4592-BC0F-EA3664CCD3A9":
                @"【已验证】当前助听程序名。两次抓包取值不同（\"Program Et -- Einstellung Eins\" → \"Universal\"），确认随程序切换而变；左右耳取值一致。",
            @"C97D21D3-D79D-4DF8-9230-BB33FA805F4E":
                @"【配对 ID】每只耳固定的 3 字节码：右耳 2FF351 / 左耳 2FCDA8，跨 3 次抓包稳定，可用来判定左右耳。",
            @"497EEB9E-B194-4F35-BC82-36FD300482A6":
                @"【配对 ID 第二份】与「信息特征 2」左右互换：右耳 2FCDA8 / 左耳 2FF351。两耳取值互换即说明是配套的一对。",
            @"5F35C43D-E0F4-4DA9-87E6-9719982CD25E":
                @"【配对 ID 副本】取值与「信息特征 2」完全相同（右耳 2FF351 / 左耳 2FCDA8），冗余备份。",
            @"353ECC73-4D2C-421B-AC1C-8DCB35CD4477":
                @"【配对 ID 副本】取值与「信息特征 3」完全相同（右耳 2FCDA8 / 左耳 2FF351），冗余备份。",
            @"8D17AC2F-1D54-4742-A49A-EF4B20784EB3":
                @"【侧别标志】信息特征 1：右耳 01 / 左耳 00（与「信息特征 9」同规律），疑为耳别/主从位，已用于耳别自动推断。",
            @"D28617FE-0AD5-40C5-A04A-BC89051FF755":
                @"【侧别标志】信息特征 9：右耳 01 / 左耳 00，规律与「信息特征 1」一致，冗余备份。",
            @"ADC3023D-BFD2-43FD-86F6-7AE05A619092":
                @"【状态标志】4 字节，首字节随连接变化（实测右耳 0F→10、左耳 1B→1C），后两字节恒为 05 00。",
            @"42E940EF-98C8-4CCD-A557-30425295AF89":
                @"【状态标志】与「状态/事件 2」逐字节同值（同一份数据的镜像），同样会随连接变化。",
            @"58BBCCC5-5A57-4E00-98D5-18C6A0408DFD":
                @"【状态块】6 字节，跨 3 次抓包恒为 00 0F 00 12 00 00，稳定未解读。",
            @"BC6829C4-B750-48E6-B6F4-48EC866A1EFB":
                @"【状态块】8 字节，仅第 4 字节会变（实测 0x38 → 0x30，即 bit3 翻转），疑为运行/音频流状态标志，待确认。",
            @"C8F7FAC0-21B2-45B8-87F8-BD49A13EFF49":
                @"【厂商流通道 1】20 字节二进制快照，含左右耳不同的尾部字节；确认该通道承载厂商数据/音频相关负载。",
            @"F3F594F9-E210-48F3-85E2-4B0CF235A9D3":
                @"【配置字节】恒为 0x88（两耳一致、跨次一致），未解读。",
            @"24E1DFF3-AE90-41BF-BFBD-2CF8DF42BF87":
                @"【状态/事件 1】两耳恒为 0x0A，未解读。",
            @"D01AB591-D282-4EF5-B83B-538E0BF32D85":
                @"【状态/事件 5】3 字节，跨 3 次抓包恒为 03 80 00，稳定未解读。",
        };
    });
    return h;
}

+ (NSString *)hintForUUID:(NSString *)uuid {
    if (!uuid) return nil;
    return VGHintMap()[[uuid uppercaseString]];
}

+ (NSArray<CBUUID *> *)vendorServiceUUIDs {
    static NSArray *a;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *s = @[
            @"7D74F4BD-C74A-4431-862C-CCE884371592",
            @"56772EAF-2153-4F74-ACF3-4368D99FBF5A",
            @"0A23AE62-C4C2-43D1-87B1-E8C83839A063",
            @"C8F777D0-21B2-45B8-87F8-BD49A13EFF49",
            @"C8F7A831-21B2-45B8-87F8-BD49A13EFF49",
            @"D1D4DC2A-215F-44D2-B44C-0F4DE3C91AF2",
        ];
        NSMutableArray *out = [NSMutableArray array];
        for (NSString *u in s) [out addObject:[CBUUID UUIDWithString:u]];
        a = [out copy];
    });
    return a;
}

+ (NSArray<CBUUID *> *)vendorStreamCharacteristicUUIDs {
    static NSArray *a;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *s = @[
            @"C8F7FAC0-21B2-45B8-87F8-BD49A13EFF49",
            @"C8F714D6-21B2-45B8-87F8-BD49A13EFF49",
            @"C8F79C9A-21B2-45B8-87F8-BD49A13EFF49",
            @"C8F73DC3-21B2-45B8-87F8-BD49A13EFF49",
            @"C8F7A8E4-21B2-45B8-87F8-BD49A13EFF49",
            @"C8F7A68A-21B2-45B8-87F8-BD49A13EFF49",
            @"C8F723DA-21B2-45B8-87F8-BD49A13EFF49",
            @"C8F7690C-21B2-45B8-87F8-BD49A13EFF49",
        ];
        NSMutableArray *out = [NSMutableArray array];
        for (NSString *u in s) [out addObject:[CBUUID UUIDWithString:u]];
        a = [out copy];
    });
    return a;
}

+ (NSInteger)knownCharacteristicCount {
    return (NSInteger)VGProfileMap().count;
}

@end
