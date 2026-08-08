import Foundation
import XCTest
@testable import HelmUI

/// Where Finder is sent when Helm reveals a path.
///
/// The reason this is a decision at all: **selecting a file Finder cannot see
/// does nothing**. `activateFileViewerSelecting` on a path that no longer exists
/// returns without opening a window, without an error and without bringing Finder
/// forward — so the button a person pressed did nothing whatsoever. Every place
/// Helm reveals a path is a place where the path may well be gone: it is offered
/// beside removal failures, in Autopilot's history of files it moved, and on
/// leftovers that were deleted a moment ago in another window.
final class RevealTargetTests: XCTestCase {

    private func target(_ path: String, existing: Set<String> = []) -> HelmReveal.Target? {
        HelmReveal.target(for: path, exists: { existing.contains($0) })
    }

    func testAPathThatIsThereIsSelected() {
        XCTAssertEqual(target("/Users/somebody/Documents/report.pdf",
                              existing: ["/Users/somebody/Documents/report.pdf"]),
                       .select(URL(fileURLWithPath: "/Users/somebody/Documents/report.pdf")))
    }

    /// The lesson, spelled once: the enclosing folder opens instead, which is
    /// where the file was and is the answer to "show me".
    ///
    /// `isDirectory: true` in the expectation, because that is what the folder's
    /// URL is — dropping the last component leaves a trailing slash, and a URL
    /// built without one is a different value for the same folder.
    func testAPathThatIsGoneOpensTheFolderItWasIn() {
        XCTAssertEqual(target("/Users/somebody/Library/Caches/com.example.app"),
                       .openEnclosing(URL(fileURLWithPath: "/Users/somebody/Library/Caches",
                                          isDirectory: true)))
    }

    /// A folder is revealed by selecting it, exactly as a file is — Finder opens
    /// the parent with the folder highlighted, rather than opening the folder.
    func testAFolderThatIsThereIsSelectedAndNotOpened() {
        XCTAssertEqual(target("/Applications/Some.app", existing: ["/Applications/Some.app"]),
                       .select(URL(fileURLWithPath: "/Applications/Some.app")))
    }

    /// Two sites already guarded a `String?` by hand and the rest did not. An
    /// empty path must reveal *nothing*: `URL(fileURLWithPath: "")` is the
    /// process's current directory, and the enclosing folder of that is `..` —
    /// so the fallback would open some folder the person never asked about.
    func testAnEmptyPathRevealsNothing() {
        XCTAssertNil(target(""))
        XCTAssertNil(target("   "))
    }
}
