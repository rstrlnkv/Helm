import Foundation
import XCTest
@testable import HelmUI

/// Where Finder is sent when Helm reveals a path.
///
/// Two reasons this is a decision at all. **Selecting a file Finder cannot see
/// does nothing** — `activateFileViewerSelecting` on a path that no longer exists
/// returns without a window and without bringing Finder forward, and every place
/// Helm reveals a path is a place the path may well be gone: beside removal
/// failures, in Autopilot's history, on leftovers deleted a moment ago. And
/// **`NSWorkspace.open` on a bundle launches it** — a `.app` runs, a
/// `.photoslibrary` mounts — so opening the enclosing folder to "show where it
/// was" would execute whatever bundle the stale row sat inside. The enclosing
/// folder is therefore *selected*, not opened, whenever it is a package.
final class RevealTargetTests: XCTestCase {

    private func target(_ path: String,
                        existing: Set<String> = [],
                        directories: Set<String> = [],
                        packages: Set<String> = []) -> HelmReveal.Target? {
        HelmReveal.target(
            for: path,
            exists: { existing.contains($0) },
            traits: { p in
                guard directories.contains(p) || packages.contains(p) else { return nil }
                return (isDirectory: true, isPackage: packages.contains(p))
            })
    }

    func testAPathThatIsThereIsSelected() {
        XCTAssertEqual(target("/Users/somebody/Documents/report.pdf",
                              existing: ["/Users/somebody/Documents/report.pdf"]),
                       .select(URL(fileURLWithPath: "/Users/somebody/Documents/report.pdf")))
    }

    /// A file that is gone: the plain folder it was in is opened to its contents,
    /// which is the answer to "show me where it was".
    ///
    /// `isDirectory: true` in the expectation, because that is what the folder's
    /// URL is — dropping the last component leaves a trailing slash, and a URL
    /// built without one is a different value for the same folder.
    func testAPathThatIsGoneOpensThePlainFolderItWasIn() {
        XCTAssertEqual(target("/Users/somebody/Library/Caches/com.example.app",
                              directories: ["/Users/somebody/Library/Caches"]),
                       .open(URL(fileURLWithPath: "/Users/somebody/Library/Caches",
                                 isDirectory: true)))
    }

    /// **The defect: a stale row inside a bundle.** The disk scan lists the
    /// top-level children of a `.app`, so a row can point at
    /// `…/Poison.app/Contents` after the file is gone. Opening the enclosing
    /// `Poison.app` would launch it — an unsigned bundle, no Gatekeeper prompt.
    /// The bundle is *selected* in its parent instead, which shows where it is
    /// and runs nothing.
    func testAGonePathInsideABundleSelectsTheBundleRatherThanOpeningIt() {
        // A directory URL (trailing slash), because that is what dropping the
        // last component of the enclosing folder leaves.
        XCTAssertEqual(target("/Applications/Poison.app/Contents",
                              packages: ["/Applications/Poison.app"]),
                       .select(URL(fileURLWithPath: "/Applications/Poison.app", isDirectory: true)))
    }

    /// A folder is revealed by selecting it, exactly as a file is — Finder opens
    /// the parent with the folder highlighted, rather than opening the folder.
    /// A bundle that exists is selected for the same reason it would be launched
    /// if opened.
    func testAFolderThatIsThereIsSelectedAndNotOpened() {
        XCTAssertEqual(target("/Applications/Some.app", existing: ["/Applications/Some.app"]),
                       .select(URL(fileURLWithPath: "/Applications/Some.app")))
    }

    /// A gone path whose enclosing folder is *also* gone — a volume that has
    /// unmounted, most often — reveals nothing. Selecting a folder Finder cannot
    /// see is silent, and `open` on it returns false; rather than pretend, the
    /// decision is `nil` so a caller can say so.
    func testAGonePathWhoseEnclosingFolderIsAlsoGoneRevealsNothing() {
        XCTAssertNil(target("/Volumes/Ejected/old/file.bin"))
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
