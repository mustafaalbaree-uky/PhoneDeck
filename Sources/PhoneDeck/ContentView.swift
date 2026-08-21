import SwiftUI

/// PhoneDeck's current look. The whole popover is one column of cards on a
/// faint accent wash: a device header, an optional countdown, a card per
/// app, and a footer that holds the controls.
///
/// The previous design is still in the build, unchanged, in
/// ClassicContentView.swift — right-click the menu bar icon to switch back.
struct ContentView: View {
    @ObservedObject var state: AppState
    @ObservedObject var monitor: DeviceMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            deviceHeader

            if let pending = state.pendingAuto {
                countdownBanner(pending)
                    .padding(.horizontal, Theme.gutter)
                    .padding(.bottom, 10)
            }

            // No ScrollView here on purpose — this list should never scroll.
            // It just grows/shrinks with however many rows are visible.
            VStack(alignment: .leading, spacing: 6) {
                ForEach(visibleRows) { row in
                    AppCardView(
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
                    sectionLabel("Found, not set up yet")
                    ForEach(state.discovered) { project in
                        DiscoveredCardView(project: project)
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 12)

            footer
        }
        .frame(width: Theme.popoverWidth)
        .background(alignment: .top) {
            Theme.backdrop
                .frame(height: 160)
                .allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.18), value: state.selection)
        .animation(.easeOut(duration: 0.2), value: state.showAutoPicker)
    }

