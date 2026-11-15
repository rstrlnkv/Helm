import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **One setting decides where a capture goes.** "After a full-screen capture"
/// (file, clipboard, both) and "Save to" (Desktop, Documents, Clipboard, Other)
/// were two settings deciding one thing, and a page that drew both would have
/// let them disagree. The first is gone; this fails while the old key still steers a capture, and while a capture
/// follows anything but the target.
final class TheSaveTargetIsOneSettingTests: XCTestCase {

    func testTheKeyTheOldSettingWroteDecidesNothing() {
        let read = ScreenshotsSettings.read(screenshotsStore([ScreenshotsSettings.Key.saveTarget: "desktop",
                                                   "afterFullScreen": "clipboard"]))
        XCTAssertEqual(read.saveTarget, .desktop)
        XCTAssertEqual(ScreenshotsSettings.read(screenshotsStore(["afterFullScreen": "clipboard"])).saveTarget, .macOS,
                       "the old key still steers a capture")
    }

    /// The deployed spellings, pinned as literals and never derived: a store from before holds these names.
    func testTheStoredKeysAreTheDeployedSpellings() {
        XCTAssertEqual(ScreenshotsSettings.Key.screenRecordingAsked, "screenRecordingAsked")
        XCTAssertEqual(ScreenshotsSettings.Key.otherFolder, "otherFolder")
        XCTAssertEqual(ScreenshotsSettings.Key.saveTarget, "saveTarget")
    }

    /// The order the two keys are written in: the folder first, because the page's mirror returns early on a target already
    /// `other`. An in-memory store shows only the final pair, so the writes are recorded.
    func testTheFolderIsWrittenBeforeTheTarget() {
        final class Recording: KeyValueStore {
            var keys: [String] = []
            func object(forKey: String) -> Any? { nil }
            func set(_ value: Any?, forKey key: String) { keys.append(key) }
        }
        let backing = Recording()
        ScreenshotsSettings.chooseOtherFolder("/tmp/Chosen",
                                              in: NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: backing))
        XCTAssertEqual(backing.keys, ["module.screenshots.otherFolder", "module.screenshots.saveTarget"])
    }

    /// The folder and the target land together, and the target reads back as `other` with that folder.
    func testChoosingAFolderStoresItAndTheOtherTarget() {
        let chosen = screenshotsStore([ScreenshotsSettings.Key.saveTarget: "desktop"])
        ScreenshotsSettings.chooseOtherFolder("/tmp/Chosen", in: chosen)
        let read = ScreenshotsSettings.read(chosen)
        XCTAssertEqual(read.saveTarget, .other)
        XCTAssertEqual(read.otherFolder, "/tmp/Chosen")
    }

    /// The first request is made once and recorded under the deployed key; a store that holds the key asks nothing.
    func testTheAccessRequestIsMadeOnceAndRecordedUnderTheDeployedKey() {
        final class Count: @unchecked Sendable { var n = 0 }
        let count = Count()
        let fresh = screenshotsStore([:])
        let capture = SCKCapture(store: fresh, request: { count.n += 1 })
        capture.requestAccess()
        capture.requestAccess()
        XCTAssertEqual(count.n, 1)
        XCTAssertEqual(fresh.bool("screenRecordingAsked", default: false), true)

        let asked = SCKCapture(store: screenshotsStore(["screenRecordingAsked": true]), request: { count.n += 1 })
        asked.requestAccess()
        XCTAssertEqual(count.n, 1, "a store from before that holds the key was asked again")
    }

    /// The engine's own preferences reach the session it hands over: the macOS save folder is read through them.
    func testTheSessionReadsTheEnginesPreferences() async throws {
        let home = scratchDirectory("shots-engine-preferences")
        let folder = home.appendingPathComponent("MacOSFolder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let preferences = FakePreferences()
        preferences.savedLocation = folder.path
        let engine = ScreenshotsEngine(preferences: preferences)
        let session = engine.session(store: screenshotsStore([ScreenshotsSettings.Key.saveTarget: "macOS"]), naming: { .english })
        let delivery = await session.deliver(makeImage(width: 8, height: 8), saves: true, copies: false)
        XCTAssertEqual(delivery.refusals, [])
        XCTAssertEqual(delivery.files.map { $0.deletingLastPathComponent().path }, [folder.path])
    }

    /// Every target, through the full-screen shortcut and through a hand-off of
    /// an area (`saves: true, copies: true`, which is what the overlay's hand-off
    /// asks): the target alone decides the file. The clipboard does not follow it alike: the hand-off copies under
    /// every target, the full-screen shortcut only under the clipboard target.
    func testEachTargetMakesItsOwnFileOrItsOwnCopyAndNothingElse() async throws {
        let home = scratchDirectory("shots-one-setting")
        let chosen = home.appendingPathComponent("Chosen", isDirectory: true)
        let documents = home.appendingPathComponent("Documents", isDirectory: true)
        for folder in [chosen, documents] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let expected: [(SaveTarget, URL?)] = [
            (.macOS, home.appendingPathComponent("Desktop")), (.desktop, home.appendingPathComponent("Desktop")),
            (.documents, documents), (.other, chosen), (.clipboard, nil)]
        XCTAssertEqual(Set(expected.map(\.0)), Set(SaveTarget.allCases), "a target was left out of the table")

        for (target, folder) in expected {
            for viaArea in [false, true] {
                let rig = Rig(home: home, settings: ScreenshotsSettings(saveTarget: target, otherFolder: chosen.path))
                rig.capture.outcome = .frozen(Freeze(displays: [Rig.display(1)], windows: []))
                let delivery: Delivery
                if viaArea {
                    delivery = await rig.session.deliver(makeImage(width: 8, height: 8), saves: true, copies: true)
                } else {
                    delivery = await rig.session.captureScreens()
                }
                let what = "\(target) \(viaArea ? "area" : "screen")"
                XCTAssertEqual(delivery.refusals, [], what)
                if let folder {
                    XCTAssertEqual(delivery.files.map { $0.deletingLastPathComponent().path }, [folder.path], what)
                    XCTAssertEqual(rig.pasteboard.copies.count, viaArea ? 1 : 0, what)
                } else {
                    XCTAssertEqual(delivery.files, [], "\(what): the clipboard target made a file")
                    XCTAssertEqual(rig.pasteboard.copies.count, 1, "\(what): the clipboard target did not copy")
                }
            }
        }
    }
}
