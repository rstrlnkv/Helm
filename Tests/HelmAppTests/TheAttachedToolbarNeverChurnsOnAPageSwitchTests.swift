import AppKit
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The two things `SettingsToolbar`'s per-page cache exists for, read off
/// the real window rather than off the source.**
///
/// Before this file, nothing under `Tests` ever built a `SettingsToolbar`, a
/// `SettingsModel` or a `HelmWindowToolbarChannel` together
/// (`command grep -rn "helmWindowToolbarChannel\|HelmWindowToolbarChannel\|SettingsToolbar\|helmWindowToolbar" Tests`
/// found nothing before this pass) — every guard on the toolbar bridge tested
/// the SwiftUI-era mechanism directly, which production no longer builds at
/// all.
///
/// Declares and withdraws go straight through the channel's own `declare` and
/// `withdraw`, bypassing SwiftUI entirely — this is a test of `SettingsToolbar`
/// and the channel's ownership rules, not of the `NSViewRepresentable` bridge
/// that calls them from a page's `body`, which `HelmWindowToolbar.swift`'s own
/// header already documents against three measured probes.
@MainActor
final class TheAttachedToolbarNeverChurnsOnAPageSwitchTests: XCTestCase {

    /// A struct rather than a tuple: `swiftlint`'s `large_tuple` rule caps a
    /// tuple at two members, and this fixture needs all four kept alive by
    /// the caller — `toolbar` above all, since `NSToolbar.delegate` and
    /// `HelmWindowToolbarChannel.onChange` both hold it only weakly.
    private struct Fixture {
        let toolbar: SettingsToolbar
        let model: SettingsModel
        let channel: HelmWindowToolbarChannel
        let window: NSWindow
    }

    private func makeToolbar() -> Fixture {
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let toolbar = SettingsToolbar(model: model, channel: channel)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        toolbar.window = window
        return Fixture(toolbar: toolbar, model: model, channel: channel, window: window)
    }

    private func content(hiddenID: String = "hidden", visibleID: String = "visible",
                         hiddenIsVisible: Bool = false) -> HelmPageToolbarContent {
        HelmPageToolbarContent(actions: [
            HelmToolbarAction(id: hiddenID, title: "Hidden Action", symbol: "eye.slash",
                              isVisible: hiddenIsVisible) {},
            HelmToolbarAction(id: visibleID, title: "Visible Action", symbol: "eye") {}
        ])
    }

    // MARK: - No grow animation on a return visit

    /// **The regression this whole pass exists to fix**: entering a page used
    /// to rewrite the one shared toolbar's `itemIdentifiers`, which AppKit
    /// animates every insertion of — the icons-grow-on-every-visit the owner
    /// reported. Selecting page A, then B, then A again must attach the exact
    /// same `NSToolbar` object A had before, with no `willAddItem` or
    /// `didRemoveItem` posted for it the second time — the same measurement
    /// the review's own probe took (`swap.swift`: "zero delegate calls").
    func testReturningToAPageReusesItsToolbarAndInsertsNothing() {
        let fixture = makeToolbar()
        let toolbar = fixture.toolbar, model = fixture.model
        let channel = fixture.channel, window = fixture.window

        model.selection = .module("test.pageA")
        channel.declare(content(), token: "test.pageA", generation: channel.nextGeneration())
        let firstToolbar = window.toolbar
        XCTAssertNotNil(firstToolbar, "page A never got a toolbar at all")

        model.selection = .module("test.pageB")
        channel.declare(content(hiddenID: "b.hidden", visibleID: "b.visible"),
                        token: "test.pageB", generation: channel.nextGeneration())
        XCTAssertNotIdentical(window.toolbar, firstToolbar, "page B is showing page A's own toolbar object")

        var added: [Notification] = []
        var removed: [Notification] = []
        let addObserver = NotificationCenter.default.addObserver(
            forName: NSToolbar.willAddItemNotification, object: nil, queue: nil) { added.append($0) }
        let removeObserver = NotificationCenter.default.addObserver(
            forName: NSToolbar.didRemoveItemNotification, object: nil, queue: nil) { removed.append($0) }
        defer {
            NotificationCenter.default.removeObserver(addObserver)
            NotificationCenter.default.removeObserver(removeObserver)
        }

        model.selection = .module("test.pageA")

        XCTAssertIdentical(window.toolbar, firstToolbar, """
            returning to page A attached a different toolbar object — the cache in \
            SettingsToolbar.pageBars did not reuse the one A already had
            """)
        XCTAssertEqual(added.count, 0, """
            \(added.count) willAddItem notification(s) fired on the return visit — an attached \
            toolbar had its items rewritten, which is the grow animation itself
            """)
        XCTAssertEqual(removed.count, 0, """
            \(removed.count) didRemoveItem notification(s) fired on the return visit — same \
            defect, the other direction
            """)
        _ = toolbar
    }

