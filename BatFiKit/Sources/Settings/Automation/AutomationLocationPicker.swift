//
//  AutomationLocationPicker.swift
//  BatFi
//
//  Map-based location picker for a rule's geofence: address search, tap-to-place,
//  "use current location", and a radius slider drawn as a circle overlay.
//

import AppKit
import AppShared
import Clients
import CoreLocation
import Dependencies
import L10n
import MapKit
import SwiftUI

struct AutomationLocationPicker: View {
    @Binding var coordinate: Coordinate?
    @Binding var radiusMeters: Double
    @Binding var label: String

    @Dependency(\.locationClient) private var locationClient

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 60, longitudeDelta: 60)
        )
    )
    @State private var search = LocationSearchModel()
    /// Nil until the first real value arrives. A default-constructed `LocationSnapshot` is
    /// `.notDetermined`, so seeding one would flash the "BatFi needs location access…" banner and
    /// an **Allow Access** button at every user, including already-authorized ones.
    @State private var snapshot: LocationSnapshot?
    @State private var isLocating = false

    // `label` (and, for the current-location/search paths, `coordinate`) has three independent
    // asynchronous writers below: the map-tap reverse geocode (`prefillLabelIfEmpty`), "use
    // current location" (`apply`, reached synchronously from `useCurrentLocation()` or later from
    // the `.task` snapshot loop), and a search selection (`select`). Nothing else sequences them,
    // so a slower request finishing after a faster, later one would otherwise silently overwrite
    // it — e.g. naming the pin for a place it's no longer at. Each writer bumps or captures this
    // counter when its request starts and checks it still matches before applying its result, so
    // a newer request always supersedes an older one.
    @State private var pinRequestGeneration = 0
    @State private var locatingGeneration = 0
    /// True while `label` holds text one of the three automated writers put there (current
    /// location, tap-to-geocode, search selection) rather than text the user typed. Lets those
    /// writers keep replacing each other's output — and the user's own edits still win over all
    /// of them, since `labelBinding`'s setter clears this the moment the user types.
    @State private var labelWasAutofilled = false

    /// A fix older than this is not good enough to answer "Use current location".
    private static let currentLocationMaxAge: TimeInterval = 300

    /// Matches the slider. The floor is the radius CoreLocation will actually monitor.
    private static let radiusRange: ClosedRange<Double> = GeoFence.minimumMonitoredRadiusMeters ... 2000

    /// What locationd monitors, which is not always what is stored: a legacy rule can hold 50 m.
    /// The circle and the readout both use this so the picker never claims to watch a smaller
    /// area than it does.
    private var monitoredRadiusMeters: Double {
        max(radiusMeters, GeoFence.minimumMonitoredRadiusMeters)
    }

    /// Whether a fix could ever arrive. Under `.denied`, `.restricted` or with Location Services
    /// off, "Locating…" would spin until the user pressed Cancel. Unknown (no snapshot yet) is
    /// treated as available: the stream yields on subscribe, and disabling the button on a value
    /// that has not arrived would leave it permanently dead wherever the stream is inert.
    private var canUseCurrentLocation: Bool {
        guard let snapshot else { return true }
        return PermissionBannerState(snapshot) == .none
    }

    /// Wraps `$label` so the label `TextField` can clear `labelWasAutofilled` on user input
    /// without the auto-fill writers below (which assign `label` directly, not through this
    /// binding) tripping the same flag.
    private var labelBinding: Binding<String> {
        Binding(
            get: { label },
            set: { newValue in
                label = newValue
                labelWasAutofilled = false
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    TextField(L10n.Automation.locationSearchPlaceholder, text: $search.query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            // A field that is only whitespace (or empty) has nothing to search
                            // for — leave Return a no-op rather than showing "No places found."
                            // for text the user never really typed.
                            guard !search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            if let first = search.completions.first {
                                Task { await select(first) }
                            }
                            // Else: the completer hasn't answered this query yet, or answered
                            // with nothing. Either way `search.hasSearched` drives the "No places
                            // found." message below reactively, so it surfaces on its own as soon
                            // as the completer responds — nothing further to do here.
                        }
                    if isLocating {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                        Text(L10n.Automation.locating)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if isLocating {
                        Button(L10n.Automation.cancel) { isLocating = false }
                            .controlSize(.small)
                    } else {
                        Button(L10n.Automation.useCurrentLocation) { useCurrentLocation() }
                            .controlSize(.small)
                            .disabled(!canUseCurrentLocation)
                    }
                }

                if !search.completions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(search.completions, id: \.self) { completion in
                            Button {
                                Task { await select(completion) }
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(completion.title)
                                    if !completion.subtitle.isEmpty {
                                        Text(completion.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Color.secondary.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else if search.hasSearched {
                    Text(L10n.Automation.locationNoResults)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            banner

            MapReader { proxy in
                Map(position: $cameraPosition, interactionModes: .all) {
                    if let coordinate {
                        let clCoordinate = coordinate.clCoordinate
                        Annotation(label.isEmpty ? " " : label, coordinate: clCoordinate) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(.red)
                                .font(.title2)
                        }
                        MapCircle(center: clCoordinate, radius: monitoredRadiusMeters)
                            .foregroundStyle(.blue.opacity(0.18))
                            .stroke(.blue, lineWidth: 1)
                    }
                }
                .onTapGesture(coordinateSpace: .local) { point in
                    if let clCoordinate = proxy.convert(point, from: .local) {
                        set(clCoordinate)
                        pinRequestGeneration += 1
                        let generation = pinRequestGeneration
                        Task { await prefillLabelIfEmpty(for: clCoordinate, generation: generation) }
                    }
                }
                .onMapCameraChange { context in
                    search.updateRegion(context.region)
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Text(L10n.Automation.locationRadius)
                Slider(value: $radiusMeters, in: Self.radiusRange, step: 50)
                Text("\(Int(monitoredRadiusMeters)) m")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(L10n.Automation.locationLabelField)
                        .frame(width: 90, alignment: .leading)
                    TextField(L10n.Automation.locationLabelPlaceholder, text: labelBinding)
                        .textFieldStyle(.roundedBorder)
                }
                Text(L10n.Automation.locationLabelCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 90)
            }
        }
        .task {
            // Subscription lifetime == sheet lifetime, so CoreLocation updates stop when the
            // picker closes. This is the only place in the app that runs continuous updates.
            normalizeRadius()
            if let coordinate { recenter(on: coordinate.clCoordinate) }
            var didSeedSearchRegion = false
            for await snapshot in locationClient.snapshotUpdates() {
                self.snapshot = snapshot
                // For a brand-new rule (no coordinate yet), `recenter(on:)` above never runs, so
                // the map camera — and with it `search`'s completer region, which only otherwise
                // updates via `onMapCameraChange` — stays on its world-spanning default until the
                // user pans. That leaves the very first search unbiased, which is exactly the
                // "wars" case this task exists to fix. Seed both the completer's region and the
                // camera from the last known fix, once: `onMapCameraChange` fires with the
                // camera's *current* region on its very first callback, so if we only seeded the
                // completer, that initial callback (order versus this snapshot is not guaranteed)
                // could immediately clobber the seed with the world-spanning default. Moving the
                // camera too means that first callback carries the biased region instead of
                // fighting it — with the side benefit that a new rule's map opens near the user
                // rather than on the whole planet.
                if !didSeedSearchRegion, coordinate == nil, let fix = snapshot.lastFix {
                    didSeedSearchRegion = true
                    let seededRegion = MKCoordinateRegion(
                        center: fix.clCoordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
                    )
                    search.updateRegion(seededRegion)
                    cameraPosition = .region(seededRegion)
                }
                if isLocating, snapshot.hasFix(fresherThan: Self.currentLocationMaxAge), let fix = snapshot.lastFix {
                    apply(fix, generation: locatingGeneration)
                    isLocating = false
                }
            }
        }
    }

    /// Rendered above the map on purpose: the previous copy sat at the bottom of scrollable
    /// content, where a user who needed it had no indication it existed.
    @ViewBuilder private var banner: some View {
        // No banner at all until the first snapshot lands: an unknown state is not a problem
        // state, and rendering one would accuse every user of having denied access.
        if let snapshot {
            switch PermissionBannerState(snapshot) {
            case .none:
                EmptyView()
            case .servicesOff:
                bannerRow(L10n.Automation.locationServicesOff, action: .openSettings)
            case .notDetermined:
                bannerRow(L10n.Automation.locationNotDetermined, action: .allowAccess)
            case .denied:
                bannerRow(L10n.Automation.locationPermissionDenied, action: .openSettings)
            case .restricted:
                bannerRow(L10n.Automation.locationRestricted, action: .none)
            }
        }
    }

    private enum BannerAction { case allowAccess, openSettings, none }

    @ViewBuilder private func bannerRow(_ message: String, action: BannerAction) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            switch action {
            case .allowAccess:
                Button(L10n.Automation.locationAllowAccess) { locationClient.requestAuthorization() }
                    .controlSize(.small)
            case .openSettings:
                Button(L10n.Automation.locationOpenSettings) { openLocationSettings() }
                    .controlSize(.small)
            case .none:
                EmptyView()
            }
        }
    }

    private func openLocationSettings() {
        // Same pattern as Onboarding.swift:104.
        guard let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices") else { return }
        NSWorkspace.shared.open(url)
    }

    private func set(_ clCoordinate: CLLocationCoordinate2D) {
        coordinate = Coordinate(latitude: clCoordinate.latitude, longitude: clCoordinate.longitude)
    }

    private func recenter(on clCoordinate: CLLocationCoordinate2D) {
        cameraPosition = .region(
            MKCoordinateRegion(
                center: clCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        )
    }

    /// No timeout. The old 12-second timer reported "couldn't determine your location" while
    /// authorization was authorizedAlways and fixes were arriving normally — it was racing
    /// locationd's push cadence, not detecting a real failure. A fresh-enough fix fills the
    /// field immediately; otherwise the button shows "Locating…" until a fix arrives.
    private func useCurrentLocation() {
        pinRequestGeneration += 1
        let generation = pinRequestGeneration
        if let snapshot, snapshot.hasFix(fresherThan: Self.currentLocationMaxAge), let fix = snapshot.lastFix {
            apply(fix, generation: generation)
        } else {
            isLocating = true
            locatingGeneration = generation
        }
    }

    /// A rule saved before the 100 m floor can hold a radius outside the slider's range, which
    /// leaves the thumb pinned at an end while the readout disagrees with it. Normalising once,
    /// when the picker appears, makes the control, the label, the circle and what CoreLocation
    /// monitors all say the same thing.
    private func normalizeRadius() {
        let normalized = min(max(radiusMeters, Self.radiusRange.lowerBound), Self.radiusRange.upperBound)
        if normalized != radiusMeters { radiusMeters = normalized }
    }

    /// `generation` is the pin-request counter captured when this "use current location" attempt
    /// started. If a newer tap, "use current location", or search selection has since bumped the
    /// counter, this result is stale and is dropped rather than moving the pin to a place the
    /// user has already left.
    private func apply(_ fix: Coordinate, generation: Int) {
        guard generation == pinRequestGeneration else { return }
        coordinate = fix
        recenter(on: fix.clCoordinate)
        // Overwrite empty text and our own earlier auto-fill alike, but never text the user
        // typed — see `labelWasAutofilled`.
        if label.isEmpty || labelWasAutofilled {
            label = L10n.Automation.currentLocationLabel
            labelWasAutofilled = true
        }
    }

    /// Names a tapped point so the user does not have to. Silent on failure — `CLGeocoder` is
    /// rate-limited and fails for ordinary reasons; an unnamed pin is fine, a blocking error for
    /// a nicety is not. `generation` is the pin-request counter captured when this tap started;
    /// checked both before starting the network request (the label may already be non-empty,
    /// user-typed) and again after it returns, so a name the user typed during the geocode wins
    /// and a superseded tap does not overwrite a newer pin. Both checks allow overwriting text
    /// that is empty *or* still marked auto-filled (`labelWasAutofilled`) from an earlier writer,
    /// but never text the user typed themselves.
    private func prefillLabelIfEmpty(for clCoordinate: CLLocationCoordinate2D, generation: Int) async {
        guard label.isEmpty || labelWasAutofilled else { return }
        let location = CLLocation(latitude: clCoordinate.latitude, longitude: clCoordinate.longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return }
        guard generation == pinRequestGeneration else { return }
        let name = placemark.name ?? placemark.locality ?? placemark.administrativeArea
        if let name, label.isEmpty || labelWasAutofilled {
            label = name
            labelWasAutofilled = true
        }
    }

    /// Captures the generation rather than bumping it up front: bumping here would supersede an
    /// unrelated in-flight request (e.g. a map-tap geocode from `prefillLabelIfEmpty`) even if
    /// this resolve then fails and writes nothing, silently discarding that other request's
    /// result for no reason. Any later tap or "use current location" still bumps the counter and
    /// fails this call's post-await guard, so supersession still works; we only stop bumping
    /// *before* knowing this attempt will actually produce a write.
    private func select(_ completion: MKLocalSearchCompletion) async {
        let generation = pinRequestGeneration
        guard let resolved = await search.resolve(completion) else {
            // No feedback shown here on a failed resolve (offline, rate-limited, unresolvable
            // completion) — needs a new localized string, deliberately deferred.
            return
        }
        // Clear unconditionally, even if this selection turns out to be superseded below: a
        // resolve did complete, so the stale suggestion list and query should not linger under a
        // pin the user has since moved elsewhere.
        search.clear()
        guard generation == pinRequestGeneration else { return }
        pinRequestGeneration += 1
        set(resolved.coordinate)
        recenter(on: resolved.coordinate)
        if label.isEmpty || labelWasAutofilled {
            label = resolved.name
            labelWasAutofilled = true
        }
    }
}

extension Coordinate {
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
