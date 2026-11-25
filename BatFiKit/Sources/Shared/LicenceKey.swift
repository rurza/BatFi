//
//  LicenceKey.swift
//  BatFi
//
//  Cleaning up a licence key the customer pasted.
//

import Foundation

/// A licence key as the customer typed or pasted it, made fit to send to the server.
///
/// Keys pasted from an email arrive with a line break or spaces inside them, and the server
/// refuses them. Whitespace of any kind goes, wherever it is, and nothing else changes: the
/// dashes and the case stay as pasted. BatFi keys come in two shapes, UUIDs (8-4-4-4-12) that
/// we issue and Gumroad keys (8-8-8-8 hex), so a key pasted without its dashes cannot be told
/// apart and is not reformatted.
public enum LicenceKey {
    public static func normalized(_ key: String) -> String {
        String(key.filter { !$0.isWhitespace && !$0.isNewline })
    }
}
