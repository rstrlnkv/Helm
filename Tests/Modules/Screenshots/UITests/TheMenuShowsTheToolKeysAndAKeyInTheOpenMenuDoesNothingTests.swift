import AppKit
import Carbon.HIToolbox
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The ⋯ menu shows each tool's key at its right, a key pressed while the menu is open does nothing, and the editor's keys
/// with the menu closed are what they were; the palette's black swatch is white on dark glass.**
///
/// The label is `NSMenuItem.keyEquivalent` with an empty modifier mask, from `EditorMenu.keyEquivalent(of:)`, which reads
/// `EditorKeys.toolKeys`, the table `EditorKeys.action` matches. The open menu is the part that is only half provable in
/// the process: the `OverlayPanel` doc comment in `CaptureOverlay.swift` records that a `keyEquivalent` "a" fired in an open
/// menu in the US layout. So the guard is `Filler.choose`, which drops an action that `EditorMenu.isSentByAKey` says a key
/// event sent, and it is asked here with a key event as the current event.
@MainActor
final class TheMenuShowsTheToolKeysAndAKeyInTheOpenMenuDoesNothingTests: XCTestCase {

    private func menu(tool: AnnotationTool? = .arrow) -> (NSMenu, EditorBarModel, () -> [EditorAction]) {
        let model = EditorBarModel()
        model.show(tool: tool, style: AnnotationStyle.standard, canUndo: false, canRedo: false)
        var sent: [EditorAction] = []
        model.perform = { sent.append($0) }
        let menu = EditorMenu.make(for: model)
        menu.delegate?.menuNeedsUpdate?(menu)
        return (menu, model, { sent })
    }

    private func flat(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { [$0] + ($0.submenu.map(flat) ?? []) }
    }

