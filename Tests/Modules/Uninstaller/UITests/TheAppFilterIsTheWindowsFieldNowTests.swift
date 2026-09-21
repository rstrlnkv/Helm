import AppKit
import HelmTestSupport
import HelmUI
import XCTest
import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// **The app filter narrows the list — read off the list, through the control a
/// person actually types into.**
///
/// This page's filter had no behavioural check at all, in either placement.
/// `AnEmptyAppsTabSaysWhichEmptinessTests` says why, and the sentence is worth
/// quoting because this file is the render it leaves room for: «the filtered
/// state is not reachable from here: the search term is the page's own `@State`
/// — deliberately, it is the one thing a person cannot retype — and a test
/// cannot write to that outside a render.» Every word of that still holds; what
/// is new is that the render exists. The term is still the page's own `@State`,
/// and the render is the way in: the field moved to the window's toolbar
/// (`helmSearchable`), `MountedRender.searchField` reads it off the window and
/// `MountedRender.type` posts the change notification SwiftUI's coordinator
/// listens for. So the one state nobody could reach is the one this file is
/// about.
///
/// **What it guards that the shared checks do not.**
/// `ASearchRunsOnReturnNotOnAKeyTests` proves `helmSearchable` moves a binding
/// per keystroke; `ASearchAsksBrewOnlyOnReturnTests` proves Homebrew wired its
/// press. Neither says a word about *this* page's `text: $search` — bind that
/// to some other piece of state, or leave `filtered` reading a term nothing
/// writes, and both of them stay green while the Uninstaller's filter does
/// nothing at all. The list is the only witness.
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

    private var mount: MountedRender?

    override func tearDown() {
        mount?.drop()
        mount = nil
        super.tearDown()
    }

    /// The page, its model and the mounted render, with the list already
    /// answered — an unanswered list draws a statement and no rows at all, and
    /// every count below would be zero for a reason that has nothing to do with
    /// the filter.
    private func page() async -> MountedRender {
        let wire = UninstallerWire(apps: Self.apps, answering: .reply)
        let vm = ModuleViewModel(transport: wire)
        let uvm = UninstallerViewModel.shared(vm: vm)
        await uvm.loadAppsIfNeeded()
        XCTAssertEqual(uvm.apps.count, Self.apps.count,
                       "precondition: the fixture's apps never reached the view model")
        let mount = MountedRender(UninstallerSettingsPage(vm: vm), width: 845, height: 700,
                                  appearance: .aqua)
        mount.settle(30)
        self.mount = mount
        return mount
    }

    /// One row of the Apps tab's `List`, whatever is drawn inside it.
    private func rows(_ mount: MountedRender) -> Int {
        mount.host.everyView.filter { $0.appKitClassName == "ListTableRowView" }.count
    }

    /// **Three rows, then one, then none — with nothing touched but the field.**
    func testTypingInTheWindowsFieldNarrowsThePagesList() async {
        let mount = await page()

        XCTAssertNotNil(mount.searchField, """
            the Apps tab put no search field in the window's toolbar, so nothing below is typed \
            into anything and every count is of a page nobody touched. That is the quiet way \
            this check dies: `helmSearchable` under `tab == 0 && step == .pick` reaching the \
            window is the whole wiring
            """)
        XCTAssertEqual(rows(mount), Self.apps.count, """
            precondition: the unfiltered list draws \(rows(mount)) rows for \
            \(Self.apps.count) apps, so a fall to one below would not be the filter
            """)

        XCTAssertTrue(mount.type("Alpha", turns: 30), "the field went away mid-word")
        XCTAssertEqual(rows(mount), 1, """
            «Alpha» left \(rows(mount)) of \(Self.apps.count) rows on the Apps tab. The field is \
            the window's toolbar's now and the term is still the page's `@State` — so either \
            `helmSearchable`'s binding is not `$search`, or `filtered` is reading something else
            """)

        XCTAssertTrue(mount.type("Zephyr", turns: 30), "the field went away")
        XCTAssertEqual(rows(mount), 0, """
            a term matching none of \(Self.apps.map(\.name)) still draws \(rows(mount)) rows — \
            the filter narrows and does not exclude, which is a list that answers a question \
            nobody asked
            """)

        XCTAssertTrue(mount.type("", turns: 30), "the field went away")
        XCTAssertEqual(rows(mount), Self.apps.count, """
            clearing the field left \(rows(mount)) of \(Self.apps.count) rows. Emptying a search \
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
        let mount = await page()
        XCTAssertNotNil(mount.searchField, "the Apps tab put no search field in the toolbar")

        XCTAssertTrue(mount.type(String(repeating: "a", count: 10_000), turns: 20),
                      "the field went away under a 10 000-character term")
        XCTAssertEqual(rows(mount), 0, """
            a 10 000-character term matched \(rows(mount)) of \(Self.apps.count) apps. Nothing on \
            this Mac is named that, so a row here is a filter that stopped filtering rather than \
            one that found something
            """)

        XCTAssertTrue(mount.type("alpha", turns: 30), "the field went away")
        XCTAssertEqual(rows(mount), 1, """
            «alpha» left \(rows(mount)) rows where «Alpha» is the app's name — the filter is \
            case-sensitive, so a person typing what they see on screen gets an empty list
            """)
        // Twice running, which posts the change notification over an unchanged
        // value: SwiftUI's binding withholds a write that changes nothing, and
        // a page that rebuilt its list from the notification rather than from
        // the value would show it here.
        XCTAssertTrue(mount.type("alpha", turns: 30), "the field went away on the repeat")
        XCTAssertEqual(rows(mount), 1, """
            typing the same term a second time left \(rows(mount)) rows where the first left 1. \
            The term did not change, so nothing about the list may
            """)

        XCTAssertTrue(mount.type("Альфа", turns: 30), "the field went away")
        XCTAssertEqual(rows(mount), 0, """
            «Альфа» matched \(rows(mount)) of \(Self.apps.map(\.name)) — the filter is answering \
            about something other than the name it was given
            """)
    }
}
