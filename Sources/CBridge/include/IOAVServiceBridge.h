#ifndef IOAVServiceBridge_h
#define IOAVServiceBridge_h

#import <Foundation/Foundation.h>
#import <stdint.h>
#import <stdbool.h>

NS_ASSUME_NONNULL_BEGIN

/// Model info read from EDID & IORegistry
@interface ExternalDisplayInfo : NSObject
@property (nonatomic, copy) NSString *manufacturer;
@property (nonatomic, copy) NSString *modelName;
@property (nonatomic, assign) uint16_t productCode;
@property (nonatomic, assign) bool isConnected;
@end

/// Bridge for Apple Silicon DCPAVServiceProxy I2C DDC/CI communication
@interface IOAVServiceBridge : NSObject

+ (instancetype)shared;

/// Discover and connect to the external Huawei MateView GT display
- (ExternalDisplayInfo *)detectExternalDisplay;

/// Read standard 1-byte VCP register (e.g., 0x10 Brightness, 0x12 Contrast, 0x14 ColorTemp, 0x62 Volume, 0x87 Sharpness, 0x8D Mute, 0xC0 UsageTime)
- (bool)readStandardVCP:(uint8_t)vcpCode currentValue:(uint16_t *)currentVal maxValue:(uint16_t *)maxVal;

/// Write standard 1-byte VCP register
- (bool)writeStandardVCP:(uint8_t)vcpCode value:(uint16_t)value;

/// Read Huawei 3-byte extended VCP register (e.g., 0xF8, 0xE1, 0x57 Saturation)
- (bool)readExtendedVCP:(uint8_t)vcp sub1:(uint8_t)sub1 sub2:(uint8_t)sub2 currentValue:(uint16_t *)currentVal maxValue:(uint16_t *)maxVal;

/// Write Huawei 3-byte extended VCP register (6-byte payload: [0x86, 0x03, vcp, sub1, sub2, val_hi, val_lo, crc])
- (bool)writeExtendedVCP:(uint8_t)vcp sub1:(uint8_t)sub1 sub2:(uint8_t)sub2 value:(uint16_t)value;

// MARK: - MacBook Built-in Display Brightness (DisplayServices)
- (bool)hasBuiltInDisplay;
- (float)getBuiltInDisplayBrightness; // 0.0 .. 1.0
- (bool)setBuiltInDisplayBrightness:(float)brightness;

// MARK: - CoreAudio Default Output Device & Built-in Speaker Control
/// Returns true if current default output device is the external monitor (DisplayPort/HDMI/QSN-CBB)
- (bool)isDefaultAudioOutputExternalMonitor;
/// Human-readable name of current default audio output device (e.g. "QSN-CBB" or "MacBook Air扬声器")
- (NSString *)currentAudioOutputDeviceName;
/// Switch macOS default audio output device between External Monitor (true) and MacBook Built-in Speaker (false)
- (bool)setDefaultAudioOutputToExternalMonitor:(bool)useExternal;
/// Read CoreAudio volume (0.0 .. 1.0) of current non-DDC audio device (e.g. MacBook Air speakers or headphones)
- (float)getSystemAudioVolume;
/// Write CoreAudio volume (0.0 .. 1.0) of current non-DDC audio device
- (bool)setSystemAudioVolume:(float)volume;
/// Read CoreAudio mute state of current non-DDC audio device
- (bool)getSystemAudioMute;
/// Write CoreAudio mute state of current non-DDC audio device
- (bool)setSystemAudioMute:(bool)mute;

// MARK: - User Idle Time & Display Sleep Assertion Check
/// Seconds since last keyboard/mouse user input event
- (double)secondsSinceLastUserInput;
/// Returns true if an active app (e.g. video player, meeting) is preventing display sleep
- (bool)isDisplaySleepPreventedByActiveMedia;

@end

NS_ASSUME_NONNULL_END

#endif /* IOAVServiceBridge_h */
