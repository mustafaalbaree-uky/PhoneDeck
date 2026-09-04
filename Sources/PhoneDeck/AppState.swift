import Foundation
import Combine

struct AppRow: Identifiable {
    let app: KnownApp
    /// When PhoneDeck last installed this app to the phone now picked, and
    /// how much that date is worth. See `InstallRecord`.
    var record: InstallRecord.Reading
    var id: String { app.id }
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

    let deviceMonitor = DeviceMonitor()
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Install dates are read per phone, so switching phones has to
        // re-read them. The cheap refresh: no ~/Code walk, just timestamps.
        deviceMonitor.targetChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refresh(includeDiscovery: false) }
            .store(in: &cancellables)
    }

    /// `includeDiscovery` is off for the cheap refreshes: walking ~/Code for
    /// stray Xcode projects is far heavier than re-reading a handful of
    /// timestamps, and nothing about it changes between two clicks.
    func refresh(includeDiscovery: Bool = true) {
        let deviceID = deviceMonitor.target?.id
        rows = AppRegistry.known.map { app in
            AppRow(
                app: app,
                record: InstallRecord.reading(stateDir: app.stateDir, deviceID: deviceID)
            )
        }
        if includeDiscovery {
            discovered = AppRegistry.scanForUnregistered()
        }
    }

    func toggle(_ id: String) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    func installSelected() {
        guard !selection.isEmpty, !isInstalling else { return }
        // Nothing installs without a phone resolved to a UDID. The scripts
        // would otherwise fall back to picking one themselves, which is the
        // behaviour the picker exists to replace.
        guard let device = deviceMonitor.target else { return }

        let targets = rows.filter { selection.contains($0.app.id) }
        isInstalling = true
        lastResultMessage = nil
        statusLine = nil

        Task {
            let result = await self.performInstalls(targets, to: device)

            self.isInstalling = false
            self.statusLine = nil
            self.selection.removeAll()
            self.refresh()
            self.lastResultMessage = Self.resultMessage(
                succeeded: result.succeeded, failed: result.failed, deviceName: device.name
            )
            // A build runs for minutes and the popover closes the moment you
            // click away, so the result has to be able to find you.
            NotificationManager.installFinished(
                succeeded: result.succeeded, failed: result.failed, deviceName: device.name
            )
        }
    }

    /// Runs each app's script in turn against one phone, streaming its
    /// output into `statusLine`.
    func performInstalls(
        _ targets: [AppRow], to device: PhoneDevice
    ) async -> (succeeded: [String], failed: [String]) {
        var succeeded: [String] = []
        var failed: [String] = []
        let environment = [
            "PHONEDECK_DEVICE_ID": device.id,
            "PHONEDECK_DEVICE_NAME": device.name,
        ]
        for row in targets {
            statusLine = "\(row.app.displayName): starting…"
            let outcome = await Installer.run(
                scriptPath: row.app.installScript,
                args: row.app.installArgs,
                environment: environment
            ) { line in
                self.statusLine = "\(row.app.displayName): \(line)"
            }
            switch outcome {
            case .success: succeeded.append(row.app.displayName)
            case .failure: failed.append(row.app.displayName)
            }
        }
        return (succeeded, failed)
    }

    static func resultMessage(succeeded: [String], failed: [String], deviceName: String) -> String {
        if failed.isEmpty {
            return "Installed to \(deviceName): \(succeeded.joined(separator: ", "))"
        } else if succeeded.isEmpty {
            return "Install to \(deviceName) failed: \(failed.joined(separator: ", ")). Check the phone is reachable and unlocked."
        } else {
            return "Installed \(succeeded.joined(separator: ", ")) to \(deviceName). Failed: \(failed.joined(separator: ", "))."
        }
    }
}
