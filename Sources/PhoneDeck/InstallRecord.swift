import Foundation

/// When PhoneDeck last pushed a build of an app to a phone.
///
/// Every reinstall script writes the epoch seconds of a successful install
/// into its app's state directory, so this is a record of what PhoneDeck
/// did rather than a reading of what is on the phone. It answers the only
/// question that still matters day to day: is the build on the phone the one
/// I built after my last change.
///
/// There are two stamps, and the difference matters once more than one phone
/// is in play. `last_install` is the old single file, written on every
/// install regardless of where the build went, so a date read from it says
/// nothing about which phone received it. `last_install_<UDID>` is per phone,
/// written since PhoneDeck learned to pick a device, and is the one that can
/// answer "is this build on the phone I am looking at". A per-phone stamp is
/// preferred whenever one exists; `last_install` is only read for apps that
/// have no per-phone history yet, which is every app installed before the
/// picker existed.
///
/// PhoneDeck used to compute a countdown here as well. Free Apple ID
/// provisioning expired seven days after the profile was issued, so an app
/// died on its own and something had to watch the clock. A paid Apple
/// Developer membership issues profiles good for a year, so there is no
/// clock left to watch and the countdown is gone.
enum InstallRecord {
    enum Scope {
        /// Installed to the phone currently picked.
        case thisDevice
        /// Installed, from before PhoneDeck recorded which phone got it.
        case unrecordedDevice
        /// This app has per-phone history, but none for the phone picked.
        case notThisDevice
        /// PhoneDeck has never installed this app anywhere.
        case never
    }

    struct Reading {
        let date: Date?
        let scope: Scope
    }

    static func reading(stateDir: String, deviceID: String?) -> Reading {
        if let deviceID, let date = stamp(at: "\(stateDir)/last_install_\(deviceID)") {
            return Reading(date: date, scope: .thisDevice)
        }

        let legacy = stamp(at: "\(stateDir)/last_install")

        // A per-phone stamp for some *other* phone is the signal that this
        // app's history is device-aware, which makes the absence of one for
        // the picked phone meaningful rather than merely unrecorded.
        if deviceID != nil, hasPerDeviceHistory(stateDir: stateDir) {
            return Reading(date: nil, scope: .notThisDevice)
        }

        guard let legacy else { return Reading(date: nil, scope: .never) }
        return Reading(date: legacy, scope: .unrecordedDevice)
    }

    private static func stamp(at path: String) -> Date? {
        guard
            let raw = try? String(contentsOfFile: path, encoding: .utf8),
            let epoch = TimeInterval(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return Date(timeIntervalSince1970: epoch)
    }

    private static func hasPerDeviceHistory(stateDir: String) -> Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: stateDir)) ?? []
        return names.contains { $0.hasPrefix("last_install_") }
    }
}
