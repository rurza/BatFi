//
//  PmsetOutput.swift
//  BatFi
//

import Foundation

/// Reads a single setting out of `pmset -g` output.
///
/// This replaces a `pmset -g | grep -w <key>` pipeline: two spawned processes to select one
/// line, where the selection is a `first(where:)`. Removing `grep` removes a process that
/// could fail to spawn, and the pipe between them that could deadlock.
public enum PmsetOutput {
    /// The value recorded against `key`, or `nil` if the key is absent or its value is not
    /// a number.
    ///
    /// `key` matches a whole whitespace-separated token, never a substring — `powermode`
    /// and `lowpowermode` are different settings and only some Macs publish the former,
    /// which is what `grep -w` was for.
    public static func value(forKey key: String, in output: String) -> UInt8? {
        for line in output.split(whereSeparator: \.isNewline) {
            let tokens = line.split(whereSeparator: \.isWhitespace)
            guard let keyIndex = tokens.firstIndex(where: { $0 == key }) else { continue }
            // The token *after* the key, not the end of the line: some settings are followed
            // by a parenthetical (`sleep 1 (sleep prevented by …)`).
            let valueIndex = tokens.index(after: keyIndex)
            guard valueIndex < tokens.endIndex else { return nil }
            return UInt8(tokens[valueIndex])
        }
        return nil
    }
}
