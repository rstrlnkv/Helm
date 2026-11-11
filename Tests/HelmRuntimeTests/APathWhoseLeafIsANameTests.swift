import Foundation
import XCTest
@testable import HelmRuntime

/// `Redact.path` hides the account name and nothing else, which is right for a
/// module whose paths name the person's folders and wrong for one whose leaf **is**
/// the name of software. These are the promises the second reading makes, and the
/// call sites that rely on them are in another target
/// (`TheLogDoesNotNameTheSoftwareTests` drives the removal that writes the line).
final class APathWhoseLeafIsANameTests: XCTestCase {
    private let home = "/Users/x"

    /// **The default has to stay `.fileName`.** Disk and Duplicates print the
    /// person's own file names home-relative through the same three lines, and
    /// whether that should change is a decision about those modules — not something
    /// to inherit from a default that moved.
    func testAnOrdinaryFileNameIsUntouchedBeyondTheHome() {
        let line = "/Users/x/Documents/thesis final.pdf"
        XCTAssertEqual(Redact.path(line, leaf: .fileName, home: home), "~/Documents/thesis final.pdf")
        XCTAssertEqual(Redact.path(line, leaf: .fileName, home: home),
                       Redact.path(line, home: home),
                       "the two readings must agree wherever the leaf is a document")
    }

    /// The folder and the extension stay: which folder a refusal was about, and
    /// whether it was a settings file or a plug-in, are what the line is read for.
    func testASoftwareLeafIsTaggedAndTheRestSurvives() {
        let shown = Redact.path("/Users/x/Library/Preferences/com.acme.tool.plist",
                                leaf: .softwareName, home: home)

        XCTAssertTrue(shown.hasPrefix("~/Library/Preferences/"), shown)
        XCTAssertTrue(shown.hasSuffix(".plist"), shown)
        XCTAssertFalse(shown.contains("com.acme.tool"), shown)
        XCTAssertTrue(shown.contains(Redact.app("com.acme.tool")), shown)
    }

    /// A bundle without an extension — the uninstaller's own shape — still has a
    /// name to hide.
    func testALeafWithNoExtensionIsStillTagged() {
        let shown = Redact.path("/Users/x/Library/Application Support/AcmeTool",
                                leaf: .softwareName, home: home)
        XCTAssertEqual(shown, "~/Library/Application Support/" + Redact.app("AcmeTool"))
    }

    /// In the *path* the leaf is delimited, so it is replaced whatever its length.
    func testAVeryShortNameIsStillTaggedInThePath() {
        let shown = Redact.path("/Users/x/Library/QuickLook/Ax.qlgenerator",
                                leaf: .softwareName, home: home)
        XCTAssertEqual(shown, "~/Library/QuickLook/" + Redact.app("Ax") + ".qlgenerator")
    }

    /// A tag tells one thing from another and survives a restart, which is the whole
    /// reason names are tagged rather than dropped.
    func testTheTagIsStableAndDistinguishing() {
        XCTAssertEqual(Redact.path("/Users/x/Library/Preferences/com.acme.tool.plist",
                                   leaf: .softwareName, home: home),
                       Redact.path("/Users/x/Library/Preferences/com.acme.tool.plist",
                                   leaf: .softwareName, home: home))
        XCTAssertNotEqual(Redact.path("/Users/x/Library/Preferences/com.acme.tool.plist",
                                      leaf: .softwareName, home: home),
                          Redact.path("/Users/x/Library/Preferences/com.other.tool.plist",
                                      leaf: .softwareName, home: home))
    }
}
