import Foundation

/// Free Apple ID provisioning is good for 7 days from when the profile is
/// issued — which is not always the same day the app was installed.
let provisioningWindowDays = 7

struct ExpiryStatus {
    let lastInstall: Date?
    /// When the app actually stops launching. Read from the provisioning
    /// profile when one is on disk, estimated from the install date otherwise.
    let expiresAt: Date?
    let daysRemaining: Int?   // nil if there's nothing to go on
    let isExpired: Bool
    /// True when `expiresAt` came from a real profile rather than the
    /// install + 7 days estimate. The estimate can be badly wrong: Xcode
    /// reuses a still-valid profile instead of issuing a new one, so a fresh
    /// install can inherit an expiry only days away.
    let isMeasured: Bool

    static let neverInstalled = ExpiryStatus(
        lastInstall: nil, expiresAt: nil, daysRemaining: nil,
        isExpired: true, isMeasured: false
    )

    static func read(stateFile: String, bundleID: String) -> ExpiryStatus {
        let installedAt = installDate(stateFile: stateFile)

        // The profile wins whenever there is one: it is what iOS enforces.
        if let expiry = ProvisioningProfiles.earliestExpiry(forBundleID: bundleID) {
            return status(lastInstall: installedAt, expiresAt: expiry, isMeasured: true)
        }

        // No profile on disk (never built here, or the profiles were cleared
        // since). Fall back to the old estimate so the row still says
        // something, flagged as unmeasured.
        guard let installedAt else { return .neverInstalled }
        let estimated = installedAt.addingTimeInterval(TimeInterval(provisioningWindowDays) * 86400)
        return status(lastInstall: installedAt, expiresAt: estimated, isMeasured: false)
    }

    private static func status(lastInstall: Date?, expiresAt: Date, isMeasured: Bool) -> ExpiryStatus {
        let secondsLeft = expiresAt.timeIntervalSinceNow
        return ExpiryStatus(
            lastInstall: lastInstall,
            expiresAt: expiresAt,
            // Rounding up, the way "expires in N days" is normally read. A
            // profile minted seconds ago has 6.99 days on it, and flooring
            // that to "6d left" right after a reinstall reads as the reset
            // having failed. Ceiling also means a still-valid app with hours
            // to go says "1d left" rather than "0d".
            daysRemaining: max(Int(ceil(secondsLeft / 86400)), 0),
            isExpired: secondsLeft <= 0,
            isMeasured: isMeasured
        )
    }

    private static func installDate(stateFile: String) -> Date? {
        guard
            let raw = try? String(contentsOfFile: stateFile, encoding: .utf8),
            let epoch = TimeInterval(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return Date(timeIntervalSince1970: epoch)
    }
}
