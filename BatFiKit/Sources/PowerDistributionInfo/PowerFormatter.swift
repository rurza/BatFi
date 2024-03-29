//
//  PowerFormatter.swift
//
//
//  Created by Adam on 14/10/2023.
//

import Foundation

let powerFormatter: MeasurementFormatter = {
    let formatter = MeasurementFormatter()
    formatter.unitStyle = .short
    let numberFormatter = NumberFormatter()
    numberFormatter.numberStyle = .decimal
    numberFormatter.minimumFractionDigits = 1
    numberFormatter.maximumFractionDigits = 1
    formatter.numberFormatter = numberFormatter
    return formatter
}()
