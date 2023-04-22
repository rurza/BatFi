//
//  ServiceRegisterer.swift
//  BatFi
//
//  Created by Adam on 22/04/2023.
//

import Foundation
import ServiceManagement

final class ServiceRegisterer {
    lazy var service = SMAppService.daemon(plistName: helperPlistName)
    static let shared = ServiceRegisterer()

    func registerServices() async throws {
        do {
            try unregisterService()
        } catch {
            print("service removal error: \(error.localizedDescription)")
        }
        try service.register()
    }

    func unregisterService() throws {
        try service.unregister()
    }
}

