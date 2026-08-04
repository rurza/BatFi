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
    @State private var searchText = ""
    @State private var snapshot = LocationSnapshot()
    @State private var isLocating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L10n.Automation.locationSearchPlaceholder, text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await search() } }
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
                        MapCircle(center: clCoordinate, radius: radiusMeters)
                            .foregroundStyle(.blue.opacity(0.18))
                            .stroke(.blue, lineWidth: 1)
                    }
                }
                .onTapGesture(coordinateSpace: .local) { point in
                    if let clCoordinate = proxy.convert(point, from: .local) {
                        set(clCoordinate)
                    }
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Text(L10n.Automation.locationRadius)
                Slider(value: $radiusMeters, in: 100...2000, step: 50)
                Text("\(Int(radiusMeters)) m")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
            }

            TextField(L10n.Automation.locationLabelPlaceholder, text: $label)
                .textFieldStyle(.roundedBorder)

        }
        .task {
            // Subscription lifetime == sheet lifetime, so CoreLocation updates stop when the
            // picker closes. This is the only place in the app that runs continuous updates.
            if let coordinate { recenter(on: coordinate.clCoordinate) }
            for await snapshot in locationClient.snapshotUpdates() {
                self.snapshot = snapshot
                if isLocating, let fix = snapshot.lastFix {
                    apply(fix)
                    isLocating = false
                }
            }
        }
    }

    /// Rendered above the map on purpose: the previous copy sat at the bottom of scrollable
    /// content, where a user who needed it had no indication it existed.
    @ViewBuilder private var banner: some View {
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
        if snapshot.hasFix(fresherThan: 300), let fix = snapshot.lastFix {
            apply(fix)
        } else {
            isLocating = true
        }
    }

    private func apply(_ fix: Coordinate) {
        coordinate = fix
        recenter(on: fix.clCoordinate)
        if label.isEmpty { label = L10n.Automation.currentLocationLabel }
    }

    private func search() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        let response = try? await MKLocalSearch(request: request).start()
        guard let item = response?.mapItems.first else { return }
        let clCoordinate = item.placemark.coordinate
        set(clCoordinate)
        recenter(on: clCoordinate)
        if label.isEmpty { label = item.name ?? query }
    }
}

extension Coordinate {
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
