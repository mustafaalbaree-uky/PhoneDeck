import SwiftUI

/// Shows its content at full height while it fits on screen, and turns it
/// into a scrolling list capped at `maxHeight` once it does not.
///
/// The popover takes its size from the hosting view's `fittingSize`, which
/// proposes no height at all, so a bare ScrollView would collapse and a
/// bare VStack would run off the bottom of the screen. `HeightCap` proposes
/// `maxHeight` to a `ViewThatFits`, which picks the plain content when it
/// fits and the ScrollView when it does not, and reports whichever height
/// that choice came out at.
struct FitOrScroll<Content: View>: View {
    var maxHeight: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        HeightCap(maxHeight: maxHeight) {
            ViewThatFits(in: .vertical) {
                content()
                ScrollView(.vertical) { content() }
            }
        }
    }
}

private struct HeightCap: Layout {
    var maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let height = min(proposal.height ?? maxHeight, maxHeight)
        return child.sizeThatFits(ProposedViewSize(width: proposal.width, height: height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
    }
}
