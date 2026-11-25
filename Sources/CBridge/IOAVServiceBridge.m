#import "IOAVServiceBridge.h"
#import <IOKit/IOKitLib.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreAudio/CoreAudio.h>
#import <AudioToolbox/AudioToolbox.h>

typedef CFTypeRef IOAVService;
extern IOAVService IOAVServiceCreateWithService(CFAllocatorRef allocator, io_service_t service);
extern IOReturn IOAVServiceReadI2C(IOAVService service, uint32_t chipAddress, uint32_t offset, void* outputBuffer, uint32_t outputBufferSize);
extern IOReturn IOAVServiceWriteI2C(IOAVService service, uint32_t chipAddress, uint32_t dataAddress, void* inputBuffer, uint32_t inputBufferSize);

extern int DisplayServicesGetBrightness(CGDirectDisplayID display, float *brightness);
extern int DisplayServicesSetBrightness(CGDirectDisplayID display, float brightness);

@implementation ExternalDisplayInfo
@end

@implementation IOAVServiceBridge {
    IOAVService _avService;
    NSLock *_i2cLock;
}

+ (instancetype)shared {
    static IOAVServiceBridge *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[IOAVServiceBridge alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _avService = NULL;
        _i2cLock = [[NSLock alloc] init];
    }
    return self;
}

- (ExternalDisplayInfo *)detectExternalDisplay {
    [_i2cLock lock];
    if (_avService) {
        CFRelease(_avService);
        _avService = NULL;
    }

    ExternalDisplayInfo *info = [[ExternalDisplayInfo alloc] init];
    info.isConnected = false;
    info.manufacturer = @"HWV";
    info.modelName = @"QSN-CBB";
    info.productCode = 0x6446;

    io_iterator_t iter;
    kern_return_t kr = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iter);
    if (kr != KERN_SUCCESS) {
        [_i2cLock unlock];
        return info;
    }

    io_service_t service;
    while ((service = IOIteratorNext(iter)) != IO_OBJECT_NULL) {
        CFStringRef loc = IORegistryEntrySearchCFProperty(service, kIOServicePlane, CFSTR("Location"), kCFAllocatorDefault, kIORegistryIterateRecursively | kIORegistryIterateParents);
        bool isExternal = (loc && [(__bridge NSString *)loc isEqualToString:@"External"]);
        if (loc) CFRelease(loc);

        if (!isExternal) {
            IOObjectRelease(service);
            continue;
        }

        IOAVService candidate = IOAVServiceCreateWithService(kCFAllocatorDefault, service);
        IOObjectRelease(service);
        if (!candidate) continue;

        uint8_t edid[128] = {0};
        IOReturn edidRet = IOAVServiceReadI2C(candidate, 0x50, 0x00, edid, 128);
        if (edidRet == KERN_SUCCESS && edid[0] == 0x00 && edid[1] == 0xFF) {
            char monitorName[14] = {0};
            for (int d = 54; d <= 108; d += 18) {
                if (edid[d] == 0x00 && edid[d+1] == 0x00 && edid[d+2] == 0x00 && edid[d+3] == 0xFC) {
                    memcpy(monitorName, &edid[d+5], 13);
                    for (int c = 0; c < 13; c++) {
                        if (monitorName[c] == '\n' || monitorName[c] == '\r' || monitorName[c] == ' ') {
                            if (monitorName[c] == '\n' || monitorName[c] == '\r') monitorName[c] = '\0';
                        }
                    }
                }
            }
            uint16_t mfg = (edid[8] << 8) | edid[9];
            char mfgId[4] = {
                (char)(((mfg >> 10) & 0x1F) + 'A' - 1),
                (char)(((mfg >> 5) & 0x1F) + 'A' - 1),
                (char)((mfg & 0x1F) + 'A' - 1),
                0
            };
            uint16_t prodCode = edid[10] | (edid[11] << 8);
            info.manufacturer = [NSString stringWithUTF8String:mfgId] ?: @"HWV";
            NSString *rawModel = [[NSString stringWithUTF8String:monitorName] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            info.modelName = (rawModel.length > 0) ? rawModel : @"QSN-CBB";
            info.productCode = prodCode;
            info.isConnected = true;
            _avService = candidate;
            break;
        } else {
            CFRelease(candidate);
        }
    }
    IOObjectRelease(iter);
    [_i2cLock unlock];
    return info;
}

- (void)invalidateServiceLocked {
    if (_avService != NULL) {
        CFRelease(_avService);
        _avService = NULL;
    }
}

