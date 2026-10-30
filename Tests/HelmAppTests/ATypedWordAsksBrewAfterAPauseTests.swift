import XCTest
import AppKit
import HelmContract
import HelmTestSupport
import HelmUI
@testable import HelmApp
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **The page's half of the same distinction — rewritten 2026-09-24 for the
/// owner's decision that search lives on a field every tab carries.**
///
/// Renamed from `ASearchAsksBrewOnlyOnReturnTests`: that title's premise
/// — "typing asks nothing" — is no longer true. Typing filters the current
/// tab's own list locally and, only once that filter finds nothing, starts a
/// pause toward asking brew; Return still asks unconditionally. This file
/// counts the same thing the old one did — the commands that left for the
/// engine — against the new contract rather than the old one.
///
/// **Moved here from `Tests/Modules/Homebrew/UITests`** — the page's search
/// field is the real `NSSearchField` the header row draws
/// (`HelmHeaderSearch`), which `LivePageUnderTheHeaderFixture` puts
/// under the row, and the fixture needs the host's own types (its own header says so), which a module's
/// `UITests` do not see.
///
/// **The row.** `LivePageUnderTheHeaderFixture` mounts the page under the card's
/// header row; each mount asserts the field is there before it types, since
/// `MountedRender.type` and `.pressReturn` act on the first field in the host.
@MainActor
final class ATypedWordAsksBrewAfterAPauseTests: XCTestCase {

    /// Counts what was asked and answers from a table. Named at construction;
    /// no default port here could reach this Mac's own brew.
    private final class Counter: HomebrewWork, @unchecked Sendable {
        private let installedList: [BrewPackage]
        init(installed: [BrewPackage] = []) { installedList = installed }

        /// Every word that was searched for, in order.
        ///
        /// Taken under the lock on both sides, in a synchronous property that
        /// returns the value rather than holding it across a suspension —
        /// the reads are made from the view model's own task and read from the
        /// test's.
        private let lock = NSLock()
        private var asked: [String] = []
        var searches: [String] { lock.withLock { asked } }

        func stream() -> AsyncStream<HomebrewNews> { AsyncStream { _ in } }
        func readStatus() async -> BrewStatus {
            BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew")
        }
        func readInstalled() async -> [BrewPackage]? { installedList }
        func readOutdated() async -> [OutdatedPackage]? { [] }
        func readDescriptions(of names: [String], isCask: Bool) async -> [String: String] { [:] }
        func find(_ query: String) async -> [SearchHit]? {
            lock.withLock { asked.append(query) }
            return []
        }
        func readDependents(of package: PackageRef) async -> [String]? { nil }
        func readInfo(about package: PackageRef) async -> PackageInfo? { nil }
        func measure(_ package: PackageRef, version: String) async -> Int? { nil }
        func readDoctor() async -> [DoctorIssue]? { nil }
        func readConfig() async -> BrewConfig? { nil }
        func perform(_ act: HomebrewAct) {}
    }

    /// Set well below the owner's real 700 ms, so each case exercises the
    /// pause itself rather than waiting it out on a real clock — CLAUDE.md's
    /// own rule for a timing test: run it alone and more than once, which the
    /// verification steps for this file do.
    private static let pause: Duration = .milliseconds(120)

    /// Turns of the run loop that also **yield**, which `MountedRender.settle`
    /// deliberately does not.
    ///
    /// The press starts a `Task` that awaits a round trip to the engine, and
    /// a settle loop holds the main actor for its whole length — so a count
    /// read after one of those is a count taken before the request could
    /// possibly have been made, and the test would fail on the harness rather
    /// than on the page. A sleep buys wall-clock time; a bare `Task.yield`
    /// would buy a turn on the pool and none.
    private func turn(_ mount: MountedRender, _ times: Int) async {
        for _ in 0..<times {
            mount.host.layoutSubtreeIfNeeded()
            try? await Task.sleep(nanoseconds: 4_000_000)
        }
    }

    /// Waits, in short turns, until either the deadline or a search has
    /// arrived — a real deadline rather than one exact sleep, for the reason
    /// CLAUDE.md gives about a timing test on a real clock.
    private func waitForASearch(_ transport: Counter, _ mount: MountedRender,
                                deadlineTurns: Int) async {
        for _ in 0..<deadlineTurns where transport.searches.isEmpty { await turn(mount, 2) }
    }

