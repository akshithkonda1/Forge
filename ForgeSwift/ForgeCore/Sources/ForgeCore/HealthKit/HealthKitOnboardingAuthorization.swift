import Foundation

/// Pure onboarding HealthKit decisions. HealthKit hides READ authorization:
/// `authorizationStatus(for:)` only reports WRITE/share, so onboarding must
/// not treat `.notDetermined` / `.sharingDenied` as "not connected" and must
/// never bounce to Health → Sharing or Settings.
public enum HealthKitOnboardingAuthorization: Sendable {

    public static let connectedDefaultsKey = "HealthKitOnboardingReadConnected"

    public enum TapAction: String, Equatable, Sendable {
        case requestReadAuthorization
        case refreshAlreadyConnected
        case stayWithoutRedirect
    }

    public enum Outcome: String, Equatable, Sendable {
        case connected
        case enableLater
    }

    public enum Redirect: String, Equatable, Sendable {
        case none
        case healthSharing
        case settings
    }

    /// First tap always requests the in-app READ sheet. Write-status and
    /// "can the share sheet appear?" never gate onboarding.
    public static func tapAction(
        alreadyConnected: Bool,
        healthAvailable: Bool
    ) -> TapAction {
        if alreadyConnected { return .refreshAlreadyConnected }
        if !healthAvailable { return .stayWithoutRedirect }
        return .requestReadAuthorization
    }

    /// A completed `requestAuthorization` (no error) is connected. Apple
    /// does not report READ grant/deny, so an unknown write status is not
    /// treated as denied.
    public static func outcome(requestCompletedWithoutError: Bool) -> Outcome {
        requestCompletedWithoutError ? .connected : .enableLater
    }

    public static func isConnected(requestCompletedWithoutError: Bool) -> Bool {
        requestCompletedWithoutError
    }

    /// `HKAuthorizationStatus` raw values: 0 notDetermined, 1 sharingDenied,
    /// 2 sharingAuthorized. None of these prove a READ denial.
    public static func isReadDenied(writeStatusRawValue: Int) -> Bool {
        _ = writeStatusRawValue
        return false
    }

    /// Onboarding never opens Health Sharing or Settings on its own.
    public static func automaticRedirect(
        canPresentWriteSheet: Bool,
        writeStatusRawValue: Int
    ) -> Redirect {
        _ = canPresentWriteSheet
        _ = writeStatusRawValue
        return .none
    }

    /// The onboarding Allow sheet is read-only.
    public static var onboardingShareTypeCount: Int { 0 }

    /// Health Records stay out of the first-connect sheet.
    public static var onboardingIncludesClinicalTypes: Bool { false }

    public static func persistConnected(requestCompletedWithoutError: Bool) -> Bool {
        requestCompletedWithoutError
    }

    /// Relaunch: a completed onboarding READ request stays live even when
    /// WRITE status and samples are empty. Non-onboarding paths pass
    /// `onboardingConnected: false` and keep the write/sample probe.
    public static func isLive(
        canWrite: Bool,
        hasReadableSamples: Bool,
        onboardingConnected: Bool
    ) -> Bool {
        canWrite || hasReadableSamples || onboardingConnected
    }

    /// Sleep fields for widgets. Only last night (same start-of-day as
    /// `HomeTrendSeries.lastNight` / `nightKey`) is published; older nights
    /// return nil so Home/Watch show empty copy.
    public static func publishedSleepFields(
        nightKey: Date?,
        lastNight: Date?,
        hours: Double?,
        score: Int?,
        calendar: Calendar = .current
    ) -> PublishedSleepFields? {
        guard let nightKey, let lastNight else { return nil }
        guard calendar.isDate(nightKey, inSameDayAs: lastNight) else { return nil }
        guard let hours, hours > 0 else { return nil }
        return PublishedSleepFields(hours: hours, score: score)
    }
}

public struct PublishedSleepFields: Equatable, Sendable {
    public var hours: Double
    public var score: Int?

    public init(hours: Double, score: Int?) {
        self.hours = hours
        self.score = score
    }
}
