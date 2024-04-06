//
//  LicenseView.swift
//  Installer
//
//  Created by Adam Różyński on 06/04/2024.
//

import L10n
import SharedUI
import SwiftUI
import WebKit

struct LicenseView: View {
    let didAccept: () -> Void
    let didDecline: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let url = Bundle.main.url(forResource: "license", withExtension: "rtf") {
            VStack(spacing: 0) {
                RTFDocumentView(rtfURL: url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: 30) {
                    Button(
                        action: didAccept,
                        label: {
                            Text(L10n.Installer.Button.Label.accept)
                        }
                    )
                    .buttonStyle(PrimaryButtonStyle(isLoading: false))
                    Button(
                        action: didDecline,
                        label: {
                            Text(L10n.Installer.Button.Label.decline)
                                .foregroundStyle(.primary)
                        }
                    )
                    .buttonStyle(.plain)
                }
                .padding()
            }
        } else {
            Text("NOOOOO")
        }
    }
}

struct RTFDocumentView: NSViewRepresentable {
    var rtfURL: URL

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()

        let contentSize = scrollView.contentSize
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height))
        textView.backgroundColor = NSColor.white
        textView.isEditable = false
        textView.autoresizingMask = [.width, .height]

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let textView = nsView.documentView as? NSTextView,
           let rtfContent = try? Data(contentsOf: rtfURL),
           let attrString = NSAttributedString(rtf: rtfContent, documentAttributes: nil) {
            textView.textStorage?.setAttributedString(attrString)
        }
    }
}

#if DEBUG
#Preview {
    LicenseView(didAccept: {}, didDecline: {})
        .frame(width: 400)
}
#endif
