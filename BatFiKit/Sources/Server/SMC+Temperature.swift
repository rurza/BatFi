//
// SMCKit
//
// The MIT License
//
// Copyright (C) 2014-2017  beltex <https://beltex.github.io>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Foundation

// ------------------------------------------------------------------------------

// MARK: Temperature

// ------------------------------------------------------------------------------

/// The list is NOT exhaustive. In addition, the names of the sensors may not be
/// mapped to the correct hardware component.
///
/// ### Sources
///
/// * powermetrics(1)
/// * https://www.apple.com/downloads/dashboard/status/istatpro.html
/// * https://github.com/hholtmann/smcFanControl
/// * https://github.com/jedda/OSX-Monitoring-Tools
/// * http://www.opensource.apple.com/source/net_snmp/
/// * http://www.parhelia.ch/blog/statics/k3_keys.html
enum TemperatureSensors {
    static let AMBIENT_AIR_0 = TemperatureSensor(name: "AMBIENT_AIR_0",
                                                 code: FourCharCode(fromStaticString: "TA0P"))
    static let AMBIENT_AIR_1 = TemperatureSensor(name: "AMBIENT_AIR_1",
                                                 code: FourCharCode(fromStaticString: "TA1P"))
    // Via powermetrics(1)
    static let CPU_0_DIE = TemperatureSensor(name: "CPU_0_DIE",
                                             code: FourCharCode(fromStaticString: "TC0F"))
    static let CPU_0_DIODE = TemperatureSensor(name: "CPU_0_DIODE",
                                               code: FourCharCode(fromStaticString: "TC0D"))
    static let CPU_0_HEATSINK = TemperatureSensor(name: "CPU_0_HEATSINK",
                                                  code: FourCharCode(fromStaticString: "TC0H"))
    static let CPU_0_PROXIMITY =
    TemperatureSensor(name: "CPU_0_PROXIMITY",
                      code: FourCharCode(fromStaticString: "TC0P"))
    static let ENCLOSURE_BASE_0 =
    TemperatureSensor(name: "ENCLOSURE_BASE_0",
                      code: FourCharCode(fromStaticString: "TB0T"))
    static let ENCLOSURE_BASE_1 =
    TemperatureSensor(name: "ENCLOSURE_BASE_1",
                      code: FourCharCode(fromStaticString: "TB1T"))
    static let ENCLOSURE_BASE_2 =
    TemperatureSensor(name: "ENCLOSURE_BASE_2",
                      code: FourCharCode(fromStaticString: "TB2T"))
    static let ENCLOSURE_BASE_3 =
    TemperatureSensor(name: "ENCLOSURE_BASE_3",
                      code: FourCharCode(fromStaticString: "TB3T"))
    static let GPU_0_DIODE = TemperatureSensor(name: "GPU_0_DIODE",
                                               code: FourCharCode(fromStaticString: "TG0D"))
    static let GPU_0_HEATSINK = TemperatureSensor(name: "GPU_0_HEATSINK",
                                                  code: FourCharCode(fromStaticString: "TG0H"))
    static let GPU_0_PROXIMITY =
    TemperatureSensor(name: "GPU_0_PROXIMITY",
                      code: FourCharCode(fromStaticString: "TG0P"))
    static let HDD_PROXIMITY = TemperatureSensor(name: "HDD_PROXIMITY",
                                                 code: FourCharCode(fromStaticString: "TH0P"))
    static let HEATSINK_0 = TemperatureSensor(name: "HEATSINK_0",
                                              code: FourCharCode(fromStaticString: "Th0H"))
    static let HEATSINK_1 = TemperatureSensor(name: "HEATSINK_1",
                                              code: FourCharCode(fromStaticString: "Th1H"))
    static let HEATSINK_2 = TemperatureSensor(name: "HEATSINK_2",
                                              code: FourCharCode(fromStaticString: "Th2H"))
    static let LCD_PROXIMITY = TemperatureSensor(name: "LCD_PROXIMITY",
                                                 code: FourCharCode(fromStaticString: "TL0P"))
    static let MEM_SLOT_0 = TemperatureSensor(name: "MEM_SLOT_0",
                                              code: FourCharCode(fromStaticString: "TM0S"))
    static let MEM_SLOTS_PROXIMITY =
    TemperatureSensor(name: "MEM_SLOTS_PROXIMITY",
                      code: FourCharCode(fromStaticString: "TM0P"))
    static let MISC_PROXIMITY = TemperatureSensor(name: "MISC_PROXIMITY",
                                                  code: FourCharCode(fromStaticString: "Tm0P"))
    static let NORTHBRIDGE = TemperatureSensor(name: "NORTHBRIDGE",
                                               code: FourCharCode(fromStaticString: "TN0H"))
    static let NORTHBRIDGE_DIODE =
    TemperatureSensor(name: "NORTHBRIDGE_DIODE",
                      code: FourCharCode(fromStaticString: "TN0D"))
    static let NORTHBRIDGE_PROXIMITY =
    TemperatureSensor(name: "NORTHBRIDGE_PROXIMITY",
                      code: FourCharCode(fromStaticString: "TN0P"))
    static let ODD_PROXIMITY = TemperatureSensor(name: "ODD_PROXIMITY",
                                                 code: FourCharCode(fromStaticString: "TO0P"))
    static let PALM_REST = TemperatureSensor(name: "PALM_REST",
                                             code: FourCharCode(fromStaticString: "Ts0P"))
    static let PWR_SUPPLY_PROXIMITY =
    TemperatureSensor(name: "PWR_SUPPLY_PROXIMITY",
                      code: FourCharCode(fromStaticString: "Tp0P"))
    static let THUNDERBOLT_0 = TemperatureSensor(name: "THUNDERBOLT_0",
                                                 code: FourCharCode(fromStaticString: "TI0P"))
    static let THUNDERBOLT_1 = TemperatureSensor(name: "THUNDERBOLT_1",
                                                 code: FourCharCode(fromStaticString: "TI1P"))

