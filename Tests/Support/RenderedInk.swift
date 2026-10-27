import AppKit
import SwiftUI
import HelmUI

/// A view mounted the way AppKit needs it before it will draw anything, in a
/// named appearance.
///
/// **A window, not a bare view**: a `List` is an AppKit table and draws nothing
/// without one, and `NSHostingView` will not lay out a `Form`'s chrome outside
/// one either. **And `NSHostingView`, never `ImageRenderer`**, which hands back a
/// blank image for the same content.
///
/// The appearance is a required argument. There is no default, because the
/// default was the bug: the pixel readings this file used to carry inherited
/// `NSApp.effectiveAppearance`, and `NSApp` in a test process is whatever the
/// person's Mac is set to that hour.
@MainActor
public final class MountedRender {

    public let host: NSHostingView<AnyView>
    public let appearance: NSAppearance.Name
    /// **The window a page-layer caller may put its own bar on.**
    /// The bar is `HelmApp`'s (`SettingsToolbar`), which this target may not depend on
    /// (`HelmTestSupport` reaches only `HelmRuntime` and `HelmUI` —
    /// `Package.swift`'s own "support may reach the shared plumbing, nothing
    /// may reach support") — so a page test that needs a live bar builds one
    /// itself, in `HelmAppTests` (`LivePageInTheToolbarFixture`), on this window,
    /// once `channel` below has given the page somewhere to declare into.
    public private(set) var window: NSWindow?

    public init<V: View>(_ view: V, width: CGFloat, height: CGFloat,
                         appearance: NSAppearance.Name, channel: HelmWindowToolbarChannel? = nil) {
        self.appearance = appearance
        let named = NSAppearance(named: appearance)
        // The window below is never ordered in, and a page that idles off
        // screen (`helmIdlesOffScreen`) would hand every reading an empty pane.
        var rootView = AnyView(VStack(spacing: 0) { view }.frame(width: width)
            .helmMeasuringBench())
        // `nil` is the ordinary case: most callers read `host` directly and
        // never look at a bar at all. Only a caller that also puts a bar
        // on `window` needs a page's
        // `.helmWindowToolbar(_:token:)` call to reach anywhere
        // (`HelmWindowToolbar.swift`'s own doc: nil channel, no declaration).
        if let channel {
            rootView = AnyView(rootView.environment(\.helmWindowToolbarChannel, channel))
        }
        host = NSHostingView(rootView: rootView)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = named
        window.contentView = host
        host.appearance = named
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        window.layoutIfNeeded()
        self.window = window
    }

    /// **The search field is in the window and never in `host`.**
    ///
    /// A page asks for one through `helmWindowToolbar`, and the bar —
    /// reached through the `channel` this mount was built with — is what
    /// builds the `NSSearchField` and puts it in the window, as a view next to
    /// `host` and not inside it, which is a different tree from the one every
    /// other reading here walks: `host.everyView(ofType: NSSearchField.self)`
    /// finds **0** whether or not the bar carries one. That is the whole hazard
    /// for a test of this kind, and it is silent — a walk of `host` finds
    /// nothing, types nothing, and reads a page nobody touched.
    ///
    /// The walk starts at the window's frame view and skips what is under
    /// `host`, so it finds the bar's field and no field a page drew itself.
    ///
    /// Nil is a real answer and not only a harness failure: a mount built with
    /// no `channel` at all publishes nothing to any bar by construction
    /// (`HelmWindowToolbarChannel`'s own doc — nil channel, no declaration); a
    /// mount built with a live `channel` and a bar in its window
    /// (`LivePageInTheToolbarFixture`, `Tests/HelmAppTests`) is the one where «no
    /// field» means the page genuinely declared none. Every caller that means
    /// «a field must be here» says so itself, loudly.
    ///
    /// **A field that is there may be hidden**: the bar keeps the field in its
    /// tree for as long as the page declares a search, and a folded search
    /// only hides it, so a hidden field is returned too.
    public var searchField: NSSearchField? {
        guard let root = window?.contentView?.superview else { return nil }
        return root.everyView(ofType: NSSearchField.self).first { !$0.isDescendant(of: host) }
    }

    /// The field of the search item on the window's own `NSToolbar` — the first `NSSearchToolbarItem` among
    /// its items.
    ///
    /// Nil when the window has no toolbar, or its toolbar lists no search item; a caller that means «a field
    /// must be here» says so itself and tells the two apart by reading `window?.toolbar` first.
    public var toolbarSearchField: NSSearchField? {
        (window?.toolbar?.items ?? []).compactMap { $0 as? NSSearchToolbarItem }.first?.searchField
    }

    /// Type `text` into the bar's search field the way AppKit delivers a
    /// keystroke — the value on the control, then the notification the field's
    /// delegate (`SettingsToolbar`) listens for. Assigning `stringValue` alone moves the
    /// control and not the binding `HelmToolbarSearch.text` carries.
    ///
    /// Returns false when there is no field to type into, so a caller can fail
    /// in its own words. Only `host` is settled afterwards: a caller that reads
    /// the bar's frames next lays the bar out itself.
    @discardableResult
    public func type(_ text: String, turns: Int = 5) -> Bool {
        guard let field = searchField else { return false }
        field.stringValue = text
        NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: field)
        settle(turns)
        return true
    }

    /// Press Return in the bar's search field, which is what
    /// `HelmToolbarSearch.onSubmit` answers to — `SettingsToolbar` wires a real
    /// `target`/`action` to the field it builds and turns
    /// `sendsActionOnEndEditing` off, so no end of editing reaches the action;
    /// Return and the clear button do, and `searchSubmitted(_:)` calls `onSubmit` only when
    /// the field is not empty. A `keyDown` carrying Return on the field editor is what delivers
    /// that Return, the same event AppKit itself would post from a keystroke.
    @discardableResult
    public func pressReturn(turns: Int = 5) -> Bool {
        guard let field = searchField, let window,
              window.makeFirstResponder(field),
              let editor = field.currentEditor() as? NSTextView,
              let ret = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                         timestamp: 0, windowNumber: window.windowNumber,
                                         context: nil, characters: "\r",
                                         charactersIgnoringModifiers: "\r",
                                         isARepeat: false, keyCode: 36)
        else { return false }
        editor.keyDown(with: ret)
        settle(turns)
        return true
    }

    /// Turns of the run loop. Both notices arrive by *growing*, over 300 ms and
    /// two round trips through `onGeometryChange`, so a reading taken on the
    /// first turn is of a frame nobody sees.
    public func settle(_ turns: Int = 40) {
        for _ in 0..<turns {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    /// Let go of the window. Called from a test's own teardown: a window left
    /// holding a hosting view holds the view model behind it too.
    public func drop() {
        window?.contentView = nil
        window = nil
    }
}
