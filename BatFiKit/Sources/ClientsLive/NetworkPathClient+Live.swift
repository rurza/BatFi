//
//  NetworkPathClient+Live.swift
//  BatFi
//

import Clients
import Dependencies
import Foundation
import Network
import os

extension NetworkPathClient: DependencyKey {
    public static let liveValue = NetworkPathClient(
        pathChanges: {
            AsyncStream { continuation in
                // One monitor per subscriber, cancelled with the stream, so nothing observes the
                // network while no geofenced rule exists.
                let monitor = NWPathMonitor()
                let previous = OSAllocatedUnfairLock<NWPath?>(initialState: nil)
                monitor.pathUpdateHandler = { path in
                    let isChange = previous.withLock { last -> Bool in
                        defer { last = path }
                        // The first callback reports the path already in force.
                        guard let last else { return false }
                        return last != path
                    }
                    if isChange, path.status == .satisfied { continuation.yield() }
                }
                monitor.start(queue: DispatchQueue(label: "NetworkPathClient", qos: .utility))
                continuation.onTermination = { _ in monitor.cancel() }
            }
        }
    )
}
