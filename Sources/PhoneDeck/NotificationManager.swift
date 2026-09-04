import Foundation
import UserNotifications

/// The one notification PhoneDeck sends: how an install you asked for
/// turned out.
///
/// There used to be a whole schedule of them, warning that free Apple ID
/// provisioning was about to lapse and announcing the unattended reinstalls
/// that renewed it. A paid Apple Developer membership signs for a year, so
/// nothing expires under you and nothing needs announcing in advance.
enum NotificationManager {
    private static let center = UNUserNotificationCenter.current()

    static func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Delivered when the last selected app finishes. A build takes minutes
    /// and the popover closes as soon as you click away, so this is usually
    /// the only place the outcome is visible.
    static func installFinished(succeeded: [String], failed: [String], deviceName: String) {
        let content = UNMutableNotificationContent()
        content.sound = .default
        if failed.isEmpty {
            content.title = succeeded.count == 1
                ? "\(succeeded[0]) installed"
                : "\(succeeded.count) apps installed"
            content.body = "\(succeeded.joined(separator: ", ")) · \(deviceName)"
        } else if succeeded.isEmpty {
            content.title = "Install failed"
            content.body = "\(failed.joined(separator: ", ")) didn't install to \(deviceName). Open PhoneDeck and try it with the phone unlocked."
        } else {
            content.title = "Partly installed"
            content.body = "\(deviceName): installed \(succeeded.joined(separator: ", ")). Failed: \(failed.joined(separator: ", "))."
        }
        deliver(content, id: "phonedeck-install-result")
    }

    /// Fires now, replacing any earlier copy rather than stacking a fresh
    /// banner on top of a stale one.
    private static func deliver(_ content: UNMutableNotificationContent, id: String) {
        center.removeDeliveredNotifications(withIdentifiers: [id])
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}
