import XCTest
@testable import Module_Uninstaller_Engine

/// Which changes in the Trash are worth looking again for.
///
/// The watcher fires for everything that lands in `~/.Trash` — a screenshot, a
/// download, forty files a person selected at once — and looking again costs a
/// directory read plus a scan of `~/Library` per app found. The question this
/// answers is the cheap one: could this event have been an application arriving?
final class TrashArrivalTests: XCTestCase {

    private let trash = "/Users/ann/.Trash"

    func testTheBundleItself() {
        XCTAssertTrue(TrashArrival.namesAnApp(["/Users/ann/.Trash/Notes Pro.app"], trash: trash))
    }

    /// The event that actually arrives. Finder copies a bundle in file by file
    /// with `kFSEventStreamCreateFlagFileEvents`, so what the callback sees is
    /// paths *inside* the bundle — the bundle's own path may never appear at all,
    /// and a rule matching only the top level would never fire on a real drag.
    func testAFileInsideTheBundle() {
        XCTAssertTrue(TrashArrival.namesAnApp(
            ["/Users/ann/.Trash/Notes Pro.app/Contents/Info.plist"], trash: trash))
    }

    func testADeepFileInsideTheBundle() {
        XCTAssertTrue(TrashArrival.namesAnApp(
            ["/Users/ann/.Trash/Notes Pro.app/Contents/Resources/en.lproj/Main.nib"], trash: trash))
    }

    /// The common case, and the one that decides whether this rule earns its
    /// keep: everything else a person throws away.
    func testAnOrdinaryFile() {
        XCTAssertFalse(TrashArrival.namesAnApp(["/Users/ann/.Trash/statement.pdf"], trash: trash))
    }

    func testAFolderThatIsNotABundle() {
        XCTAssertFalse(TrashArrival.namesAnApp(
            ["/Users/ann/.Trash/old work/notes.txt"], trash: trash))
    }

    /// A bundle one folder down is not something the sweep can see —
    /// `trashedApps()` reads the top level of the Trash only — so waking it for
    /// one is a scan that cannot find anything.
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

    /// The volume is case-insensitive by default, so `.App` names the same
    /// bundle `.app` does and the sweep would find it.
    func testExtensionCaseDoesNotDecide() {
        XCTAssertTrue(TrashArrival.namesAnApp(["/Users/ann/.Trash/Notes Pro.App"], trash: trash))
    }

    /// A trailing slash is how a directory path arrives from some APIs, and it
    /// must not turn the bundle into something else.
    func testATrailingSlash() {
        XCTAssertTrue(TrashArrival.namesAnApp(["/Users/ann/.Trash/Notes Pro.app/"], trash: trash))
    }

    /// A file named like a bundle is still worth a look: the sweep reads its
    /// `Info.plist` and refuses it there, where the refusal is one plist read
    /// rather than a rule here pretending to know what is on disk.
    func testTheRuleJudgesThePathAndNotTheDisk() {
        XCTAssertTrue(TrashArrival.namesAnApp(["/Users/ann/.Trash/not really.app"], trash: trash))
    }
}
