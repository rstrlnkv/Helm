import Foundation

/// The last conversion, and whether it is still safe to take back.
///
/// An undo is a blind edit: it deletes a number of characters at the caret and
/// types others. That is only correct while the caret is still where the
/// conversion left it — same app, nothing typed since. Anywhere else it eats
/// somebody's text.
public struct UndoRecord: Equatable, Sendable {
    public let event: ConversionEvent
    private var valid = true
    private var softened = false

    public init(event: ConversionEvent) { self.event = event }

    public func canUndo(in bundleID: String) -> Bool {
        // An empty id is "no idea which app", which is not a match for anything
        // — the same rule `AppScope` applies before typing at all.
        !bundleID.isEmpty && valid && bundleID == event.app
    }

    /// Called when anything happens that certainly moved the caret.
    public mutating func invalidate() { valid = false }

    /// Called for a chord, which may have been the undo shortcut arriving.
    ///
    /// The tap sees the shortcut's own keys before Carbon delivers the action,
    /// so a chord cannot be treated as "the caret moved" without the shortcut
    /// killing its own record. One chord is forgiven; a second is not, because
    /// by then it was somebody navigating rather than asking for an undo.
    public mutating func soften() {
        if softened { valid = false } else { softened = true }
    }

    public func reversePlan() -> SwitchPlan? {
        SwitchPlan.make(replacing: event.after, with: event.before,
                        trailing: event.trailing.first)
    }
}
