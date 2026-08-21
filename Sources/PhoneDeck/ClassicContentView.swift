import SwiftUI

// The original PhoneDeck look, kept verbatim so the new design is fully
// reversible: right-click the menu bar icon → "Use the classic look" swaps
// back to this at runtime, no rebuild. See RootView.swift.

struct ClassicContentView: View {
    @ObservedObject var state: AppState
    @ObservedObject var monitor: DeviceMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            deviceHeader
            if let pending = state.pendingAuto {
                Divider()
                countdownBanner(pending)
            }

            // No ScrollView here on purpose — this list should never scroll.
            // It just grows/shrinks with however many rows are visible.
            VStack(alignment: .leading, spacing: 4) {
                ForEach(visibleRows) { row in
                    ClassicAppRowView(
                        row: row,
                        isSelected: state.selection.contains(row.app.id),
                        isAutoSelected: state.autoReinstallIDs.contains(row.app.id),
                        autoSelectionFull: state.autoReinstallIDs.count >= AutoReinstallSettings.maxAutoReinstallApps,
                        showAutoStar: state.showAutoPicker,
                        onToggle: { state.toggle(row.app.id) },
                        onToggleAuto: { state.toggleAutoReinstall(row.app.id) }
                    )
                }

                if state.showAutoPicker && !state.discovered.isEmpty {
                    Text("Found, not set up yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    ForEach(state.discovered) { project in
                        ClassicDiscoveredRowView(project: project)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 2)

            footer
        }
        .frame(width: 340)
    }

    /// Every known app while managing which 3 are starred; just the starred
    /// ones the rest of the time, so day-to-day the list is only what
    /// actually auto-reinstalls.
    private var visibleRows: [AppRow] {
        state.showAutoPicker ? state.rows : state.rows.filter { state.autoReinstallIDs.contains($0.app.id) }
    }

