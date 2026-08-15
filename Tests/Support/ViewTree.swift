import AppKit

/// The rendered view tree, walked once instead of eleven times.
///
/// Every UI check in this suite that measures something reaches for the same
/// four lines — a nested `func walk`, a `var found`, a predicate, and
/// `view.subviews.forEach(walk)` — and there were eleven of them across five
/// targets before this existed. That is the shape `scratchDirectory` and
/// `RepoSource` were each in before they moved here.
///
/// **It is deliberately not `first(ofType:)`.** Four of the eleven need more than
/// «is there one of these under here», and a helper that offered only the easy
/// question would have made those four unrepresentable — which is the rule about
/// a helper being no simpler than the thing it stands for, applied to plumbing
/// rather than to a fake. What they actually need:
///
/// - the view, by AppKit **type** (`NSProgressIndicator`);
/// - the view, by the **name** of a class the SDK does not export — `_FocusRingView`
///   and `_NSGraphicsView` are how this suite finds a control and a card, and
///   they can only be matched as strings;
/// - the view's **parent**, which the walker must have been holding;
/// - what the view is **inside**, which is state carried down the recursion —
///   VPN's card measurement counts focus rings *outside* a card and would be
///   wrong by every ring on the page without it.
///
/// So the primitive is the sequence with its ancestry, and the two convenient
/// readings are built on it. Coordinate conversion stays at the call site: a
/// frame means nothing without the space it was read in, and which space that is
/// is the caller's question.
public extension NSView {

    /// This view and everything under it, outermost first.
    ///
    /// Includes `self`, which every hand-written walk here did — each began
    /// `walk(host)` with the predicate applied to the host — and a version that
    /// quietly dropped the root would change what nine tests measure.
    var everyView: [NSView] {
        [self] + subviews.flatMap(\.everyView)
    }

    /// The same walk, each view with the chain above it, outermost first and not
    /// including the view itself.
    ///
    /// `ancestry.last` is the parent; `ancestry.contains` answers «what am I
    /// inside», which is the state the two VPN measurements carry down by hand.
    var everyViewWithAncestry: [(view: NSView, ancestry: [NSView])] {
        var out: [(view: NSView, ancestry: [NSView])] = []
        func walk(_ view: NSView, _ ancestry: [NSView]) {
            out.append((view, ancestry))
            for sub in view.subviews { walk(sub, ancestry + [view]) }
        }
        walk(self, [])
        return out
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
