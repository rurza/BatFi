//
//  StatusItem.swift
//
//
//  Created by Adam Różyński on 25/04/2024.
//

import AppShared
import Defaults
import DefaultsKeys
import BatteryIndicator
import Combine
import SwiftUI

private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

final class StatusItemModel: ObservableObject {
    @Published
    var powerState: PowerState

    init(powerState: PowerState) {
        self.powerState = powerState
    }
}

struct StatusItem: View {
    var sizePassthrough: PassthroughSubject<CGSize, Never>
    @ObservedObject var batteryIndicatorModel: BatteryIndicatorView.Model
    @ObservedObject var model: StatusItemModel

    @Default(.showTimeLeftNextToStatusIcon)
    private var showTimeLeftNextToStatusIcon

    var body: some View {
        HStack(spacing: 2) {
            if let timeLeftDescription, showTimeLeftNextToStatusIcon {
                Text(timeLeftDescription)
                    .offset(y: -1)
                    .fontWeight(.medium)
            }
            BatteryIndicatorView(model: self.batteryIndicatorModel)
                .frame(width: 33, height: 13)
                .offset(x: 2, y: -1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fixedSize()
        .padding(.horizontal, 2)
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
        let time = Time.timeLeft(time: model.powerState.timeLeft)
        guard case let .time(timeLeft) = time.info else { return nil }
        return shortTimeFormatter.string(from: Double(timeLeft * 60))
    }
}
