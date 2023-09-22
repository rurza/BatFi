import AppShared
import Clients
import Dependencies
import Foundation
import SecureXPC
import Shared
import SystemConfiguration

extension PowerSettingClient: DependencyKey {
    public static var liveValue: PowerSettingClient {
        func powerSettingInfo(_ store: SCDynamicStore) -> PowerSettingInfo? {
            guard 
                let settings = SCDynamicStoreCopyValue(store, Private.kIOPMDynamicStoreSettingsKey as CFString) as? [String: Any],
                let lowPowerMode = settings[Private.kIOPMLowPowerModeKey] as? UInt8,
                let powerMode = PowerMode(rawValue: lowPowerMode)
            else {
                return nil
            }
            let supportsHighPowerMode = settings[Private.kIOPMHighPowerModeKey] != nil
            return PowerSettingInfo(powerMode: powerMode, supportsHighPowerMode: supportsHighPowerMode)
        }
        
        func createClient() -> XPCClient {
            XPCClient.forMachService(
                named: Constant.helperBundleIdentifier,
                withServerRequirement: try! .sameTeamIdentifier
            )
        }
        
        let observer = Observer()
        let client = Self(
            powerSettingInfoChanges: {
                AsyncStream { continuation in
                    guard let observer else {
                        return
                    }
                    if let info = powerSettingInfo(observer.store) {
                        continuation.yield(info)
                    }
                    let id = UUID()
                    observer.addHandler(id) {
                        if let info = powerSettingInfo(observer.store) {
                            continuation.yield(info)
                        }
                    }
                    continuation.onTermination = { _ in
                        observer.removeHandler(id)
                    }
                }
            },
            setPowerMode: { powerMode, source in
                let settings: [PowerSource: [PowerSetting]] = [source: [.powerMode(powerMode: powerMode)]]
                let option = PowerSettingOption(settings: settings)
                try await createClient().sendMessage(option, to: XPCRoute.powerSettingOption)
            }
        )
        return client
    }
    
    private class Observer {
        private let handlersQueue = DispatchQueue(label: "software.micropixels.BatFi.PowerSettingClient.Observer")
        
        private var handlers = [UUID: () -> Void]()
        private(set) var store: SCDynamicStore!
        
        init?() {
            guard let store = setUpObserving() else {
                return nil
            }
            self.store = store
        }
        
        private func setUpObserving() -> SCDynamicStore? {
            let info = Unmanaged.passUnretained(self).toOpaque()
            var context = SCDynamicStoreContext()
            context.info = info
            guard
                let store = SCDynamicStoreCreate(nil, "software.micropixels.BatFi" as CFString, { store, changedKeys, info in
                    guard let info else {
                        return
                    }
                    let observer = Unmanaged<Observer>.fromOpaque(info).takeUnretainedValue()
                    observer.updatePowerSetting()
                }, &context),
                SCDynamicStoreSetNotificationKeys(store, [Private.kIOPMDynamicStoreSettingsKey] as CFArray, nil)
            else {
                return nil
            }
            let source = SCDynamicStoreCreateRunLoopSource(nil, store, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes)
            return store
        }
        
        private func updatePowerSetting() {
            handlersQueue.sync { [weak self] in
                self?.handlers.values.forEach { $0() }
            }
        }

        func removeHandler(_ id: UUID) {
            handlersQueue.sync { [weak self] in
                self?.handlers[id] = nil
            }
        }

        func addHandler(_ id: UUID, _ handler: @escaping () -> Void) {
            handlersQueue.sync { [weak self] in
                self?.handlers[id] = handler
            }
        }
    }
}
