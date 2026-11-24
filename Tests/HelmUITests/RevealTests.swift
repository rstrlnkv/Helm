import Foundation
import XCTest
@testable import HelmUI

/// Where Finder is sent when Helm reveals a path: a path that is gone falls
/// back to its enclosing folder, and a folder that is a package is selected,
/// never opened, because opening a bundle launches or mounts it.
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
    /// `isDirectory: true` in the expectation: dropping the last component
    /// leaves a trailing slash, and a URL without one is a different value.
    func testAPathThatIsGoneOpensThePlainFolderItWasIn() {
        XCTAssertEqual(target("/Users/somebody/Library/Caches/com.example.app",
                              directories: ["/Users/somebody/Library/Caches"]),
                       .open(URL(fileURLWithPath: "/Users/somebody/Library/Caches",
                                 isDirectory: true)))
    }

    /// A stale row inside a bundle (`…/Poison.app/Contents`): opening the
    /// enclosing `Poison.app` would launch an unsigned bundle with no
    /// Gatekeeper prompt. The bundle is selected in its parent instead.
    func testAGonePathInsideABundleSelectsTheBundleRatherThanOpeningIt() {
        // A directory URL, as dropping the last component leaves.
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

    /// A gone path whose enclosing folder is also gone, most often an unmounted
    /// volume, reveals nothing: the decision is `nil` so a caller can say so.
    func testAGonePathWhoseEnclosingFolderIsAlsoGoneRevealsNothing() {
        XCTAssertNil(target("/Volumes/Ejected/old/file.bin"))
    }

    /// An empty path reveals nothing: `URL(fileURLWithPath: "")` is the
    /// process's current directory, and the fallback would open some folder
    /// the person never asked about.
    func testAnEmptyPathRevealsNothing() {
        XCTAssertNil(target(""))
        XCTAssertNil(target("   "))
    }
}
