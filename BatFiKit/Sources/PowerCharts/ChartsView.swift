//
//  ChartsView.swift
//
//
//  Created by Adam on 19/08/2023.
//

import AppShared
import Clients
import Dependencies
import L10n
import Persistence
import SwiftUI
import Charts

public struct ChartsView: View {
    @StateObject private var model = Model()
    @Dependency(\.calendar) private var calendar

    public init() { }

    public var body: some View {
        VStack(alignment: .leading) {
            Text(L10n.Menu.Charts.chartsHeader)
                .foregroundStyle(.secondary)
                .font(.callout)
                .padding(.bottom, 6)
            if !model.powerStatePoints.isEmpty {
                Chart(model.powerStatePoints) {
                    let offsetDate = model.offsetDateFor($0)
                    AreaMark(
                        x: .value("Time", $0.timestamp ..< offsetDate),
                        y: .value("Level", $0.batteryLevel),
                        series: .value("Charging Representation", PlottablePowerState.charging($0.representation))
                    )
                    .foregroundStyle(by: .value("", PlottablePowerState.charging($0.representation)))

                    AreaMark(
                        x: .value("Time", $0.timestamp ..< offsetDate),
                        yStart: .value("level", $0.batteryLevel),
                        yEnd: .value("level", 100),
                        series: .value("", PlottablePowerState.chargerConnected($0.chargerConntectedAndIsCharging))
                    )
                    .foregroundStyle(by: .value("", PlottablePowerState.chargerConnected($0.chargerConntectedAndIsCharging)))

                    LineMark(
                        x: .value("Time", $0.timestamp ..< offsetDate),
                        y: .value("Battery Level", $0.batteryLevel)
                    )
                    .foregroundStyle(by: .value("Visual battery state", PlottablePowerState.visualBatteryState($0.visualBatteryState)))
                }
                .chartForegroundStyleScale(mapping: { (powerState: PlottablePowerState) in
                    switch powerState {
                    case .charging(let chargingRepresentation):
                        switch chargingRepresentation {
                        case .charging:
                            Color(.chartGreen)
                        case .inhibiting:
                            Color(.chartLightGreen)
                        case .discharging:
                            Color.clear
                        }
                    case .chargerConnected(let chargerConnected):
                        switch chargerConnected {
                        case .chargerConnectedAndIsCharging:
                            Color(.chartLightGreen)
                        case .chargerConnected:
                            Color(.chartLightOrange)
                        case .noCharger:
                            Color.clear
                        }
                    case .visualBatteryState(let visualBatteryState):
                        switch visualBatteryState {
                        case .low:
                            Color(.chartRed)
                        case .normal:
                            Color(.chartBlue)
                        }
                    }
                })
                .chartYScale(domain: 0...100)
                .chartXScale(domain: model.fromDate ... model.toDate)
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
                                Text(date, format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)).minute())
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
                VStack(alignment: .leading, spacing: 3) {
                    LegendView(label: L10n.AppChargingMode.State.Title.charging, color: Color(.chartLightGreen))
                    LegendView(label: L10n.AppChargingMode.State.Title.inhibit, color: Color(.chartLightOrange))
                }
            } else {
                Text(L10n.Menu.Charts.waitingForData)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private enum PlottablePowerState: Plottable {
    init?(primitivePlottable: Int) {
        switch primitivePlottable {
        case 2...4:
            if let representation = ChargingRepresentation(rawValue: primitivePlottable) {
                self = .charging(representation)
            } else {
                return nil
            }
        case 5...6:
            if let visualBatteryState = VisualBatteryState(rawValue: primitivePlottable) {
                self = .visualBatteryState(visualBatteryState)
            } else {
                return nil
            }
        case 7...9:
            if let chargerConnected = ChargerConnected(rawValue: primitivePlottable) {
                self = .chargerConnected(chargerConnected)
            } else {
                return nil
            }
        default:
            return nil
        }
    }

    case charging(ChargingRepresentation)
    case chargerConnected(ChargerConnected)
    case visualBatteryState(VisualBatteryState)

    var primitivePlottable: Int {
        switch self {
        case .charging(let representation):
            return representation.rawValue
        case .chargerConnected(let chargerConnected):
            return chargerConnected.rawValue
        case .visualBatteryState(let state):
            return state.rawValue
        }
    }

    enum ChargingRepresentation: Int {
        case charging = 2
        case inhibiting = 3
        case discharging = 4
    }

    enum VisualBatteryState: Int {
        case low = 5
        case normal = 6
    }

    enum ChargerConnected: Int {
        case chargerConnectedAndIsCharging = 7
        case chargerConnected = 8
        case noCharger = 9
    }
}

extension PowerStatePoint {
    fileprivate func plottablePowerStateFor(representation: PlottablePowerState.ChargingRepresentation) -> PlottablePowerState {
        return PlottablePowerState.charging(representation)
    }

    fileprivate var representation: PlottablePowerState.ChargingRepresentation {
        switch self.appMode {
        case .initial, .inhibit:
            return .inhibiting
        case .charging, .forceCharge:
            return .charging
        case .forceDischarge, .chargerNotConnected:
            return .discharging
        }
    }

    fileprivate var visualBatteryState: PlottablePowerState.VisualBatteryState {
        if self.batteryLevel <= 20 {
            return .low
        } else {
            return .normal
        }
    }

    fileprivate var chargerConntectedAndIsCharging: PlottablePowerState.ChargerConnected {
        if chargerConnected && representation == .charging {
            return .chargerConnectedAndIsCharging
        } else if chargerConnected {
            return .chargerConnected
        } else {
            return .noCharger
        }
    }
}

