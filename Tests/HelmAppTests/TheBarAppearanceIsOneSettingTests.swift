import Foundation
import HelmRuntime
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The bar's look is one stored setting, under a key of its own.**
///
/// Every check goes through a scratch store (`InMemoryKeyValueStore` under the
/// host's own namespace), never `UserDefaults.standard`: the setting is read
/// and written by `AppSettings.barAppearance(in:)` and
/// `AppSettings.setBarAppearance(_:in:)`, the same two the property delegates
/// to. Nothing here builds a window.
///
/// The key is not `appearance`: that one already holds light, dark or the
/// system's choice (`AppAppearance`), and a second meaning under a deployed key
/// would read one setting's value as the other's.
@MainActor
final class TheBarAppearanceIsOneSettingTests: XCTestCase {

    /// The host's namespace over a scratch backing, and the backing itself so
    /// a test can read the raw value the store wrote.
    private func scratch() -> (store: NamespacedStore, backing: InMemoryKeyValueStore) {
        let backing = InMemoryKeyValueStore()
        return (AppSettings.store.over(backing), backing)
    }

    private func rawBarAppearance(_ backing: InMemoryKeyValueStore) -> Any? {
        backing.object(forKey: "module.app.barAppearance")
    }

    func testAnAbsentOrUnknownStoredValueReadsFlat() {
        let (store, backing) = scratch()
        XCTAssertEqual(AppSettings.barAppearance(in: store), .flat, "nothing stored reads flat")

        backing.set("liquidGlass", forKey: "module.app.barAppearance")
        XCTAssertEqual(AppSettings.barAppearance(in: store), .liquidGlass)

        backing.set("glass", forKey: "module.app.barAppearance")
        XCTAssertEqual(AppSettings.barAppearance(in: store), .flat, "an unknown spelling reads flat")

        backing.set("", forKey: "module.app.barAppearance")
        XCTAssertEqual(AppSettings.barAppearance(in: store), .flat, "the empty string reads flat")
    }

    func testTheInitialiserFoldsTheSameWay() {
        XCTAssertEqual(HelmBarAppearance(stored: ""), .flat)
        XCTAssertEqual(HelmBarAppearance(stored: "glass"), .flat)
        XCTAssertEqual(HelmBarAppearance(stored: "liquidGlass"), .liquidGlass)
        XCTAssertEqual(HelmBarAppearance(stored: "flat"), .flat)
    }

    func testAWritePostsTheNotificationOnce() {
        let (store, _) = scratch()
        var posted = 0
        let watch = NotificationCenter.default.addObserver(
            forName: .helmBarAppearanceChanged, object: nil, queue: nil) { _ in posted += 1 }
        defer { NotificationCenter.default.removeObserver(watch) }

        AppSettings.setBarAppearance(.liquidGlass, in: store)
        XCTAssertEqual(posted, 1, "one write, one notification")
        XCTAssertEqual(AppSettings.barAppearance(in: store), .liquidGlass)
    }

    func testTheKeyIsItsOwnAndLightDarkIsLeftAlone() {
        XCTAssertEqual(HelmBarAppearance.storageKey, "barAppearance")
        XCTAssertNotEqual(HelmBarAppearance.storageKey, "appearance")

        let (store, backing) = scratch()
        store.set(AppAppearance.dark.rawValue, for: "appearance")
        AppSettings.setBarAppearance(.liquidGlass, in: store)

        XCTAssertEqual(store.string("appearance", default: ""), AppAppearance.dark.rawValue,
                       "writing the bar's look must leave light/dark where it was")
        XCTAssertEqual(rawBarAppearance(backing) as? String, "liquidGlass")
    }

    /// The default answers an unwritten key and a failed write alike, so a
    /// round-trip through the non-default is the only read that tells them
    /// apart: write `liquidGlass`, then look at the raw string in the store.
    func testTheNonDefaultIsWrittenAndReadBackRaw() {
        let (store, backing) = scratch()
        AppSettings.setBarAppearance(.liquidGlass, in: store)
        let raw = rawBarAppearance(backing) as? String
        XCTAssertEqual(raw, "liquidGlass",
                       "nothing was written under barAppearance: the read-back below is the default answering for the setting")
        XCTAssertEqual(AppSettings.barAppearance(in: store), .liquidGlass)
    }
}
