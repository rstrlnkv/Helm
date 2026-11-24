import XCTest
@testable import Module_Layout_Engine
import Carbon.HIToolbox

/// ⌥Delete takes out the word before the caret. The module has to know that.
///
/// A modified caret key (⌘←, ⌥←, ⌘↑, ⌥Delete) is navigation, not a chord
/// (`TapEvent`). As a chord it would spend `UndoRecord.soften()`'s forgiveness
/// and store the word it ended.
///
/// What a person does: types `ghbdtn `, watches it become `привет `, presses
/// ⌥Delete to take that word back out, and taps the bound key. A live undo
/// would send seven backspaces and `ghbdtn ` into text the module never saw.
///
/// The cost is named where it is paid: somebody who records ⌘← as their fix
/// hotkey loses the forgiveness. That is the safe direction.
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
    /// an ordinary chord is still a chord **and carries its keycode**.
    ///
    /// This layer does not decide whether a chord may be forgiven — it cannot,
    /// because that is a comparison against the shortcut the person recorded,
    /// which lives in the engine's settings. It hands the code on, so the
    /// comparison is possible at all and ⌘V and ⌘Space are not the same event.
    func testAnOrdinaryChordIsStillAChordAndKeepsItsKeycode() {
        for key in [kVK_ANSI_A, kVK_ANSI_V, kVK_ANSI_Z, kVK_Space, kVK_ANSI_S] {
            XCTAssertEqual(TapEvent.classify(keycode: key, modified: true),
                           .chord(UInt16(key)),
                           "keycode \(key) with a modifier is not proof the caret moved — but "
                           + "which key it was decides whether the engine may forgive it")
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
