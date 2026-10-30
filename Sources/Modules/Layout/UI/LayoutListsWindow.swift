import AppKit
import HelmRuntime
import HelmUI
import SwiftUI

/// The two lists that grow, in a window of their own.
///
/// Visited rarely and edited deliberately, they grow without limit, so they live
/// here rather than on the settings page. The content is a plain view
/// (`LayoutLists`) so it can be measured and photographed on the bench; the window
/// is `HostWindow`'s.
@MainActor final class LayoutListsWindow: HostWindow {

    private static let minWidth: CGFloat = 520
    private static let idealWidth: CGFloat = 560
    private static let minHeight: CGFloat = 420
    private static let idealHeight: CGFloat = 560

    func show(_ lists: LayoutLists) {
        present(lists.frame(minWidth: Self.minWidth, idealWidth: Self.idealWidth,
                            minHeight: Self.minHeight, idealHeight: Self.idealHeight),
                title: LyStr.listsWindowTitle,
                styleMask: [.titled, .closable, .resizable])
    }
}
