import SwiftUI

/// The space a row leaves where a checkbox would be.
///
/// Two lists draw tickable rows beside rows that cannot be ticked — Login Items
/// holds what macOS protects, the Uninstaller holds the app bundle itself, which
/// the plan always takes — and both filled the gap by hand. The Uninstaller wrote
/// 16 twice and Login Items wrote 14, so its protected rows stepped 2 pt left of
/// every markable one: the name began at x = 56.0 with a checkbox and 54.0
/// without.
///
/// A number typed in three places with one of them wrong is the argument for one
/// place, and a number typed at all is the argument for measuring it:
/// `ARowWithNothingToTickKeepsTheColumnTests` hosts a real `.checkbox` toggle and
/// pins `side` against what AppKit says it wants. AppKit owns that size and can
/// change it in a release; nothing else in the tree would notice.
///
/// A clear rectangle rather than a hidden `Toggle`, which would be the same width
/// by construction: these lists run to hundreds of rows, and a real control per
/// row is a control per row.
public struct HelmCheckboxSlot: View {
    /// What macOS draws a `.checkbox` toggle at, measured rather than chosen.
    ///
    /// Internal, not `public`: no other target reads the number — they draw the
    /// slot — and the one thing that does is the test that measures it, through
    /// `@testable`.
    static let side: CGFloat = 16

    public init() {}

    public var body: some View {
        Color.clear
            .frame(width: Self.side, height: Self.side)
            // It stands in for a control and is not one: a VoiceOver stop here
            // would announce a checkbox that is not there.
            .accessibilityHidden(true)
    }
}
