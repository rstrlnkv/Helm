import XCTest
@testable import Module_Uninstaller_Engine

/// Which changes in the Trash are worth looking again for.
///
/// The watcher fires for everything that lands in `~/.Trash`, and looking again
/// costs a scan per app found: could this event be an application arriving?
final class TrashArrivalTests: XCTestCase {

    private let trash = "/Users/ann/.Trash"

    func testTheBundleItself() {
        XCTAssertTrue(TrashArrival.namesAnApp(["/Users/ann/.Trash/Notes Pro.app"], trash: trash))
    }

    /// The event that actually arrives: with file events the callback sees paths
    /// inside the bundle, and the bundle's own path may never appear.
    func testAFileInsideTheBundle() {
        XCTAssertTrue(TrashArrival.namesAnApp(
            ["/Users/ann/.Trash/Notes Pro.app/Contents/Info.plist"], trash: trash))
    }

    func testADeepFileInsideTheBundle() {
        XCTAssertTrue(TrashArrival.namesAnApp(
            ["/Users/ann/.Trash/Notes Pro.app/Contents/Resources/en.lproj/Main.nib"], trash: trash))
    }

    /// The common case: everything else a person throws away.
    func testAnOrdinaryFile() {
        XCTAssertFalse(TrashArrival.namesAnApp(["/Users/ann/.Trash/statement.pdf"], trash: trash))
    }

    func testAFolderThatIsNotABundle() {
        XCTAssertFalse(TrashArrival.namesAnApp(
            ["/Users/ann/.Trash/old work/notes.txt"], trash: trash))
    }

    /// A bundle one folder down is not something the sweep can see
    /// (`trashedApps()` reads the top level only).
    func testABundleInsideAFolderInTheTrash() {
        XCTAssertFalse(TrashArrival.namesAnApp(
            ["/Users/ann/.Trash/old work/Notes Pro.app/Contents/Info.plist"], trash: trash))
    }

    func testSomethingOutsideTheTrash() {
        XCTAssertFalse(TrashArrival.namesAnApp(["/Users/ann/Downloads/Notes Pro.app"], trash: trash))
    }

    /// A folder whose name merely starts the same way. `.Trashcan` is not the
    /// Trash, and a prefix test without the separator says it is.
    func testASiblingFolderWithASimilarName() {
        XCTAssertFalse(TrashArrival.namesAnApp(["/Users/ann/.Trashcan/Notes Pro.app"], trash: trash))
    }

    /// One arrival in a batch of forty is still an arrival.
    func testOneAppAmongOrdinaryFiles() {
        XCTAssertTrue(TrashArrival.namesAnApp(
            ["/Users/ann/.Trash/a.pdf", "/Users/ann/.Trash/b.png",
             "/Users/ann/.Trash/Notes Pro.app/Contents/MacOS/Notes Pro"], trash: trash))
    }

    func testNothingAtAll() {
        XCTAssertFalse(TrashArrival.namesAnApp([], trash: trash))
    }

    /// The sweep filters on `app` as spelled and lists no `.App`, so waking it
    /// for one is a scan that finds nothing.
    func testExtensionIsComparedAsSpelled() {
        XCTAssertFalse(TrashArrival.namesAnApp(["/Users/ann/.Trash/Notes Pro.App"], trash: trash))
    }

    /// Only the extension `app` names a bundle: a name that merely ends in the
    /// letters, or starts its extension with them, is an ordinary file.
    func testOnlyTheExtensionAppNamesABundle() {
        XCTAssertFalse(TrashArrival.namesAnApp(["/Users/ann/.Trash/myapp"], trash: trash))
        XCTAssertFalse(TrashArrival.namesAnApp(["/Users/ann/.Trash/Notes Pro.application"], trash: trash))
    }

    /// A trailing slash is how a directory path arrives from some APIs, and it
    /// must not turn the bundle into something else.
    func testATrailingSlash() {
        XCTAssertTrue(TrashArrival.namesAnApp(["/Users/ann/.Trash/Notes Pro.app/"], trash: trash))
    }

    /// A file named like a bundle is still worth a look: the sweep refuses it at
    /// its `Info.plist`, and this rule does not read the disk.
    func testTheRuleJudgesThePathAndNotTheDisk() {
        XCTAssertTrue(TrashArrival.namesAnApp(["/Users/ann/.Trash/not really.app"], trash: trash))
    }
}
