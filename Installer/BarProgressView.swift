//
//  CustomProgressView.swift
//  Installer
//
//  Created by Adam Różyński on 31/03/2024.
//

import SwiftUI

struct BarProgressView: NSViewRepresentable {
    var value: Double?

    func makeNSView(context: Context) -> NSProgressIndicator {
        let progressView = NSProgressIndicator()
        progressView.style = .bar
        progressView.isIndeterminate = false
        progressView.minValue = 0
        progressView.maxValue = 1
        progressView.isDisplayedWhenStopped = false

        return progressView
    }

    func updateNSView(_ nsView: NSProgressIndicator, context: Context) {
        if let value {
            if value != 0 {
                nsView.isIndeterminate = false
                nsView.doubleValue = value
                nsView.stopAnimation(nil)
            } else {
                nsView.isIndeterminate = true
                nsView.stopAnimation(nil)
            }
        } else {
            nsView.isIndeterminate = true
            nsView.startAnimation(nil)
        }
    }
}

#Preview  {
    VStack {
        BarProgressView(value: 0.33)
        BarProgressView(value: 100)
        BarProgressView(value: nil)
        BarProgressView(value: 0)
            .border(Color.accentColor)
    }
    .padding()
    .frame(width: 300)
}
