//
//  ChartMarkInterval.swift
//  BatFi
//

import Foundation

/// The x-axis extent of a single chart mark.
///
/// Returns a `Range` rather than a bare upper bound on purpose. Callers plot
/// `start ..< end`, and `Range` traps on `lowerBound > upperBound`, so handing back a
/// loose `Date` leaves every call site free to reintroduce the crash. Constructing the
/// range here means there is exactly one place that has to be right.
public enum ChartMarkInterval {
    /// Width given to a mark whose natural end does not lie after its start.
    public static let minimumWidth: TimeInterval = 0.1

    /// - Parameter naturalEnd: Where the mark would end if the data were well behaved —
    ///   the next sample's timestamp, or `Date.now` for the newest sample. `nil` when
    ///   there is no such date.
    ///
    /// A `naturalEnd` at or before `start` is not treated as an error worth surfacing: it
    /// means the wall clock moved backwards between the fetch that produced `start` and
    /// the render that produced `naturalEnd` (an NTP correction after wake will do it), and
    /// the honest drawing of a sample whose duration is unknown is a hairline, not a crash.
    public static func range(start: Date, naturalEnd: Date?) -> Range<Date> {
        guard let naturalEnd, naturalEnd > start else {
            return start ..< start.addingTimeInterval(minimumWidth)
        }
        return start ..< naturalEnd
    }
}
