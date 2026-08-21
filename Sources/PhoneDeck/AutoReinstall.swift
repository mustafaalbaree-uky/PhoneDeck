import Foundation

/// Knobs for the unattended reinstall, persisted so they survive a relaunch.
enum AutoReinstallSettings {
    private static let defaults = UserDefaults.standard

    /// Reinstall without being asked, whenever the phone is reachable.
    static var enabled: Bool {
        get {
            // Default on: an app that silently dies after 7 days is the
            // problem PhoneDeck exists to solve, so opting in by hand would
            // just be another thing to forget.
            if defaults.object(forKey: "autoReinstallEnabled") == nil { return true }
            return defaults.bool(forKey: "autoReinstallEnabled")
        }
        set { defaults.set(newValue, forKey: "autoReinstallEnabled") }
    }

    /// An app becomes eligible once it has this many days or fewer left.
    /// Two rather than one: reinstalling early costs nothing (the clock
    /// restarts at 7 either way) and leaves a spare day for the phone to be
    /// unreachable before anything actually lapses.
    static let thresholdDays = 2

    /// How long the "about to reinstall" warning sits before the install
    /// actually starts. Long enough to notice the banner, walk over to the
    /// phone and cancel if there's unsaved state in an app; short enough
    /// that a phone that only passes through Wi-Fi range briefly still
    /// gets its renewal.
    static let warningLeadTime: TimeInterval = 5 * 60

    /// After a failed auto-attempt, leave that app alone this long instead
    /// of retrying every minute against a phone that clearly isn't ready.
    static let failureBackoff: TimeInterval = 2 * 60 * 60

    /// "Skip" on the warning banner postpones that batch by this much.
    static let skipBackoff: TimeInterval = 4 * 60 * 60

    /// Don't repeat the "expiring and I can't reach your phone" warning more
    /// often than this.
    static let unreachableWarningInterval: TimeInterval = 6 * 60 * 60

    /// Once an app is this close to the edge, an unreachable phone is worth
    /// interrupting for.
    static let urgentDays = 1

    /// App id → don't auto-touch it again before this date. Persisted because
    /// PhoneDeck relaunches (a rebuild, a logout) would otherwise forget a
    /// "Skip" and re-arm the same batch minutes later.
    static var snoozes: [String: Date] {
        get { (defaults.dictionary(forKey: "autoReinstallSnoozes") as? [String: Date]) ?? [:] }
        set {
            // Drop lapsed entries on the way out so the dictionary can't grow
            // stale keys for apps that left the registry.
            let live = newValue.filter { $0.value > Date() }
            defaults.set(live, forKey: "autoReinstallSnoozes")
        }
    }

    /// Free Apple ID provisioning only allows 3 sideloaded apps on the phone
    /// at once, so at most this many can be starred for unattended
    /// reinstall — the rest of the registry stays reachable for a manual
    /// reinstall, they just never fire on their own.
    static let maxAutoReinstallApps = 3

    /// Which known apps are allowed to reinstall themselves unattended.
    /// Persisted by id so it survives a relaunch and a registry reorder.
    static var selectedIDs: Set<String> {
        get {
            if let stored = defaults.array(forKey: "autoReinstallSelectedIDs") as? [String] {
                return Set(stored)
            }
            // Never configured yet: fall back to the first three known apps
            // rather than defaulting to "nothing auto-reinstalls", which
            // would silently disable the whole feature for existing users
            // the moment this setting shipped.
            return Set(AppRegistry.known.prefix(maxAutoReinstallApps).map(\.id))
        }
        set { defaults.set(Array(newValue), forKey: "autoReinstallSelectedIDs") }
    }
}

