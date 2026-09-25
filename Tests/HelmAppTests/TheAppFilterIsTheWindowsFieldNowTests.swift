import AppKit
import HelmContract
import HelmTestSupport
import HelmUI
import XCTest
import Module_Uninstaller_Engine
@testable import HelmApp
@testable import Module_Uninstaller_UI

/// **The app filter narrows the list — read off the list, through the control a
/// person actually types into.**
///
/// **Moved here 2026-09-24, from `Tests/Modules/Uninstaller/UITests`, when
/// `UninstallerSettingsPage` moved off `.helmSearchable` onto
/// `.helmWindowToolbar`.** The field lives in the window's own `NSToolbar`
/// now (`SettingsToolbar`, `HelmApp`-only — `LivePageToolbarFixture`'s own
/// header says why a module's own `UITests` target has no way to build one),
/// so a check that types into it has to live where that toolbar can be built:
/// `Tests/HelmAppTests`, per `CLAUDE.md`'s own "put a check for the app
/// layer in `Tests/HelmAppTests`, since the host does take a test target and
/// there is no reason to move code out of it to reach one." `UninstallerWire`,
/// the engine double the original file drove, is a fixture private to
/// `Module_Uninstaller_UITests` and cannot cross that boundary either — the
/// inline `AppsStub` below answers the one command this file needs
/// (`.listApps`) and nothing else.
///
/// **What it guards that the shared checks do not.**
/// `ASearchRunsOnReturnNotOnAKeyTests` proves a declared search's binding
/// moves per keystroke; `ATypedWordAsksBrewAfterAPauseTests` proves
/// Homebrew wired its own field the same way. Neither says a word about
/// *this* page's `text: $search` — bind that to some other piece of state, or
/// leave `filtered` reading a term nothing writes, and both of them stay
/// green while the Uninstaller's filter does nothing at all. The list is the
/// only witness.
///
/// **The rows are counted and never the pixels.** `ListTableRowView` is one per
/// row of the `List` the Apps tab draws, so 3, 1 and 0 are three different
/// structures rather than three different drawings — a pixel comparison of the
/// same three states would also pass over a list that redrew for any other
/// reason, and over one that drew the same rows in a different order.
@MainActor
final class TheAppFilterIsTheWindowsFieldNowTests: XCTestCase {

    /// Three names with nothing in common, so a filter that matches one cannot
    /// be a filter that matched a shared substring.
    private static let apps = [
        InstalledApp(name: "Alpha", bundleID: "com.example.alpha",
                     path: "/Applications/Alpha.app", sizeBytes: 4_096),
        InstalledApp(name: "Bravo", bundleID: "com.example.bravo",
                     path: "/Applications/Bravo.app", sizeBytes: 4_096),
        InstalledApp(name: "Charlie", bundleID: "com.example.charlie",
                     path: "/Applications/Charlie.app", sizeBytes: 4_096),
    ]