    static let all = [AMBIENT_AIR_0.code: AMBIENT_AIR_0,
                      AMBIENT_AIR_1.code: AMBIENT_AIR_1,
                      CPU_0_DIE.code: CPU_0_DIE,
                      CPU_0_DIODE.code: CPU_0_DIODE,
                      CPU_0_HEATSINK.code: CPU_0_HEATSINK,
                      CPU_0_PROXIMITY.code: CPU_0_PROXIMITY,
                      ENCLOSURE_BASE_0.code: ENCLOSURE_BASE_0,
                      ENCLOSURE_BASE_1.code: ENCLOSURE_BASE_1,
                      ENCLOSURE_BASE_2.code: ENCLOSURE_BASE_2,
                      ENCLOSURE_BASE_3.code: ENCLOSURE_BASE_3,
                      GPU_0_DIODE.code: GPU_0_DIODE,
                      GPU_0_HEATSINK.code: GPU_0_HEATSINK,
                      GPU_0_PROXIMITY.code: GPU_0_PROXIMITY,
                      HDD_PROXIMITY.code: HDD_PROXIMITY,
                      HEATSINK_0.code: HEATSINK_0,
                      HEATSINK_1.code: HEATSINK_1,
                      HEATSINK_2.code: HEATSINK_2,
                      MEM_SLOT_0.code: MEM_SLOT_0,
                      MEM_SLOTS_PROXIMITY.code: MEM_SLOTS_PROXIMITY,
                      PALM_REST.code: PALM_REST,
                      LCD_PROXIMITY.code: LCD_PROXIMITY,
                      MISC_PROXIMITY.code: MISC_PROXIMITY,
                      NORTHBRIDGE.code: NORTHBRIDGE,
                      NORTHBRIDGE_DIODE.code: NORTHBRIDGE_DIODE,
                      NORTHBRIDGE_PROXIMITY.code: NORTHBRIDGE_PROXIMITY,
                      ODD_PROXIMITY.code: ODD_PROXIMITY,
                      PWR_SUPPLY_PROXIMITY.code: PWR_SUPPLY_PROXIMITY,
                      THUNDERBOLT_0.code: THUNDERBOLT_0,
                      THUNDERBOLT_1.code: THUNDERBOLT_1]
}

struct TemperatureSensor {
    let name: String
    let code: FourCharCode
}

enum TemperatureUnit {
    case celsius
    case fahrenheit
    case kelvin

    static func toFahrenheit(_ celsius: Double) -> Double {
        // https://en.wikipedia.org/wiki/Fahrenheit#Definition_and_conversions
        return (celsius * 1.8) + 32
    }

    static func toKelvin(_ celsius: Double) -> Double {
        // https://en.wikipedia.org/wiki/Kelvin
        return celsius + 273.15
    }
}

extension SMCKit {
    static func allKnownTemperatureSensors() throws ->
    [TemperatureSensor] {
        var sensors = [TemperatureSensor]()

        for sensor in TemperatureSensors.all.values {
            if try isKeyFound(sensor.code) { sensors.append(sensor) }
        }

        return sensors
    }

    static func allUnknownTemperatureSensors() throws -> [TemperatureSensor] {
        let keys = try allKeys()

        return keys.filter { $0.code.toString().hasPrefix("T") &&
            $0.info == DataTypes.SP78 &&
            TemperatureSensors.all[$0.code] == nil
        }
        .map { TemperatureSensor(name: "Unknown", code: $0.code) }
    }

    /// Get current temperature of a sensor
    static func temperature(
        _ sensorCode: FourCharCode,
        unit: TemperatureUnit = .celsius
    ) throws -> Double {
        let data = try readData(SMCKey(code: sensorCode, info: DataTypes.SP78))

        let temperatureInCelsius = Double(fromSP78: (data.0, data.1))

        switch unit {
        case .celsius:
            return temperatureInCelsius
        case .fahrenheit:
            return TemperatureUnit.toFahrenheit(temperatureInCelsius)
        case .kelvin:
            return TemperatureUnit.toKelvin(temperatureInCelsius)
        }
    }
}
