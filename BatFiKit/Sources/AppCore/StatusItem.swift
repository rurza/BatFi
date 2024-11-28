//
//  StatusItem.swift
//
//
//  Created by Adam Różyński on 25/04/2024.
//

import AppShared
import Defaults
import DefaultsKeys
import Dependencies
import BatteryIndicator
import Combine
import SwiftUI

private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

struct StatusItem: View {
    var sizePassthrough: PassthroughSubject<CGSize, Never>
    @ObservedObject var batteryIndicatorModel: BatteryIndicatorViewModel
    @ObservedObject var model: StatusItemModel

    @Default(.showTimeLeftNextToStatusIcon)
    private var showTimeLeftNextToStatusIcon

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            if let timeLeftDescription, showTimeLeftNextToStatusIcon {
                Text(timeLeftDescription)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .padding(.trailing, 1) // adds padding to look horizontally centered
                    .id("timeLeft")
                    .offset(x: showTimeLeftNextToStatusIcon && self.timeLeftDescription != nil ? 0 : 300)
                    .opacity(showTimeLeftNextToStatusIcon && self.timeLeftDescription != nil ? 1 : 0)
                    .animation(.default.delay(0.1), value: showTimeLeftNextToStatusIcon)
                    .animation(.default.delay(0.1), value: timeLeftDescription)
            }
            BatteryIndicatorView(model: self.batteryIndicatorModel)
                .frame(width: 30, height: 13)
            if batteryIndicatorModel.showPercentageNextToIndicator && batteryIndicatorModel.showPercentage {
                Text(batteryIndicatorModel.batteryLevel, format: .percent)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .id("batteryLevel")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: -1)
        .fixedSize()
        .overlay(
            GeometryReader { geometryProxy in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: geometryProxy.size)
            }
        )
        .onPreferenceChange(
            SizePreferenceKey.self,
            perform: { size in
                sizePassthrough.send(size)
            }
        )
    }

    var timeLeftDescription: String? {
        guard let timeLeft = model.powerState?.timeLeft else { return nil }
        let time = Time.timeLeft(time: timeLeft)
        guard case let .time(timeLeft) = time.info else { return nil }
        return shortTimeFormatter.string(from: Double(timeLeft * 60))
    }
}

@MainActor
final class StatusItemModel: ObservableObject {
    @Published
    var powerState: PowerState?

    @Dependency(\.powerSourceClient.powerSourceChanges)
    private var powerSourceChanges

    init() {
        setUpObserving()
    }

    private func setUpObserving() {
        Task {
            for await powerState in powerSourceChanges() {
                self.powerState = powerState
            }
        }
    }
}
