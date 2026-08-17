import SwiftUI
import MapKit
import CoreLocation
import UIKit

private enum FoodSearchKind: String, CaseIterable, Identifiable {
    case restaurants, cafes, fastFood, grocery
    var id: String { rawValue }
    var title: String {
        switch self {
        case .restaurants: return "Restaurants"
        case .cafes: return "Cafes"
        case .fastFood: return "Fast food"
        case .grocery: return "Markets"
        }
    }
    var query: String {
        switch self {
        case .restaurants: return "restaurants"
        case .cafes: return "cafes"
        case .fastFood: return "fast food"
        case .grocery: return "grocery"
        }
    }
}

/// Restaurants tab: a live Apple Map of nearby places plus the saved menu catalog.
struct LifestylePlacesView: View {
    @ObservedObject var vm: LifestyleViewModel
    @ObservedObject var locationLogger: LocationMealLogger
    @EnvironmentObject var store: AppStore
    @ObservedObject private var location = LifestyleLocationStore.shared

    @State private var camera: MapCameraPosition = .userLocation(followsHeading: false, fallback: .automatic)
    @State private var selectedPlace: NearbyPlace?
    @State private var showCatalog = false
    @State private var hasCentered = false
    @State private var searchText = ""
    @State private var foodKind: FoodSearchKind = .restaurants
    @State private var showOpenSettings = false

    var body: some View {
        VStack(spacing: 16) {
            searchBar
            foodFilters
            mapCard
            statusRow
            nearbyList
            catalogToggle
            if showCatalog {
                NutritionDatabaseView(vm: vm)
            }
        }
        .task { await bootstrap() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            location.refreshAuthorization()
            if location.isAuthorized {
                Task { await followUserAndSearch() }
            }
        }
        .onChange(of: location.currentLocation?.timestamp) { _, _ in
            guard let loc = location.currentLocation else { return }
            if !hasCentered || location.anchorSource == .gps {
                hasCentered = true
                camera = .region(MKCoordinateRegion(
                    center: loc.coordinate,
                    latitudinalMeters: 1_200,
                    longitudinalMeters: 1_200
                ))
            }
            if location.nearby.isEmpty {
                Task { await runSearch() }
            }
        }
        .alert("Location is off", isPresented: $showOpenSettings) {
            Button("Open Settings") { openSystemSettings() }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Turn it on so Places can default to you. It stays on this iPhone — Forge never uploads it. Settings → Privacy & Security → Location Services → Forge.")
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
                Button(location.canAsk ? "Allow" : "Turn on") {
                    Task { await requestLocationPermission() }
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
        if location.canAsk { return "Forge needs your location" }
        if !location.isAuthorized { return "Location is off" }
        if location.currentLocation != nil { return location.anchorSource.statusLine }
        return "Finding your location"
    }

    private var statusDetail: String {
        if location.canAsk {
            return "Allow location so the map opens on you. It never leaves this iPhone."
        }
        if !location.isAuthorized {
            return "Turn it on in Settings. Location stays on-device — Forge never uploads it."
        }
        if let loc = location.currentLocation {
            let acc = max(5, Int(loc.horizontalAccuracy.rounded()))
            return "±\(acc) m · \(location.nearby.count) places nearby"
        }
        if ProcessInfo.processInfo.isiOSAppOnMac {
            return "This Mac has no GPS. Waiting on a Wi‑Fi location from macOS."
        }
        #if targetEnvironment(simulator)
        return "Simulator has no GPS until you set Features → Location → Apple."
        #else
        return "Waiting on GPS — the map will jump to you."
        #endif
    }

    private var nearbyList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Nearby")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Button {
                    Task { await runSearch() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.ember)
            }

            if let error = location.lastError, location.nearby.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(.warning)
                    Button("Try again") {
                        Task { await runSearch() }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.ember)
                }
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
                                Text(placeLine(place))
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
        if !location.isAuthorized {
            await requestLocationPermission()
            return
        }
        await followUserAndSearch()
    }

    /// System When In Use sheet if we can still ask. Settings if they already said no.
    private func requestLocationPermission() async {
        if location.canAsk {
            let status = await location.requestAccess()
            if location.isAuthorized {
                await followUserAndSearch()
            } else if status == .denied || status == .restricted {
                showOpenSettings = true
            }
            return
        }
        if !location.isAuthorized {
            showOpenSettings = true
        }
    }

    private func followUserAndSearch() async {
        location.startTracking()
        let loc: CLLocation?
        if let current = location.currentLocation {
            loc = current
        } else {
            loc = await location.latestLocation()
        }
        if let loc {
            hasCentered = true
            camera = .region(MKCoordinateRegion(
                center: loc.coordinate,
                latitudinalMeters: 1_200,
                longitudinalMeters: 1_200
            ))
        } else {
            camera = .userLocation(followsHeading: false, fallback: .automatic)
        }
        await runSearch()
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundColor(.textTertiary)
            TextField("Search restaurants or menus…", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await runSearch() } }
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.textMuted)
                }
            }
        }
        .padding(12)
        .background(Color.surface)
        .cornerRadius(12)
    }

    private var foodFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FoodSearchKind.allCases) { kind in
                    Button {
                        foodKind = kind
                        Task { await runSearch() }
                    } label: {
                        Text(kind.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(foodKind == kind ? .background : .textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(foodKind == kind ? Color.textPrimary : Color.surface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func runSearch() async {
        let typed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        await location.refreshNearby(query: typed.isEmpty ? foodKind.query : typed)
    }

    private func placeLine(_ place: NearbyPlace) -> String {
        let hasMenu = locationLogger.catalogMenu(for: place.name) != nil
        if let category = place.categoryLabel, !category.isEmpty {
            return hasMenu ? "\(category) · Menu" : category
        }
        return hasMenu ? "Menu available" : (place.address?.isEmpty == false ? place.address! : "Apple Maps place")
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

    private var catalogMenu: [MenuItem]? {
        locationLogger.catalogMenu(for: place.name)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(place.name)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        if let category = place.categoryLabel {
                            Text(category)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.ember)
                        }
                        if let address = place.address, !address.isEmpty {
                            Text(address)
                                .font(.system(size: 13))
                                .foregroundColor(.textSecondary)
                        }
                        Text(place.distanceLabel + " away")
                            .font(.system(size: 13))
                            .foregroundColor(.textTertiary)
                    }

                    HStack(spacing: 10) {
                        Button {
                            location.openInMaps(place)
                        } label: {
                            label("Maps", icon: "map.fill")
                        }
                        Button {
                            location.directions(to: place)
                        } label: {
                            label("Walk", icon: "arrow.triangle.turn.up.right.diamond.fill")
                        }
                    }

                    if let phone = place.phoneNumber, let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                        Link(destination: url) {
                            Text(phone)
                                .font(.system(size: 14))
                                .foregroundColor(.textSecondary)
                        }
                    }

                    if let site = place.url {
                        Link(destination: site) {
                            Text("Website / menu")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.ember)
                        }
                    }

                    if let menu = catalogMenu, !menu.isEmpty {
                        Text("Menu")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Text("From Forge’s kitchen file for this chain. Tap a dish to log it.")
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
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
                    } else {
                        Text("Menu")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Text("Apple Maps found this kitchen. Open it in Maps for hours and any published menu, or use the website if they have one.")
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
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
