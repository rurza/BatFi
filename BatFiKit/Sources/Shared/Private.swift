import Foundation

public class Private {
    public static let kIOPMDynamicStoreSettingsKey = "State:/IOKit/PowerManagement/CurrentSettings"
    
    public static let kIOPMLowPowerModeKey = "LowPowerMode"
    public static let kIOPMHighPowerModeKey = "HighPowerMode"
    
    public static let (IOPMCopyPMPreferences, IOPMFeatureIsAvailable, IOPMSetPMPreferences) = {
        var IOPMCopyPMPreferencesPointer: UnsafeMutableRawPointer?
        var IOPMFeatureIsAvailablePointer: UnsafeMutableRawPointer?
        var IOPMSetPMPreferencesPointer: UnsafeMutableRawPointer?
        if let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) {
            IOPMCopyPMPreferencesPointer = dlsym(handle, "IOPMCopyPMPreferences")
            IOPMFeatureIsAvailablePointer = dlsym(handle, "IOPMFeatureIsAvailable")
            IOPMSetPMPreferencesPointer = dlsym(handle, "IOPMSetPMPreferences")
            dlclose(handle)
        }
        let IOPMCopyPMPreferences =
        unsafeBitCast(IOPMCopyPMPreferencesPointer, to: (@convention(c) () -> Unmanaged<CFMutableDictionary>)?.self)
        let IOPMFeatureIsAvailable =
        unsafeBitCast(IOPMFeatureIsAvailablePointer, to: (@convention(c) (_ feature: CFString, _ power_source: CFString) -> Bool)?.self)
        let IOPMSetPMPreferences =
        unsafeBitCast(IOPMSetPMPreferencesPointer, to: (@convention(c) (_ ESPrefs: CFDictionary) -> IOReturn)?.self)
        return (IOPMCopyPMPreferences, IOPMFeatureIsAvailable, IOPMSetPMPreferences)
    }()
}
