import Foundation
import UserNotifications

/// Schedules local notifications warning that an app's free Apple ID
/// provisioning is about to lapse. Notifications are computed directly from
/// each app's exact install timestamp rather than polled, so the OS
/// delivers them on schedule even if PhoneDeck isn't running at the moment
/// they're due.
enum NotificationManager {
    private static let center = UNUserNotificationCenter.current()
    private static let idPrefix = "phonedeck-expiry-"

    /// Identifiers the AppDelegate matches on when a banner is acted upon.
    static let autoWarningCategory = "phonedeck-auto-warning"
    static let actionInstallNow = "phonedeck-install-now"
    static let actionSkip = "phonedeck-skip"

    static func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Puts the two buttons on the "about to reinstall" banner, so stopping
    /// it never requires finding the menu bar icon first.
    static func registerCategories() {
        let category = UNNotificationCategory(
            identifier: autoWarningCategory,
            actions: [
                UNNotificationAction(identifier: actionInstallNow, title: "Reinstall Now", options: []),
                UNNotificationAction(identifier: actionSkip, title: "Skip For Now", options: []),
            ],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    /// The heads-up before an unattended reinstall starts. Delivered
    /// immediately; the install itself waits out the countdown.
    static func warnBeforeAutoReinstall(names: [String], fireAt: Date) {
        let minutes = max(Int((fireAt.timeIntervalSinceNow / 60).rounded()), 1)
        let content = UNMutableNotificationContent()
        content.sound = .default
        content.categoryIdentifier = autoWarningCategory
        if names.count == 1 {
            content.title = "Reinstalling \(names[0]) in \(minutes) min"
        } else {
            content.title = "Reinstalling \(names.count) apps in \(minutes) min"
        }
        // Naming the apps matters more than naming the mechanism: the point
        // of the delay is deciding whether anything in those apps is
        // mid-flight right now.
        content.body = "\(names.joined(separator: ", ")) — provisioning is nearly up. Skip it if you're in the middle of something."
        deliver(content, id: "phonedeck-auto-warning")
    }

    static func autoReinstallFinished(succeeded: [String], failed: [String]) {
        let content = UNMutableNotificationContent()
        content.sound = .default
        if failed.isEmpty {
            content.title = "Renewed for another 7 days"
            content.body = "Reinstalled \(succeeded.joined(separator: ", "))."
        } else if succeeded.isEmpty {
            content.title = "Automatic reinstall failed"
            content.body = "\(failed.joined(separator: ", ")) didn't install. Open PhoneDeck and try it with the phone unlocked."
        } else {
            content.title = "Partly renewed"
            content.body = "Reinstalled \(succeeded.joined(separator: ", ")). Failed: \(failed.joined(separator: ", "))."
        }
        deliver(content, id: "phonedeck-auto-result")
    }

    /// The escalation for when the deadline is here and the automatic path
    /// can't run, because there is no phone to install to.
    static func warnUnreachable(names: [String], anyExpired: Bool) {
        let content = UNMutableNotificationContent()
        content.sound = .default
        content.title = anyExpired
            ? "\(names.joined(separator: ", ")) — provisioning has lapsed"
            : "\(names.joined(separator: ", ")) expire within a day"
        content.body = "PhoneDeck can't reach your iPhone. Plug it in, or put it on this Wi-Fi network, and the reinstall runs by itself."
        deliver(content, id: "phonedeck-unreachable")
    }

    /// Fires now, replacing any earlier copy of the same kind rather than
    /// stacking a fresh banner on top of a stale one.
    private static func deliver(_ content: UNMutableNotificationContent, id: String) {
        center.removeDeliveredNotifications(withIdentifiers: [id])
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    /// Rebuilds every pending expiry notification from scratch based on the
    /// current rows. Cheap and always correct after a reinstall shifts an
    /// app's expiry date, so callers can just call this after every refresh.
    /// Only starred apps are scheduled: unstarred apps are ignored so deleted
    /// or unmanaged apps do not generate unwanted notifications.
    static func reschedule(rows: [AppRow], starredIDs: Set<String>) {
        center.getPendingNotificationRequests { pending in
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)

            let calendar = Calendar.current
            let now = Date()

            // Group apps by the calendar day their "1 day left" warning
            // should fire on, so two apps expiring hours apart on the same
            // day produce one notification instead of two back to back.
            var byDay: [Date: [String]] = [:]
            for row in rows where starredIDs.contains(row.app.id) {
                guard let expiry = row.status.expiresAt else { continue }
                let notifyAt = expiry.addingTimeInterval(-86400)
                guard notifyAt > now else { continue }
                let day = calendar.startOfDay(for: notifyAt)
                byDay[day, default: []].append(row.app.displayName)
            }

            for (day, names) in byDay {
                // Fire at 9am on the notify day rather than each app's exact
                // hour — the whole point of grouping is one predictable time
                // instead of several scattered ones. If 9am has already
                // passed today (e.g. PhoneDeck reinstalled something this
                // afternoon, landing the warning day on today), fire
                // shortly instead of silently skipping it.
                var comps = calendar.dateComponents([.year, .month, .day], from: day)
                comps.hour = 9
                var fireDate = calendar.date(from: comps) ?? day
                if fireDate <= now {
                    fireDate = now.addingTimeInterval(60)
                }

                let content = UNMutableNotificationContent()
                content.sound = .default
                if names.count == 1 {
                    content.title = "\(names[0]) expires tomorrow"
                    content.body = "Free Apple ID provisioning lapses in 1 day. Reinstall from PhoneDeck to renew it."
                } else {
                    content.title = "\(names.count) apps expire tomorrow"
                    content.body = "\(names.joined(separator: ", ")) lose provisioning in 1 day. Reinstall from PhoneDeck to renew them."
                }

                let triggerComps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: false)
                let identifier = idPrefix + ISO8601DateFormatter().string(from: day)
                center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            }
        }
    }
}
