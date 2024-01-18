//
//  Formatters.swift
//  
//
//  Created by Adam on 08/05/2023.
//

import Foundation
import L10n

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

public let energyFormatter: MeasurementFormatter = {
    let formatter = CustomMeasurementFormatter()
    formatter.unitOptions = .providedUnit
    formatter.unitStyle = .short
    let numberFormatter = NumberFormatter()
    numberFormatter.numberStyle = .decimal
    numberFormatter.minimumFractionDigits = 3
    numberFormatter.maximumFractionDigits = 3
    formatter.numberFormatter = numberFormatter
    return formatter
}()

private class CustomMeasurementFormatter: MeasurementFormatter {
    override func string(from measurement: Measurement<Unit>) -> String {
        var string = super.string(from: measurement)
        if unitStyle == .short {
            if string.count >= measurement.unit.symbol.count + 2 {
                let index = string.index(string.endIndex, offsetBy: -(measurement.unit.symbol.count + 1))
                if string[index].isWhitespace {
                    string.remove(at: index)
                }
            }
        }
        return string
    }
}

public extension UnitEnergy {
    static let wattHours = UnitEnergy(symbol: L10n.UnitEnergy.Symbol.wattHours, converter: UnitConverterLinear(coefficient: 3600))
}
