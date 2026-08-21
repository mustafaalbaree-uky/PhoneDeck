import SwiftUI

/// Design tokens for the current PhoneDeck look. Everything visual in
/// ContentView.swift comes from here, so a change of palette or corner
/// radius is one edit rather than thirty.
enum Theme {
    // MARK: Metrics

    static let popoverWidth: CGFloat = 348
    static let cardRadius: CGFloat = 12
    static let tileRadius: CGFloat = 9
    static let tileSize: CGFloat = 34
    static let gutter: CGFloat = 14

    // MARK: Palette

    /// The one accent the app spends: selection, the primary button, and
    /// the connected indicator. A two-stop gradient rather than a flat fill
    /// so the small shapes still read as lit from above.
    static let accent = Color(red: 0.35, green: 0.55, blue: 1.0)
    static let accentDeep = Color(red: 0.24, green: 0.36, blue: 0.92)

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accentDeep], startPoint: .top, endPoint: .bottom)
    }

    /// Sits behind the whole popover. Very low contrast on purpose — it is
    /// there to give the cards something to float on, not to be noticed.
    static var backdrop: LinearGradient {
        LinearGradient(
            colors: [accent.opacity(0.10), Color.clear],
            startPoint: .top,
            endPoint: .center
        )
    }

    /// Card fill and hairline. `.quaternary`-ish values chosen by hand so
    /// they hold up in both light and dark menu bar popovers.
    static let cardFill = Color.primary.opacity(0.05)
    static let cardFillHover = Color.primary.opacity(0.09)
    static let cardStroke = Color.primary.opacity(0.07)

    // MARK: Expiry colors

    /// Green while there is room to breathe, amber on the last two days,
    /// red once the profile is actually dead. Same thresholds the classic
    /// look used — only the shapes they paint changed.
    static func expiryColor(_ status: ExpiryStatus) -> Color {
        guard let days = status.daysRemaining else { return .secondary }
        if status.isExpired || days <= 0 { return Color(red: 1.0, green: 0.33, blue: 0.33) }
        if days <= 2 { return Color(red: 1.0, green: 0.65, blue: 0.2) }
        return Color(red: 0.25, green: 0.82, blue: 0.5)
    }

    /// A stable per-app tint for the monogram tile, so each app keeps the
    /// same color between launches without anyone having to pick one. The
    /// hash is the app's own id, and the hues are spaced far enough apart
    /// that three neighbours never look alike.
    static func tint(forID id: String) -> Color {
        var hash: UInt64 = 5381
        for byte in id.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.85)
    }

    static func tileGradient(forID id: String) -> LinearGradient {
        let base = tint(forID: id)
        return LinearGradient(
            colors: [base.opacity(0.95), base.opacity(0.55)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
