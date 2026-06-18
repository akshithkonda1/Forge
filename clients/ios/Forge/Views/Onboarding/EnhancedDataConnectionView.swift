import SwiftUI

struct EnhancedDataConnectionView: View {
    @ObservedObject private var dataManager = OnboardingDataManager.shared
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Connect Your Data")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)

            Text("Forge works best with Health, Calendar, and notifications enabled.")
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                permissionRow("HealthKit", enabled: dataManager.healthKitAuthorized)
                permissionRow("Calendar", enabled: dataManager.calendarAuthorized)
                permissionRow("Notifications", enabled: dataManager.notificationsAuthorized)
                permissionRow("Contacts", enabled: dataManager.contactsAuthorized)
            }

            if let snapshot = dataManager.healthSnapshot {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Snapshot")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textTertiary)
                    Text("RHR \(snapshot.restingHeartRate ?? 0) · Steps \(snapshot.steps ?? 0) · Sleep \(String(format: "%.1f", snapshot.sleepHours ?? 0))h")
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .forgeBorderedCard()
            }

            EmberButton(title: "Connect Everything", icon: "link") {
                Task { await dataManager.requestAllPermissions() }
            }

            EmberButton(title: "Continue", icon: "chevron.right") {
                onNext()
            }
        }
        .padding(24)
    }

    private func permissionRow(_ title: String, enabled: Bool) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.white)
            Spacer()
            Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                .foregroundColor(enabled ? .forgeSuccess : .textTertiary)
        }
        .padding(12)
        .forgeBorderedCard()
    }
}