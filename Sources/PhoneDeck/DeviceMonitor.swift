import Foundation
import Combine

/// Polls `devicectl` for a connected, paired iPhone. Polling rather than an
/// IOKit notification stream because devicectl is already the source of
/// truth the reinstall scripts use, and asking it directly avoids drifting
/// out of sync with what a build would actually see.
/// How the phone is reachable right now. Both values support installing;
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

final class DeviceMonitor: ObservableObject {
    @Published private(set) var connected: Bool = false
    @Published private(set) var deviceName: String?
    @Published private(set) var deviceModel: String?
    @Published private(set) var transport: DeviceTransport?

    /// Fires once on every false → true transition, so the UI can surface
    /// itself the moment a phone appears without re-announcing on every poll.
    let didConnect = PassthroughSubject<Void, Never>()

    private var timer: Timer?
    private let pollInterval: TimeInterval = 3

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
            let result = Self.queryDevicectl()
            DispatchQueue.main.async {
                guard let self else { return }
                let wasConnected = self.connected
                self.connected = result != nil
                self.deviceName = result?.name
                self.deviceModel = result?.model
                self.transport = result?.transport
                if !wasConnected && self.connected {
                    self.didConnect.send()
                }
            }
        }
    }

    private struct DevicectlResult: Decodable {
        struct Result: Decodable { let devices: [Device] }
        struct Device: Decodable {
            struct DeviceProperties: Decodable { let name: String }
            struct HardwareProperties: Decodable { let marketingName: String }
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
    private static func queryDevicectl() -> (name: String, model: String, transport: DeviceTransport)? {
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
            return nil
        }
        process.waitUntilExit()

        guard
            let data = try? Data(contentsOf: tmpFile),
            let parsed = try? JSONDecoder().decode(DevicectlResult.self, from: data)
        else { return nil }

        // The transportType match happens here rather than in devicectl's
        // --filter expression: the filter language has no way to say "this
        // key is present", and an OR of the two known values would silently
        // drop any future transport Apple adds.
        let live = parsed.result.devices.compactMap { device -> (name: String, model: String, transport: DeviceTransport)? in
            guard let raw = device.connectionProperties.transportType else { return nil }
            let transport: DeviceTransport = (raw == "wired") ? .wired : .network
            return (
                name: device.deviceProperties.name,
                model: device.hardwareProperties.marketingName,
                transport: transport
            )
        }

        // A cabled phone wins if both are somehow reported, since that's the
        // link a build will actually take.
        return live.first(where: { $0.transport == .wired }) ?? live.first
    }
}