- (bool)ensureServiceLocked {
    if (_avService != NULL) return true;
    io_iterator_t iter;
    kern_return_t kr = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iter);
    if (kr != KERN_SUCCESS) return false;

    io_service_t service;
    while ((service = IOIteratorNext(iter)) != IO_OBJECT_NULL) {
        CFStringRef loc = IORegistryEntrySearchCFProperty(service, kIOServicePlane, CFSTR("Location"), kCFAllocatorDefault, kIORegistryIterateRecursively | kIORegistryIterateParents);
        bool isExternal = (loc && [(__bridge NSString *)loc isEqualToString:@"External"]);
        if (loc) CFRelease(loc);
        if (isExternal) {
            _avService = IOAVServiceCreateWithService(kCFAllocatorDefault, service);
            IOObjectRelease(service);
            break;
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iter);
    return (_avService != NULL);
}

- (bool)readStandardVCP:(uint8_t)vcpCode currentValue:(uint16_t *)currentVal maxValue:(uint16_t *)maxVal {
    [_i2cLock lock];
    if (![self ensureServiceLocked]) {
        [_i2cLock unlock];
        return false;
    }

    uint8_t sendBuf[4];
    sendBuf[0] = 0x82;
    sendBuf[1] = 0x01; // Get VCP Feature
    sendBuf[2] = vcpCode;
    sendBuf[3] = 0x6E ^ 0x51 ^ sendBuf[0] ^ sendBuf[1] ^ sendBuf[2];

    bool success = false;
    for (int retry = 0; retry < 3; retry++) {
        if (![self ensureServiceLocked]) break;
        IOReturn ret = IOAVServiceWriteI2C(_avService, 0x37, 0x51, sendBuf, 4);
        usleep(45000);
        if (ret != KERN_SUCCESS) {
            [self invalidateServiceLocked];
            continue;
        }

        uint8_t recvBuf[12] = {0};
        ret = IOAVServiceReadI2C(_avService, 0x37, 0x51, recvBuf, 11);
        usleep(15000);
        if (ret != KERN_SUCCESS) {
            [self invalidateServiceLocked];
            continue;
        }

        if (recvBuf[2] == 0x02 && recvBuf[3] == 0x00 && recvBuf[4] == vcpCode) {
            if (maxVal) *maxVal = ((uint16_t)recvBuf[6] << 8) | recvBuf[7];
            if (currentVal) *currentVal = ((uint16_t)recvBuf[8] << 8) | recvBuf[9];
            success = true;
            break;
        }
    }
    [_i2cLock unlock];
    return success;
}

- (bool)writeStandardVCP:(uint8_t)vcpCode value:(uint16_t)value {
    [_i2cLock lock];
    if (![self ensureServiceLocked]) {
        [_i2cLock unlock];
        return false;
    }

    uint8_t sendBuf[6];
    sendBuf[0] = 0x84;
    sendBuf[1] = 0x03; // Set VCP Feature
    sendBuf[2] = vcpCode;
    sendBuf[3] = (value >> 8) & 0xFF;
    sendBuf[4] = value & 0xFF;
    sendBuf[5] = 0x6E ^ 0x51 ^ sendBuf[0] ^ sendBuf[1] ^ sendBuf[2] ^ sendBuf[3] ^ sendBuf[4];

    IOReturn ret = IOAVServiceWriteI2C(_avService, 0x37, 0x51, sendBuf, 6);
    if (ret != KERN_SUCCESS) {
        // Re-bind service handle on hotplug/sleep reconnect and retry once
        [self invalidateServiceLocked];
        if ([self ensureServiceLocked]) {
            ret = IOAVServiceWriteI2C(_avService, 0x37, 0x51, sendBuf, 6);
        }
    }
    usleep(50000);
    [_i2cLock unlock];
    return (ret == KERN_SUCCESS);
}

