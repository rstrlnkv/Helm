import XCTest
@testable import Module_Layout_Engine
import Carbon.HIToolbox

/// ⌥Delete takes out the word before the caret. The module has to know that.
///
/// **It did not, and the cost was somebody else's text.** `CGKeyTap.deliver`
/// asked «is a modifier held» before it looked at which key, so ⌘←, ⌥←, ⌘↑ and
/// ⌥Delete all arrived as `.chord`. A chord is the one boundary that is *not*
/// proof the caret moved — the head-inserted tap sees the recorded hotkey's own
/// keys before Carbon dispatches the action, so `UndoRecord.soften()` forgives
/// one and `movedTheCaret` is false, which means the word it ended is **stored**.
///
/// What a person does: types `ghbdtn `, watches it become `привет `, presses
/// ⌥Delete to take that word back out, and taps the bound key. What they got:
/// the undo record was still live, so seven backspaces and `ghbdtn ` went into
/// whatever the caret was in front of — text the module had never looked at.
///
/// The cost of the repair is named where it is paid: somebody who records ⌘←
/// as their fix hotkey loses the forgiveness and their gesture stops firing.
/// That is the safe direction. The other way round destroys text for everyone
/// who deletes a word with ⌥Delete, which is most people.
final class AModifiedDeleteIsNotAGestureTests: XCTestCase {

    func testAModifiedDeleteIsACaretMove() {
        XCTAssertEqual(TapEvent.classify(keycode: kVK_Delete, modified: true), .navigation,
                       "⌥Delete removes the word before the caret; reported as a chord it "
                       + "leaves the undo live over text that is gone")
    }

    func testEveryModifiedCaretKeyIsACaretMove() {
        for key in [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
                    kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown] {
            XCTAssertEqual(TapEvent.classify(keycode: key, modified: true), .navigation,
                           "keycode \(key) held with a modifier still moves the caret")
        }
    }

    /// The control that stops «report everything as navigation» from passing:
    /// an ordinary chord is still a chord, because it may be the recorded
    /// hotkey arriving before Carbon dispatches it.
    func testAnOrdinaryChordIsStillAChord() {
        for key in [kVK_ANSI_A, kVK_ANSI_V, kVK_ANSI_Z, kVK_Space, kVK_ANSI_S] {
            XCTAssertEqual(TapEvent.classify(keycode: key, modified: true), .chord,
                           "keycode \(key) with a modifier is not proof the caret moved, and "
                           + "treating it as one has the gesture destroy its own precondition")
        }
    }

    /// And nothing about the unmodified path moved: Delete on its own is still
    /// a backspace, not a caret move, because the buffer follows it exactly.
    func testTheUnmodifiedKeysAreUnchanged() {
        XCTAssertEqual(TapEvent.classify(keycode: kVK_Delete, modified: false), .backspace)
        XCTAssertEqual(TapEvent.classify(keycode: kVK_Space, modified: false), .space)
        XCTAssertEqual(TapEvent.classify(keycode: kVK_Return, modified: false), .newline)
        XCTAssertEqual(TapEvent.classify(keycode: kVK_LeftArrow, modified: false), .navigation)
        XCTAssertEqual(TapEvent.classify(keycode: kVK_Escape, modified: false), .navigation)
        XCTAssertNil(TapEvent.classify(keycode: kVK_ANSI_A, modified: false),
                     "a plain letter key needs the unicode string, and nil is how this says so")
    }
}
