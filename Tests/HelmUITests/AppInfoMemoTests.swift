import AppKit
import XCTest
@testable import HelmUI

/// `AppInfo.resolve` asks LaunchServices for a path, `FileManager` for a display
/// name and `NSWorkspace` for an icon — three trips to the system, measured at
/// about 0.14 ms together. `HelmAppRuleRow` calls it in its **initialiser**, and
/// three modules draw lists of those rows, so a scroll or a filter re-runs it
/// once per visible row and the Uninstaller already keeps a private `NSCache`
/// for the icon half of the same question.
///
/// **The assertion is object identity, not the value.** Whether the answer is
/// right is a question about the system's own tables, and it comes out the same
/// with the memo present or absent; whether the memo is there at all is only
/// visible as the *same object* coming back.
final class AppInfoMemoTests: XCTestCase {

    /// A bundle id LaunchServices cannot know, so the answer is the fallback
    /// pair and the test does not depend on what is installed here.
    private let unknown = "com.example.helm.tests.not-installed"

    func testTheSameBundleIDIsResolvedOnceAndHandedBack() {
        let first = AppInfo.resolve(unknown)
        let second = AppInfo.resolve(unknown)

        XCTAssertEqual(first.name, unknown, "an unknown id answers with itself, as it always did")
        XCTAssertTrue(first.icon === second.icon,
                      "the icon was fetched again for a bundle id already resolved")
    }

    /// One entry per id, not one entry: a memo that answers every id with the
    /// first one it saw would pass the test above.
    func testTwoBundleIDsGetTwoAnswers() {
        let one = AppInfo.resolve(unknown)
        let other = AppInfo.resolve(unknown + ".other")

        XCTAssertEqual(one.name, unknown)
        XCTAssertEqual(other.name, unknown + ".other")
    }

    /// The fallback above exercises none of the three lookups the memo exists to
    /// save, so one id that every Mac has: what is drawn has to be the app's own
    /// name and its own icon, cached or not.
    func testAnAppThatIsReallyInstalledStillAnswersWithItsOwnNameAndIcon() throws {
        let finder = "com.apple.finder"
        try XCTSkipIf(NSWorkspace.shared.urlForApplication(withBundleIdentifier: finder) == nil,
                      "LaunchServices cannot see Finder on this machine")

        let first = AppInfo.resolve(finder)
        XCTAssertNotEqual(first.name, finder, "the id came back instead of the display name")
        XCTAssertGreaterThan(first.icon.size.width, 0, "an icon with no size draws nothing")
        XCTAssertTrue(first.icon === AppInfo.resolve(finder).icon)
    }

    /// The icon half, keyed by path, because the Uninstaller's rows hold a path
    /// and a bundle in `~/.Trash` is not what LaunchServices answers for.
    func testAnIconIsFetchedOncePerPath() {
        let path = "/System/Library/CoreServices/Finder.app"
        let first = AppInfo.icon(forFile: path)

        XCTAssertGreaterThan(first.size.width, 0)
        XCTAssertTrue(first === AppInfo.icon(forFile: path),
                      "the disk was asked again for a path already drawn")
    }
}
