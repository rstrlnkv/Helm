import AppKit
import XCTest
@testable import HelmUI

/// A list of app rules is **stored** by bundle id and **read** by name, and two
/// pages sorted it by the key.
///
/// `com.apple.Safari`, `com.tinyapp.Zed`, `org.mozilla.firefox` reads as Safari,
/// Zed, Firefox — an order with no rule on screen, which is worse than an
/// arbitrary one because the eye keeps looking for the rule. Both pages drew the
/// name in the row and neither sorted by it.
///
/// The resolver is an argument so this can be asserted at all: what
/// LaunchServices answers for an installed app is a fact about this Mac, and a
/// test built on «Safari is called Safari here» measures the machine.
final class AListOfAppsIsSortedTheWayItIsReadTests: XCTestCase {

    private let names = ["b.zed": "Zed", "a.safari": "Safari", "c.firefox": "Firefox"]

    func testTheOrderIsTheNameAndNotTheIdentifier() {
        XCTAssertEqual(AppInfo.sortedByName(Array(names.keys)) { self.names[$0] ?? $0 },
                       ["c.firefox", "a.safari", "b.zed"])
    }

    /// `localizedStandardCompare`, not `<`: the Finder's own order, which is
    /// case-insensitive and reads a run of digits as a number. `<` puts «Ableton
    /// 10» before «Ableton 9» and every lowercase name after every uppercase one.
    func testTheOrderIsTheOneTheFinderWouldUse() {
        let byName = ["1": "Ableton 10", "2": "Ableton 9", "3": "aardvark", "4": "Zulu"]
        XCTAssertEqual(AppInfo.sortedByName(["1", "2", "3", "4"]) { byName[$0] ?? $0 },
                       ["3", "2", "1", "4"])
    }

    /// Two apps can carry one name — a copy in `~/Applications`, a beta beside a
    /// release — and «sorted» has to mean one order rather than whichever the
    /// sort happened to produce, or the list reshuffles under the pointer.
    func testTwoAppsWithOneNameStillHaveOneOrder() {
        let same = { (_: String) in "Same" }
        XCTAssertEqual(AppInfo.sortedByName(["b.two", "a.one"], name: same), ["a.one", "b.two"])
        XCTAssertEqual(AppInfo.sortedByName(["a.one", "b.two"], name: same), ["a.one", "b.two"])
    }

    /// And the default resolver is the one the rows draw with, or this sorts by
    /// something nobody sees. An id LaunchServices cannot know answers with
    /// itself, which is exactly what the row shows for it.
    func testTheDefaultResolverIsTheOneTheRowDraws() {
        let ids = ["com.example.helm.tests.zz", "com.example.helm.tests.aa"]
        XCTAssertEqual(AppInfo.sortedByName(ids), ids.sorted())
    }
}
