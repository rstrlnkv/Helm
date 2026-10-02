import CoreGraphics
import Foundation
import HelmRuntime
import XCTest
@testable import Module_Screenshots_Engine

/// **"Remember last selection" off means nothing is remembered.** The record is
/// erased with the switch, through the one function both the bar and any page
/// go through; left behind it would reappear, stale, the day the option is
/// switched on again.
final class SwitchingRememberOffErasesTheSelectionTests: XCTestCase {

    private func store() -> NamespacedStore {
        NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
    }

    private func remember(in store: NamespacedStore) throws {
        let record = try XCTUnwrap(RememberedSelection(display: "AAAA-1111", rect: CGRect(x: 10, y: 20, width: 300, height: 200)))
        record.write(to: store)
        XCTAssertNotNil(RememberedSelection.read(store), "the record was not written, so nothing below proves an erase")
    }

    func testSwitchingItOffErasesTheRecord() throws {
        let kept = store()
        ScreenshotsSettings.setRememberSelection(true, in: kept)
        try remember(in: kept)
        ScreenshotsSettings.setRememberSelection(false, in: kept)
        XCTAssertNil(RememberedSelection.read(kept))
        for key in [RememberedSelection.Key.display, RememberedSelection.Key.x, RememberedSelection.Key.y,
                    RememberedSelection.Key.width, RememberedSelection.Key.height] {
            XCTAssertNil(kept.object(key), "\(key) is still stored")
        }
        XCTAssertFalse(ScreenshotsSettings.read(kept).rememberSelection)
    }

    func testSwitchingItOnKeepsTheRecord() throws {
        let kept = store()
        try remember(in: kept)
        ScreenshotsSettings.setRememberSelection(true, in: kept)
        XCTAssertNotNil(RememberedSelection.read(kept))
        XCTAssertTrue(ScreenshotsSettings.read(kept).rememberSelection)
    }

    private static let keys = [RememberedSelection.Key.display, RememberedSelection.Key.x, RememberedSelection.Key.y,
                               RememberedSelection.Key.width, RememberedSelection.Key.height]

    /// A record some other process half wrote — a number where the display
    /// goes, a string and a Boolean where numbers go, one key missing, a
    /// not-a-number — is no record to `read`, and the switch going off must
    /// still take every one of its keys, not only the ones that parse.
    func testSwitchingItOffErasesARecordWhoseKeysAreGarbage() {
        let kept = store()
        ScreenshotsSettings.setRememberSelection(true, in: kept)
        kept.set(42, for: RememberedSelection.Key.display)
        kept.set("wide", for: RememberedSelection.Key.x)
        kept.set(true, for: RememberedSelection.Key.width)
        kept.set(Double.nan, for: RememberedSelection.Key.height)
        XCTAssertEqual(Self.keys.filter { kept.object($0) != nil }.count, 4, "the garbage was not stored, so nothing below proves an erase")
        XCTAssertNil(RememberedSelection.read(kept))
        ScreenshotsSettings.setRememberSelection(false, in: kept)
        for key in Self.keys { XCTAssertNil(kept.object(key), "\(key) survived the switch going off") }
    }

    /// Off and then on again: the record stays gone — on keeps what there is,
    /// it does not bring back what off took.
    func testSwitchingItOffThenOnLeavesItErased() throws {
        let kept = store()
        ScreenshotsSettings.setRememberSelection(true, in: kept)
        try remember(in: kept)
        ScreenshotsSettings.setRememberSelection(false, in: kept)
        ScreenshotsSettings.setRememberSelection(true, in: kept)
        XCTAssertTrue(ScreenshotsSettings.read(kept).rememberSelection)
        XCTAssertNil(RememberedSelection.read(kept))
        for key in Self.keys { XCTAssertNil(kept.object(key), "\(key) came back with the switch") }
    }
}
