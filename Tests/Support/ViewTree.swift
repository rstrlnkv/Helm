import AppKit

/// The rendered view tree, walked once instead of eleven times.
///
/// Every UI check in this suite that measures something reaches for the same
/// four lines — a nested `func walk`, a `var found`, a predicate, and
/// `view.subviews.forEach(walk)` — and there were eleven of them across five
/// targets before this existed. That is the shape `scratchDirectory` and
/// `RepoSource` were each in before they moved here.
///
/// Two readings are built on the one walk, `everyView`: by AppKit **type**, and by the
/// **name** of a class the SDK does not export — `_FocusRingView` and `_NSGraphicsView`
/// can only be matched as strings. Coordinate conversion stays at the call site: a
/// frame means nothing without the space it was read in, and which space that is is
/// the caller's question.
public extension NSView {

    /// This view and everything under it, outermost first.
    ///
    /// Includes `self`, which every hand-written walk here did — each began
    /// `walk(host)` with the predicate applied to the host.
    var everyView: [NSView] {
        [self] + subviews.flatMap(\.everyView)
    }

    /// The name AppKit gave this view's class.
    ///
    /// Spelled `"\(type(of: view))"` at seven call sites, and it is not
    /// decoration: the views SwiftUI produces on macOS are private classes with
    /// no symbol to match against, so `_FocusRingView`, `_NSGraphicsView` and
    /// `_NSCoreHostingView<AppKit…>` are matched as text or not at all.
    var appKitClassName: String { "\(type(of: self))" }

    /// Everything under here of one AppKit type, outermost first.
    func everyView<T: NSView>(ofType type: T.Type) -> [T] {
        everyView.compactMap { $0 as? T }
    }

    /// Everything under here whose class is named `name`, outermost first.
    ///
    /// Exact rather than a prefix, because the two spellings mean different
    /// things: `_FocusRingView` is one class, and `_NSCoreHostingView<AppKit…>`
    /// is a generic whose full name a caller matches with `hasPrefix` on
    /// `appKitClassName` itself. A helper that chose one for everybody would have
    /// made the other read wrong at a glance.
    func everyView(named name: String) -> [NSView] {
        everyView.filter { $0.appKitClassName == name }
    }
}
