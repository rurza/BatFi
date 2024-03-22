//
//  Formatters.swift
//
//
//  Created by Adam on 08/05/2023.
//

import Foundation

public let timeFormatter: DateComponentsFormatter = {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute]
    formatter.unitsStyle = .short
    return formatter
}()

public let temperatureFormatter: MeasurementFormatter = {
    let formatter = MeasurementFormatter()
    formatter.unitStyle = .short
    let numberFormatter = NumberFormatter()
    numberFormatter.numberStyle = .decimal
    numberFormatter.maximumFractionDigits = 1
    formatter.numberFormatter = numberFormatter
    return formatter
}()

public let percentageFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .percent
    formatter.minimumIntegerDigits = 1
    formatter.maximumFractionDigits = 0
    return formatter
}()
