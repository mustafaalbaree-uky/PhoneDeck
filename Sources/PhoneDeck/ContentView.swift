import SwiftUI

/// PhoneDeck's current look. The whole popover is one column of cards on a
/// faint accent wash: a device header, a card per app, and a footer that
/// holds the controls.
///
/// The previous design is still in the build, unchanged, in
/// ClassicContentView.swift. Right-click the menu bar icon to switch back.
struct ContentView: View {
    @ObservedObject var state: AppState
    @ObservedObject var monitor: DeviceMonitor
    @State private var pickerOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            deviceHeader

            // No ScrollView here on purpose. This list should never scroll,
            // it just grows and shrinks with however many rows there are.
            VStack(alignment: .leading, spacing: 6) {
                ForEach(state.rows) { row in
                    AppCardView(
                        row: row,
                        isSelected: state.selection.contains(row.app.id),
                        onToggle: { state.toggle(row.app.id) }
                    )
                }

                if !state.discovered.isEmpty {
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

    /// The header is also the device picker. It only opens when there is a
    /// choice to make: more than one phone reachable, or a phone picked
    /// earlier that PhoneDeck has to be able to hand back.
    ///
    /// The list expands inside the popover rather than dropping an NSMenu.
    /// The popover is `.transient` and closes on the first mouse-down it
    /// sees outside itself, which a menu's own event tracking is a good way
    /// to trip; expanding in place cannot fight it. A SwiftUI `Menu` also
    /// throws away most of a custom label under `.borderlessButton`, which
    /// left the header as a bare line of text.
    private var deviceHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsPicker {
                // A real Button rather than a tap gesture on the row: it
                // gets the accessibility role, the keyboard, and the click
                // handling for free.
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { pickerOpen.toggle() }
                } label: {
                    headerBody
                }
                .buttonStyle(.plain)
                .help(pickerOpen ? "Close the phone list" : "Choose which iPhone to install to")
            } else {
                headerBody
            }

            if showsPicker && pickerOpen {
                VStack(alignment: .leading, spacing: 4) {
                    pickerRow(
                        title: "Whichever is here",
                        detail: nil,
                        icon: "sparkles",
                        picked: monitor.preferredDeviceID == nil
                    ) { monitor.choose(nil) }

                    ForEach(monitor.devices) { device in
                        pickerRow(
                            // Two of the phones answer to the same name, so
                            // the model is part of the line underneath.
                            title: device.name,
                            detail: "\(device.model) · \(device.transport.label)",
                            icon: device.transport == .wired ? "cable.connector" : "wifi",
                            picked: device.id == monitor.preferredDeviceID
                        ) { monitor.choose(device) }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .onChange(of: showsPicker) { canPick in
            if !canPick { pickerOpen = false }
        }
    }

    private var headerBody: some View {
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
                Text(headerTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let icon = headerSubtitleIcon {
                        Image(systemName: icon)
                            .font(.system(size: 9, weight: .semibold))
                    }
                    Text(headerSubtitle)
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 6)

            if monitor.connected {
                LiveDot()
            }
            if showsPicker {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(pickerOpen ? 180 : 0))
            }
        }
        .contentShape(Rectangle())
    }

    private func pickerRow(
        title: String,
        detail: String?,
        icon: String,
        picked: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            withAnimation(.easeOut(duration: 0.16)) { pickerOpen = false }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 13)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if picked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(picked ? Theme.accent.opacity(0.12) : Theme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(picked ? Theme.accent.opacity(0.5) : Theme.cardStroke, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// A picked phone that has gone away is never quietly swapped for
    /// another one, so the header has three states rather than two.
    private var headerTitle: String {
        if let target = monitor.target { return target.model }
        if monitor.preferredMissing {
            return "\(monitor.preferredDeviceName ?? "Chosen iPhone") not reachable"
        }
        return "No iPhone connected"
    }

    private var headerSubtitle: String {
        if let target = monitor.target {
            // The transport is worth showing: a Wi-Fi link installs fine but
            // is slower and can drop mid-build, so it helps to know which
            // one is in play before starting.
            return "\(target.name) · \(target.transport.label)"
        }
        if monitor.preferredMissing && !monitor.devices.isEmpty {
            return monitor.devices.count == 1
                ? "1 other iPhone reachable"
                : "\(monitor.devices.count) other iPhones reachable"
        }
        return "Waiting for a paired iPhone"
    }

    private var headerSubtitleIcon: String? {
        guard let target = monitor.target else { return nil }
        return target.transport == .wired ? "cable.connector" : "wifi"
    }

    private var showsPicker: Bool {
        monitor.devices.count > 1 || monitor.preferredDeviceID != nil
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusStrip

            HStack(spacing: 8) {
                PillButton(title: "All") {
                    state.selection = Set(state.rows.map { $0.app.id })
                }
                PillButton(title: "None") {
                    state.selection = []
                }
                Spacer(minLength: 0)
                installButton
            }

            // Tied to there being no phone at all, and nothing else. It
            // used to also require a selection, which meant the first click
            // on an app grew the footer by a line, resized the popover under
            // the cursor, and shoved every card up. When a phone is around
            // but the picked one is away, the header already names the phone
            // it is waiting for, so this line would only repeat it.
            if !monitor.connected && monitor.devices.isEmpty {
                Text("Plug in the iPhone, or put it on this Wi-Fi network, to install.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 14)
    }

    private var installButton: some View {
        let enabled = !state.selection.isEmpty && !state.isInstalling && monitor.connected
        return Button {
            state.installSelected()
        } label: {
            HStack(spacing: 6) {
                if state.isInstalling {
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 12, height: 12)
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(state.isInstalling ? "Installing…" : "Install \(state.selection.count)")
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
    /// streams through it line by line, but with nothing to report it takes
    /// no room at all rather than leaving an empty band under the apps.
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
    let onToggle: () -> Void

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
        // The whole card is the checkbox. A 34pt tall target instead of a
        // 14pt one, and nothing to aim at.
        .onTapGesture(perform: onToggle)
        .onHover { hovering = $0 }
        .help(isSelected ? "Selected for install, click to deselect" : "Click to select for install")
    }

    /// The only thing worth saying about an app that is not its name: when
    /// PhoneDeck last put a build of it on the phone now picked.
    private var subtitle: String {
        switch row.record.scope {
        case .never: return "Never installed via PhoneDeck"
        case .notThisDevice: return "Never installed to this iPhone"
        case .thisDevice, .unrecordedDevice:
            guard let lastInstall = row.record.date else { return "Never installed via PhoneDeck" }

            let dateFormatter = DateFormatter()
            dateFormatter.setLocalizedDateFormatFromTemplate("MMMd")
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short

            return "Installed \(dateFormatter.string(from: lastInstall)), \(timeFormatter.string(from: lastInstall))"
        }
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
                Text("No install script yet")
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

/// A soft blinking dot for a live connection. Slow and low contrast on
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
