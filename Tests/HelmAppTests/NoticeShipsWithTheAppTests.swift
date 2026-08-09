import XCTest
import HelmTestSupport

/// `NOTICE.md` is the app's only attribution now, so it has to reach the copy.
///
/// The About page carried a visible «Flag artwork: flag-icons, MIT» line, and
/// it is gone: MIT asks for the notice to *accompany* copies, not to be drawn
/// on a screen, and `NOTICE.md` ships inside the bundle with the copyright and
/// the full permission text. That is allowed, and it moves the whole obligation
/// onto one file that nothing in the app reads — so nothing in the app would
/// ever notice it going missing.
///
/// Two ways it can go missing, and this fails on either. The file can lose the
/// attribution it exists for, and `Scripts/package-app.sh` can stop copying it
/// into `Contents/Resources` — a `cp` that is one line of a hundred, with no
/// build error and no visible symptom, because a bundle without a notice looks
/// exactly like a bundle with one.
///
/// Source-reading rather than bundle-reading for the reason
/// `ReleaseBuildsTheProductTests` gives: the packaged app is a release build
/// away, and a guard that only holds after `package-app.sh` has run is a guard
/// that does not hold in `swift test`.
final class NoticeShipsWithTheAppTests: XCTestCase {

    /// The words MIT asks for: the copyright line and the permission notice.
    /// Quoted here rather than read out of the file — two sides reading one
    /// constant is a check that cannot fail.
    func testTheNoticeCarriesTheFlagAttributionAndItsPermissionText() throws {
        let notice = try RepoSource.text(of: "NOTICE.md")

        XCTAssertTrue(notice.contains("flag-icons"),
                      "NOTICE.md no longer names the artwork it attributes")
        XCTAssertTrue(notice.contains("Panayiotis Lipiridis"),
                      "NOTICE.md no longer carries the copyright holder")
        XCTAssertTrue(notice.contains(
            "The above copyright notice and this permission notice shall be included in all"),
                      "NOTICE.md no longer carries MIT's permission notice, which is the "
                      + "one sentence the licence requires to travel with a copy")
    }

    /// And the packaging step puts it where a copy of the app can be read from.
    func testThePackagingScriptCopiesTheNoticeIntoTheBundle() throws {
        let copies = try RepoSource.lines(of: "Scripts/package-app.sh")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("#") && $0.contains("NOTICE.md") }

        XCTAssertFalse(copies.isEmpty,
                       "package-app.sh does not mention NOTICE.md, so the app ships with "
                       + "no attribution at all — the About page's visible credit was "
                       + "removed on the strength of this copy")
        XCTAssertTrue(copies.contains { $0.contains("RESOURCES_DIR") },
                      "NOTICE.md is named but does not land in Contents/Resources: \(copies)")
    }
}
