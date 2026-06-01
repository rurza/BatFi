//
//  AutomationLocationPicker.swift
//  BatFi
//
//  Map-based location picker for a rule's geofence: address search, tap-to-place,
//  "use current location", and a radius slider drawn as a circle overlay.
//

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
    @State private var permissionDenied = false
    @State private var isLocating = false
    @State private var locationMessage: String?

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
                }
                Button(L10n.Automation.useCurrentLocation) {
                    Task { await useCurrentLocation() }
                }
                .controlSize(.small)
                .disabled(isLocating)
            }

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
                Slider(value: $radiusMeters, in: 50...2000, step: 50)
                Text("\(Int(radiusMeters)) m")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
            }

            TextField(L10n.Automation.locationLabelPlaceholder, text: $label)
                .textFieldStyle(.roundedBorder)

            if permissionDenied {
                Text(L10n.Automation.locationPermissionDenied)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let locationMessage {
                Text(locationMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            // Ask for permission as soon as the location section is shown, so the prompt
            // appears when the user opts into a location condition (no-op once determined).
            locationClient.requestAuthorization()
            if let coordinate {
                recenter(on: coordinate.clCoordinate)
            }
        }
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

    private func useCurrentLocation() async {
        if locationClient.authorizationStatus() == .denied {
            permissionDenied = true
            return
        }
        isLocating = true
        locationMessage = nil
        defer { isLocating = false }
        let coordinate = await locationClient.currentCoordinate()
        if let coordinate {
            permissionDenied = false
            locationMessage = nil
            self.coordinate = coordinate
            recenter(on: coordinate.clCoordinate)
            if label.isEmpty { label = L10n.Automation.currentLocationLabel }
        } else if locationClient.authorizationStatus() == .denied {
            permissionDenied = true
        } else {
            locationMessage = L10n.Automation.locationCouldNotDetermine
        }
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
