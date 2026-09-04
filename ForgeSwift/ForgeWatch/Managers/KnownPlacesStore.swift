import Foundation
import CoreLocation
import Observation
import ForgeCore

// MARK: - Known places (privacy-first place detection)
//
// The user labels their current location ("this is my gym") from the
// Context screen. Coordinates are stored ONLY in the App Group on-device
// — they never join WatchARIAContext, the snapshot, or any network
// payload. Detection is foreground-only in v1: on app activation we take
// one location fix and compare against saved places; matches surface as
// mode *suggestions*, never silent switches.

enum PlaceLabel: String, Codable, CaseIterable, Identifiable {
    case gym
    case home
    case office

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gym:    return "Gym"
        case .home:   return "Home"
        case .office: return "Office"
        }
    }

    /// The lifestyle mode a detected place suggests.
    var suggestedMode: LifestyleMode {
        switch self {
        case .gym:    return .gym
        case .home:   return .homeRecovery
        case .office: return .deskCoding
        }
    }
}

struct KnownPlace: Codable, Identifiable, Equatable {
    var id: UUID
    var label: PlaceLabel
    var latitude: Double
    var longitude: Double

    init(id: UUID = UUID(), label: PlaceLabel, latitude: Double, longitude: Double) {
        self.id = id
        self.label = label
        self.latitude = latitude
        self.longitude = longitude
    }

    func distance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }
}

@MainActor
@Observable
final class KnownPlacesStore {

    nonisolated static let matchRadiusMeters: CLLocationDistance = 150

    private(set) var places: [KnownPlace] = []

    private let defaults = UserDefaults(suiteName: WatchSnapshotStore.appGroupID)
    private static let key = "forge.watch.knownPlaces.v1"

    init() {
        if let data = defaults?.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode([KnownPlace].self, from: data) {
            places = stored
        }
    }

    func save(label: PlaceLabel, coordinate: CLLocationCoordinate2D) {
        // One place per label in v1 — relabeling your gym just moves it.
        places.removeAll { $0.label == label }
        places.append(KnownPlace(label: label, latitude: coordinate.latitude, longitude: coordinate.longitude))
        persist()
    }

    func remove(label: PlaceLabel) {
        places.removeAll { $0.label == label }
        persist()
    }

    func nearest(to coordinate: CLLocationCoordinate2D, within radius: CLLocationDistance = KnownPlacesStore.matchRadiusMeters) -> KnownPlace? {
        places
            .map { (place: $0, distance: $0.distance(to: coordinate)) }
            .filter { $0.distance <= radius }
            .min { $0.distance < $1.distance }?
            .place
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(places) {
            defaults?.set(data, forKey: Self.key)
        }
    }
}

// MARK: - PlaceDetector (one-shot foreground fixes)

@MainActor
final class PlaceDetector: NSObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// One coordinate or nil — never throws, never blocks the UI path.
    func currentCoordinate() async -> CLLocationCoordinate2D? {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            return nil // ask this pass; detect on the next one
        case .restricted, .denied:
            return nil
        default:
            break
        }
        // A second call while one is in flight just misses this round.
        guard continuation == nil else { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        Task { @MainActor in
            self.continuation?.resume(returning: coordinate)
            self.continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.continuation?.resume(returning: nil)
            self.continuation = nil
        }
    }
}
