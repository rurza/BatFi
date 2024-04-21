//
//  TempOverrideBatteryLevelIntent.swift
//  BatFi
//
//  Created by Adam Różyński on 18/04/2024.
//

import Foundation

import App
import AppIntents

struct TempOverrideBatteryLevelIntent: AppIntent {
    static var title: LocalizedStringResource = .init("intent.override.title", defaultValue: "Temporarily Override Battery Level")

    static var description =
    IntentDescription(.init("intent.override.description", defaultValue: "Discharging works only with the lid opened."))

    @AppDependency
    var app: BatFi

    @Parameter(
        title: .init("intent.override.parameter.title", defaultValue: "Limit"),
        description: .init("intent.override.parameter.description", defaultValue: "Battery percent"),
        inclusiveRange: (0, 100)
    )
    var limit: Int

    func perform() async throws -> some IntentResult {
        await app.dischargeBattery(to: limit)
        return .result()
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Charge or run on battery power (when the lid is opened) until the limit of \(\.$limit) is reached.")
    }

    static var openAppWhenRun: Bool { true }
}
