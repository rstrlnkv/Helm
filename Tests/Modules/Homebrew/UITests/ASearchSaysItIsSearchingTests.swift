import XCTest
import AppKit
import SwiftUI
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **Поиск answered the question while it was still being asked.**
///
/// The results area was `listOrEmpty(hb.searchHits, empty: HbStr.noResults,
/// busy: HbStr.searching)` with `empty` non-optional, so the busy branch was
/// unreachable by construction: `HbStr.searching` was translated into all eight
/// languages and drawn nowhere — `command grep -rn "HbStr.searching" Sources/`
/// found the parameter and nothing else. One search is two `brew search` runs,
/// measured by this module's own comment at about nine seconds, and for those
/// nine seconds the screen said «Ничего не найдено.» — the same drawing as a
/// true zero and as a refusal.
///
/// The mount drives the real search field, because the results area is gated on
/// the page's own `query` as well as on the reading, and a test that set only
/// the view model would be measuring half the seam.
///
/// **That field is the window's now** (`helmSearchable`), so the typing goes
/// through `MountedRender.type`, which reads the control off the window's
/// toolbar. It is not in `mount.host` at all — measured 2026-09-20,
/// `host.everyView(ofType:)` finds 0 search fields where the representable it
/// replaced gave 1 — which is exactly how a test of this shape goes quiet
/// rather than red, so the absence is a failure here and not a skipped step.
///
/// **The band moved up with the row that is gone.** It was 110…420, named as
/// «below the search field and above the status line»; the field's 32 pt row
/// and the rule under it have left the page, so the results area now starts at
/// the top of the pane. 40…380 is the same claim about the same area, and it is
/// still a band rather than the whole page for the reason `RenderedInk.bytes`
/// gives: a whole-page comparison is dominated by the status line, which says
/// three different things in these three runs.
@MainActor
final class ASearchSaysItIsSearchingTests: XCTestCase {

    private final class Catalogue: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }
        enum Answer { case hanging, none, refusing }
        let answer: Answer
        init(_ answer: Answer) { self.answer = answer }

        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled:
                return try JSONEncoder().encode([BrewPackage]())
            case .search:
                switch answer {
                case .hanging: try await Task.sleep(nanoseconds: 60_000_000_000)
                case .refusing: throw CancellationError()
                case .none: break
                }
                return try JSONEncoder().encode([SearchHit]())
            case .descriptions:
                return try JSONEncoder().encode([String: String]())
            default:
                return Data()
            }
        }
    }

    private struct Reading {
        let spinners: Int
        let picture: Data?
    }

    private func searched(_ answer: Catalogue.Answer) async -> Reading {
        let transport = Catalogue(answer)
        let mvm = ModuleViewModel(transport: transport)
        let hb = HomebrewViewModel.shared(vm: mvm)
        let mount = MountedRender(HomebrewSettingsPage(vm: mvm),
                                  width: 984, height: 520, appearance: .aqua)
        let loading = Task { @MainActor in await hb.loadIfNeeded() }
        hb.segment = .search
        func turn(_ times: Int) async {
            for _ in 0..<times {
                mount.host.layoutSubtreeIfNeeded()
                try? await Task.sleep(nanoseconds: 4_000_000)
            }
        }
        await turn(20)
        // The page's `query` is its own `@State`, so the word has to arrive the
        // way a person types it: through the field the page asked the window
        // for.
        XCTAssertTrue(mount.type("cad"), """
            the search segment put no field in the window's toolbar, so nothing below is \
            measured — every reading after this would be taken from a page nobody typed into
            """)
        let searching = Task { @MainActor in await hb.search("cad") }
        await turn(60)
        let spinners = mount.host.everyView(ofType: NSProgressIndicator.self).count
        // The results area alone is what these three readings are a claim about
        // (`RenderedInk.bytes`); the head of the file says why it starts where
        // it does.
        let picture = mount.pixels(40...380)
        mount.drop()
        _ = loading
        _ = searching
        withExtendedLifetime(transport) {}
        return Reading(spinners: spinners, picture: picture)
    }

    /// Three answers, three drawings — and the wait is the only one that moves.
    func testTheNineSecondsSayTheyAreNineSeconds() async {
        let waiting = await searched(.hanging)
        let none = await searched(.none)
        let refused = await searched(.refusing)

        XCTAssertGreaterThan(waiting.spinners, 0, """
            a `brew search` is out and nothing on the page moves — which is nine seconds of \
            «No results.» over a question still being asked
            """)
        XCTAssertEqual(none.spinners, 0, "an answered search with no hits is not something to wait for")
        XCTAssertEqual(refused.spinners, 0, "a refused search is not something to wait for")

        XCTAssertNotNil(waiting.picture)
        XCTAssertNotEqual(waiting.picture, none.picture, """
            the search that is running and the search that found nothing are one drawing
            """)
        XCTAssertNotEqual(none.picture, refused.picture, """
            «No results.» and a refusal are one drawing, so the app answers a question that was \
            never put
            """)
    }
}
