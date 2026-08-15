import Foundation
import CoreLocation
import MapKit
import Combine

/// Live location + nearby Apple Maps places for Lifestyle.
///
/// Default is always the user. Live GPS first, then the last place we
/// saved for them on this iPhone. Coordinates never leave the device —
/// not ARIA, not the backend, not a snapshot. Apple Maps search runs
/// on-device / through Apple, not Forge. Cold `kCLErrorLocationUnknown`
/// is ignored. Simulator and “Designed for iPhone” on macOS have no GPS
/// radio — they need a simulated pin or a Wi‑Fi location from the Mac.
@MainActor
final class LifestyleLocationStore: NSObject, ObservableObject {
    static let shared = LifestyleLocationStore()

    enum AnchorSource: String {
        case gps, cached, saved
        var statusLine: String {
            switch self {
            case .gps: return "Using your location"
            case .cached, .saved: return "Using your last location"
            }
        }
    }

    @Published private(set) var authorization: CLAuthorizationStatus
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var isTracking = false
    @Published private(set) var nearby: [NearbyPlace] = []
    @Published private(set) var isSearching = false
    @Published private(set) var anchorSource: AnchorSource = .saved
    @Published var lastError: String?

    private let manager = CLLocationManager()
    private var authWaiters: [CheckedContinuation<CLAuthorizationStatus, Never>] = []
    private var upgradedAccuracy = false
    private var unknownRetries = 0

    /// Simulator, Mac Catalyst, and “Designed for iPhone” on Apple silicon
    /// have no GPS radio. macOS 27 gives a Wi‑Fi / IP fix, or nothing until
    /// Features → Location / System Settings is turned on.
    private static var noHardwareGPS: Bool {
        #if targetEnvironment(simulator)
        return true
        #elseif targetEnvironment(macCatalyst)
        return true
        #else
        return ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }

    nonisolated private static var emulatedLocationHint: String {
        #if targetEnvironment(simulator)
        return "Simulator has no GPS. Features → Location → Apple (or a city run). In Xcode: Debug → Simulate Location."
        #else
        if ProcessInfo.processInfo.isiOSAppOnMac {
            return "This Mac has no GPS. Turn on Location Services for Forge in System Settings. The first Wi‑Fi fix can take a few seconds — then tap Refresh."
        }
        return "Couldn't get a location fix yet. Wait a moment and tap Refresh."
        #endif
    }

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        // Simulator has no GPS radio. Coarse + pause-on-stationary never
        // delivers a fix unless Features → Location is already set — and
        // even then the first reading often has accuracy < 0.
        if Self.noHardwareGPS {
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            manager.distanceFilter = kCLDistanceFilterNone
            manager.pausesLocationUpdatesAutomatically = false
        } else {
            manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
            manager.distanceFilter = 40
            manager.pausesLocationUpdatesAutomatically = true
        }
        manager.activityType = .other
        currentLocation = Self.usable(manager.location) ?? Self.loadSavedLocation()
        if currentLocation != nil {
            anchorSource = manager.location != nil ? .cached : .saved
        }
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    var canAsk: Bool { authorization == .notDetermined }

    func refreshAuthorization() {
        authorization = manager.authorizationStatus
    }

    func requestAccess() async -> CLAuthorizationStatus {
        if authorization != .notDetermined { return authorization }
        manager.requestWhenInUseAuthorization()
        return await withCheckedContinuation { continuation in
            authWaiters.append(continuation)
        }
    }

    func startTracking() {
        guard isAuthorized else { return }
        if !CLLocationManager.locationServicesEnabled() {
            lastError = Self.noHardwareGPS && ProcessInfo.processInfo.isiOSAppOnMac
                ? "Location Services are off on this Mac. System Settings → Privacy & Security → Location Services."
                : "Location Services are off. Enable them in Settings."
            return
        }
        if currentLocation == nil {
            if let live = Self.usable(manager.location) {
                adopt(live, source: .cached)
            } else if let saved = Self.loadSavedLocation() {
                adopt(saved, source: .saved)
            }
        }
        if !isTracking {
            manager.desiredAccuracy = Self.noHardwareGPS
                ? kCLLocationAccuracyHundredMeters
                : kCLLocationAccuracyThreeKilometers
            manager.startUpdatingLocation()
            isTracking = true
            upgradedAccuracy = false
            unknownRetries = 0
        }
        // requestLocation() on Simulator races startUpdatingLocation and
        // usually fails with kCLErrorLocationUnknown. Device still uses it
        // as a one-shot kick when we have no pin yet.
        if currentLocation == nil, !Self.noHardwareGPS {
            manager.requestLocation()
        }
        if lastError != nil, currentLocation != nil {
            lastError = nil
        }
    }

