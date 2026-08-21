import ServiceManagement

/// Wraps SMAppService so PhoneDeck can register itself to launch at login —
/// the only way "plug in the phone" actually works without opening the app
/// by hand first. Requires the app to live in /Applications.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Silent on purpose: this is a convenience toggle, not a
            // critical path, and a system alert would be noisier than
            // the failure is worth explaining.
        }
    }
}
