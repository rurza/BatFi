//
//  ChartsView.swift
//
//
//  Created by Adam on 19/08/2023.
//

import AppShared
import Charts
import Clients
import Dependencies
import Persistence
import SwiftUI

public struct ChartsView: View {
    @StateObject private var model = Model()
    @Dependency(\.calendar) private var calendar

    public init() { }

    public var body: some View {
        Chart(model.powerStatePoints) {
            BarMark(
                x: .value("Time", $0.timestamp ..< $0.timestamp.advanced(by: 60 * 15)),
                y: .value("Battery Level", $0.batteryLevel),
                width: 0.6
            )
            .foregroundStyle(by: .value("App mode", $0.appMode.representation))
        }
        .chartForegroundStyleScale(colorsForAllModes())
        .chartYAxis {
            AxisMarks(
                values: [0, 50, 100]
            ) {
                AxisValueLabel(format: Decimal.FormatStyle.Percent.percent.scale(1))
            }

            AxisMarks(
                values: [0, 25, 50, 75, 100]
            ) {
                AxisGridLine()
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                if let date = value.as(Date.self) {
                    let hour = calendar.component(.hour, from: date)
                    AxisValueLabel {
                        Text(date, format: .dateTime.hour(.conversationalDefaultDigits(amPM: .abbreviated)))
                    }
                    if hour == 0 {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                    } else {
                        AxisGridLine()
                        AxisTick()
                    }
                }
            }
        }
        .chartLegend(position: .bottom, alignment: .leading, spacing: nil) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(colorsForAllModes(), id: \.key) { pair in
                    HStack {
                        Circle().frame(width: 8, height: 8)
                            .foregroundStyle(pair.value)
                        Text(pair.key.description)
                            .foregroundColor(Color.secondary)
                            .font(.callout)
                    }
                }
            }
            .foregroundStyle(.primary)
        }
    }

    func colorsForAllModes() -> KeyValuePairs<AppChargingMode.Representation, Color> {
        [
            .discharging: Color.red,
            .charging: Color.green,
            .inhibiting: Color.blue,
        ]
    }
}

extension AppChargingMode {
    var representation: Representation {
        switch self {
        case .initial, .inhibit:
            return .inhibiting
        case .charging, .forceCharge:
            return .charging
        case .forceDischarge, .chargerNotConnected:
            return .discharging
        }
    }


    enum Representation: String, Plottable {
        case charging
        case inhibiting
        case discharging

        var description: String {
            switch self {
            case .charging:
                return "Charging"
            case .inhibiting:
                return "Inhibit charging"
            case .discharging:
                return "Discharging"
            }
        }
    }
}
