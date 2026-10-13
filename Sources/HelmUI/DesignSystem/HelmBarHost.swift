import SwiftUI

extension NSHostingView {
    /// A hosting view for a zone of the page bar: it hands SwiftUI no safe area of its container.
    ///
    /// The settings window's `.pageBar` build has no toolbar, so its titlebar lies over the bar and the bar's top safe area is the
    /// titlebar's. A hosting view under it passes that inset on, and SwiftUI centres its content in what is
    /// left, below the middle of the zone's frame. The regions are set here, at construction: on a view that
    /// has already been laid out the ink did not move
    /// (`TheBarsInkSitsInTheMiddleOfTheBarTests` reads it from the window's bitmap).
    @MainActor
    public static func inBar(rootView: Content) -> NSHostingView<Content> {
        let host = NSHostingView(rootView: rootView)
        host.safeAreaRegions = []
        host.sizingOptions = [.intrinsicContentSize]
        return host
    }
}
