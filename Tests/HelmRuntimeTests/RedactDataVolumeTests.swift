import XCTest
@testable import HelmRuntime

/// On an APFS boot volume group every file under the home directory is
/// reachable twice: as `/Users/name/…` and as
/// `/System/Volumes/Data/Users/name/…`. `Redact.path` matched the literal home
/// prefix, so the second spelling carried the account name straight into the
/// log — and a user can point a disk scan at `/System/Volumes/Data` by hand,
/// which is where the scan root is logged from.
final class RedactDataVolumeTests: XCTestCase {
    private let home = "/Users/someone"
    private let twin = "/System/Volumes/Data/Users/someone"

    func testTheDataVolumeTwinIsRedactedToo() {
        XCTAssertEqual(Redact.path("\(twin)/Documents/tax.pdf", home: home),
                       "~/Documents/tax.pdf")
    }

    func testTheTwinOfHomeItselfIsHome() {
        XCTAssertEqual(Redact.path(twin, home: home), "~")
    }

    func testThePlainSpellingStillWorks() {
        XCTAssertEqual(Redact.path("\(home)/Desktop/a.txt", home: home), "~/Desktop/a.txt")
        XCTAssertEqual(Redact.path(home, home: home), "~")
    }

    /// A path that merely starts with the same characters is a different path.
    func testANeighbourWithASharedPrefixIsNotRedacted() {
        XCTAssertEqual(Redact.path("/Users/someone-else/x", home: home),
                       "/Users/someone-else/x")
        XCTAssertEqual(Redact.path("/System/Volumes/Data/Users/someone-else/x", home: home),
                       "/System/Volumes/Data/Users/someone-else/x")
    }

    func testSomewhereElseEntirelyIsLeftAlone() {
        XCTAssertEqual(Redact.path("/Applications/Helm.app", home: home),
                       "/Applications/Helm.app")
    }

    func testAnEmptyHomeRedactsNothing() {
        XCTAssertEqual(Redact.path("/Users/someone/x", home: ""), "/Users/someone/x")
    }
}
