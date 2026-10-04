import Foundation
import ForgeCore

/// On-device Life Ops board: Calendar + Reminders → counts ARIA can coach on.
/// Never holds titles. Built per payload, never persisted.
@MainActor
enum LifeOpsBoard {
    static func digest() -> LifeOpsDigest {
        LifeOpsDigest.build(
            assets: CalendarManager.shared.lifestyleAssets,
            reminders: RemindersManager.shared.accessState == .connected
                ? RemindersManager.shared.workload
                : nil,
            busyToday: CalendarManager.shared.busyWindowsToday
        )
    }
}
