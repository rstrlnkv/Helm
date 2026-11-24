import AppKit

/// The rendered view tree, walked by one shared walk rather than a nested
/// `func walk` in every UI check.
///
/// Two readings are built on the one walk, `everyView`: by AppKit **type**, and by the
/// **name** of a class the SDK does not export — `_FocusRingView` and `_NSGraphicsView`
/// can only be matched as strings. Coordinate conversion stays at the call site: a
/// frame means nothing without the space it was read in, and which space that is is
/// the caller's question.
public extension NSView {

    /// This view and everything under it, outermost first.
    ///
    /// Includes `self`, so a predicate applies to the host too.
    var everyView: [NSView] {
        [self] + subviews.flatMap(\.everyView)
    }

    /// The name AppKit gave this view's class.
    ///
    /// The views SwiftUI produces on macOS are private classes with
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
    /// `appKitClassName` itself.
    func everyView(named name: String) -> [NSView] {
        everyView.filter { $0.appKitClassName == name }
    }
}
