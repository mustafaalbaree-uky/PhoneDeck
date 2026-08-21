import Foundation

/// One iOS app PhoneDeck knows how to reinstall: it has a repo, a reinstall
/// script that follows the "rebuild, install, stamp last_install" shape used
/// by ClipKeyboard and Hu, and a state directory holding that stamp.
struct KnownApp: Identifiable {
    let id: String            // stable key, e.g. "hu"
    let displayName: String
    let bundleID: String      // used to find this app's provisioning profile
    let repoPath: String      // absolute path to the repo/project directory
    let installScript: String // absolute path to the reinstall script
    let installArgs: [String] // extra args the script needs every time
    let stateDir: String      // absolute path holding last_install

    var lastInstallFile: String { stateDir + "/last_install" }
}

/// An Xcode project PhoneDeck found on disk that isn't wired up to a known
/// reinstall script yet. Shown so nothing is invisible, but not installable
/// until it gets a script.
struct DiscoveredProject: Identifiable {
    var id: String { path }
    let name: String
    let path: String
}

enum AppRegistry {
    private static let home = FileManager.default.homeDirectoryForCurrentUser.path

    /// Apps PhoneDeck can actually reinstall today. Add an entry here once a
    /// project grows a reinstall script of its own.
    static let known: [KnownApp] = [
        KnownApp(
            id: "shadiliya",
            displayName: "Shadiliya",
            bundleID: "com.mammer55.hu",
            repoPath: "\(home)/Code/shadiliya",
            installScript: "\(home)/Code/shadiliya/tools/install.sh",
            // Permanent, by preference: Mustafa does not want the watch app
            // (13 Aug 2026). Not a workaround, so do not remove it.
            //
            // It began as one. Building with the watch failed on 8 Aug 2026
            // ("watchOS 26.2 must be installed") even though the SDK showed up
            // in `xcodebuild -showsdks`. That breakage is gone, verified by a
            // clean build with the watch target on 13 Aug 2026, which is why
            // the old "until this gets sorted out" note is no longer here.
            installArgs: ["--no-watch"],
            stateDir: "\(home)/.shadiliya"
        ),
        KnownApp(
            id: "clipkeyboard",
            displayName: "ClipKeyboard",
            bundleID: "com.mammer55.clipkeyboard",
            repoPath: "\(home)/Code/ClipKeyboard",
            installScript: "\(home)/Code/ClipKeyboard/tools/reinstall_clipkeyboard.sh",
            installArgs: [],
            stateDir: "\(home)/.clipkeyboard"
        ),
        KnownApp(
            id: "tasbih",
            displayName: "Tasbih",
            bundleID: "com.mustafaalbaree.dhikr",
            repoPath: "\(home)/Code/tasbih/ios",
            installScript: "\(home)/Code/tasbih/ios/tools/install.sh",
            installArgs: [],
            stateDir: "\(home)/.tasbih"
        ),
        KnownApp(
            id: "ontime",
            displayName: "On Time",
            bundleID: "com.mammer55.ontime",
            repoPath: "\(home)/Code/ontime",
            installScript: "\(home)/Code/ontime/tools/install.sh",
            installArgs: [],
            stateDir: "\(home)/.ontime"
        ),
    ]

    /// Directory names never worth descending into while scanning for stray
    /// Xcode projects — dependency trees and build output, not source.
    private static let skipDirNames: Set<String> = [
        "node_modules", "Pods", "build", "build-watch", "DerivedData",
        ".git", ".build", "Carthage", "xcuserdata",
    ]

    /// Walks ~/Code looking for .xcodeproj directories that aren't already
    /// part of a known app, so a new iOS project shows up automatically
    /// instead of staying invisible until someone remembers to register it.
    static func scanForUnregistered() -> [DiscoveredProject] {
        let codeRoot = "\(home)/Code"
        let fm = FileManager.default
        let knownPaths = Set(known.map { $0.repoPath })

        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: codeRoot),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var found: [DiscoveredProject] = []
        var seenNames = Set<String>()

        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

            if isDir && skipDirNames.contains(name) {
                enumerator.skipDescendants()
                continue
            }

            guard isDir, name.hasSuffix(".xcodeproj") else { continue }
            enumerator.skipDescendants() // never look inside a project bundle

            let projectName = String(name.dropLast(".xcodeproj".count))
            let repoDir = url.deletingLastPathComponent().path

            // Already covered by a known app (script lives somewhere under
            // that repo)? Skip it.
            if knownPaths.contains(where: { repoDir == $0 || repoDir.hasPrefix($0 + "/") }) {
                continue
            }
            // Nested workspace/project pairs (e.g. QadaTracker.xcodeproj and
            // its .xcworkspace) would otherwise show up twice.
            guard !seenNames.contains(projectName) else { continue }
            seenNames.insert(projectName)

            found.append(DiscoveredProject(name: projectName, path: repoDir))
        }

        return found.sorted { $0.name < $1.name }
    }
}