    func testTypingAsksNothingAtOnceThenTheLastWordAfterThePause() async {
        let transport = Counter()
        defer { withExtendedLifetime(transport) {} }
        let hb = HomebrewViewModel(work: transport)
        hb.searchPause = Self.pause
        let fixture = LivePageUnderTheHeaderFixture(HomebrewSettingsPage(hb: hb),
                                                  selection: .module(HomebrewDescriptor.id.rawValue),
                                                  width: 984, height: 520)
        let mount = fixture.mount
        defer { fixture.drop() }
        await hb.loadIfNeeded()
        await turn(mount, 25)

        XCTAssertNotNil(fixture.searchField, """
            the header row holds no search field (the page declared none, or the row did not draw it) \
            to type into
            """)

        // `turns: 0` on every keystroke but the last — `MountedRender.type`'s
        // own default settle is five turns of twenty milliseconds each, a
        // hundred milliseconds that alone exceeds this test's pause and would
        // let an intermediate prefix's own pause fire between two keystrokes
        // typed as fast as this loop can type them.
        for word in ["w", "wg", "wge", "wgex"] {
            XCTAssertTrue(mount.type(word, turns: 0), """
                «\(word)» was never typed (no search field in the header row, as the guard \
                above says) and neither count below is about this page
                """)
        }
        XCTAssertEqual(transport.searches, [], """
            typing sent \(transport.searches.count) searches to the engine before the pause had \
            elapsed — the trigger fires on a timer, not on a keystroke
            """)

        await waitForASearch(transport, mount, deadlineTurns: 60)
        XCTAssertEqual(transport.searches, ["wgex"], """
            past the pause the engine saw \(transport.searches) — an earlier prefix must not \
            have reached it, and only the word left in the field should
            """)
    }

    /// Return does not wait for the pause — a fresh word followed at once by
    /// Return asks before a pause set to ten seconds could ever have fired on
    /// its own.
    func testReturnAsksAtOnceWithoutWaitingForThePause() async {
        let transport = Counter()
        defer { withExtendedLifetime(transport) {} }
        let hb = HomebrewViewModel(work: transport)
        hb.searchPause = .seconds(10)
        let fixture = LivePageUnderTheHeaderFixture(HomebrewSettingsPage(hb: hb),
                                                  selection: .module(HomebrewDescriptor.id.rawValue),
                                                  width: 984, height: 520)
        let mount = fixture.mount
        defer { fixture.drop() }
        await hb.loadIfNeeded()
        await turn(mount, 25)

        XCTAssertNotNil(fixture.searchField, """
            the header row holds no search field (the page declared none, or the row did not draw it) \
            to type into
            """)

        XCTAssertTrue(mount.type("wget"), "the field never took the word")
        XCTAssertTrue(mount.pressReturn(), "Return never reached the field")
        await waitForASearch(transport, mount, deadlineTurns: 60)
        XCTAssertEqual(transport.searches, ["wget"], """
            Return sent \(transport.searches) — nothing at all means Return no longer asks \
            unconditionally, and the pause could not have fired in this time on its own
            """)
    }

    /// A word that matches something already installed asks nothing on its
    /// own: the trigger is "the local filter found nothing", and typing
    /// `wget` against an installed `wget` finds a row.
    func testAWordThatMatchesAnInstalledPackageAsksNothingOnItsOwn() async {
        let transport = Counter(installed: [BrewPackage(name: "wget", version: "1.25.0",
                                                        isCask: false)])
        defer { withExtendedLifetime(transport) {} }
        let hb = HomebrewViewModel(work: transport)
        hb.searchPause = Self.pause
        let fixture = LivePageUnderTheHeaderFixture(HomebrewSettingsPage(hb: hb),
                                                  selection: .module(HomebrewDescriptor.id.rawValue),
                                                  width: 984, height: 520)
        let mount = fixture.mount
        defer { fixture.drop() }
        await hb.loadIfNeeded()
        await turn(mount, 25)

        XCTAssertNotNil(fixture.searchField, """
            the header row holds no search field (the page declared none, or the row did not draw it) \
            to type into
            """)

        XCTAssertTrue(mount.type("wget"), "the field never took the word")
        await turn(mount, 80)   // several multiples of the pause
        XCTAssertEqual(transport.searches, [], """
            \(transport.searches) — the installed row already answers "wget", so the pause had \
            nothing to ask brew about
            """)
    }
}