    // MARK: - A hidden action

    /// **Owner item (C), restated for the one-item action capsule
    /// (`HelmToolbarActionsCapsule`) that replaced one plain `NSToolbarItem`
    /// per action: a hidden action leaves the capsule and its menu form,
    /// while `itemIdentifiers` stays equal across the flip.** There is only
    /// ever one `helm.actions` item now, so "stays in the identifier list"
    /// is trivially true of it; what has to be checked instead is that the
    /// *declared* set — read through `menuFormRepresentation`, the floor
    /// AppKit falls back to when the capsule itself overflows — is what
    /// actually moves, and that the bar's own identifier list does not.
    func testAHiddenActionLeavesTheCapsuleAndItsMenuFormWhileIdentifiersStayEqual() {
        // `toolbar` is kept, not discarded: `NSToolbar.delegate` is weak
        // (`NSToolbar.h`) and `channel.onChange` captures it weakly too, so
        // a discarded `SettingsToolbar` deallocates the instant `makeToolbar`
        // returns and every call below becomes a no-op against a dead object
        // — measured by writing this test wrong first, which read back the
        // toolbar's own construction-time state and nothing this test did.
        let fixture = makeToolbar()
        let toolbar = fixture.toolbar, model = fixture.model
        let channel = fixture.channel, window = fixture.window

        model.selection = .module("test.pageC")
        channel.declare(content(hiddenIsVisible: false), token: "test.pageC",
                        generation: channel.nextGeneration())

        guard let bar = window.toolbar else { return XCTFail("page C never got a toolbar") }
        let identifiersBefore = bar.itemIdentifiers
        guard let actionsItem = bar.items.first(where: { $0.itemIdentifier.rawValue == "helm.actions" })
        else {
            return XCTFail("no single actions item in \(bar.items.map(\.itemIdentifier.rawValue))")
        }

        XCTAssertEqual(actionsItem.menuFormRepresentation?.title, "Visible Action", """
            with the hidden action out of the capsule, the overflow menu form should name the \
            one remaining action rather than \(actionsItem.menuFormRepresentation?.title ?? "nothing")
            """)

        // Flip it live, the way Homebrew's own segment switch does.
        channel.declare(content(hiddenIsVisible: true), token: "test.pageC",
                        generation: channel.nextGeneration())
        XCTAssertEqual(bar.itemIdentifiers, identifiersBefore, """
            the identifier list moved when a hidden action became visible — one capsule item's \
            own declared set is what sizes its reserve, and the bar's identifiers must not care
            """)
        XCTAssertEqual(actionsItem.menuFormRepresentation?.submenu?.items.count, 2, """
            with both actions visible, the menu form should be a submenu naming both, not \
            \(String(describing: actionsItem.menuFormRepresentation?.submenu?.items.count))
            """)
        _ = toolbar
    }

    // MARK: - A module switched off while its own page is showing falls back

