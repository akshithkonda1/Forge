import SwiftUI
import MapKit
import CoreLocation

/// Restaurants tab: a live Apple Map of nearby places plus the saved menu catalog.
struct LifestylePlacesView: View {
    @ObservedObject var vm: LifestyleViewModel
    @ObservedObject var locationLogger: LocationMealLogger
    @EnvironmentObject var store: AppStore
    @ObservedObject private var location = LifestyleLocationStore.shared

    @State private var camera: MapCameraPosition = .automatic
    @State private var selectedPlace: NearbyPlace?
    @State private var showCatalog = false
    @State private var hasCentered = false

    var body: some View {
        VStack(spacing: 16) {
            mapCard
            statusRow
            nearbyList
            catalogToggle
            if showCatalog {
                NutritionDatabaseView(vm: vm)
            }
        }
        .task { await bootstrap() }
        .onChange(of: location.currentLocation?.timestamp) { _, _ in
            guard !hasCentered, let loc = location.currentLocation else { return }
            hasCentered = true
            camera = .region(MKCoordinateRegion(
                center: loc.coordinate,
                latitudinalMeters: 1_200,
                longitudinalMeters: 1_200
            ))
        }
        .sheet(item: $selectedPlace) { place in
            NearbyPlaceSheet(
                place: place,
                locationLogger: locationLogger,
                vm: vm
            )
            .presentationDetents([.medium, .large])
        }
    }

    private var mapCard: some View {
        ZStack(alignment: .topTrailing) {
            Map(position: $camera, selection: $selectedPlace) {
                UserAnnotation()
                ForEach(location.nearby) { place in
                    Marker(place.name, systemImage: "fork.knife", coordinate: place.coordinate)
                        .tint(Color(hex: "FF4D00"))
                        .tag(place)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapPitchToggle()
            }
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.borderColor.opacity(0.4), lineWidth: 1)
            )

            VStack(spacing: 8) {
                mapButton(icon: "location.fill") {
                    Task { await recenter() }
                }
                mapButton(icon: "arrow.triangle.turn.up.right.diamond.fill") {
                    location.openCurrentLocationInMaps()
                }
            }
            .padding(10)
        }
    }

    private func mapButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textPrimary)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            Image(systemName: location.isAuthorized ? "location.fill" : "location.slash")
                .foregroundColor(location.isAuthorized ? .vitality : .warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text(statusDetail)
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            if location.isSearching {
                ProgressView().controlSize(.small)
            } else if !location.isAuthorized {
                Button("Enable") {
                    Task { await bootstrap() }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.ember)
            }
        }
        .padding(12)
        .background(Color.surface)
        .cornerRadius(14)
    }

    private var statusTitle: String {
        if !location.isAuthorized { return "Location is off" }
        if location.isTracking { return "Tracking your location" }
        return "Location ready"
    }

    private var statusDetail: String {
        if !location.isAuthorized {
            return "Forge uses Apple Maps to show restaurants around you. Location stays on-device."
        }
        if let loc = location.currentLocation {
            let acc = max(5, Int(loc.horizontalAccuracy.rounded()))
            return "±\(acc) m · \(location.nearby.count) places nearby"
        }
        return "Getting a GPS fix…"
    }

    private var nearbyList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Nearby")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Button {
                    Task { await location.refreshNearby() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.ember)
            }

            if let error = location.lastError, location.nearby.isEmpty {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundColor(.warning)
            } else if location.nearby.isEmpty {
                Text("No restaurants found yet. Move a little or tap Refresh.")
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
            } else {
                ForEach(location.nearby.prefix(8)) { place in
                    Button { selectedPlace = place } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.ember)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                    .lineLimit(1)
                                Text(place.address?.isEmpty == false ? place.address! : "Apple Maps place")
                                    .font(.system(size: 11))
                                    .foregroundColor(.textTertiary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(place.distanceLabel)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.textSecondary)
                        }
                        .padding(12)
                        .background(Color.surface)
                        .cornerRadius(14)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var catalogToggle: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showCatalog.toggle() }
        } label: {
            HStack {
                Text(showCatalog ? "Hide saved menus" : "Browse saved restaurant menus")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Image(systemName: showCatalog ? "chevron.up" : "chevron.down")
            }
            .foregroundColor(.textSecondary)
            .padding(14)
            .background(Color.surfaceElevated)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private func bootstrap() async {
        if location.canAsk || !location.isAuthorized {
            let status = await location.requestAccess()
            if status == .denied || status == .restricted {
                location.lastError = "Location is denied. Enable it in Settings → Privacy → Location Services → Forge."
                return
            }
        }
        location.startTracking()
        if let loc = await location.latestLocation() {
            camera = .region(MKCoordinateRegion(
                center: loc.coordinate,
                latitudinalMeters: 1_200,
                longitudinalMeters: 1_200
            ))
        }
        await location.refreshNearby()
    }

    private func recenter() async {
        if let loc = await location.latestLocation() {
            withAnimation {
                camera = .region(MKCoordinateRegion(
                    center: loc.coordinate,
                    latitudinalMeters: 1_000,
                    longitudinalMeters: 1_000
                ))
            }
        }
    }
}

private struct NearbyPlaceSheet: View {
    let place: NearbyPlace
    @ObservedObject var locationLogger: LocationMealLogger
    @ObservedObject var vm: LifestyleViewModel
    @ObservedObject private var location = LifestyleLocationStore.shared
    @Environment(\.dismiss) private var dismiss

    private var menu: [MenuItem] {
        locationLogger.lookupMenu(for: place.name)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(place.name)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.textPrimary)
                        if let address = place.address, !address.isEmpty {
                            Text(address)
                                .font(.system(size: 13))
                                .foregroundColor(.textSecondary)
                        }
                        Text(place.distanceLabel + " away")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.ember)
                    }

                    HStack(spacing: 10) {
                        Button {
                            location.openInMaps(place)
                        } label: {
                            label("Open in Maps", icon: "map.fill")
                        }
                        Button {
                            location.directions(to: place)
                        } label: {
                            label("Directions", icon: "arrow.triangle.turn.up.right.diamond.fill")
                        }
                    }

                    Text("Log a meal")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.textPrimary)

                    ForEach(menu) { item in
                        Button {
                            locationLogger.detectedVenue = place.name
                            locationLogger.logSelectedMeal(item, to: vm)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.textPrimary)
                                    Text("\(item.calories) cal · \(item.protein)g protein")
                                        .font(.system(size: 12))
                                        .foregroundColor(.textTertiary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundColor(.ember)
                            }
                            .padding(14)
                            .background(Color.surfaceElevated)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(Color.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func label(_ title: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
            Text(title)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.ember)
        .cornerRadius(12)
    }
}