- (bool)readExtendedVCP:(uint8_t)vcp sub1:(uint8_t)sub1 sub2:(uint8_t)sub2 currentValue:(uint16_t *)currentVal maxValue:(uint16_t *)maxVal {
    [_i2cLock lock];
    if (![self ensureServiceLocked]) {
        [_i2cLock unlock];
        return false;
    }

    uint8_t sendBuf[6];
    sendBuf[0] = 0x84;
    sendBuf[1] = 0x01; // Get Extended VCP Feature
    sendBuf[2] = vcp;
    sendBuf[3] = sub1;
    sendBuf[4] = sub2;
    sendBuf[5] = 0x6E ^ 0x51 ^ sendBuf[0] ^ sendBuf[1] ^ sendBuf[2] ^ sendBuf[3] ^ sendBuf[4];

    bool success = false;
    for (int retry = 0; retry < 3; retry++) {
        if (![self ensureServiceLocked]) break;
        IOReturn ret = IOAVServiceWriteI2C(_avService, 0x37, 0x51, sendBuf, 6);
        usleep(60000);
        if (ret != KERN_SUCCESS) {
            [self invalidateServiceLocked];
            continue;
        }

        uint8_t recvBuf[14] = {0};
        ret = IOAVServiceReadI2C(_avService, 0x37, 0x51, recvBuf, 12);
        usleep(25000);
        if (ret != KERN_SUCCESS) {
            [self invalidateServiceLocked];
            continue;
        }

        if (recvBuf[2] == 0x02 && recvBuf[3] == 0x00 && recvBuf[4] == vcp && recvBuf[5] == sub2) {
            if (maxVal) *maxVal = ((uint16_t)recvBuf[6] << 8) | recvBuf[7];
            if (currentVal) *currentVal = ((uint16_t)recvBuf[8] << 8) | recvBuf[9];
            success = true;
            break;
        }
    }
    [_i2cLock unlock];
    return success;
}

- (bool)writeExtendedVCP:(uint8_t)vcp sub1:(uint8_t)sub1 sub2:(uint8_t)sub2 value:(uint16_t)value {
    [_i2cLock lock];
    if (![self ensureServiceLocked]) {
        [_i2cLock unlock];
        return false;
    }

    uint8_t sendBuf[8];
    sendBuf[0] = 0x86;
    sendBuf[1] = 0x03; // Set Extended VCP Feature
    sendBuf[2] = vcp;
    sendBuf[3] = sub1;
    sendBuf[4] = sub2;
    sendBuf[5] = (value >> 8) & 0xFF;
    sendBuf[6] = value & 0xFF;
    sendBuf[7] = 0x6E ^ 0x51 ^ sendBuf[0] ^ sendBuf[1] ^ sendBuf[2] ^ sendBuf[3] ^ sendBuf[4] ^ sendBuf[5] ^ sendBuf[6];

    IOReturn ret = IOAVServiceWriteI2C(_avService, 0x37, 0x51, sendBuf, 8);
    if (ret != KERN_SUCCESS) {
        [self invalidateServiceLocked];
        if ([self ensureServiceLocked]) {
            ret = IOAVServiceWriteI2C(_avService, 0x37, 0x51, sendBuf, 8);
        }
    }
    usleep(65000);
    [_i2cLock unlock];
    return (ret == KERN_SUCCESS);
}

// MARK: - MacBook Built-in Display Brightness (DisplayServices)

- (CGDirectDisplayID)builtInDisplayID {
    uint32_t count = 0;
    CGDirectDisplayID displays[16];
    if (CGGetActiveDisplayList(16, displays, &count) != kCGErrorSuccess) return kCGNullDirectDisplay;
    for (uint32_t i = 0; i < count; i++) {
        if (CGDisplayIsBuiltin(displays[i])) {
            return displays[i];
        }
    }
    return kCGNullDirectDisplay;
}

- (bool)hasBuiltInDisplay {
    return ([self builtInDisplayID] != kCGNullDirectDisplay);
}

- (float)getBuiltInDisplayBrightness {
    CGDirectDisplayID dID = [self builtInDisplayID];
    if (dID == kCGNullDirectDisplay) return -1.0f;
    float b = 0.5f;
    if (DisplayServicesGetBrightness(dID, &b) == 0) {
        return b;
    }
    return -1.0f;
}

- (bool)setBuiltInDisplayBrightness:(float)brightness {
    CGDirectDisplayID dID = [self builtInDisplayID];
    if (dID == kCGNullDirectDisplay) return false;
    float clamped = fmaxf(0.0f, fminf(1.0f, brightness));
    return (DisplayServicesSetBrightness(dID, clamped) == 0);
}

// MARK: - CoreAudio Default Output Device & Built-in Speaker Control

- (AudioDeviceID)defaultOutputDeviceID {
    AudioObjectPropertyAddress addr = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    AudioDeviceID devID = kAudioObjectUnknown;
    UInt32 size = sizeof(devID);
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, NULL, &size, &devID);
    return devID;
}