    private var deviceHeader: some View {
        HStack {
            Circle()
                .fill(monitor.connected ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(monitor.connected ? (monitor.deviceModel ?? "iPhone connected") : "No iPhone connected")
                    .font(.system(size: 13, weight: .medium))
                if monitor.connected, let name = monitor.deviceName {
                    // The transport is worth showing: a Wi-Fi link installs
                    // fine but is slower and can drop mid-build, so it helps
                    // to know which one is in play before starting.
                    Text(monitor.transport.map { "\(name) · \($0.label)" } ?? name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    /// The visible half of the warning that also went out as a banner: what
    /// is about to be rebuilt, how long is left, and a way out.
    private func countdownBanner(_ pending: PendingAuto) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.orange)
                // A live-ticking countdown rather than a fixed "in 5 min",
                // which would be a lie the moment the popover is reopened.
                Text("Reinstalling in ")
                    .font(.system(size: 12, weight: .medium))
                    + Text(pending.fireAt, style: .timer)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                Spacer()
            }
            Text(pending.names.joined(separator: ", "))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Apps restart when they're reinstalled. Cancel if you're in the middle of entering something.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Cancel") { state.cancelPendingAuto(snooze: true) }
                    .font(.caption)
                Button("Do it now") { state.runPendingAutoNow() }
                    .font(.caption)
                Spacer()
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
    }

    private var footer: some View {
        VStack(spacing: 4) {
            statusStrip

            Toggle(isOn: $state.autoEnabled) {
                Text("Reinstall expiring apps automatically")
                    .font(.caption)
            }
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle(isOn: $state.showAutoPicker) {
                Text("Manage auto-reinstall apps")
                    .font(.caption)
            }
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Only means anything once the toggle above is on — that's what
            // reveals the stars this count is describing.
            if state.showAutoPicker {
                Text("Auto-reinstall slots: \(state.autoReinstallIDs.count)/\(AutoReinstallSettings.maxAutoReinstallApps) — star the apps above")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Select all") { state.selection = Set(visibleRows.map { $0.app.id }) }
                    .font(.caption)
                Button("Select expiring") {
                    state.selection = Set(visibleRows.filter { ($0.status.daysRemaining ?? 0) <= 1 }.map { $0.app.id })
                }
                    .font(.caption)
                Spacer()
                Button {
                    state.reinstallSelected()
                } label: {
                    if state.isInstalling {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Reinstall (\(state.selection.count))")
                    }
                }
                .disabled(state.selection.isEmpty || state.isInstalling || !monitor.connected)
            }

            // Tied to the phone being absent, and nothing else. It used to
            // also require a selection, which meant the first click on an app
            // grew the footer by a line, resized the popover under the
            // cursor, and shoved every card up. The reason the button is
            // dead is the missing phone, so say it as soon as the phone is
            // missing and leave the height alone while apps are picked.
            if !monitor.connected {
                Text("Plug in the iPhone, or put it on this Wi-Fi network, to reinstall.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 12)
    }

    /// Always occupies the same one-line height, whether idle, streaming a
    /// live install step, or showing the final result — so nothing about
    /// the window ever resizes while an install is running.
    private var statusStrip: some View {
        HStack(spacing: 5) {
            if state.isInstalling {
                ProgressView().controlSize(.small)
            }
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 14)
    }

    private var statusText: String {
        if state.isInstalling {
            return state.statusLine ?? "Working…"
        }
        return state.lastResultMessage ?? " "
    }
}

private struct ClassicAppRowView: View {
    let row: AppRow
    let isSelected: Bool
    let isAutoSelected: Bool
    let autoSelectionFull: Bool
    let showAutoStar: Bool
    let onToggle: () -> Void
    let onToggleAuto: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { isSelected }, set: { _ in onToggle() }))
                .toggleStyle(.checkbox)
                .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(row.app.displayName)
                    .font(.system(size: 13))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            if showAutoStar {
                autoStar
            }
            badge
        }
    }

    /// Stars this app in or out of the unattended-reinstall set. Disabled
    /// (not hidden) once the cap is full and this app isn't already one of
    /// the starred ones, so it's clear why tapping does nothing.
    private var autoStar: some View {
        Button(action: onToggleAuto) {
            Image(systemName: isAutoSelected ? "star.fill" : "star")
                .font(.system(size: 12))
                .foregroundStyle(isAutoSelected ? .yellow : .secondary.opacity(0.5))
        }
        .buttonStyle(.plain)
        .disabled(!isAutoSelected && autoSelectionFull)
        .help(isAutoSelected
            ? "Auto-reinstalled when it's expiring. Click to stop."
            : (autoSelectionFull
                ? "Auto-reinstall slots are full — unstar one first"
                : "Auto-reinstall this app when it's expiring"))
    }

    private var subtitle: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short

        // The expiry date is the useful half — it comes from the app's actual
        // provisioning profile, which is what iOS enforces, and it does not
        // always land seven days after the install.
        let expiry = row.status.expiresAt.map { "expires \(formatter.string(from: $0))" }

        guard let lastInstall = row.status.lastInstall else {
            guard let expiry else { return "Never installed via PhoneDeck" }
            return "Not installed via PhoneDeck, \(expiry)"
        }
        // The clock time of the install, on its own line under the dates so
        // every row breaks the same way. Two installs on the same day are
        // otherwise indistinguishable here.
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        let time = timeFormatter.string(from: lastInstall)

        let installed = "Installed \(formatter.string(from: lastInstall))"
        guard let expiry else { return "\(installed)\n\(time)" }
        return "\(installed), \(expiry)\n\(time)"
    }

    @ViewBuilder
    private var badge: some View {
        let days = row.status.daysRemaining
        Text(badgeText(row.status))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor(days).opacity(0.18))
            .foregroundStyle(badgeColor(days))
            .clipShape(Capsule())
    }

    private func badgeText(_ status: ExpiryStatus) -> String {
        guard let days = status.daysRemaining else { return "unknown" }
        // isExpired, not days == 0: daysRemaining rounds up, so an app with
        // hours left says "1d left" and only a genuinely dead profile is
        // called expired.
        if status.isExpired { return "expired" }
        return "\(days)d left"
    }

    private func badgeColor(_ days: Int?) -> Color {
        guard let days else { return .secondary }
        if days <= 0 { return .red }
        if days <= 2 { return .orange }
        return .green
    }
}

private struct ClassicDiscoveredRowView: View {
    let project: DiscoveredProject

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.system(size: 13))
                Text("No reinstall script yet")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
