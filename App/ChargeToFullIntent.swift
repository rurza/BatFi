//
//  ChargeToFullIntent.swift
//
//
//  Created by Adam Różyński on 15/04/2024.
//

import App
import AppIntents
import L10n

struct ChargeToFullIntent: AppIntent {
    static var title: LocalizedStringResource = .init("intent.charge_to_full.title", defaultValue: "Charge to 100%")

    @AppDependency
    var app: BatFi

    func perform() async throws -> some IntentResult {
        await app.chargeToFull()
        return .result()
    }

    static var openAppWhenRun: Bool { true }
}
