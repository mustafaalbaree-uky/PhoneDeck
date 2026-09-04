import Foundation
import Combine

/// Polls `devicectl` for connected, paired iPhones. Polling rather than an
/// IOKit notification stream because devicectl is already the source of
/// truth the reinstall scripts use, and asking it directly avoids drifting
/// out of sync with what a build would actually see.
/// How a phone is reachable right now. Both values support installing;
/// they differ only in what the UI says.
enum DeviceTransport {
    case wired
    case network

    var label: String {
        switch self {
        case .wired: return "connected"
        case .network: return "over Wi-Fi"
        }
    }
}

/// One iPhone devicectl can reach at this moment.
struct PhoneDevice: Identifiable, Equatable {
    /// The hardware UDID, which is both what `xcodebuild -destination id:`
    /// expects and what `devicectl device install --device` accepts. It is
    /// the value handed to an install script, so it has to be this one and
    /// not the CoreDevice UUID devicectl prints in its own list.
    let id: String
    let name: String
    let model: String
    let transport: DeviceTransport
}

final class DeviceMonitor: ObservableObject {
    /// Every iPhone reachable right now, cabled ones first.
    @Published private(set) var devices: [PhoneDevice] = []

    /// The UDID of the phone Mustafa picked, or nil while PhoneDeck is
    /// choosing for him. A choice is remembered across launches and is
    /// honoured strictly: when the picked phone is not around, PhoneDeck
    /// refuses to install rather than falling through to whichever other
    /// phone happens to be on the network, since that other phone is often
    /// somebody else's.
    @Published private(set) var preferredDeviceID: String?

    /// The name the picked phone had when it was picked, so the UI can name
    /// the phone it is waiting for even while that phone is away.
    @Published private(set) var preferredDeviceName: String?

    /// True when a phone has been picked and is not reachable.
    var preferredMissing: Bool {
        guard let preferredDeviceID else { return false }
        return !devices.contains { $0.id == preferredDeviceID }
    }

    /// The phone an install would go to, or nil if there isn't one.
    var target: PhoneDevice? {
        if let preferredDeviceID {
            return devices.first { $0.id == preferredDeviceID }
        }
        // A cabled phone wins when nothing has been picked, since that's the
        // link a build will actually take.
        return devices.first { $0.transport == .wired } ?? devices.first
    }

    @Published private(set) var connected: Bool = false

    /// Fires once on every false → true transition, so the UI can surface
    /// itself the moment a phone appears without re-announcing on every poll.
    let didConnect = PassthroughSubject<Void, Never>()

    /// Fires whenever the picked phone changes, so per-device install
    /// records get re-read for the phone now in play.
    let targetChanged = PassthroughSubject<Void, Never>()

    private var timer: Timer?
    private let pollInterval: TimeInterval = 3

    private static let preferredIDKey = "preferredDeviceID"
    private static let preferredNameKey = "preferredDeviceName"

    init() {
        preferredDeviceID = UserDefaults.standard.string(forKey: Self.preferredIDKey)
        preferredDeviceName = UserDefaults.standard.string(forKey: Self.preferredNameKey)
    }

    /// Picks a phone by hand. `nil` hands the choice back to PhoneDeck.
    func choose(_ device: PhoneDevice?) {
        let previous = target?.id
        preferredDeviceID = device?.id
        preferredDeviceName = device?.name
        UserDefaults.standard.set(device?.id, forKey: Self.preferredIDKey)
        UserDefaults.standard.set(device?.name, forKey: Self.preferredNameKey)
        connected = target != nil
        if target?.id != previous {
            targetChanged.send()
        }
    }

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let found = Self.queryDevicectl()
            DispatchQueue.main.async {
                guard let self else { return }
                guard found != self.devices else { return }
                let wasConnected = self.connected
                let previousTarget = self.target?.id
                self.devices = found
                self.connected = self.target != nil
                if !wasConnected && self.connected {
                    self.didConnect.send()
                }
                if self.target?.id != previousTarget {
                    self.targetChanged.send()
                }
            }
        }
    }

    private struct DevicectlResult: Decodable {
        struct Result: Decodable { let devices: [Device] }
        struct Device: Decodable {
            struct DeviceProperties: Decodable { let name: String }
            struct HardwareProperties: Decodable {
                let marketingName: String
                let udid: String
            }
            struct ConnectionProperties: Decodable { let transportType: String? }
            let deviceProperties: DeviceProperties
            let hardwareProperties: HardwareProperties
            let connectionProperties: ConnectionProperties
        }
        let result: Result
    }

    /// Asks devicectl for iPhones reachable right now, over USB or over the
    /// local network.
    ///
    /// devicectl's "State" column (and the JSON's connectionProperties.
    /// tunnelState it's derived from) is NOT a stable presence signal: it
    /// flips between "connected", "disconnected", and "available (paired)"
    /// as devicectl opens and tears down its on-demand tunnel, even while
    /// the link never moves. Filtering on any single one of those values
    /// (tried "available", then "connected") left PhoneDeck flapping
    /// between seeing and losing a phone that was present the whole time.
    ///
    /// The stable signal is connectionProperties.transportType, which is
    /// set while a link exists and absent entirely on stale pairing records
    /// for phones that aren't around (an old device that last checked in
    /// months ago has no transportType key at all). It takes two values:
    /// "wired" for USB and "localNetwork" for a Wi-Fi-paired phone. Both
    /// install fine — the reinstall scripts resolve their destination via
    /// `xcodebuild -showdestinations`, which lists network devices too — so
    /// gating on "wired" alone wrongly refused to install to a phone that
    /// was reachable and would have accepted the build.
    private static func queryDevicectl() -> [PhoneDevice] {
        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("phonedeck-devices-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "devicectl", "list", "devices",
            "--filter", "hardwareProperties.deviceType == 'iPhone'",
            "--json-output", tmpFile.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return []
        }
        process.waitUntilExit()

        guard
            let data = try? Data(contentsOf: tmpFile),
            let parsed = try? JSONDecoder().decode(DevicectlResult.self, from: data)
        else { return [] }

        // The transportType match happens here rather than in devicectl's
        // --filter expression: the filter language has no way to say "this
        // key is present", and an OR of the two known values would silently
        // drop any future transport Apple adds.
        let live = parsed.result.devices.compactMap { device -> PhoneDevice? in
            guard let raw = device.connectionProperties.transportType else { return nil }
            return PhoneDevice(
                id: device.hardwareProperties.udid,
                name: device.deviceProperties.name,
                model: device.hardwareProperties.marketingName,
                transport: raw == "wired" ? .wired : .network
            )
        }

        // Cabled first, then alphabetical. A stable order keeps the picker
        // from reshuffling under the cursor between two three-second polls,
        // and makes the automatic pick deterministic.
        return live.sorted { lhs, rhs in
            if (lhs.transport == .wired) != (rhs.transport == .wired) {
                return lhs.transport == .wired
            }
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.id < rhs.id
        }
    }
}
