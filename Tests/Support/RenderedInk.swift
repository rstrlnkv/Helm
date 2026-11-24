import AppKit
import SwiftUI
@testable import HelmUI

/// A view mounted the way AppKit needs it before it will draw anything, in a
/// named appearance.
///
/// **A window, not a bare view**: a `List` is an AppKit table and draws nothing
/// without one, and `NSHostingView` will not lay out a `Form`'s chrome outside
/// one either. **And `NSHostingView`, never `ImageRenderer`**, which hands back a
/// blank image for the same content.
///
/// The appearance is required, with no default: a default would inherit
/// `NSApp.effectiveAppearance`, which in a test process is whatever the
/// person's Mac is set to that hour.
@MainActor
public final class MountedRender {

    public let host: NSHostingView<AnyView>
    /// **The window `host` is the content of**, never ordered in. The settings window's own header row is
    /// not here: a caller that wants it mounts the page under `helmCardHeader`
    /// (`LivePageUnderTheHeaderFixture`, `Tests/HelmAppTests`).
    public private(set) var window: NSWindow?

    public init<V: View>(_ view: V, width: CGFloat, height: CGFloat,
                         appearance: NSAppearance.Name) {
        let named = NSAppearance(named: appearance)
        // The window below is never ordered in, and a page that idles off
        // screen (`helmIdlesOffScreen`) would hand every reading an empty pane.
        let rootView = AnyView(VStack(spacing: 0) { view }.frame(width: width)
            .helmMeasuringBench())
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

    /// The page's search field, in the header row of the card inside `host`.
    ///
    /// The header row (`helmCardHeader`) draws it as `HelmHeaderSearch` in the
    /// same hosting view as the page, so a walk of `host` finds it only where the
    /// mount was given the row (`LivePageUnderTheHeaderFixture`,
    /// `Tests/HelmAppTests`). Nil is a real answer where a page declared none; a
    /// caller that needs a field says so itself. A hidden field is returned too.
    public var searchField: NSSearchField? {
        host.everyView(ofType: NSSearchField.self).first
    }

    /// Type `text` into the header row's search field the way AppKit delivers a
    /// keystroke — the value on the control, then the notification the field's
    /// delegate (`HelmHeaderSearch.Coordinator`) listens for. Assigning `stringValue` alone moves the
    /// control and not the binding `HelmHeaderQuery.text` carries.
    ///
    /// Returns false when there is no field to type into, so a caller can fail
    /// in its own words. Only `host` is settled afterwards, which holds
    /// the header row when the mount has one.
    @discardableResult
    public func type(_ text: String, turns: Int = 5) -> Bool {
        guard let field = searchField else { return false }
        field.stringValue = text
        NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: field)
        settle(turns)
        return true
    }

    /// Press Return in the header row's search field, which is what
    /// `HelmHeaderQuery.onSubmit` answers to. `HelmHeaderSearch` turns
    /// `sendsActionOnEndEditing` off, so only Return and the clear button reach
    /// the action, and `HelmHeaderSearch.Coordinator.submitted(_:)` calls
    /// `onSubmit` only for a non-empty field. A `keyDown` carrying Return on the
    /// field editor is the event AppKit itself would post.
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
