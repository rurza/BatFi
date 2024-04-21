//
//  DischargeBatteryIntent.swift
//
//
//  Created by Adam Różyński on 15/04/2024.
//

import App
import AppIntents
import L10n

struct DischargeBatteryIntent: AppIntent {
    static var title: LocalizedStringResource = .init("intent.discharge.title", defaultValue: "Run on Battery")

    static var description =
    IntentDescription(.init("intent.discharge.description", defaultValue: "Works only with the lid opened."))

    @AppDependency
    var app: BatFi

    func perform() async throws -> some IntentResult {
        await app.dischargeBattery(to: 0)
        return .result()
    }

    static var openAppWhenRun: Bool { true }
}
