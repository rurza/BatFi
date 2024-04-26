//
//  TurnOffOverrideIntent.swift
//  BatFi
//
//  Created by Adam Różyński on 26/04/2024.
//

import App
import AppIntents

struct TurnOffOverrideIntent: AppIntent {
    static var title: LocalizedStringResource = .init("intent.stop_override.title", defaultValue: "Stop charge override")

    @AppDependency
    var app: BatFi

    func perform() async throws -> some IntentResult {
        await app.stopOverride()
        return .result()
    }

    static var openAppWhenRun: Bool { true }
}
