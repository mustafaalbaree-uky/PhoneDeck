import SwiftUI

// The original PhoneDeck look, kept so the newer design stays reversible:
// right-click the menu bar icon, pick "Use the classic look", and the
// popover swaps to this at runtime with no rebuild. See RootView.swift.

struct ClassicContentView: View {
    @ObservedObject var state: AppState
    @ObservedObject var monitor: DeviceMonitor
    @State private var pickerOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            deviceHeader

            // No ScrollView here on purpose. This list should never scroll,
            // it just grows and shrinks with however many rows there are.
            VStack(alignment: .leading, spacing: 4) {
                ForEach(state.rows) { row in
                    ClassicAppRowView(
                        row: row,
                        isSelected: state.selection.contains(row.app.id),
                        onToggle: { state.toggle(row.app.id) }
                    )
                }

                if !state.discovered.isEmpty {
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

    private var deviceHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(monitor.connected ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(headerTitle)
                        .font(.system(size: 13, weight: .medium))
                    // The transport is worth showing: a Wi-Fi link installs
                    // fine but is slower and can drop mid-build, so it helps
                    // to know which one is in play before starting.
                    Text(headerSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // Only when there is a choice to make: several phones
                // reachable, or one picked earlier that has to be handed
                // back somehow. Expanded in place rather than dropped as a
                // menu, for the reason spelled out in ContentView.
                if showsPicker {
                    Button(pickerOpen ? "Done" : "Change") {
                        pickerOpen.toggle()
                    }
                    .font(.caption)
                }
            }

            if showsPicker && pickerOpen {
                VStack(alignment: .leading, spacing: 2) {
                    pickerRow(title: "Whichever is here", picked: monitor.preferredDeviceID == nil) {
                        monitor.choose(nil)
                    }
                    ForEach(monitor.devices) { device in
                        // Two of the phones answer to the same name, so the
                        // model is part of the line.
                        pickerRow(
                            title: "\(device.name) · \(device.model) · \(device.transport.label)",
                            picked: device.id == monitor.preferredDeviceID
                        ) { monitor.choose(device) }
                    }
                }
                .padding(.leading, 16)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .onChange(of: showsPicker) { canPick in
            if !canPick { pickerOpen = false }
        }
    }

    private func pickerRow(title: String, picked: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            pickerOpen = false
        } label: {
            HStack(spacing: 5) {
                Image(systemName: picked ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 10))
                    .foregroundStyle(picked ? Color.accentColor : Color.secondary)
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var showsPicker: Bool {
        monitor.devices.count > 1 || monitor.preferredDeviceID != nil
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
            return "\(target.name) · \(target.transport.label)"
        }
        if monitor.preferredMissing && !monitor.devices.isEmpty {
            return monitor.devices.count == 1
                ? "1 other iPhone reachable"
                : "\(monitor.devices.count) other iPhones reachable"
        }
        return "Waiting for a paired iPhone"
    }

    private var footer: some View {
        VStack(spacing: 4) {
            statusStrip

            HStack {
                Button("Select all") { state.selection = Set(state.rows.map { $0.app.id }) }
                    .font(.caption)
                Button("Select none") { state.selection = [] }
                    .font(.caption)
                Spacer()
                Button {
                    state.installSelected()
                } label: {
                    if state.isInstalling {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Install (\(state.selection.count))")
                    }
                }
                .disabled(state.selection.isEmpty || state.isInstalling || !monitor.connected)
            }

            // Tied to there being no phone at all, and nothing else. It
            // used to also require a selection, which meant the first click
            // on an app grew the footer by a line, resized the popover under
            // the cursor, and shoved every card up. When a phone is around
            // but the picked one is away, the header already names the phone
            // it is waiting for, so this line would only repeat it.
            if !monitor.connected && monitor.devices.isEmpty {
                Text("Plug in the iPhone, or put it on this Wi-Fi network, to install.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 12)
    }

    /// Always occupies the same one line height, whether idle, streaming a
    /// live install step, or showing the final result, so nothing about the
    /// window ever resizes while an install is running.
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
    let onToggle: () -> Void

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
        }
    }

    private var subtitle: String {
        switch row.record.scope {
        case .never: return "Never installed via PhoneDeck"
        case .notThisDevice: return "Never installed to this iPhone"
        case .thisDevice, .unrecordedDevice:
            guard let lastInstall = row.record.date else { return "Never installed via PhoneDeck" }

            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short

            // The clock time sits under the date so every row breaks the same
            // way. Two installs on the same day are otherwise indistinguishable.
            return "Installed \(dateFormatter.string(from: lastInstall))\n\(timeFormatter.string(from: lastInstall))"
        }
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
                Text("No install script yet")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
