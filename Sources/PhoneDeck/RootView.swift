import SwiftUI

/// The undo switch for the redesign.
///
/// Both looks are compiled in and both talk to the same `AppState`, so
/// flipping between them is a preference, not a rebuild: right-click the
/// menu bar icon and pick "Use the classic look". The choice is remembered
/// across launches.
enum LookSettings {
    static let classicKey = "useClassicLook"

    static var useClassic: Bool {
        get { UserDefaults.standard.bool(forKey: classicKey) }
        set { UserDefaults.standard.set(newValue, forKey: classicKey) }
    }
}

struct RootView: View {
    @ObservedObject var state: AppState
    @ObservedObject var monitor: DeviceMonitor
    @AppStorage(LookSettings.classicKey) private var useClassic = false

    var body: some View {
        if useClassic {
            ClassicContentView(state: state, monitor: monitor)
        } else {
            ContentView(state: state, monitor: monitor)
        }
    }
}
