import AppKit
import SwiftUI
import XCTest
@testable import Module_Launchpad_UI

/// Whether a tile's name is cut and how far the hover scroll goes (`LaunchpadLabel.overflow`): pure, from the name, the room and the scale. A short name is whole and does not scroll, a long German one with
/// no break point is cut and the distance reaches its end, a name that breaks needs more than two lines to be cut (one when the cell holds one line), and a room that is not a room scrolls nothing.
final class LaunchpadLabelTests: XCTestCase {
    func testAShortNameDoesNotScroll() {
        XCTAssertEqual(LaunchpadLabel.overflow(name: "Safari", room: 120, scale: 1, oneLine: false), 0)
        XCTAssertEqual(LaunchpadLabel.overflow(name: "Mail", room: 120, scale: 1, oneLine: true), 0)
    }

    func testALongNameWithNoBreakPointScrollsFarEnoughToShowItsEnd() {
        let name = "Festplattendienstprogramm"
        let distance = LaunchpadLabel.overflow(name: name, room: 100, scale: 1, oneLine: false)
        XCTAssertGreaterThan(distance, 0, "subject: it is cut at 100 pt")
        XCTAssertEqual(LaunchpadLabel.overflow(name: name, room: 300, scale: 1, oneLine: false), 0, "and whole at 300")
        XCTAssertGreaterThan(LaunchpadLabel.overflow(name: name, room: 80, scale: 1, oneLine: false), distance, "a narrower room scrolls further")
    }

    func testANameThatBreaksIsCutOnlyPastTwoLinesOrOneWhenTheCellHoldsOne() {
        let name = "Microsoft Remote Desktop Beta"
        XCTAssertEqual(LaunchpadLabel.overflow(name: name, room: 120, scale: 1, oneLine: false), 0, "two lines hold it")
        XCTAssertGreaterThan(LaunchpadLabel.overflow(name: name, room: 120, scale: 1, oneLine: true), 0, "one line does not")
        XCTAssertGreaterThan(LaunchpadLabel.overflow(name: name, room: 50, scale: 1, oneLine: false), 0, "three lines do not fit in two")
    }

    func testARoomThatIsNotARoomScrollsNothing() {
        for room in [CGFloat.nan, .infinity, 0, -10] {
            XCTAssertEqual(LaunchpadLabel.overflow(name: "Festplattendienstprogramm", room: room, scale: 1, oneLine: false), 0, "\(room)")
        }
        XCTAssertEqual(LaunchpadLabel.overflow(name: "", room: 100, scale: 1, oneLine: false), 0)
    }

    // MARK: Built names: soft hyphens and scripts that break anywhere

    private let softHyphened = ["Festplatten\u{AD}dienstprogramm", "System\u{AD}einstellungen", "Compartilhamen\u{AD}to de Tela"]
    private let japanese = ["VoiceOverユーティリティ", "ColorSyncユーティリティ", "フィードバックアシスタント"]

    func testASoftHyphenAndAScriptThatBreaksAnywhereAreBreakPoints() {
        for name in softHyphened + japanese + ["ターミナル", "시스템 설정", "磁盘工具"] { XCTAssertTrue(LaunchpadLabel.canBreak(name), name) }
        for name in ["Festplattendienstprogramm", "Safari", "Terminal"] { XCTAssertFalse(LaunchpadLabel.canBreak(name), name) }
        XCTAssertEqual(LaunchpadLabel.shrink("Festplatten\u{AD}dienstprogramm"), 0.85)
        XCTAssertEqual(LaunchpadLabel.shrink("Festplattendienstprogramm"), LaunchpadMetrics.unbreakableShrink)
    }

    /// At the room 1024 x 768 gives at x1 (97 pt): the soft-hyphened name holds on two lines at 0.85, the same word without its soft hyphen is one line and cut.
    func testTheBuiltNamesHoldOnTwoLinesWhereTheirBareSpellingIsCut() {
        XCTAssertGreaterThan(LaunchpadLabel.overflow(name: "Festplattendienstprogramm", room: 97, scale: 0.71, oneLine: false), 0, "subject: the bare word is cut")
        for name in softHyphened + japanese {
            XCTAssertEqual(LaunchpadLabel.overflow(name: name, room: 97, scale: 0.71, oneLine: false), 0, "\(name): two lines hold it")
        }
        XCTAssertGreaterThan(LaunchpadLabel.overflow(name: "Festplatten\u{AD}dienstprogramm", room: 97, scale: 0.71, oneLine: true), 0, "one line (names off) cuts it")
    }

    /// The tile's `Text` breaks where `overflow` says it may: the soft hyphen and a Japanese name give two lines at a width that holds them, not one cut line.
    @MainActor func testSwiftUIBreaksTheNamesWhereTheLabelSaysItCan() {
        func height(_ name: String) -> CGFloat {
            NSHostingView(rootView: Text(name).font(.system(size: 11 * 0.85)).fixedSize(horizontal: false, vertical: true).frame(width: 97)).fittingSize.height
        }
        let one = height("A")
        for name in ["Festplatten\u{AD}dienstprogramm", "VoiceOverユーティリティ", "フィードバックアシスタント"] {
            XCTAssertEqual(height(name) / one, 2, accuracy: 0.3, "\(name): two lines")
        }
    }
}
