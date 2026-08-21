import Foundation

/// The provisioning profiles Xcode has issued on this Mac, read straight off
/// disk.
///
/// This is the authority on when an app stops launching. PhoneDeck used to
/// infer that from `last_install` + 7 days, which quietly assumed every
/// rebuild mints a fresh profile — it doesn't. Xcode reuses a profile that is
/// still valid, so the clock can keep running from an issue date well before
/// the install. Reading the profile removes the guess.
enum ProvisioningProfiles {
    private static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Developer/Xcode/UserData/Provisioning Profiles")

    /// Earliest expiry across the app's own profile and any profile nested
    /// under its bundle ID (extensions, widgets, a watch app).
    ///
    /// Earliest rather than latest on purpose: a dead extension profile takes
    /// the whole app down with it, so the soonest death is the one that
    /// matters.
    static func earliestExpiry(forBundleID bundleID: String) -> Date? {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return nil }

        var earliest: Date?
        for file in files where file.pathExtension == "mobileprovision" {
            guard
                let plist = plist(at: file),
                let entitlements = plist["Entitlements"] as? [String: Any],
                let appID = entitlements["application-identifier"] as? String,
                let expiry = plist["ExpirationDate"] as? Date
            else { continue }

            // appID is TEAMID.com.example.app. Match the app itself and
            // anything nested under it, but not a sibling that merely shares
            // a prefix (com.example.appstore).
            let isOurs = appID.hasSuffix(".\(bundleID)") || appID.contains(".\(bundleID).")
            guard isOurs else { continue }

            if earliest == nil || expiry < earliest! { earliest = expiry }
        }
        return earliest
    }

    /// A .mobileprovision is a CMS signature wrapped around a plain XML
    /// plist. Slicing the payload out beats shelling out to `security cms -D`
    /// once per profile on every refresh, and refresh runs on every poll.
    private static func plist(at url: URL) -> [String: Any]? {
        guard
            let data = try? Data(contentsOf: url),
            let start = data.range(of: Data("<?xml".utf8)),
            let end = data.range(of: Data("</plist>".utf8), options: .backwards)
        else { return nil }

        let payload = data[start.lowerBound..<end.upperBound]
        guard let object = try? PropertyListSerialization.propertyList(
            from: payload, options: [], format: nil
        ) else { return nil }
        return object as? [String: Any]
    }
}
