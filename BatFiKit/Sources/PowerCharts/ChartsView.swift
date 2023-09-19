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
                    LineMark(
                        x: .value("Time", $0.timestamp),
                        y: .value("Battery Level", $0.batteryLevel)
                    )

                    if $0.appMode == .charging || $0.appMode == .forceCharge {
                        AreaMark(x: .value("Time", $0.timestamp),
                                 yStart: .value("Battery Level", 0),
                                 yEnd: .value("Battery Level", 100),
                                 series: .value("Mode", $0.appMode.rawValue)
                        )
                        .opacity(0.2)
                    }

                    if $0.appMode == .inhibit {
                        AreaMark(x: .value("Time", $0.timestamp),
                                 yStart: .value("Battery Level", 0),
                                 yEnd: .value("Battery Level", 100),
                                 series: .value("Mode", $0.appMode.rawValue)
                        )
                        .foregroundStyle(Color.yellow)
                        .opacity(0.2)
                    }
                }
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
            } else {
                Text(L10n.Menu.Charts.waitingForData)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            Task { await model.fetchPowerStatePoints() }
        }
    }
}
