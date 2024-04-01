//
//  InstallationState.swift
//  Installer
//
//  Created by Adam Różyński on 31/03/2024.
//

import Foundation

enum InstallationState: Equatable, CustomStringConvertible {
    case initial
    case downloading(progress: Double?)
    case downloadError(NSError)
    case unzipping
    case unzippingError(NSError)
    case moving
    case movingError(NSError)
    case done

    var progress: Double? {
        switch self {
        case .downloading(let progress):
            return progress
        case .unzipping, .moving:
            return nil
        case .downloadError, .unzippingError, .movingError, .initial:
            return 0
        case .done:
            return 1
        }
    }

    var description: String {
        switch self {
        case .initial:
            return "Initial"
        case .downloading(let progress):
            return "Downloading: \(progress?.description ?? "Waiting" )"
        case .downloadError(let error):
            return "Download error: \(error.localizedDescription)"
        case .unzipping:
            return "Unzipping"
        case .unzippingError(let error):
            return "Unzipping error: \(error.localizedDescription)"
        case .moving:
            return "Moving"
        case .movingError(let error):
            return "Moving error: \(error.localizedDescription)"
        case .done:
            return "Done"
        }
    }

}
