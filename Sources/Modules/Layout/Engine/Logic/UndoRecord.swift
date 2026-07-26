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

    public init(event: ConversionEvent) { self.event = event }

    public func canUndo(in bundleID: String) -> Bool { valid && bundleID == event.app }

    /// Called when anything happens that could have moved the caret.
    public mutating func invalidate() { valid = false }

    public func reversePlan() -> SwitchPlan? {
        SwitchPlan.make(replacing: event.after, with: event.before)
    }
}
