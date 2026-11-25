//
//  LocationSearchModel.swift
//  BatFi
//
//  Address autocomplete for the rule editor's map picker. Kept out of the view so the picker
//  body stays readable and so the completer's delegate lifetime is explicit.
//
//  The picker previously ran MKLocalSearch on submit and silently took mapItems.first, which
//  is how searching "wars" dropped a pin in a Warsaw suburb with no indication that a choice
//  had been made on the user's behalf.
//

import Foundation
import MapKit
import Observation

@MainActor
@Observable
final class LocationSearchModel: NSObject, MKLocalSearchCompleterDelegate {
    var query: String = "" {
        didSet {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                completions = []
                hasSearched = false
                // Cancels any in-flight completer work for the previous fragment. Without this
                // the completer keeps its last non-empty `queryFragment` and can still deliver a
                // `completerDidUpdateResults` for it after the field has been cleared.
                completer.queryFragment = ""
                return
            }
            // Reset until the completer actually reports back for this fragment — it, not the
            // keystroke, is what should flip `hasSearched`. Otherwise "No places found" flashes
            // on every keystroke before the completer's asynchronous response arrives.
            hasSearched = false
            completer.queryFragment = trimmed
        }
    }

    private(set) var completions: [MKLocalSearchCompletion] = []
    /// True once the completer has actually responded to the current (non-empty) query.
    /// Distinguishes "nothing typed yet" and "waiting on a response" from "typed something that
    /// matched nothing", so the no-results message only appears once it is true.
    private(set) var hasSearched = false

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.resultTypes = [.address, .pointOfInterest]
        completer.delegate = self
    }

    /// Bias results toward what the user is looking at. Without this, a short query resolves
    /// against the whole world.
    func updateRegion(_ region: MKCoordinateRegion) {
        completer.region = region
    }

    func clear() {
        query = ""
        completions = []
        hasSearched = false
    }

    /// Turns a chosen completion into a real coordinate.
    func resolve(_ completion: MKLocalSearchCompletion) async -> (coordinate: CLLocationCoordinate2D, name: String)? {
        let request = MKLocalSearch.Request(completion: completion)
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else {
            return nil
        }
        return (item.placemark.coordinate, item.name ?? completion.title)
    }

    // MARK: - MKLocalSearchCompleterDelegate

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        // The delegate's `completer` parameter is non-Sendable and crosses into this
        // main-actor-isolated closure, which the compiler flags under strict concurrency even
        // though the call is synchronous. `self.completer` is the same instance and is already
        // main-actor isolated, so read through it instead (see LocationClient+Live.swift for
        // the same pattern).
        MainActor.assumeIsolated {
            // A completion can still land after the field was cleared (see `query`'s didSet) —
            // e.g. one already in flight when `clear()` reset `queryFragment`. Guard on the
            // model's own current query, not just the completer's, so a late callback can't
            // resurrect the dropdown under an empty field.
            guard !self.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                completions = []
                return
            }
            completions = Array(self.completer.results.prefix(5))
            hasSearched = true
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            completions = []
            // Same staleness guard as above: only a response to a currently-typed query counts
            // as "searched".
            guard !self.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            hasSearched = true
        }
    }
}
