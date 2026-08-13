import Foundation
import CoreLocation
import MapKit
import Combine

/// Live location + nearby Apple Maps places for Lifestyle.
///
/// The old one-shot `requestLocation()` path could hang forever: it asked
/// for permission and then waited on a continuation that was often not
/// installed yet when the callback fired. This store owns the manager on
/// the main actor, publishes the last fix, and times out instead of stalling
/// the tab.
@MainActor
final class LifestyleLocationStore: NSObject, ObservableObject {
    static let shared = LifestyleLocationStore()

    @Published private(set) var authorization: CLAuthorizationStatus
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var isTracking = false
    @Published private(set) var nearby: [NearbyPlace] = []
    @Published private(set) var isSearching = false
    @Published var lastError: String?

    private let manager = CLLocationManager()
    private var authWaiters: [CheckedContinuation<CLAuthorizationStatus, Never>] = []
    private var locationWaiters: [CheckedContinuation<CLLocation, Error>] = []

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 25
        manager.pausesLocationUpdatesAutomatically = true
        manager.activityType = .fitness
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    var canAsk: Bool { authorization == .notDetermined }

    func requestAccess() async -> CLAuthorizationStatus {
        if authorization != .notDetermined { return authorization }
        manager.requestWhenInUseAuthorization()
        return await withCheckedContinuation { continuation in
            authWaiters.append(continuation)
        }
    }

    func startTracking() {
        guard isAuthorized else { return }
        guard !isTracking else { return }
        manager.startUpdatingLocation()
        isTracking = true
        lastError = nil
    }

    func stopTracking() {
        guard isTracking else { return }
        manager.stopUpdatingLocation()
        isTracking = false
    }

    /// Latest fix, or a fresh one with an 8-second timeout so the UI never spins.
    func latestLocation() async -> CLLocation? {
        if let currentLocation, Date().timeIntervalSince(currentLocation.timestamp) < 45 {
            return currentLocation
        }
        if isAuthorized { startTracking() }
        return await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask { @MainActor in
                await self.waitForFix()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    func refreshNearby(query: String = "restaurants") async {
        guard let location = await latestLocation() else {
            lastError = isAuthorized
                ? "Couldn't get a GPS fix. Try again in the open."
                : "Location access is off. Enable it to see nearby places."
            nearby = []
            return
        }
        isSearching = true
        lastError = nil
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .restaurant, .cafe, .bakery, .brewery, .foodMarket, .winery,
        ])
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 2_400,
            longitudinalMeters: 2_400
        )

        do {
            let response = try await MKLocalSearch(request: request).start()
            nearby = response.mapItems
                .compactMap { item -> NearbyPlace? in
                    guard let coord = item.placemark.location?.coordinate else { return nil }
                    let meters = item.placemark.location?.distance(from: location) ?? 0
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
                .sorted { $0.distanceMeters < $1.distanceMeters }
        } catch {
            lastError = "Apple Maps couldn't search nearby. Check the network and try again."
            nearby = []
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

    private func waitForFix() async -> CLLocation? {
        if let currentLocation, Date().timeIntervalSince(currentLocation.timestamp) < 45 {
            return currentLocation
        }
        return try? await withCheckedThrowingContinuation { continuation in
            locationWaiters.append(continuation)
        }
    }

    private func resumeAuthWaiters(_ status: CLAuthorizationStatus) {
        let waiters = authWaiters
        authWaiters.removeAll()
        waiters.forEach { $0.resume(returning: status) }
    }

    private func resumeLocationWaiters(_ result: Result<CLLocation, Error>) {
        let waiters = locationWaiters
        locationWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(with: result)
        }
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
        guard let location = locations.last else { return }
        Task { @MainActor in
            currentLocation = location
            lastError = nil
            resumeLocationWaiters(.success(location))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            lastError = error.localizedDescription
            resumeLocationWaiters(.failure(error))
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
