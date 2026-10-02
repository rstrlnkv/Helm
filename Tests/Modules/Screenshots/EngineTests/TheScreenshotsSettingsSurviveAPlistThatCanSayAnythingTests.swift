import Foundation
import HelmRuntime
import XCTest
@testable import Module_Screenshots_Engine

/// The property list is a file any process running as the person can write. A
/// stored value that is not one of the cases reads as the default; it is never
/// a crash and never "off".
final class TheScreenshotsSettingsSurviveAPlistThatCanSayAnythingTests: XCTestCase {

    private func store(_ values: [String: Any] = [:]) -> NamespacedStore {
        let backing = InMemoryKeyValueStore()
        for (key, value) in values { backing.set(value, forKey: "module.screenshots.\(key)") }
        return NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: backing)
    }

    func testAnEmptyStoreIsTheDefaults() {
        let read = ScreenshotsSettings.read(store())
        XCTAssertEqual(read, .defaults)
        XCTAssertEqual(read.saveTarget, .macOS)
        XCTAssertEqual(read.format, .png)
        XCTAssertTrue(read.thumbnail)
        XCTAssertTrue(read.shutterSound)
        XCTAssertFalse(read.showCursor)
        XCTAssertEqual(read.timer, .none)
        XCTAssertFalse(read.rememberSelection)
        XCTAssertNil(read.otherFolder)
    }

    func testEveryCaseReadsBack() {
        for target in SaveTarget.allCases {
            XCTAssertEqual(ScreenshotsSettings.read(store([ScreenshotsSettings.Key.saveTarget: target.rawValue])).saveTarget, target)
        }
        for format in ShotFormat.allCases {
            XCTAssertEqual(ScreenshotsSettings.read(store([ScreenshotsSettings.Key.format: format.rawValue])).format, format)
        }
        for timer in CaptureTimer.allCases {
            XCTAssertEqual(ScreenshotsSettings.read(store([ScreenshotsSettings.Key.timer: timer.rawValue])).timer, timer)
        }
        for mode in PanelMode.allCases {
            XCTAssertEqual(ScreenshotsSettings.read(store([ScreenshotsSettings.Key.panelMode: mode.rawValue])).panelMode, mode)
        }
        XCTAssertFalse(ScreenshotsSettings.read(store([ScreenshotsSettings.Key.thumbnail: false])).thumbnail)
        XCTAssertFalse(ScreenshotsSettings.read(store([ScreenshotsSettings.Key.shutterSound: false])).shutterSound)
        XCTAssertTrue(ScreenshotsSettings.read(store([ScreenshotsSettings.Key.showCursor: true])).showCursor)
        XCTAssertTrue(ScreenshotsSettings.read(store([ScreenshotsSettings.Key.rememberSelection: true])).rememberSelection)
        XCTAssertEqual(ScreenshotsSettings.read(store([ScreenshotsSettings.Key.otherFolder: "/tmp/x"])).otherFolder, "/tmp/x")
    }

    func testGarbageReadsAsTheDefaultsAndNeverAsOff() {
        let garbage: [Any] = [Data([1]), ["file"], "FILE", "", 1e300, Int.max, -1, Double.nan, 2]
        for value in garbage {
            let read = ScreenshotsSettings.read(store([
                ScreenshotsSettings.Key.saveTarget: value, ScreenshotsSettings.Key.format: value,
                ScreenshotsSettings.Key.thumbnail: value, ScreenshotsSettings.Key.shutterSound: value,
                ScreenshotsSettings.Key.showCursor: value, ScreenshotsSettings.Key.timer: value,
                ScreenshotsSettings.Key.rememberSelection: value, ScreenshotsSettings.Key.panelMode: value,
                ScreenshotsSettings.Key.otherFolder: value is String && value as! String != "" ? "" : value]))
            XCTAssertEqual(read.saveTarget, .macOS, "\(value)")
            XCTAssertEqual(read.format, .png, "\(value)")
            XCTAssertTrue(read.thumbnail, "a thumbnail setting of \(value) was read as off")
            XCTAssertTrue(read.shutterSound, "a shutter setting of \(value) was read as off")
            XCTAssertFalse(read.showCursor, "\(value)")
            XCTAssertEqual(read.timer, .none, "a timer of \(value) was read as a countdown")
            XCTAssertFalse(read.rememberSelection, "\(value)")
            XCTAssertEqual(read.panelMode, .area, "\(value)")
            XCTAssertNil(read.otherFolder, "a folder of \(value) was read as a path")
        }
    }

    func testATimerThatIsNotAChoiceIsNoCountdown() {
        for seconds in [1, 7, 60, 3600, Int.max] {
            XCTAssertEqual(ScreenshotsSettings.read(store([ScreenshotsSettings.Key.timer: seconds])).timer, .none, "\(seconds)")
        }
    }

    func testAFolderLongerThanAnyPathIsNone() {
        let long = "/" + String(repeating: "a", count: ScreenshotsSettings.longestFolder)
        XCTAssertNil(ScreenshotsSettings.read(store([ScreenshotsSettings.Key.otherFolder: long])).otherFolder)
    }

    func testOnlyTheClipboardMakesNoFile() {
        for target in SaveTarget.allCases {
            XCTAssertEqual(target.savesAFile, target != .clipboard, "\(target)")
        }
    }

    func testTheFormatsNameTheirFiles() {
        XCTAssertEqual(ShotFormat.png.pathExtension, "png")
        XCTAssertEqual(ShotFormat.jpeg.pathExtension, "jpg")
    }
}
