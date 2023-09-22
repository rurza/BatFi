import Foundation

class Private {
    static let systemstats_get_top_coalitions = {
        var systemstats_get_top_coalitionsPointer: UnsafeMutableRawPointer?
        if let handle = dlopen("/usr/lib/libsystemstats.dylib", RTLD_LAZY) {
            systemstats_get_top_coalitionsPointer = dlsym(handle, "systemstats_get_top_coalitions")
            dlclose(handle)
        }
        let systemstats_get_top_coalitions =
        unsafeBitCast(systemstats_get_top_coalitionsPointer, to: (@convention(c) (_ duration: Int, _ count: Int) -> Unmanaged<NSDictionary>)?.self)
        return systemstats_get_top_coalitions
    }()
}