    /// Answers `.listApps` with a fixed list and everything else with empty
    /// `Data` — the same "the module could not answer" spelling
    /// `UninstallerWire` uses, without carrying the rest of that fixture's
    /// state, which this file never needs.
    private final class AppsStub: EngineTransport, @unchecked Sendable {
        var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }
        private let apps: [InstalledApp]
        init(apps: [InstalledApp]) { self.apps = apps }
        func send(_ command: EngineCommand) async throws -> Data {
            guard UninstallerCommand(rawValue: command.name) == .listApps else { return Data() }
            return (try? JSONEncoder().encode(apps)) ?? Data()
        }
    }

    private var fixture: LivePageToolbarFixture?

    override func tearDown() {
        fixture?.drop()
        fixture = nil
        super.tearDown()
    }

    /// The page, its model and the mounted, attached toolbar, with the list
    /// already answered — an unanswered list draws a statement and no rows at
    /// all, and every count below would be zero for a reason that has nothing
    /// to do with the filter.
    private func page() async -> LivePageToolbarFixture {
        let transport = AppsStub(apps: Self.apps)
        let vm = ModuleViewModel(transport: transport)
        let uvm = UninstallerViewModel.shared(vm: vm)
        await uvm.loadAppsIfNeeded()
        XCTAssertEqual(uvm.apps.count, Self.apps.count,
                       "precondition: the fixture's apps never reached the view model")
        let fixture = LivePageToolbarFixture(UninstallerSettingsPage(vm: vm),
                                             selection: .module(UninstallerDescriptor.id.rawValue),
                                             width: 845, height: 700)
        fixture.settle(30)
        self.fixture = fixture
        return fixture
    }

    /// One row of the Apps tab's `List`, whatever is drawn inside it.
    private func rows(_ fixture: LivePageToolbarFixture) -> Int {
        fixture.mount.host.everyView.filter { $0.appKitClassName == "ListTableRowView" }.count
    }

    /// **Three rows, then one, then none — with nothing touched but the field.**
    func testTypingInTheWindowsFieldNarrowsThePagesList() async {
        let fixture = await page()

        XCTAssertNotNil(fixture.mount.searchField, """
            the Apps tab put no search field in the window's toolbar, so nothing below is typed \
            into anything and every count is of a page nobody touched. That is the quiet way \
            this check dies: `toolbarContent`'s `search:` not reaching the window at all is the \
            whole wiring
            """)
        XCTAssertEqual(rows(fixture), Self.apps.count, """
            precondition: the unfiltered list draws \(rows(fixture)) rows for \
            \(Self.apps.count) apps, so a fall to one below would not be the filter
            """)

        XCTAssertTrue(fixture.mount.type("Alpha", turns: 30), "the field went away mid-word")
        XCTAssertEqual(rows(fixture), 1, """
            «Alpha» left \(rows(fixture)) of \(Self.apps.count) rows on the Apps tab. The field is \
            the window's toolbar's now and the term is still the page's `@State` — so either \
            `toolbarContent`'s `search` binding is not `$search`, or `filtered` is reading \
            something else
            """)

        XCTAssertTrue(fixture.mount.type("Zephyr", turns: 30), "the field went away")
        XCTAssertEqual(rows(fixture), 0, """
            a term matching none of \(Self.apps.map(\.name)) still draws \(rows(fixture)) rows — \
            the filter narrows and does not exclude, which is a list that answers a question \
            nobody asked
            """)

        XCTAssertTrue(fixture.mount.type("", turns: 30), "the field went away")
        XCTAssertEqual(rows(fixture), Self.apps.count, """
            clearing the field left \(rows(fixture)) of \(Self.apps.count) rows. Emptying a search \
            is how a person gets the whole list back, and there is no other control on this page \
            that does it
            """)
    }

    /// **The inputs a person is not supposed to give it.**
    ///
    /// A term longer than any name on any Mac, the same term twice running, and
    /// a term in a case and an alphabet the list is not written in. None of
    /// them is exotic — a paste is the first, a double keystroke the second,
    /// and this Mac runs in Russian — and the filter is a `localizedCase‑
    /// InsensitiveContains` over names the engine hands over, so all three go
    /// straight into Foundation.
    func testTheFilterSurvivesAnEmptyAHugeAndARepeatedTerm() async {
        let fixture = await page()
        XCTAssertNotNil(fixture.mount.searchField, "the Apps tab put no search field in the toolbar")

        XCTAssertTrue(fixture.mount.type(String(repeating: "a", count: 10_000), turns: 20),
                      "the field went away under a 10 000-character term")
        XCTAssertEqual(rows(fixture), 0, """
            a 10 000-character term matched \(rows(fixture)) of \(Self.apps.count) apps. Nothing on \
            this Mac is named that, so a row here is a filter that stopped filtering rather than \
            one that found something
            """)

        XCTAssertTrue(fixture.mount.type("alpha", turns: 30), "the field went away")
        XCTAssertEqual(rows(fixture), 1, """
            «alpha» left \(rows(fixture)) rows where «Alpha» is the app's name — the filter is \
            case-sensitive, so a person typing what they see on screen gets an empty list
            """)
        // Twice running, which posts the change notification over an unchanged
        // value: SwiftUI's binding withholds a write that changes nothing, and
        // a page that rebuilt its list from the notification rather than from
        // the value would show it here.
        XCTAssertTrue(fixture.mount.type("alpha", turns: 30), "the field went away on the repeat")
        XCTAssertEqual(rows(fixture), 1, """
            typing the same term a second time left \(rows(fixture)) rows where the first left 1. \
            The term did not change, so nothing about the list may
            """)

        XCTAssertTrue(fixture.mount.type("Альфа", turns: 30), "the field went away")
        XCTAssertEqual(rows(fixture), 0, """
            «Альфа» matched \(rows(fixture)) of \(Self.apps.map(\.name)) — the filter is answering \
            about something other than the name it was given
            """)
    }
}
