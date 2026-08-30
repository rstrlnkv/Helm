import AppKit
import HelmRuntime
import HelmUI
import SwiftUI

/// The two lists that grow, in a window of their own.
///
/// **They were sections on the settings page, and the page is where somebody
/// changes their mind about how the module behaves.** A list of words and a
/// list of apps are not that: they are visited rarely, edited deliberately, and
/// they grow without limit — so between them they pushed the three switches
/// somebody actually reaches for below the fold on any window shorter than the
/// screen.
///
/// **The window is `HostWindow`'s, which moved to `HelmUI` for this.** The other
/// route was a new `ModuleDescriptor` member, and one module of ten
/// implementing a contract member is what `headerAccessory` was — deleted the
/// same morning this was built, for that reason.
///
/// The content is a plain view (`LayoutLists`) rather than something the window
/// builds, so it can be measured and photographed on the bench. This module
/// learned that from its own introduction, which was a `.sheet` — «five extra
/// `NSWindow`s per offscreen render, and nothing of the first screen a new user
/// meets inside the page's own layers».
@MainActor final class LayoutListsWindow: HostWindow {

    func show(_ lists: LayoutLists) {
        present(lists.frame(minWidth: 520, idealWidth: 560,
                            minHeight: 420, idealHeight: 560),
                title: LyStr.listsWindowTitle,
                styleMask: [.titled, .closable, .resizable])
    }
}
