import XCTest
import Carbon.HIToolbox
@testable import Module_Layout_Engine

/// A person's clipboard is not borrowed when Helm cannot put it back.
///
/// Defect class kept: a clipboard destroyed (data overwritten; REQUIRED in
/// ARCHITECTURE.md § What proves what). `AXSelection`'s paste route and copy route
/// each save a string and restore a string, so a clipboard holding RTF, an image
/// or a promised file comes back as plain text or nothing. `PasteboardSafety`
/// decides; this file guards that each route asks it before the first write or
/// key. `PasteboardSafetyTests` keeps the decision itself.
///
/// The fakes carry their ports' states only: a pasteboard with types, a change
/// count and writes; a focus that answers nothing and refuses a set (the state of
/// an Electron app); keys that record what was pressed. Nothing here touches the
/// real pasteboard, the accessibility tree or posts an event.
final class TheClipboardIsLeftAloneWhenItCannotBeGivenBackTests: XCTestCase {

    private final class FakePasteboard: PasteboardPort, @unchecked Sendable {
        private let lock = NSLock()
        private var held: [String]
        private var text: String?
        private var writeCount = 0
        init(types: [String], string: String? = "mine") { held = types; text = string }
        var types: [String] { lock.withLock { held } }
        var changeCount: Int { lock.withLock { writeCount } }
        var writes: Int { lock.withLock { writeCount } }
        func string() -> String? { lock.withLock { text } }
        func clear() { lock.withLock { writeCount += 1; held = []; text = nil } }
        func setString(_ value: String) {
            lock.withLock { writeCount += 1; held = ["public.utf8-plain-text"]; text = value }
        }
    }

    private struct FocusWithNoAnswer: FocusedTextPort {
        func selectedText() -> String? { nil }
        func setSelectedText(_ text: String) -> Bool { false }
    }

    private final class RecordingKeys: CommandKeyPort, @unchecked Sendable {
        private let lock = NSLock()
        private var keys: [UInt16] = []
        var pressed: [UInt16] { lock.withLock { keys } }
        func press(_ key: UInt16) { lock.withLock { keys.append(key) } }
    }

    private func selection(types: [String]) -> (AXSelection, FakePasteboard, RecordingKeys) {
        let pasteboard = FakePasteboard(types: types)
        let keys = RecordingKeys()
        return (AXSelection(pasteboard: pasteboard, focus: FocusWithNoAnswer(), keys: keys),
                pasteboard, keys)
    }

    func testAReplaceLeavesAClipboardHoldingRichTextAlone() {
        let (refusing, pasteboard, keys) = selection(types: ["public.rtf"])
        XCTAssertFalse(refusing.replaceSelection(with: "привет"))
        XCTAssertEqual(pasteboard.writes, 0, "the clipboard was written over")
        XCTAssertEqual(keys.pressed, [], "a paste was sent into a clipboard it would destroy")
        XCTAssertEqual(pasteboard.types, ["public.rtf"])

        // Control: plain text only is borrowed, so the same call pastes.
        let (borrowing, plain, plainKeys) = selection(types: ["public.utf8-plain-text"])
        _ = borrowing.replaceSelection(with: "привет")
        XCTAssertEqual(plainKeys.pressed, [UInt16(kVK_ANSI_V)], "control: no paste was sent")
        XCTAssertGreaterThan(plain.writes, 0, "control: the clipboard was never used")
    }

    func testACopyLeavesAClipboardHoldingRichTextAlone() {
        let (refusing, pasteboard, keys) = selection(types: ["public.rtf"])
        XCTAssertNil(refusing.selectedText())
        XCTAssertEqual(keys.pressed, [], "a copy was sent into a clipboard it would destroy")
        XCTAssertEqual(pasteboard.writes, 0, "the clipboard was written over")

        // Control: plain text only is borrowed, so the same call copies.
        let (borrowing, _, plainKeys) = selection(types: ["public.utf8-plain-text"])
        _ = borrowing.selectedText()
        XCTAssertEqual(plainKeys.pressed, [UInt16(kVK_ANSI_C)], "control: no copy was sent")
    }
}
