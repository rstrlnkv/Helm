import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **One setting decides where a capture goes.** "After a full-screen capture"
/// (file, clipboard, both) and "Save to" (Desktop, Documents, Clipboard, Other)
/// were two settings deciding one thing, and a page that drew both would have
/// let them disagree. The first is gone; this fails while any second key that
/// names a destination is left in the module, and while a capture follows
/// anything but the target.
final class TheSaveTargetIsOneSettingTests: XCTestCase {

    private func store(_ values: [String: Any]) -> NamespacedStore {
        let backing = InMemoryKeyValueStore()
        for (key, value) in values { backing.set(value, forKey: "module.screenshots.\(key)") }
        return NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: backing)
    }

    func testNoSecondSettingNamesWhereACaptureGoes() throws {
        let reads = try SwiftSource.uncommented(under: "Sources/Modules/Screenshots")
        XCTAssertGreaterThan(reads.count, 10, "the scan read almost nothing, so an empty answer means nothing")
        XCTAssertTrue(reads.contains { $0.text.contains("saveTarget") }, "the scan did not read the setting it guards")
        for word in ["afterFullScreen", "ScreenDestination"] {
            XCTAssertEqual(reads.filter { $0.text.contains(word) }.map(\.path), [],
                           "\(word) is a second setting for where a capture goes")
        }
    }

    func testTheKeyTheOldSettingWroteDecidesNothing() {
        let read = ScreenshotsSettings.read(store([ScreenshotsSettings.Key.saveTarget: "desktop",
                                                   "afterFullScreen": "clipboard"]))
        XCTAssertEqual(read.saveTarget, .desktop)
        XCTAssertEqual(ScreenshotsSettings.read(store(["afterFullScreen": "clipboard"])).saveTarget, .macOS,
                       "the old key still steers a capture")
    }

    /// Every target, through the full-screen shortcut and through a hand-off of
    /// an area (`saves: true, copies: true`, which is what the overlay's hand-off
    /// asks): the same answer, because the same setting is the only thing asked.
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
