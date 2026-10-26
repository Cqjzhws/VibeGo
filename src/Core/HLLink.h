//
//  HLLink.h — Vibe Go 助听器 BLE 连接管理
//
//  公开接口（其他模块复用连接 / CBCentralManager）
//

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>

NS_ASSUME_NONNULL_BEGIN

@interface HLLink : NSObject <CBCentralManagerDelegate, CBPeripheralDelegate>
+ (instancetype)shared;
- (void)start;
- (NSArray<CBPeripheral *> *)connectedPeripherals;
- (BOOL)applyMute:(BOOL)mute;
- (BOOL)holdActive;
- (NSString *)statusText;
@end

// 外部控制
void HLSetCallMode(BOOL on);
void HLReapplyNow(void);
void HLSetPlayingProvider(BOOL (^p)(void));

NS_ASSUME_NONNULL_END
