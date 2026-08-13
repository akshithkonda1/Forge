import CloudKit
import ForgeCore
import SwiftUI
import UIKit

// ============================================================
// MARK: - Accepting a support share
// ============================================================

/// The receiving half of partner sharing.
///
/// A supporter taps the invite in Messages, iOS opens the CloudKit share URL,
/// and the system hands the share metadata back to whichever app declares
/// `CKSharingSupported` for that container — us. Accepting it is what actually
/// grants access; until this runs, an invite is an offer nobody took up.
///
/// This is also the only place that may write to `PartnerInviteAcceptance`. The
/// Messages extension deliberately cannot: it is gone by the time CloudKit
/// answers, so anything it recorded would be an intention, not an acceptance.
enum PartnerShareAcceptance {

    static let containerIdentifier = "iCloud.com.forge.ForgeSwift"

    /// Posted once a share is accepted, so open cycle UI can refresh without
    /// polling. Carries no digest — only the fact that something changed.
    static let didAcceptNotification = Notification.Name("forge.partnerShare.didAccept")

    static func accept(_ metadata: CKShare.Metadata) {
        // Only accept shares from our own container. A share URL is a link
        // anyone can send; without this check, tapping a stranger's invite for
        // an unrelated app would still route through Forge.
        guard metadata.containerIdentifier == containerIdentifier else { return }

        Task { @MainActor in
            do {
                let share = try await CKContainer(identifier: containerIdentifier)
                    .accept(metadata)
                if let url = share.url {
                    PartnerInviteAcceptance.record(shareURL: url)
                }
                // Now that this device actually holds a share, it is worth
                // subscribing and asking APNs for a token. Doing either earlier
                // would prompt every user for notifications over a feature they
                // may never use.
                await PartnerCycleSharing.shared.subscribeToUpdates()
                await PartnerCycleSharing.shared.fetchSharedDigest()
                UIApplication.shared.registerForRemoteNotifications()
                NotificationCenter.default.post(name: didAcceptNotification, object: nil)
            } catch {
                // Left unrecorded on purpose. A failed accept that still marked
                // itself accepted would show the supporter a "you're following
                // along" bubble for a share they cannot read.
                #if DEBUG
                print("[PartnerShareAcceptance] accept failed: \(error.localizedDescription)")
                #endif
            }
        }
    }
}

// ============================================================
// MARK: - Delegates
// ============================================================

/// SwiftUI's `App` has no hook for CloudKit share acceptance, so the app vends a
/// delegate purely to receive it.
///
/// Both the application-level and scene-level callbacks are implemented. iOS
/// calls the scene one for scene-based apps — which this is — but the
/// application one still fires in launch paths where no scene has connected yet,
/// and a share dropped on the floor at cold launch is precisely the case a
/// supporter hits when they tap the invite without Forge already running.
final class ForgeAppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        PartnerShareAcceptance.accept(metadata)
    }

    /// The silent push a `CKDatabaseSubscription` sends when the owner writes a
    /// new digest. It carries no payload by design, so the only correct response
    /// is to go and fetch.
    ///
    /// Without this the subscription is inert: it wakes the device and the app
    /// does nothing with the wake-up. Returning the right `UIBackgroundFetchResult`
    /// matters too — iOS throttles apps that report `.noData` for pushes it
    /// delivered, so a wrong answer here degrades future delivery.
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async
    -> UIBackgroundFetchResult {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
              notification.containerIdentifier == PartnerShareAcceptance.containerIdentifier
        else { return .noData }

        let digests = await PartnerCycleSharing.shared.fetchSharedDigest()
        return digests.isEmpty ? .noData : .newData
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Simulator and unprovisioned builds land here. Not surfaced: the
        // Support pane refetches on appear, so a supporter without push sees
        // fresh data a moment later rather than never.
        #if DEBUG
        print("[PartnerShareAcceptance] APNs registration failed: \(error.localizedDescription)")
        #endif
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil,
                                                 sessionRole: connectingSceneSession.role)
        // Only the delegate class is set. `sceneClass` stays nil so SwiftUI keeps
        // providing the scene itself — overriding it here would replace the
        // WindowGroup and leave the app with no UI.
        configuration.delegateClass = ForgeSceneDelegate.self
        return configuration
    }
}

final class ForgeSceneDelegate: NSObject, UIWindowSceneDelegate {

    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        PartnerShareAcceptance.accept(cloudKitShareMetadata)
    }
}