    func stopTracking() {
        guard isTracking else { return }
        manager.stopUpdatingLocation()
        isTracking = false
    }

    /// Always the user: live GPS, then the system cache, then the last
    /// place we saved for them. Never a canned city.
    func latestLocation() async -> CLLocation? {
        if let currentLocation, Self.isFresh(currentLocation, maxAge: 180) {
            return currentLocation
        }
        if isAuthorized { startTracking() }
        let wait = Self.noHardwareGPS ? 14.0 : 8.0
        let deadline = Date().addingTimeInterval(wait)
        while Date() < deadline {
            if let currentLocation { return currentLocation }
            if let live = Self.usable(manager.location) {
                adopt(live, source: .cached)
                return live
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        if let live = Self.usable(manager.location) {
            adopt(live, source: .cached)
            return live
        }
        if let saved = currentLocation ?? Self.loadSavedLocation() {
            adopt(saved, source: .saved)
            return saved
        }
        if Self.noHardwareGPS {
            lastError = Self.emulatedLocationHint
        }
        return nil
    }

    func refreshNearby(query: String = "restaurants") async {
        isSearching = true
        lastError = nil
        defer { isSearching = false }

        guard let location = await latestLocation() else {
            lastError = isAuthorized
                ? "Finding your location…"
                : "Turn on Location to see places around you."
            nearby = []
            return
        }

        if await search(query: query, around: location, meters: 2_400) { return }
        if await search(query: query, around: location, meters: 12_000) { return }
        // Simulator Maps often returns nothing when the POI filter is tight.
        if await search(query: query, around: location, meters: 20_000, relaxFilter: true) { return }

        if nearby.isEmpty {
            lastError = "No places around you yet. Try Refresh."
        }
    }

    func openInMaps(_ place: NearbyPlace) {
        place.mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsMapTypeKey: MKMapType.standard.rawValue,
        ])
    }

    func directions(to place: NearbyPlace) {
        place.mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking,
        ])
    }

    func openCurrentLocationInMaps() {
        guard let currentLocation else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: currentLocation.coordinate))
        item.name = "Current Location"
        item.openInMaps(launchOptions: nil)
    }

    private func adopt(_ location: CLLocation, source: AnchorSource) {
        currentLocation = location
        anchorSource = source
        Self.save(location)
        if source == .gps, !upgradedAccuracy {
            upgradedAccuracy = true
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        }
    }

    @discardableResult
    private func search(
        query: String,
        around location: CLLocation,
        meters: CLLocationDistance,
        relaxFilter: Bool = false
    ) async -> Bool {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        if !relaxFilter {
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [
                .restaurant, .cafe, .bakery, .brewery, .foodMarket, .winery,
            ])
        }
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: meters,
            longitudinalMeters: meters
        )
        do {
            let response = try await MKLocalSearch(request: request).start()
            let rows = response.mapItems.compactMap { Self.place(from: $0, relativeTo: location) }
                .sorted { $0.distanceMeters < $1.distanceMeters }
            if !rows.isEmpty {
                nearby = rows
                lastError = nil
                return true
            }
        } catch {
            lastError = Self.searchErrorCopy(error)
        }
        return false
    }

    nonisolated private static func place(from item: MKMapItem, relativeTo origin: CLLocation) -> NearbyPlace? {
        guard let coord = item.placemark.location?.coordinate else { return nil }
        let meters = item.placemark.location?.distance(from: origin) ?? 0
        return NearbyPlace(
            name: item.name ?? "Place",
            category: item.pointOfInterestCategory?.rawValue,
            categoryLabel: NearbyPlace.label(for: item.pointOfInterestCategory),
            coordinate: coord,
            distanceMeters: meters,
            mapItem: item,
            address: [
                item.placemark.subThoroughfare,
                item.placemark.thoroughfare,
                item.placemark.locality,
            ].compactMap { $0 }.joined(separator: " "),
            phoneNumber: item.phoneNumber,
            url: item.url
        )
    }

    nonisolated private static func loadSavedLocation() -> CLLocation? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "forge.lifestyle.lastLat") != nil else { return nil }
        let lat = defaults.double(forKey: "forge.lifestyle.lastLat")
        let lon = defaults.double(forKey: "forge.lifestyle.lastLon")
        let acc = defaults.object(forKey: "forge.lifestyle.lastAcc") as? Double ?? 65
        return usable(CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: 0,
            horizontalAccuracy: acc,
            verticalAccuracy: -1,
            timestamp: Date()
        ))
    }

    nonisolated private static func save(_ location: CLLocation) {
        let defaults = UserDefaults.standard
        defaults.set(location.coordinate.latitude, forKey: "forge.lifestyle.lastLat")
        defaults.set(location.coordinate.longitude, forKey: "forge.lifestyle.lastLon")
        defaults.set(location.horizontalAccuracy, forKey: "forge.lifestyle.lastAcc")
    }

    nonisolated private static func usable(_ location: CLLocation?) -> CLLocation? {
        guard let location else { return nil }
        let coord = location.coordinate
        guard CLLocationCoordinate2DIsValid(coord) else { return nil }
        guard abs(coord.latitude) > 0.01 || abs(coord.longitude) > 0.01 else { return nil }
        // Simulator's first simulated pin often arrives with accuracy < 0
        // ("invalid") even though the coordinate is Apple Park / the GPX.
        if location.horizontalAccuracy < 0 {
            guard noHardwareGPS else { return nil }
            return CLLocation(
                coordinate: coord,
                altitude: location.altitude,
                horizontalAccuracy: 65,
                verticalAccuracy: location.verticalAccuracy,
                timestamp: location.timestamp
            )
        }
        guard location.horizontalAccuracy < 20_000 else { return nil }
        return location
    }

    nonisolated private static func isFresh(_ location: CLLocation, maxAge: TimeInterval) -> Bool {
        Date().timeIntervalSince(location.timestamp) < maxAge && usable(location) != nil
    }

    nonisolated private static func searchErrorCopy(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain || ns.domain == "MKErrorDomain" {
            return "Apple Maps couldn't search nearby. Check the network and try again."
        }
        return "Couldn't find nearby places. Move a little or tap Refresh."
    }

    nonisolated private static func locationErrorCopy(_ error: Error) -> String? {
        let cl = error as? CLError
        switch cl?.code {
        case .locationUnknown, .headingFailure, .none:
            // Transient on device. Simulator with Features → Location → None
            // stays here forever — caller decides when to explain that.
            return nil
        case .denied, .restricted:
            if noHardwareGPS, ProcessInfo.processInfo.isiOSAppOnMac {
                return "Location is off. System Settings → Privacy & Security → Location Services → Forge."
            }
            return "Location is off. Enable it in Settings → Privacy → Location Services → Forge."
        case .network:
            return "Can't reach location services. Check Wi‑Fi or cellular."
        case .regionMonitoringDenied, .regionMonitoringFailure, .regionMonitoringSetupDelayed:
            return nil
        default:
            return "Couldn't get a GPS fix. Try again in the open."
        }
    }

    private func resumeAuthWaiters(_ status: CLAuthorizationStatus) {
        let waiters = authWaiters
        authWaiters.removeAll()
        waiters.forEach { $0.resume(returning: status) }
    }

}