- (UInt32)transportTypeForDevice:(AudioDeviceID)devID {
    if (devID == kAudioObjectUnknown) return 0;
    UInt32 transport = 0;
    UInt32 size = sizeof(transport);
    AudioObjectPropertyAddress addr = {
        kAudioDevicePropertyTransportType,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    AudioObjectGetPropertyData(devID, &addr, 0, NULL, &size, &transport);
    return transport;
}

- (NSString *)nameForAudioDevice:(AudioDeviceID)devID {
    if (devID == kAudioObjectUnknown) return @"未知扬声器";
    CFStringRef nameRef = NULL;
    UInt32 size = sizeof(nameRef);
    AudioObjectPropertyAddress addr = {
        kAudioObjectPropertyName,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    if (AudioObjectGetPropertyData(devID, &addr, 0, NULL, &size, &nameRef) == noErr && nameRef) {
        NSString *name = [NSString stringWithString:(__bridge NSString *)nameRef];
        CFRelease(nameRef);
        return name;
    }
    return @"扬声器";
}

- (bool)isDefaultAudioOutputExternalMonitor {
    AudioDeviceID devID = [self defaultOutputDeviceID];
    if (devID == kAudioObjectUnknown) return true;
    UInt32 transport = [self transportTypeForDevice:devID];
    // 'dprt' (0x64707274) = DisplayPort, 'hdmi' (0x68646d69) = HDMI
    if (transport == kAudioDeviceTransportTypeDisplayPort || transport == kAudioDeviceTransportTypeHDMI) {
        return true;
    }
    NSString *name = [self nameForAudioDevice:devID];
    if ([name containsString:@"QSN-CBB"] || [name containsString:@"MateView"]) {
        return true;
    }
    return false;
}

- (NSString *)currentAudioOutputDeviceName {
    AudioDeviceID devID = [self defaultOutputDeviceID];
    return [self nameForAudioDevice:devID];
}

- (bool)setDefaultAudioOutputToExternalMonitor:(bool)useExternal {
    AudioObjectPropertyAddress listAddr = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    UInt32 listSize = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &listAddr, 0, NULL, &listSize) != noErr || listSize == 0) return false;
    int devCount = listSize / sizeof(AudioDeviceID);
    AudioDeviceID *devices = calloc(1, listSize);
    if (!devices) return false;
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &listAddr, 0, NULL, &listSize, devices) != noErr) {
        free(devices);
        return false;
    }

    AudioDeviceID targetID = kAudioObjectUnknown;
    for (int i = 0; i < devCount; i++) {
        AudioDeviceID d = devices[i];
        // Check output channels > 0
        AudioObjectPropertyAddress streamAddr = {
            kAudioDevicePropertyStreamConfiguration,
            kAudioDevicePropertyScopeOutput,
            kAudioObjectPropertyElementMain
        };
        UInt32 bufSize = 0;
        if (AudioObjectGetPropertyDataSize(d, &streamAddr, 0, NULL, &bufSize) != noErr || bufSize == 0) continue;
        AudioBufferList *bufList = calloc(1, bufSize);
        if (!bufList) continue;
        int outChannels = 0;
        if (AudioObjectGetPropertyData(d, &streamAddr, 0, NULL, &bufSize, bufList) == noErr) {
            for (UInt32 b = 0; b < bufList->mNumberBuffers; b++) {
                outChannels += bufList->mBuffers[b].mNumberChannels;
            }
        }
        free(bufList);
        if (outChannels == 0) continue;

        UInt32 tr = [self transportTypeForDevice:d];
        NSString *name = [self nameForAudioDevice:d];
        bool isExt = (tr == kAudioDeviceTransportTypeDisplayPort || tr == kAudioDeviceTransportTypeHDMI || [name containsString:@"QSN-CBB"] || [name containsString:@"MateView"]);
        if (useExternal && isExt) {
            targetID = d;
            break;
        } else if (!useExternal && tr == kAudioDeviceTransportTypeBuiltIn) {
            targetID = d;
            break;
        }
    }
    free(devices);

    if (targetID == kAudioObjectUnknown) return false;

    AudioObjectPropertyAddress defAddr = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    OSStatus status = AudioObjectSetPropertyData(kAudioObjectSystemObject, &defAddr, 0, NULL, sizeof(targetID), &targetID);
    return (status == noErr);
}

