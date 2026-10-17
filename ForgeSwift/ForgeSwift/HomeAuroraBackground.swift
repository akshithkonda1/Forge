import SwiftUI
import ForgeCore

/// Home sits on the shared flat field. The aurora mesh, motes, and drift
/// loops were retired with the premium rewrite — keeping a stub so call
/// sites (`HomeView`) stay stable.
enum HomeReadinessBand: Int, Hashable {
    case low, fair, good, peak

    init(score: Int) {
        switch HomeReadinessTokens.band(for: score) {
        case .peak: self = .peak
        case .good: self = .good
        case .fair: self = .fair
        case .low:  self = .low
        }
    }

    var tint: Color {
        switch self {
        case .peak: return Color(hex: HomeReadinessTokens.Band.peak.hex)
        case .good: return Color(hex: HomeReadinessTokens.Band.good.hex)
        case .fair: return Color(hex: HomeReadinessTokens.Band.fair.hex)
        case .low:  return Color(hex: HomeReadinessTokens.Band.low.hex)
        }
    }
}

struct HomeAuroraBackground: View {
    let readinessScore: Int
    var showsGrain: Bool = false
    static let showsAurora = false

    var body: some View {
        Color.background
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
