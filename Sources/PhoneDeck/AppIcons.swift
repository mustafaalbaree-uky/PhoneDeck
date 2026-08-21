import AppKit
import SwiftUI

/// Finds each app's real icon in its own repo and hands it to the UI.
///
/// The icon is read straight from the project's `AppIcon.appiconset` rather
/// than from the copy on the phone: PhoneDeck already knows where every
/// repo is, the asset catalog is the source the build itself uses, and it
/// stays readable whether or not the phone is around.
@MainActor
final class AppIconLoader: ObservableObject {
    static let shared = AppIconLoader()

    /// app id → icon. A miss is cached as a nil entry so a project with no
    /// icon isn't re-walked on every redraw.
    @Published private(set) var icons: [String: NSImage?] = [:]
    private var inFlight: Set<String> = []

    /// Returns the icon if it's already loaded, and otherwise starts the
    /// search and returns nil. Callers observe this object, so the row
    /// redraws with the icon the moment it lands.
    func icon(for app: KnownApp) -> NSImage? {
        if let cached = icons[app.id] { return cached }
        guard !inFlight.contains(app.id) else { return nil }
        inFlight.insert(app.id)

        let id = app.id
        let repo = app.repoPath
        Task.detached(priority: .utility) {
            let image = AppIconLoader.findIcon(inRepo: repo)
            await MainActor.run {
                self.icons[id] = image
                self.inFlight.remove(id)
            }
        }
        return nil
    }

    // MARK: - Disk search

    /// Directories that never hold a hand-made app icon but do hold tens of
    /// thousands of files. Walking into them turns a 20ms search into a
    /// multi-second one.
    private nonisolated static let skippedDirectories: Set<String> = [
        ".git", ".build", "build", "DerivedData", "node_modules",
        "Pods", "Carthage", ".swiftpm", "dist", "vendor"
    ]

    private nonisolated static func findIcon(inRepo repo: String) -> NSImage? {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: repo)
        guard let walker = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        var candidates: [URL] = []
        for case let url as URL in walker {
            let name = url.lastPathComponent
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                if skippedDirectories.contains(name) { walker.skipDescendants() }
                continue
            }
            guard url.pathExtension.lowercased() == "png",
                  url.deletingLastPathComponent().pathExtension == "appiconset"
            else { continue }
            candidates.append(url)
        }
        guard !candidates.isEmpty else { return nil }

        // A repo can hold several icon sets — the watch app, an app clip, a
        // widget. Prefer one that isn't obviously a companion target, then
        // take the biggest image in whatever's left.
        let companion = ["watch", "widget", "clip", "extension", "intents"]
        let preferred = candidates.filter { url in
            let path = url.path.lowercased()
            return !companion.contains { path.contains($0) }
        }
        let pool = preferred.isEmpty ? candidates : preferred

        return pool
            .compactMap { url -> (NSImage, Int)? in
                guard let image = NSImage(contentsOf: url) else { return nil }
                // pixelsWide, not size: NSImage reports points, and two icons
                // can claim the same point size at different resolutions.
                let pixels = image.representations.map(\.pixelsWide).max() ?? 0
                return (image, pixels)
            }
            .max { $0.1 < $1.1 }?
            .0
    }
}

/// The app's own icon, squircled and finished with the same gloss the tiles
/// had before it: a sheen across the top half and a hairline rim, so a flat
/// PNG and a gradient monogram sit in the same list without one looking
/// pasted on. Falls back to the monogram tile when a repo has no icon.
struct AppIconTile: View {
    let app: KnownApp
    let isSelected: Bool
    @ObservedObject private var loader = AppIconLoader.shared

    var body: some View {
        ZStack {
            if isSelected {
                RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                    .fill(Theme.accentGradient)
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            } else if let icon = loader.icon(for: app) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
                gloss
            } else {
                RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                    .fill(Theme.tileGradient(forID: app.id))
                Text(String(app.displayName.prefix(1)).uppercased())
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.95))
                gloss
            }
        }
        .frame(width: Theme.tileSize, height: Theme.tileSize)
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
    }

    /// Light from above: a bright band over the top, a faint lift from the
    /// bottom edge, and a rim that keeps the shape's edge crisp against
    /// both a dark and a light popover.
    private var gloss: some View {
        RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.30), location: 0.0),
                        .init(color: .white.opacity(0.08), location: 0.45),
                        .init(color: .clear, location: 0.55),
                        .init(color: .white.opacity(0.06), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.35), .black.opacity(0.12)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
            )
            .allowsHitTesting(false)
    }
}
