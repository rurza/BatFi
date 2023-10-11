import Foundation

public class Private {
    public static let (systemstats_get_top_coalitions, systemstats_get_battery_charge_graph) = {
        var systemstats_get_top_coalitionsPointer: UnsafeMutableRawPointer?
        var systemstats_get_battery_charge_graphPointer: UnsafeMutableRawPointer?
        if let handle = dlopen("/usr/lib/libsystemstats.dylib", RTLD_LAZY) {
            systemstats_get_top_coalitionsPointer = dlsym(handle, "systemstats_get_top_coalitions")
            systemstats_get_battery_charge_graphPointer = dlsym(handle, "systemstats_get_battery_charge_graph")
            dlclose(handle)
        }
        let systemstats_get_top_coalitions =
        unsafeBitCast(systemstats_get_top_coalitionsPointer, to: (@convention(c) (_ duration: Int, _ count: Int) -> Unmanaged<NSDictionary>)?.self)
        let systemstats_get_battery_charge_graph =
        unsafeBitCast(systemstats_get_battery_charge_graphPointer, to: (@convention(c) () -> Unmanaged<NSDictionary>)?.self)
        return (systemstats_get_top_coalitions, systemstats_get_battery_charge_graph)
    }()
}
