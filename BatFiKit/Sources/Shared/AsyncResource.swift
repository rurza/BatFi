//
//  AsyncResource.swift
//  BatFiKit
//
//  Created by Adam Różyński on 11.01.2025.
//

import Foundation

public enum AsyncResource<Resource> {
    case initial
    case loading
    case loaded(Resource)
    case error(NSError)

    public var isLoading: Bool {
        switch self {
        case .loading: return true
        default: return false
        }
    }

    public var error: NSError? {
        switch self {
        case .error(let error): return error
        default: return nil
        }
    }

    public var resource: Resource? {
        switch self {
        case .loaded(let resource): return resource
        default: return nil
        }
    }
}

extension AsyncResource: Equatable where Resource: Equatable { }

extension AsyncResource: Hashable where Resource: Hashable { }
