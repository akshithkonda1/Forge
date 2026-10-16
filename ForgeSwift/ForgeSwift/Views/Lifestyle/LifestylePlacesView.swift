import SwiftUI
import MapKit
import CoreLocation
import UIKit
import ForgeCore

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

    @State private var camera: MapCameraPosition = .automatic
    @State private var selectedPlace: NearbyPlace?
    @State private var showCatalog = false
    @State private var hasCentered = false
    @State private var searchText = ""
    @State private var foodKind: FoodSearchKind = .restaurants
    @State private var showOpenSettings = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
            PlacesSearchField(text: $searchText, prompt: "Search restaurants or menus…") {
                Task { await runSearch() }
            }
            foodFilters
            mapCard
            nearbyCard
            catalogCard
            if showCatalog {
                NutritionDatabaseView(vm: vm)
            }
        }
        .task { await bootstrap() }
        .onChange(of: foodKind) { _, _ in
            Task { await runSearch() }
        }
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

    // MARK: Map card

    /// One card: the map (or the location prompt) with a status footer under it.
    private var mapCard: some View {
        VStack(spacing: 0) {
            if location.currentLocation != nil {
                liveMap
                mapFooter
            } else {
                mapPlaceholder
            }
        }
        .forgeContentCard(tint: .amber, padding: 0)
    }

    private var liveMap: some View {
        Map(position: $camera, selection: $selectedPlace) {
            UserAnnotation()
            ForEach(location.nearby) { place in
                Marker(place.name, systemImage: "fork.knife", coordinate: place.coordinate)
                    .tint(Color.ember)
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
        .overlay(alignment: .bottomTrailing) {
            ForgeIconButton(
                systemImage: "arrow.triangle.turn.up.right.diamond.fill",
                accessibilityLabel: "Open in Maps",
                tinted: false
            ) {
                location.openCurrentLocationInMaps()
            }
            .background(.ultraThinMaterial, in: Circle())
            .padding(FDS.Spacing.md)
        }
    }

    /// Shown until the first fix. It carries the whole status, so the footer is hidden.
    private var mapPlaceholder: some View {
        VStack(spacing: ForgeLayout.blockGap) {
            ForgeIconWell(
                systemImage: location.isAuthorized ? "location.viewfinder" : "location.slash",
                tint: location.isAuthorized ? Color.vitality : Color.warning,
                diameter: 48
            )
            VStack(spacing: ForgeLayout.pairGap) {
                Text(location.isAuthorized ? "Finding you" : "Turn on Location")
                    .font(FDS.TypeScale.Dynamic.title)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .forgeWrapping()
                    .accessibilityAddTraits(.isHeader)
                Text(statusDetail)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .forgeWrapping()
            }
            if !location.isAuthorized {
                permissionButton
                    .frame(maxWidth: 280)
            } else if location.isSearching {
                ProgressView().controlSize(.small)
            }
        }
        .padding(ForgeLayout.cardPadding)
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    private var mapFooter: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            HStack(alignment: .firstTextBaseline, spacing: ForgeLayout.rowGap) {
                Image(systemName: location.isAuthorized ? "location.fill" : "location.slash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(location.isAuthorized ? Color.vitality : Color.warning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text(statusTitle)
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                    Text(statusDetail)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textTertiary)
                        .forgeWrapping()
                }
                .layoutPriority(1)
                Spacer(minLength: FDS.Spacing.xs)
                if location.isSearching {
                    ProgressView().controlSize(.small)
                }
            }
            if !location.isAuthorized {
                permissionButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ForgeLayout.cardPadding)
    }

    private var permissionButton: some View {
        ForgeSecondaryButton(title: location.canAsk ? "Allow" : "Turn on", accent: .amber) {
            Task { await requestLocationPermission() }
        }
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

    /// Locating is a wait. Raw Core Location strings never reach the person.
    private var displayableNearbyError: String? {
        guard location.nearby.isEmpty, let error = location.lastError else { return nil }
        let lowered = error.lowercased()
        if lowered.contains("kclerror") || lowered.contains("finding your location") {
            return nil
        }
        return error
    }

    // MARK: Nearby card

    private var nearbyPlaces: [NearbyPlace] {
        Array(location.nearby.prefix(8))
    }

    private var nearbyCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            nearbyHeader
            nearbyContent
        }
        .forgeContentCard(tint: .amber)
    }

    private var nearbyHeader: some View {
        HStack(alignment: .center, spacing: FDS.Spacing.sm) {
            VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                Text("Nearby")
                    .forgeSectionLabel(tint: .textTertiary)
                    .accessibilityAddTraits(.isHeader)
                if !nearbyPlaces.isEmpty {
                    ForgeCardMeta(text: "\(nearbyPlaces.count) place\(nearbyPlaces.count == 1 ? "" : "s")")
                }
            }
            Spacer(minLength: FDS.Spacing.sm)
            ForgeIconButton(
                systemImage: "arrow.clockwise",
                accent: .amber,
                accessibilityLabel: "Refresh",
                tinted: false
            ) {
                Task { await runSearch() }
            }
        }
    }

    @ViewBuilder
    private var nearbyContent: some View {
        if let error = displayableNearbyError {
            VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
                ForgeEmptyNote(
                    title: error,
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .warning
                )
                ForgeSecondaryButton(title: "Try again", accent: .amber) {
                    Task { await runSearch() }
                }
            }
        } else if location.nearby.isEmpty {
            ForgeEmptyNote(
                title: "No restaurants found yet.",
                message: "Move a little or tap Refresh.",
                systemImage: "fork.knife",
                tint: .amber
            )
        } else {
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                ForEach(nearbyPlaces) { place in
                    Button {
                        selectedPlace = place
                    } label: {
                        ForgeListRow(
                            icon: "fork.knife",
                            iconColor: .amber,
                            title: place.name,
                            subtitle: placeLine(place),
                            trailing: place.distanceLabel,
                            showChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens place details")
                }
            }
        }
    }

    // MARK: Saved menus

    private var catalogCard: some View {
        Button {
            withAnimation(reduceMotion ? nil : ForgeMotion.smooth) { showCatalog.toggle() }
        } label: {
            HStack(spacing: ForgeLayout.rowGap) {
                Text(showCatalog ? "Hide saved menus" : "Browse saved restaurant menus")
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Spacer(minLength: FDS.Spacing.xs)
                Image(systemName: showCatalog ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textMuted)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, ForgeLayout.rowVerticalPadding)
            .frame(minHeight: ForgeUX.minTap)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(showCatalog ? "Expanded" : "Collapsed")
        .forgeContentCard()
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
            camera = .automatic
        }
        await runSearch()
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var foodKindOptions: [ForgeSegmentOption<FoodSearchKind>] {
        FoodSearchKind.allCases.map { kind in
            ForgeSegmentOption<FoodSearchKind>(value: kind, title: kind.title)
        }
    }

    private var foodFilters: some View {
        ForgeSegmentedControl(foodKindOptions, selection: $foodKind, accent: .amber)
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
}

// MARK: - Search field

/// Magnifier, field and clear button on the opaque inset tile used for fields that sit
/// directly on the screen background. Padding 12, 44 pt tall, 44 pt clear target.
private struct PlacesSearchField: View {
    @Binding var text: String
    var prompt: String
    var onSubmit: () -> Void

    var body: some View {
        HStack(spacing: FDS.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.textTertiary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .font(HomeType.body)
                .foregroundStyle(Color.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { onSubmit() }
                .padding(.trailing, text.isEmpty ? ForgeLayout.tilePadding : 0)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.textMuted)
                        .frame(width: ForgeUX.minTap, height: ForgeUX.minTap)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, ForgeLayout.tilePadding)
        .frame(minHeight: ForgeUX.minTap)
        .forgeInsetTile(radius: ForgeLayout.innerRadius)
    }
}

// MARK: - Place sheet

private struct NearbyPlaceSheet: View {
    let place: NearbyPlace
    @ObservedObject var locationLogger: LocationMealLogger
    @ObservedObject var vm: LifestyleViewModel
    @ObservedObject private var location = LifestyleLocationStore.shared
    @Environment(\.dismiss) private var dismiss

    private var catalogMenu: [MenuItem]? {
        locationLogger.catalogMenu(for: place.name)
    }

    private var phoneURL: URL? {
        guard let phone = place.phoneNumber else { return nil }
        return URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
                    header
                    actions
                    if phoneURL != nil || place.url != nil {
                        contactCard
                    }
                    menuCard
                }
                .forgeScreenInsets(top: FDS.Spacing.lg)
            }
            .background(Color.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    // MARK: Header and actions

    private var metaLine: String {
        var parts: [String] = []
        if let category = place.categoryLabel, !category.isEmpty {
            parts.append(category)
        }
        parts.append(place.distanceLabel + " away")
        return parts.joined(separator: " · ")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            Text(place.name)
                .font(FDS.TypeScale.Dynamic.title)
                .foregroundStyle(Color.textPrimary)
                .forgeWrapping()
                .accessibilityAddTraits(.isHeader)
            if let address = place.address, !address.isEmpty {
                Text(address)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }
            Text(metaLine)
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
                .forgeWrapping()
        }
    }

    /// Directions is the sheet's one primary; Maps is the secondary.
    private var actions: some View {
        VStack(spacing: ForgeLayout.tileGap) {
            ForgePrimaryButton(
                title: "Directions",
                icon: "arrow.triangle.turn.up.right.diamond.fill"
            ) {
                location.directions(to: place)
            }
            ForgeSecondaryButton(title: "Open in Maps", icon: "map.fill", accent: .amber) {
                location.openInMaps(place)
            }
        }
    }

    // MARK: Contact

    private var contactCard: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            if let phone = place.phoneNumber, let url = phoneURL {
                Link(destination: url) {
                    ForgeListRow(
                        icon: "phone.fill",
                        iconColor: .amber,
                        title: phone,
                        showChevron: true
                    )
                }
            }
            if let site = place.url {
                Link(destination: site) {
                    ForgeListRow(
                        icon: "safari",
                        iconColor: .amber,
                        title: "Website / menu",
                        showChevron: true
                    )
                }
            }
        }
        .forgeContentCard(tint: .amber)
    }

    // MARK: Menu

    @ViewBuilder
    private var menuCard: some View {
        if let menu = catalogMenu, !menu.isEmpty {
            VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
                ForgeCardHeader("Menu", meta: "\(menu.count) items")
                Text("From Forge’s kitchen file for this chain. Tap a dish to log it.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .forgeWrapping()
                VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                    ForEach(menu) { item in
                        menuRow(item)
                    }
                }
            }
            .forgeContentCard(tint: .amber)
        } else {
            VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
                ForgeCardHeader("Menu")
                Text("Apple Maps found this kitchen. Open it in Maps for hours and any published menu, or use the website if they have one.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
            }
            .forgeContentCard(tint: .amber)
        }
    }

    private func menuRow(_ item: MenuItem) -> some View {
        Button {
            ForgeHaptics.play(.press)
            locationLogger.detectedVenue = place.name
            locationLogger.logSelectedMeal(item, to: vm)
            dismiss()
        } label: {
            HStack(spacing: ForgeLayout.rowGap) {
                VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                    Text(item.name)
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Text("\(item.calories) cal · \(item.protein)g protein")
                        .font(HomeType.body)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(2)
                }
                .layoutPriority(1)
                Spacer(minLength: FDS.Spacing.xs)
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.ember)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, ForgeLayout.rowVerticalPadding)
            .frame(minHeight: ForgeUX.minTap)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.name), \(item.calories) calories, \(item.protein) grams protein")
        .accessibilityHint("Logs this dish and closes")
    }
}