extension AppState {
    /// Re-checks the world every minute: expiry dates move as time passes,
    /// and the phone can come and go without a `didConnect` edge (a poll can
    /// miss the transition, or PhoneDeck can launch with the phone already
    /// on Wi-Fi).
    func startAutoReinstallLoop() {
        autoPollTimer?.invalidate()
        autoPollTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluateAuto() }
        }
        evaluateAuto()
    }

    /// The whole decision, in one place: who is due, can we reach the phone,
    /// and is anything already in flight.
    func evaluateAuto() {
        guard autoEnabled, !isInstalling, pendingAuto == nil else { return }

        // Statuses drift with the clock, so re-read before judging. Skipping
        // the ~/Code scan keeps this cheap enough to run every minute.
        refresh(includeDiscovery: false)

        let due = rows.filter(isDueForAuto)
        guard !due.isEmpty else { return }

        if deviceMonitor.connected {
            armAuto(for: due)
        } else {
            warnIfUnreachable(due)
        }
    }

    private func isDueForAuto(_ row: AppRow) -> Bool {
        // Not one of the (at most 3) starred apps: PhoneDeck never touches
        // it on its own, no matter how close it is to expiring.
        guard autoReinstallIDs.contains(row.app.id) else { return false }
        // No days remaining at all means nothing is known about this app —
        // never installed here and no profile on disk. Guessing would mean
        // building something that may never have built on this Mac.
        guard let days = row.status.daysRemaining else { return false }
        if let until = snoozedUntil[row.app.id], until > Date() { return false }
        return days <= AutoReinstallSettings.thresholdDays
    }

    /// Announces the reinstall and starts the countdown. Nothing is built
    /// until the countdown ends, so the warning is a real chance to stop it.
    private func armAuto(for due: [AppRow]) {
        let fireAt = Date().addingTimeInterval(AutoReinstallSettings.warningLeadTime)
        let pending = PendingAuto(
            rowIDs: due.map(\.app.id),
            names: due.map(\.app.displayName),
            fireAt: fireAt
        )
        pendingAuto = pending
        NotificationManager.warnBeforeAutoReinstall(names: pending.names, fireAt: fireAt)

        autoTimer?.invalidate()
        autoTimer = Timer.scheduledTimer(withTimeInterval: AutoReinstallSettings.warningLeadTime, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.runPendingAutoNow() }
        }
    }

    /// Starts the armed batch immediately — the countdown expiring, or
    /// "Reinstall now" on the banner.
    func runPendingAutoNow() {
        guard let pending = pendingAuto, !isInstalling else { return }
        autoTimer?.invalidate()
        autoTimer = nil
        pendingAuto = nil

        // The phone may have wandered off during the warning window.
        guard deviceMonitor.connected else {
            warnIfUnreachable(rows.filter { pending.rowIDs.contains($0.app.id) })
            return
        }

        let targets = rows.filter { pending.rowIDs.contains($0.app.id) }
        guard !targets.isEmpty else { return }

        isInstalling = true
        lastResultMessage = nil
        statusLine = nil

        Task {
            let result = await self.performInstalls(targets)
            self.isInstalling = false
            self.statusLine = nil
            self.refresh()

            // Back off on the ones that failed so a phone that's locked or
            // mid-reboot doesn't put PhoneDeck in a retry loop.
            let failedIDs = targets
                .filter { result.failed.contains($0.app.displayName) }
                .map(\.app.id)
            let retryAt = Date().addingTimeInterval(AutoReinstallSettings.failureBackoff)
            for id in failedIDs { self.snoozedUntil[id] = retryAt }

            self.lastResultMessage = Self.resultMessage(
                succeeded: result.succeeded, failed: result.failed
            )
            NotificationManager.autoReinstallFinished(
                succeeded: result.succeeded, failed: result.failed
            )
        }
    }

    /// Drops the armed batch. `snooze` is what the "Skip" action passes, so
    /// the same apps don't re-arm thirty seconds later.
    func cancelPendingAuto(snooze: Bool = false) {
        autoTimer?.invalidate()
        autoTimer = nil
        guard let pending = pendingAuto else { return }
        pendingAuto = nil

        if snooze {
            let until = Date().addingTimeInterval(AutoReinstallSettings.skipBackoff)
            for id in pending.rowIDs { snoozedUntil[id] = until }
        }
    }

    /// The fallback path: something is nearly dead and there is no phone to
    /// install to, so the only useful move is to tell Mustafa.
    private func warnIfUnreachable(_ due: [AppRow]) {
        let urgent = due.filter { ($0.status.daysRemaining ?? .max) <= AutoReinstallSettings.urgentDays }
        guard !urgent.isEmpty else { return }

        if let last = lastUnreachableWarning,
           Date().timeIntervalSince(last) < AutoReinstallSettings.unreachableWarningInterval {
            return
        }
        lastUnreachableWarning = Date()

        NotificationManager.warnUnreachable(
            names: urgent.map(\.app.displayName),
            anyExpired: urgent.contains { $0.status.isExpired }
        )
    }
}