    private func keyEvent(code: Int, characters: String) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                         windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters,
                         isARepeat: false, keyCode: UInt16(code))!
    }

    /// Every tool item shows the letter `EditorKeys` matches for that tool, no modifier; items that are not a tool show none.
    func testEachToolItemShowsItsKeyAndNoOtherItemDoes() {
        let (menu, _, _) = menu()
        var shown: [AnnotationTool: String] = [:]
        for item in flat(menu) {
            guard let action = item.representedObject as? EditorAction else { continue }
            if case .tool(let tool) = action {
                XCTAssertEqual(item.keyEquivalentModifierMask, [], "\(item.title)")
                shown[tool] = item.keyEquivalent
            } else {
                XCTAssertEqual(item.keyEquivalent, "", "\(item.title) is not a tool and shows a key")
            }
        }
        XCTAssertEqual(Set(shown.keys), [.arrow, .rectangle, .ellipse, .line, .text, .blur], "the menu's tools")
        for (tool, label) in shown {
            // The letter the label says, asked of the key that EditorKeys matches: the table and the matcher are one.
            let key = EditorKeys.toolKeys.first { $0.tool == tool }
            XCTAssertEqual(label, key?.letter.lowercased(), "\(tool)")
            XCTAssertEqual(EditorKeys.action(keyCode: UInt16(key?.code ?? -1), flags: []), .tool(tool), "\(tool): the label and the key part")
        }
    }

    /// Every key of the table still does what it did with the menu closed, and no other plain key becomes a tool.
    func testTheEditorsKeysAreUnchangedWithTheMenuClosed() {
        let expected: [Int: AnnotationTool] = [kVK_ANSI_A: .arrow, kVK_ANSI_R: .rectangle, kVK_ANSI_O: .ellipse, kVK_ANSI_L: .line,
                                               kVK_ANSI_N: .pen, kVK_ANSI_P: .pencil, kVK_ANSI_H: .highlighter,
                                               kVK_ANSI_B: .blur, kVK_ANSI_T: .text]
        for code in 0..<128 {
            let got = EditorKeys.action(keyCode: UInt16(code), flags: [])
            if let tool = expected[code] { XCTAssertEqual(got, .tool(tool), "code \(code)") }
            else if case .tool = got { XCTFail("code \(code) became a tool key") }
        }
        XCTAssertEqual(Set(EditorKeys.toolKeys.map(\.code)), Set(expected.keys), "the table holds the nine keys and no more")
        // E is the eraser, the one plain key that is a mode and no tool; it is in no row of the table and no item of the menu.
        XCTAssertEqual(EditorKeys.action(keyCode: UInt16(kVK_ANSI_E), flags: []), .erase)
        XCTAssertNil(EditorKeys.action(keyCode: UInt16(kVK_ANSI_E), flags: .command), "⌘E erased")
        XCTAssertFalse(EditorKeys.toolKeys.contains { $0.code == kVK_ANSI_E }, "the eraser's key is in the tools' table")
        for code in 0..<128 where code != kVK_ANSI_E {
            XCTAssertNotEqual(EditorKeys.action(keyCode: UInt16(code), flags: []), .erase, "code \(code) became the eraser's key")
        }
        // U is the ruler's switch, on the same terms: no tool, no row of the table, no item of the menu, nothing with a modifier.
        XCTAssertEqual(EditorKeys.action(keyCode: UInt16(kVK_ANSI_U), flags: []), .toggleRuler)
        XCTAssertNil(EditorKeys.action(keyCode: UInt16(kVK_ANSI_U), flags: .command), "⌘U switched the ruler")
        XCTAssertFalse(EditorKeys.toolKeys.contains { $0.code == kVK_ANSI_U }, "the ruler's key is in the tools' table")
        for code in 0..<128 where code != kVK_ANSI_U {
            XCTAssertNotEqual(EditorKeys.action(keyCode: UInt16(code), flags: []), .toggleRuler, "code \(code) became the ruler's key")
        }
    }

    /// An action sent by a key while a menu is open is dropped; the same action sent by a click goes. With the event the
    /// run loop took from the queue as the current one, the way an item's action reads it.
    func testAKeySentActionIsDroppedAndAClickSentOneIsNot() throws {
        _ = NSApplication.shared
        let (menu, _, sent) = menu(tool: nil)
        let rectangle = try XCTUnwrap(flat(menu).first { $0.title == ScStr.tool(.rectangle) })
        let index = try XCTUnwrap(rectangle.menu?.index(of: rectangle))

        NSApp.postEvent(keyEvent(code: kVK_ANSI_R, characters: "r"), atStart: true)
        let key = NSApp.nextEvent(matching: .keyDown, until: .distantPast, inMode: .default, dequeue: true)
        XCTAssertEqual(NSApp.currentEvent?.type, .keyDown, "control: the key is the current event")
        XCTAssertNotNil(key)
        rectangle.menu?.performActionForItem(at: index)
        XCTAssertEqual(sent(), [], "a key reached the item's action")

        NSApp.postEvent(NSEvent.mouseEvent(with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!, atStart: true)
        _ = NSApp.nextEvent(matching: .leftMouseUp, until: .distantPast, inMode: .default, dequeue: true)
        XCTAssertEqual(NSApp.currentEvent?.type, .leftMouseUp, "control: the click is the current event")
        rectangle.menu?.performActionForItem(at: index)
        XCTAssertEqual(sent(), [.tool(.rectangle)], "a click does not reach the item's action")
    }

    /// Labels are dropped in one place: with it returning "" no item shows a key.
    func testTheLabelsAreOneFunction() throws {
        let source = try RepoSource.text(of: "Sources/Modules/Screenshots/UI/EditorMenu.swift")
        XCTAssertEqual(source.components(separatedBy: "keyEquivalent(of:").count - 1, 1, "the one use of the function")
    }

    // MARK: the swatch

    func testBlackIsDrawnWhiteOnDarkGlassInThePalettesGridOnly() {
        XCTAssertEqual(EditorSwatch.drawn(.black, scheme: .dark, blackTurnsWhiteInDark: true), .white)
        XCTAssertEqual(EditorSwatch.drawn(.black, scheme: .light, blackTurnsWhiteInDark: true), .black)
        XCTAssertEqual(EditorSwatch.drawn(.black, scheme: .dark, blackTurnsWhiteInDark: false), .black, "the colours pop-over keeps its black")
        for color in AnnotationColor.allCases where color != .black {
            XCTAssertEqual(EditorSwatch.drawn(color, scheme: .dark, blackTurnsWhiteInDark: true), color)
        }
    }

    func testTheItemSymbolsAreTemplateImages() throws {
        for symbol in EditorPalette.objects.compactMap(\.symbol) + [EditorPalette.selectSymbol] {
            XCTAssertTrue(try XCTUnwrap(EditorMenu.image(symbol: symbol)).isTemplate, symbol)
        }
    }
}