    /// Every known app while managing which 3 are starred; just the starred
    /// ones the rest of the time, so day-to-day the list is only what
    /// actually auto-reinstalls.
    private var visibleRows: [AppRow] {
        state.showAutoPicker ? state.rows : state.rows.filter { state.autoReinstallIDs.contains($0.app.id) }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.tertiary)
            .padding(.top, 6)
            .padding(.leading, 2)
    }

    // MARK: - Header

    private var deviceHeader: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                    .fill(monitor.connected
                          ? AnyShapeStyle(Theme.accentGradient)
                          : AnyShapeStyle(Color.primary.opacity(0.08)))
                Image(systemName: monitor.connected ? "iphone.gen3" : "iphone.slash")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(monitor.connected ? Color.white : Color.secondary)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(monitor.connected ? (monitor.deviceModel ?? "iPhone connected") : "No iPhone connected")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                if monitor.connected, let name = monitor.deviceName {
                    // The transport is worth showing: a Wi-Fi link installs
                    // fine but is slower and can drop mid-build, so it helps
                    // to know which one is in play before starting.
                    HStack(spacing: 4) {
                        Image(systemName: monitor.transport == .wired ? "cable.connector" : "wifi")
                            .font(.system(size: 9, weight: .semibold))
                        Text(monitor.transport.map { "\(name) · \($0.label)" } ?? name)
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                } else if !monitor.connected {
                    Text("Waiting for a paired iPhone")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 6)

            if monitor.connected {
                LiveDot()
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: - Countdown

    /// The visible half of the warning that also went out as a banner: what
    /// is about to be rebuilt, how long is left, and a way out.
    private func countdownBanner(_ pending: PendingAuto) -> some View {
        let amber = Color(red: 1.0, green: 0.65, blue: 0.2)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(amber)
                // A live-ticking countdown rather than a fixed "in 5 min",
                // which would be a lie the moment the popover is reopened.
                (Text("Reinstalling in ")
                    .font(.system(size: 12, weight: .semibold))
                 + Text(pending.fireAt, style: .timer)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit()))
                Spacer(minLength: 0)
            }

            Text(pending.names.joined(separator: ", "))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Apps restart when they're reinstalled. Cancel if you're in the middle of entering something.")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                PillButton(title: "Cancel", tint: amber) { state.cancelPendingAuto(snooze: true) }
                PillButton(title: "Do it now", tint: amber, filled: true) { state.runPendingAutoNow() }
                Spacer(minLength: 0)
            }
            .padding(.top, 1)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(amber.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .strokeBorder(amber.opacity(0.28), lineWidth: 1)
                )
        )
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusStrip

            VStack(alignment: .leading, spacing: 7) {
                Toggle(isOn: $state.autoEnabled) {
                    Text("Reinstall expiring apps automatically")
                        .font(.system(size: 11.5))
                }
                Toggle(isOn: $state.showAutoPicker) {
                    Text("Manage auto-reinstall apps")
                        .font(.system(size: 11.5))
                }
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(Theme.accent)

            // Only means anything once the toggle above is on — that's what
            // reveals the stars this count is describing.
            if state.showAutoPicker {
                SlotMeter(used: state.autoReinstallIDs.count,
                          total: AutoReinstallSettings.maxAutoReinstallApps)
            }

            HStack(spacing: 8) {
                PillButton(title: "All") {
                    state.selection = Set(visibleRows.map { $0.app.id })
                }
                PillButton(title: "Expiring") {
                    state.selection = Set(visibleRows.filter { ($0.status.daysRemaining ?? 0) <= 1 }.map { $0.app.id })
                }
                Spacer(minLength: 0)
                reinstallButton
            }

            // Tied to the phone being absent, and nothing else. It used to
            // also require a selection, which meant the first click on an app
            // grew the footer by a line, resized the popover under the
            // cursor, and shoved every card up. The reason the button is
            // dead is the missing phone, so say it as soon as the phone is
            // missing and leave the height alone while apps are picked.
            if !monitor.connected {
                Text("Plug in the iPhone, or put it on this Wi-Fi network, to reinstall.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 14)
    }

    private var reinstallButton: some View {
        let enabled = !state.selection.isEmpty && !state.isInstalling && monitor.connected
        return Button {
            state.reinstallSelected()
        } label: {
            HStack(spacing: 6) {
                if state.isInstalling {
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 12, height: 12)
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(state.isInstalling ? "Installing…" : "Reinstall \(state.selection.count)")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(enabled ? Color.white : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(enabled
                               ? AnyShapeStyle(Theme.accentGradient)
                               : AnyShapeStyle(Color.primary.opacity(0.07)))
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// Only present when there is something to say. It still has a fixed
    /// height while it's up, so the popover holds still as install output
    /// streams through it line by line — but with nothing to report it takes
    /// no room at all, rather than leaving an empty band under the apps.
    @ViewBuilder
    private var statusStrip: some View {
        if let text = statusText {
            HStack(spacing: 6) {
                if state.isInstalling {
                    ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 10, height: 10)
                }
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 12)
        }
    }

    private var statusText: String? {
        if state.isInstalling {
            return state.statusLine ?? "Working…"
        }
        return state.lastResultMessage
    }
}

// MARK: - App card

private struct AppCardView: View {
    let row: AppRow
    let isSelected: Bool
    let isAutoSelected: Bool
    let autoSelectionFull: Bool
    let showAutoStar: Bool
    let onToggle: () -> Void
    let onToggleAuto: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 11) {
            AppIconTile(app: row.app, isSelected: isSelected)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.app.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            if showAutoStar {
                autoStar
            }
            ExpiryRing(status: row.status)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(isSelected
                      ? Theme.accent.opacity(0.14)
                      : (hovering ? Theme.cardFillHover : Theme.cardFill))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent.opacity(0.55) : Theme.cardStroke,
                              lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        // The whole card is the checkbox now. A 34pt-tall target instead of
        // a 14pt one, and nothing to aim at.
        .onTapGesture(perform: onToggle)
        .onHover { hovering = $0 }
        .help(isSelected ? "Selected for reinstall — click to deselect" : "Click to select for reinstall")
    }

    /// Stars this app in or out of the unattended-reinstall set. Disabled
    /// (not hidden) once the cap is full and this app isn't already one of
    /// the starred ones, so it's clear why tapping does nothing.
    private var autoStar: some View {
        Button(action: onToggleAuto) {
            Image(systemName: isAutoSelected ? "star.fill" : "star")
                .font(.system(size: 12))
                .foregroundStyle(isAutoSelected
                                 ? AnyShapeStyle(Color(red: 1.0, green: 0.78, blue: 0.25))
                                 : AnyShapeStyle(Color.secondary.opacity(0.45)))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .disabled(!isAutoSelected && autoSelectionFull)
        .help(isAutoSelected
            ? "Auto-reinstalled when it's expiring. Click to stop."
            : (autoSelectionFull
                ? "Auto-reinstall slots are full — unstar one first"
                : "Auto-reinstall this app when it's expiring"))
    }

    /// One line now, not two: the ring carries the countdown, so this text
    /// only has to say when the app was last installed.
    private var subtitle: String {
        // Month/day only, no year: the whole window these dates describe is
        // seven days wide, so the year is never the thing in question and
        // dropping it is what lets both dates fit on one line.
        let dateFormatter = DateFormatter()
        dateFormatter.setLocalizedDateFormatFromTemplate("Md")
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short

        // The expiry date is the useful half — it comes from the app's actual
        // provisioning profile, which is what iOS enforces, and it does not
        // always land seven days after the install.
        guard let lastInstall = row.status.lastInstall else {
            guard let expiry = row.status.expiresAt else { return "Never installed via PhoneDeck" }
            return "Not installed here · expires \(dateFormatter.string(from: expiry))"
        }
        // Only the install date here. The expiry moved into the ring, whose
        // tooltip carries the exact date — repeating it on this line was
        // what pushed the text into an ellipsis.
        return "Installed \(dateFormatter.string(from: lastInstall)), \(timeFormatter.string(from: lastInstall))"
    }
}

/// Days left as an arc of the 7-day provisioning window, with the number in
/// the middle. Reads at a glance from across the desk, which "5d left" in
/// 10pt type never did.
private struct ExpiryRing: View {
    let status: ExpiryStatus

    var body: some View {
        let color = Theme.expiryColor(status)
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: 3)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            label
                .foregroundStyle(color)
        }
        .frame(width: 30, height: 30)
        .help(helpText)
    }

    @ViewBuilder
    private var label: some View {
        // isExpired, not days == 0: daysRemaining rounds up, so an app with
        // hours left says "1d" and only a genuinely dead profile gets the
        // exclamation mark.
        if status.isExpired {
            Image(systemName: "exclamationmark").font(.system(size: 12, weight: .bold))
        } else if let days = status.daysRemaining {
            (Text("\(days)").font(.system(size: 12, weight: .bold, design: .rounded))
             + Text("d").font(.system(size: 8, weight: .bold, design: .rounded)))
        } else {
            Text("?").font(.system(size: 12, weight: .bold, design: .rounded))
        }
    }

    private var fraction: CGFloat {
        guard let days = status.daysRemaining, !status.isExpired else { return 1 }
        return min(max(CGFloat(days) / CGFloat(provisioningWindowDays), 0.04), 1)
    }

    private var helpText: String {
        guard let expiry = status.expiresAt else { return "No provisioning profile found" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let source = status.isMeasured ? "from the provisioning profile" : "estimated from the install date"
        return "Expires \(formatter.string(from: expiry)) (\(source))"
    }
}

private struct DiscoveredCardView: View {
    let project: DiscoveredProject

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
                    .foregroundStyle(.tertiary)
                Image(systemName: "questionmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: Theme.tileSize, height: Theme.tileSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("No reinstall script yet")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .help(project.path)
    }
}

// MARK: - Small parts

/// The three auto-reinstall slots as three pips. Cheaper to read than
/// "2/3" and it makes the cap feel like a real, finite thing.
private struct SlotMeter: View {
    let used: Int
    let total: Int

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 3) {
                ForEach(0..<total, id: \.self) { index in
                    Capsule()
                        .fill(index < used ? AnyShapeStyle(Theme.accentGradient)
                                           : AnyShapeStyle(Color.primary.opacity(0.12)))
                        .frame(width: 14, height: 4)
                }
            }
            Text("\(used) of \(total) auto slots used — star the apps above")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
    }
}

/// A soft blinking dot for a live connection. Slow and low-contrast on
/// purpose: it should read as "alive", not as an alarm.
private struct LiveDot: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Color(red: 0.25, green: 0.82, blue: 0.5))
            .frame(width: 7, height: 7)
            .overlay(
                Circle()
                    .stroke(Color(red: 0.25, green: 0.82, blue: 0.5).opacity(0.5), lineWidth: 3)
                    .scaleEffect(pulsing ? 1.9 : 1.0)
                    .opacity(pulsing ? 0 : 0.8)
            )
            .onAppear {
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                    pulsing = true
                }
            }
            .accessibilityLabel("iPhone reachable")
    }
}

/// The quiet button shape used everywhere except the one primary action.
private struct PillButton: View {
    let title: String
    var tint: Color = .primary
    var filled: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(filled ? AnyShapeStyle(Color.white) : AnyShapeStyle(tint))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(filled
                                   ? AnyShapeStyle(tint.opacity(0.85))
                                   : AnyShapeStyle(hovering ? Theme.cardFillHover : Theme.cardFill))
                )
                .overlay(Capsule().strokeBorder(filled ? Color.clear : Theme.cardStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
