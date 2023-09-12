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
        VStack(alignment: .leading, spacing: 8) {
            Text("Last 12 hours")
                .foregroundStyle(.secondary)
                .font(.callout)
            Chart(model.powerStatePoints) {
                let offsetDate = model.offsetDateFor($0)
                BarMark(
                    x: .value("Time", $0.timestamp ..< offsetDate),
                    y: .value("Battery Level", $0.batteryLevel),
                    width: .inset(0),
                    height: .inset(0)
                )
                .foregroundStyle(by: .value("App mode", $0.appMode.representation))

                LineMark(
                    x: .value("Time", $0.timestamp ..< offsetDate),
                    y: .value("Battery Level", $0.batteryLevel)
                )

                BarMark(
                    x: .value("Time", $0.timestamp ..< offsetDate),
                    y: .value("Charger connected", $0.chargerConnected ? 100 - $0.batteryLevel : 0),
                    width: .inset(0),
                    height: .inset(0)
                )
                .foregroundStyle(chargerConnectedForegrondColorFor($0))
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
                AxisMarks(values: .stride(by: .hour, count: 3, roundLowerBound: true)) { value in
                    if let date = value.as(Date.self) {
                        let hour = calendar.component(.hour, from: date)
                        AxisValueLabel {
                            Text(date, format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
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
            .chartLegend(.hidden)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(colorsForAllModes(), id: \.key) { pair in
                    LegendView(label: pair.key.description, color: pair.value)
                }
                LegendView(label: "Charger connected", color: .orange.opacity(0.4))
            }
        }
    }

    func colorsForAllModes() -> KeyValuePairs<AppChargingMode.Representation, Color> {
        [
            .charging: Color.green,
            .inhibiting: Color.green.opacity(0.4),
        ]
    }

    func chargerConnectedForegrondColorFor(_ powerStatePoint: PowerStatePoint) -> Color {
        if powerStatePoint.chargerConnected && powerStatePoint.appMode.representation == .charging {
            return .green.opacity(0.4)
        } else {
            return .orange.opacity(0.5)
        }
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
