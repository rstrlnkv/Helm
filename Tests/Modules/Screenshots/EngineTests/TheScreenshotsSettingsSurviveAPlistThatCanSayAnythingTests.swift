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
        XCTAssertEqual(ScreenshotsSettings.read(store()), .defaults)
        XCTAssertEqual(ScreenshotsSettings.defaults.afterFullScreen, .file)
        XCTAssertTrue(ScreenshotsSettings.defaults.thumbnail)
    }

    func testEveryCaseReadsBack() {
        for destination in ScreenDestination.allCases {
            let read = ScreenshotsSettings.read(store([ScreenshotsSettings.Key.afterFullScreen: destination.rawValue]))
            XCTAssertEqual(read.afterFullScreen, destination)
        }
        XCTAssertFalse(ScreenshotsSettings.read(store([ScreenshotsSettings.Key.thumbnail: false])).thumbnail)
    }

    func testGarbageReadsAsTheDefaultsAndNeverAsOff() {
        let garbage: [Any] = [5, Data([1]), ["file"], "FILE", "", 1e300, Int.max]
        for value in garbage {
            let read = ScreenshotsSettings.read(store([ScreenshotsSettings.Key.afterFullScreen: value,
                                                       ScreenshotsSettings.Key.thumbnail: value]))
            XCTAssertEqual(read.afterFullScreen, .file, "\(value)")
            XCTAssertTrue(read.thumbnail, "a thumbnail setting of \(value) was read as off")
        }
    }

    func testTheDestinationsSayWhatTheyDo() {
        XCTAssertTrue(ScreenDestination.file.saves && !ScreenDestination.file.copies)
        XCTAssertTrue(!ScreenDestination.clipboard.saves && ScreenDestination.clipboard.copies)
        XCTAssertTrue(ScreenDestination.both.saves && ScreenDestination.both.copies)
    }
}
