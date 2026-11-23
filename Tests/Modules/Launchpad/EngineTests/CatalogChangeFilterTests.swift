import XCTest
@testable import Module_Launchpad_Engine

/// Which changed paths cost a re-read: an app arriving or going, not the files written inside a bundle.
final class CatalogChangeFilterTests: XCTestCase {
    func testABundleItselfAndItsInfoPlistCount() {
        XCTAssertTrue(CatalogChange.concerns("/Applications/Foo.app"))
        XCTAssertTrue(CatalogChange.concerns("/Applications/Utilities/Foo.app/Contents/Info.plist"))
        XCTAssertTrue(CatalogChange.concerns("/Applications/Foo.app/"))
    }

    func testFilesInsideABundleDoNot() {
        XCTAssertFalse(CatalogChange.concerns("/Applications/Foo.app/Contents/MacOS/Foo"))
        XCTAssertFalse(CatalogChange.concerns("/Applications/Foo.app/Contents/Resources/en.lproj/InfoPlist.strings"))
        XCTAssertFalse(CatalogChange.concerns("/Applications/Foo.app/Contents/Applications/Bar.app"))
    }

    func testAFolderOfAppsCountsAndAHiddenEntryDoesNot() {
        XCTAssertTrue(CatalogChange.concerns("/Applications/Utilities"))
        XCTAssertFalse(CatalogChange.concerns("/Applications/.DS_Store"))
        XCTAssertFalse(CatalogChange.concerns(""))
    }

    func testOneConcerningPathAmongNoiseIsEnough() {
        let noise = ["/Applications/Foo.app/Contents/MacOS/Foo", "/Applications/.DS_Store"]
        XCTAssertFalse(CatalogChange.concerns(noise))
        XCTAssertTrue(CatalogChange.concerns(noise + ["/Applications/Bar.app"]))
    }
}