extension LifestyleLocationStore: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorization = manager.authorizationStatus
            resumeAuthWaiters(authorization)
            if isAuthorized {
                startTracking()
            } else {
                stopTracking()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = Self.usable(locations.last) else { return }
        Task { @MainActor in
            adopt(location, source: .gps)
            lastError = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            // kCLErrorDomain 0 = locationUnknown. Core Location fires this
            // while the first fix is still coming. Keep waiting — unless
            // we are in Simulator with no simulated location at all.
            if Self.locationErrorCopy(error) == nil {
                unknownRetries += 1
                if let live = Self.usable(manager.location) {
                    adopt(live, source: .cached)
                    lastError = nil
                    return
                }
                if Self.noHardwareGPS, unknownRetries >= 3, currentLocation == nil {
                    lastError = Self.emulatedLocationHint
                }
                return
            }
            guard let copy = Self.locationErrorCopy(error) else { return }
            lastError = copy
        }
    }
}

struct NearbyPlace: Identifiable, Hashable {
    let name: String
    let category: String?
    let categoryLabel: String?
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: Double
    let mapItem: MKMapItem
    let address: String?
    let phoneNumber: String?
    let url: URL?

    static func label(for category: MKPointOfInterestCategory?) -> String? {
        guard let category else { return nil }
        switch category {
        case .restaurant: return "Restaurant"
        case .cafe: return "Cafe"
        case .bakery: return "Bakery"
        case .brewery: return "Brewery"
        case .foodMarket: return "Market"
        case .winery: return "Winery"
        default: return category.rawValue
            .replacingOccurrences(of: "MKPOICategory", with: "")
        }
    }

    var id: String {
        "\(name)-\(coordinate.latitude)-\(coordinate.longitude)"
    }

    var distanceLabel: String {
        if distanceMeters < 1_000 {
            return "\(Int(distanceMeters.rounded())) m"
        }
        return String(format: "%.1f km", distanceMeters / 1_000)
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: NearbyPlace, rhs: NearbyPlace) -> Bool { lhs.id == rhs.id }
}