- (AudioDeviceID)builtInOrActiveNonDDCDeviceID {
    AudioDeviceID defID = [self defaultOutputDeviceID];
    if (![self isDefaultAudioOutputExternalMonitor] && defID != kAudioObjectUnknown) {
        return defID;
    }
    // Find built-in speaker device
    AudioObjectPropertyAddress listAddr = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    UInt32 listSize = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &listAddr, 0, NULL, &listSize) != noErr || listSize == 0) return defID;
    int devCount = listSize / sizeof(AudioDeviceID);
    AudioDeviceID *devices = calloc(1, listSize);
    if (!devices) return defID;
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &listAddr, 0, NULL, &listSize, devices) != noErr) {
        free(devices);
        return defID;
    }

    AudioDeviceID builtInID = defID;
    for (int i = 0; i < devCount; i++) {
        AudioDeviceID d = devices[i];
        AudioObjectPropertyAddress streamAddr = {
            kAudioDevicePropertyStreamConfiguration,
            kAudioDevicePropertyScopeOutput,
            kAudioObjectPropertyElementMain
        };
        UInt32 bufSize = 0;
        if (AudioObjectGetPropertyDataSize(d, &streamAddr, 0, NULL, &bufSize) != noErr || bufSize == 0) continue;
        AudioBufferList *bufList = calloc(1, bufSize);
        if (!bufList) continue;
        int outChannels = 0;
        if (AudioObjectGetPropertyData(d, &streamAddr, 0, NULL, &bufSize, bufList) == noErr) {
            for (UInt32 b = 0; b < bufList->mNumberBuffers; b++) {
                outChannels += bufList->mBuffers[b].mNumberChannels;
            }
        }
        free(bufList);
        if (outChannels == 0) continue;

        if ([self transportTypeForDevice:d] == kAudioDeviceTransportTypeBuiltIn) {
            builtInID = d;
            break;
        }
    }
    free(devices);
    return builtInID;
}

- (float)getSystemAudioVolume {
    AudioDeviceID devID = [self builtInOrActiveNonDDCDeviceID];
    if (devID == kAudioObjectUnknown) return 0.5f;
    Float32 vol = 0.5f;
    UInt32 size = sizeof(vol);
    AudioObjectPropertyAddress addr = {
        kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        kAudioDevicePropertyScopeOutput,
        kAudioObjectPropertyElementMain
    };
    if (AudioObjectGetPropertyData(devID, &addr, 0, NULL, &size, &vol) == noErr) {
        return vol;
    }
    return 0.5f;
}

- (bool)setSystemAudioVolume:(float)volume {
    AudioDeviceID devID = [self builtInOrActiveNonDDCDeviceID];
    if (devID == kAudioObjectUnknown) return false;
    Float32 clamped = fmaxf(0.0f, fminf(1.0f, volume));
    AudioObjectPropertyAddress addr = {
        kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        kAudioDevicePropertyScopeOutput,
        kAudioObjectPropertyElementMain
    };
    return (AudioObjectSetPropertyData(devID, &addr, 0, NULL, sizeof(clamped), &clamped) == noErr);
}

- (bool)getSystemAudioMute {
    AudioDeviceID devID = [self builtInOrActiveNonDDCDeviceID];
    if (devID == kAudioObjectUnknown) return false;
    UInt32 mute = 0;
    UInt32 size = sizeof(mute);
    AudioObjectPropertyAddress addr = {
        kAudioDevicePropertyMute,
        kAudioDevicePropertyScopeOutput,
        kAudioObjectPropertyElementMain
    };
    if (AudioObjectGetPropertyData(devID, &addr, 0, NULL, &size, &mute) == noErr) {
        return (mute != 0);
    }
    return false;
}

- (bool)setSystemAudioMute:(bool)mute {
    AudioDeviceID devID = [self builtInOrActiveNonDDCDeviceID];
    if (devID == kAudioObjectUnknown) return false;
    UInt32 val = mute ? 1 : 0;
    AudioObjectPropertyAddress addr = {
        kAudioDevicePropertyMute,
        kAudioDevicePropertyScopeOutput,
        kAudioObjectPropertyElementMain
    };
    return (AudioObjectSetPropertyData(devID, &addr, 0, NULL, sizeof(val), &val) == noErr);
}

// MARK: - User Idle Time & Display Sleep Assertion Check

- (double)secondsSinceLastUserInput {
    CFTimeInterval idle = CGEventSourceSecondsSinceLastEventType(
        kCGEventSourceStateCombinedSessionState,
        kCGAnyInputEventType
    );
    return (double)idle;
}

- (bool)isDisplaySleepPreventedByActiveMedia {
    CFDictionaryRef assertionsStatus = NULL;
    if (IOPMCopyAssertionsStatus(&assertionsStatus) == kIOReturnSuccess && assertionsStatus != NULL) {
        NSDictionary *dict = (__bridge NSDictionary *)assertionsStatus;
        NSNumber *preventDisplay = dict[(__bridge NSString *)kIOPMAssertionTypePreventUserIdleDisplaySleep];
        NSNumber *noDisplaySleep = dict[(__bridge NSString *)kIOPMAssertionTypeNoDisplaySleep];
        bool active = (preventDisplay && preventDisplay.intValue > 0) || (noDisplaySleep && noDisplaySleep.intValue > 0);
        CFRelease(assertionsStatus);
        return active;
    }
    return false;
}

@end
