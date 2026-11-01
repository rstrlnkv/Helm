import Foundation

/// The last conversion, and whether it is still safe to take back.
///
/// An undo is a blind edit: it deletes a number of characters at the caret and
/// types others. That is only correct while the caret is still where the
/// conversion left it — same app, nothing typed since. Anywhere else it eats
/// somebody's text.
struct UndoRecord: Equatable, Sendable {
    let event: ConversionEvent
    /// The input sources the conversion switched between. An undo is the person
    /// saying «I meant what I typed» — and what they typed was typed on `from`,
    /// so putting the text back without putting the keyboard back manufactures
    /// the very defect the module exists to fix, one word later. Required, not
    /// defaulted: a record that cannot say where the keyboard was is a record
    /// that cannot be taken back whole.
    let from: String
    let to: String
    private var valid = true
    private var softened = false

    init(event: ConversionEvent, from: String, to: String) {
        self.event = event
        self.from = from
        self.to = to
    }

    func canUndo(in bundleID: String) -> Bool {
        // An empty id is "no idea which app", which is not a match for anything
        // — the same rule `AppScope` applies before typing at all.
        !bundleID.isEmpty && valid && bundleID == event.app
    }

    /// Called for every event but a chord on the recorded hotkey's key.
    mutating func invalidate() { valid = false }

    /// Called for a chord on the recorded hotkey's key, which may have been the
    /// undo shortcut arriving. Any other chord, like any other event, invalidates.
    ///
    /// The tap sees the shortcut's own keys before Carbon delivers the action,
    /// so that chord cannot be treated as "the caret moved" without the
    /// shortcut killing its own record. One is forgiven; a second is not.
    mutating func soften() {
        if softened { valid = false } else { softened = true }
    }

    func reversePlan() -> SwitchPlan? {
        SwitchPlan.make(replacing: event.after, with: event.before,
                        trailing: event.trailing.first)
    }
}
