import Foundation
import Combine

struct AppRow: Identifiable {
    let app: KnownApp
    var status: ExpiryStatus
    var id: String { app.id }
}

/// A reinstall that has been announced and starts when `fireAt` passes,
/// unless it's cancelled first. The gap is deliberate: it's the window in
/// which "don't type anything into that app right now" is still actionable.
struct PendingAuto {
    let rowIDs: [String]
    let names: [String]
    let fireAt: Date
}

@MainActor
final class AppState: ObservableObject {
    @Published var rows: [AppRow] = []
    @Published var discovered: [DiscoveredProject] = []
    @Published var selection: Set<String> = []
    @Published var isInstalling = false
    @Published var lastResultMessage: String?
    /// Most recent line the running install script printed, shown live in a
    /// fixed-size status strip so the window never resizes while installing.
    @Published var statusLine: String?

    /// Reinstall expiring apps unattended whenever the phone is reachable.
    @Published var autoEnabled: Bool = AutoReinstallSettings.enabled {
        didSet {
            AutoReinstallSettings.enabled = autoEnabled
            if autoEnabled {
                evaluateAuto()
            } else {
                cancelPendingAuto()
            }
        }
    }
    /// Non-nil while an announced reinstall is counting down.
    @Published var pendingAuto: PendingAuto?

    /// Whether the popover is showing every known app (so the rest can be
    /// starred or unstarred) or just the ones already starred. Off by
    /// default: day to day, only the apps that actually auto-reinstall
    /// matter, and the full registry is clutter. Not persisted — each
    /// launch starts back in the quiet view.
    @Published var showAutoPicker = false

    /// Ids of the (at most `AutoReinstallSettings.maxAutoReinstallApps`)
    /// apps starred for unattended reinstall. Every other known app stays
    /// in the list for a manual reinstall but is never touched on its own.
    @Published var autoReinstallIDs: Set<String> = AutoReinstallSettings.selectedIDs

    /// Stars or unstars an app for auto-reinstall. Silently ignored once the
    /// cap is full — the star button in the UI disables itself in that case,
    /// so this is just a safety net against a stale tap.
    func toggleAutoReinstall(_ id: String) {
        if autoReinstallIDs.contains(id) {
            autoReinstallIDs.remove(id)
        } else if autoReinstallIDs.count < AutoReinstallSettings.maxAutoReinstallApps {
            autoReinstallIDs.insert(id)
        } else {
            return
        }
        AutoReinstallSettings.selectedIDs = autoReinstallIDs
        NotificationManager.reschedule(rows: rows, starredIDs: autoReinstallIDs)
    }

    /// Countdown to the armed batch, and the once-a-minute re-evaluation.
    /// Held here rather than in the extension because stored properties
    /// can't live in one.
    var autoTimer: Timer?
    var autoPollTimer: Timer?
    /// App id → don't auto-touch it again before this date. Set by a failed
    /// attempt and by "Skip" on the warning banner; kept on disk so it
    /// outlives a relaunch.
    var snoozedUntil: [String: Date] {
        get { AutoReinstallSettings.snoozes }
        set { AutoReinstallSettings.snoozes = newValue }
    }
    var lastUnreachableWarning: Date?

    let deviceMonitor = DeviceMonitor()

    /// `includeDiscovery` is off for the once-a-minute auto check: walking
    /// ~/Code for stray Xcode projects is far too heavy to do on that
    /// cadence, and nothing about it changes an expiry date.
    func refresh(includeDiscovery: Bool = true) {
        rows = AppRegistry.known.map { app in
            AppRow(app: app, status: ExpiryStatus.read(
                stateFile: app.lastInstallFile, bundleID: app.bundleID
            ))
        }
        if includeDiscovery {
            discovered = AppRegistry.scanForUnregistered()
        }
        NotificationManager.reschedule(rows: rows, starredIDs: autoReinstallIDs)
    }

    func toggle(_ id: String) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    func reinstallSelected() {
        guard !selection.isEmpty, !isInstalling else { return }
        // A hand-driven install takes over from anything armed: it covers the
        // same ground, and leaving the countdown running would start a second
        // build right behind this one.
        cancelPendingAuto()

        let targets = rows.filter { selection.contains($0.app.id) }
        isInstalling = true
        lastResultMessage = nil
        statusLine = nil

        Task {
            let result = await self.performInstalls(targets)

            self.isInstalling = false
            self.statusLine = nil
            self.selection.removeAll()
            self.refresh()
            self.lastResultMessage = Self.resultMessage(
                succeeded: result.succeeded, failed: result.failed
            )
        }
    }

    /// Runs each app's script in turn, streaming its output into
    /// `statusLine`. Shared by the manual button and the unattended path so
    /// both behave identically.
    func performInstalls(_ targets: [AppRow]) async -> (succeeded: [String], failed: [String]) {
        var succeeded: [String] = []
        var failed: [String] = []
        for row in targets {
            statusLine = "\(row.app.displayName): starting…"
            let outcome = await Installer.run(scriptPath: row.app.installScript, args: row.app.installArgs) { line in
                self.statusLine = "\(row.app.displayName): \(line)"
            }
            switch outcome {
            case .success: succeeded.append(row.app.displayName)
            case .failure: failed.append(row.app.displayName)
            }
        }
        return (succeeded, failed)
    }

    static func resultMessage(succeeded: [String], failed: [String]) -> String {
        if failed.isEmpty {
            return "Reinstalled: \(succeeded.joined(separator: ", "))"
        } else if succeeded.isEmpty {
            return "Reinstall failed: \(failed.joined(separator: ", ")). Check the phone is reachable and unlocked."
        } else {
            return "Reinstalled \(succeeded.joined(separator: ", ")). Failed: \(failed.joined(separator: ", "))."
        }
    }
}