    /// **Defect this pass's own review found**: `refresh()` used to arm the
    /// grace period only on a genuine selection change, so a module switched
    /// off while *its own* page stayed the one on screen never fell back to
    /// name-only at all — contradicting this class's own header, which
    /// promises the fallback for exactly that case. `"test.pageD"` is never a
    /// real, live module — `ModuleHost.shared.liveModule(_:)` answers `nil`
    /// for it, the same answer a module actually switched off gets
    /// (`isModuleSwitchedOff()`) — so withdrawing its declaration with no
    /// selection change exercises that path directly.
    ///
    /// This also covers the second half of the same finding: once the grace
    /// period has spent itself and the bar has fallen back, a later,
    /// non-selection refresh (a language change, here) must not re-attach the
    /// stale bar just because `refresh()` ran again (`fellBackToNameOnly`).
    func testAModuleSwitchedOffWhileItsPageIsShowingFallsBackToNameOnly() {
        let fixture = makeToolbar()
        let model = fixture.model, channel = fixture.channel, window = fixture.window
        let savedInterval = SettingsToolbar.graceInterval
        SettingsToolbar.graceInterval = 0.02
        defer { SettingsToolbar.graceInterval = savedInterval }

        model.selection = .module("test.pageD")
        let generation = channel.nextGeneration()
        channel.declare(content(), token: "test.pageD", generation: generation)
        let liveBar = window.toolbar
        XCTAssertNotNil(liveBar, "page D never got a toolbar while declaring")

        channel.withdraw(token: "test.pageD", generation: generation)
        XCTAssertIdentical(window.toolbar, liveBar, """
            the bar changed the instant the withdraw landed — it should stay frozen, showing \
            the last-known content, until the grace period decides nothing more is coming
            """)

        let graceRanOut = expectation(description: "grace period runs out")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { graceRanOut.fulfill() }
        wait(for: [graceRanOut], timeout: 2)

        XCTAssertNotIdentical(window.toolbar, liveBar, """
            the frozen bar is still attached after the grace period ran out with nothing \
            redeclared — a module switched off while its own page was showing must fall back \
            to the shared name-only toolbar, per this class's own header
            """)

        let nameOnlyBar = window.toolbar
        NotificationCenter.default.post(name: .helmLanguageChanged, object: nil)
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        XCTAssertIdentical(window.toolbar, nameOnlyBar, """
            a language change re-attached page D's stale bar after it had already fallen back \
            to name-only — fellBackToNameOnly should have kept it on the shared bar
            """)
    }

    // MARK: - A frozen bar drops what its live closures captured

    /// **The retention this pass's own review found**: `PageBar.content` kept
    /// whatever a live declaration's closures had captured — a page's own
    /// view model, in production — even after the bar froze, because nothing
    /// ever replaced it with something closure-free. `[captured]` forces the
    /// action's closure to hold its own strong reference at declare time,
    /// independent of the local `var` this test clears right after — so
    /// `weakCaptured` surviving past that point can only mean something
    /// *else* still holds it, and after a withdraw the only remaining
    /// candidate is `SettingsToolbar` itself.
    func testAFrozenBarDropsTheClosuresItsContentCaptured() {
        final class Captured {}
        let fixture = makeToolbar()
        let model = fixture.model, channel = fixture.channel

        var captured: Captured? = Captured()
        weak var weakCaptured = captured

        model.selection = .module("test.pageE")
        let generation = channel.nextGeneration()
        channel.declare(HelmPageToolbarContent(actions: [
            HelmToolbarAction(id: "x", title: "X", symbol: "x.circle") { [captured] in _ = captured }
        ]), token: "test.pageE", generation: generation)
        captured = nil
        XCTAssertNotNil(weakCaptured, "precondition: the declared closure was not the object's own copy")

        channel.withdraw(token: "test.pageE", generation: generation)

        XCTAssertNil(weakCaptured, """
            the object a live action's closure captured is still alive after withdraw — the \
            frozen bar kept the live closure instead of a closure-free copy of its content, \
            which is how a switched-off module's view model outlives its own cache for the \
            rest of the session
            """)
        _ = model
    }
}
