import XCTest
import AppKit
import SwiftUI
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **The page's half of the same distinction.**
///
/// `ASearchRunsOnReturnNotOnAKeyTests` proves that `helmSearchable`
/// keeps the binding and the press apart. What it cannot prove is that *this*
/// page wired the press to anything: a page that declares the search and
/// forgets `onSubmit` has a control a person can type in and a Поиск segment
/// that never asks `brew` a thing, and every assertion about the results area
/// would go on passing, because a page that was never asked draws the same
/// prompt as a page nobody has typed into.
///
/// So this counts the commands that left for the engine. The fixture answers
/// `.search` with nothing, which is enough: what is being counted is the
/// asking.
@MainActor
final class ASearchAsksBrewOnlyOnReturnTests: XCTestCase {

    /// Counts what was asked and answers from a table. Named at construction;
    /// no default port here could reach this Mac's own brew.
    private final class Counter: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }

        /// The payload of every `.search` that was sent, in order.
        ///
        /// Taken under the lock on both sides, in a synchronous property that
        /// returns the value rather than holding it across a suspension —
        /// `send` is called from the view model's own task and read from the
        /// test's.
        private let lock = NSLock()
        private var asked: [String] = []
        var searches: [String] { lock.withLock { asked } }

        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled: return try JSONEncoder().encode([BrewPackage]())
            case .search:
                // Failable, the way this module's other search fixture reads the
                // same payload (`AStaleSearchDoesNotLandOnANewerOneTests`).
                let word = String(data: command.payload, encoding: .utf8) ?? ""
                lock.withLock { asked.append(word) }
                return try JSONEncoder().encode([SearchHit]())
            case .descriptions: return try JSONEncoder().encode([String: String]())
            default: return Data()
            }
        }
    }

    /// Turns of the run loop that also **yield**, which `MountedRender.settle`
    /// deliberately does not.
    ///
    /// The press starts a `Task` that awaits a round trip to the transport, and
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

    func testTypingAsksNothingAndReturnAsksOnce() async {
        let transport = Counter()
        defer { withExtendedLifetime(transport) {} }
        let mvm = ModuleViewModel(transport: transport)
        let hb = HomebrewViewModel.shared(vm: mvm)
        let mount = MountedRender(HomebrewSettingsPage(vm: mvm),
                                  width: 984, height: 520, appearance: .aqua)
        defer { mount.drop() }
        await hb.loadIfNeeded()
        hb.segment = .search
        await turn(mount, 25)

        for word in ["w", "wg", "wge", "wget"] {
            XCTAssertTrue(mount.type(word), """
                the Поиск segment put no search field in the window's toolbar, so «\(word)» was \
                never typed and neither count below is about this page
                """)
            await turn(mount, 10)
        }
        XCTAssertEqual(transport.searches, [], """
            typing sent \(transport.searches.count) searches to the engine — one search is two \
            `brew search` runs, about nine seconds by this module's own measurement, so a \
            search per letter is four of them out at once for one word
            """)

        XCTAssertTrue(mount.pressReturn(), "Return never reached the field")
        // The press starts a request; the count is read after the page has had
        // turns to make it rather than in the same breath as the press.
        await turn(mount, 40)
        XCTAssertEqual(transport.searches, ["wget"], """
            Return sent \(transport.searches) where it is the one press that asks. Nothing at \
            all is a Поиск segment that can no longer search; anything else is a word the page \
            asked about that nobody had finished typing
            """)
    }
}
