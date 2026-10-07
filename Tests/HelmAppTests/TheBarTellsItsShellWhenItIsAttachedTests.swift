import AppKit
@testable import HelmUI
import XCTest
@testable import HelmApp

/// **A `SettingsToolbar` calls `barAttached` when the window takes a bar it was not showing, and only then;
/// a bar whose shape changed (a spacer came or went) replaces the window's bar, a bar whose spacer only
/// changed width does not.** The window here is never ordered front or back, made key or activated
/// (`NSWindow(contentRect:styleMask:backing:defer: true)`, `isReleasedWhenClosed = false`), and its toolbar
/// is taken off at the end of each test.
///
/// The negative, a toolbar with no window never calling `barAttached`, is in
/// `TheToolbarLeadsWithWhatItsShellGivesTests`.
@MainActor
final class TheBarTellsItsShellWhenItIsAttachedTests: XCTestCase {

    private func unshownWindow() -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1060, height: 700),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        return window
    }

    /// The width constraint of the item's view, the one the toolbar keeps to size the spacer.
    private func widthConstant(of item: NSToolbarItem?) -> CGFloat? {
        item?.view?.constraints.first { $0.firstAttribute == .width && $0.secondItem == nil }?.constant
    }

    /// Total failure prints: "barAttached was called <n> times when the window took its first bar, not once: the
    /// shell is not told the window took a bar" / "barAttached was called again for the bar already on screen:
    /// <n> calls in all, the shell is told again for nothing" / "barAttached was called <n> times after a spacer
    /// came, not twice: the window took a new bar and the shell was not told".
    func testBarAttachedIsCalledOnceForABarThatWasNotShowingAndNotForTheSameBarAgain() {
        var calls = 0
        let model = SettingsModel(host: ModuleHost.shared)
        let toolbar = SettingsToolbar(model: model, channel: HelmWindowToolbarChannel(), lead: .spacer,
                                      barAttached: { calls += 1 })
        let window = unshownWindow()
        defer { window.toolbar = nil }
        toolbar.window = window
        XCTAssertEqual(calls, 1,
                       "barAttached was called \(calls) times when the window took its first bar, not once: the shell is not told the window took a bar")
        model.selection = .general
        XCTAssertEqual(calls, 1,
                       "barAttached was called again for the bar already on screen: \(calls) calls in all, the shell is told again for nothing")
        toolbar.paneMoved(leading: 200, width: 856)
        XCTAssertEqual(calls, 2,
                       "barAttached was called \(calls) times after a spacer came, not twice: the window took a new bar and the shell was not told")
    }

    /// The mutant this test must catch: `hasSpacer` taken out of the cache key (`ShapeSignature`).
    /// Total failure prints: "the window took no toolbar" / "the window lost its toolbar when the pane was told" /
    /// "the window kept the bar built before the pane was known: no spacer at sidebar 200" (also with "; first item
    /// <id>") / "the spacer item's width is <w>, not 123.5 at sidebar 200" / "a moved width replaced the window's
    /// bar: a settle would restart the bar for every pixel of a drag" / "the spacer stayed <w> after the pane moved
    /// to 260, not 183.5: the cache key knows only yes or no" / "the window lost its toolbar at the rail" / "the
    /// window kept the spacer bar at the rail: the name lands past where the bar could put it" / "the bar at the
    /// rail still opens with the spacer".
    func testAFlipPutsAFreshBarOnTheWindowAndAMovedWidthDoesNot() throws {
        let model = SettingsModel(host: ModuleHost.shared)
        let toolbar = SettingsToolbar(model: model, channel: HelmWindowToolbarChannel(), lead: .spacer)
        let window = unshownWindow()
        defer { window.toolbar = nil }
        toolbar.window = window
        let before = try XCTUnwrap(window.toolbar, "the window took no toolbar")

        toolbar.paneMoved(leading: 200, width: 856)
        let withSpacer = try XCTUnwrap(window.toolbar, "the window lost its toolbar when the pane was told")
        XCTAssertFalse(withSpacer === before,
                       "the window kept the bar built before the pane was known: no spacer at sidebar 200")
        XCTAssertEqual(withSpacer.items.first?.itemIdentifier.rawValue, "helm.leadingSpacer",
                       "the window kept the bar built before the pane was known: no spacer at sidebar 200; first item \(String(describing: withSpacer.items.first?.itemIdentifier.rawValue))")
        XCTAssertEqual(widthConstant(of: withSpacer.items.first) ?? -1, 123.5, accuracy: 0.0001,
                       "the spacer item's width is \(String(describing: widthConstant(of: withSpacer.items.first))), not 123.5 at sidebar 200")

        toolbar.paneMoved(leading: 260, width: 796)
        XCTAssertTrue(window.toolbar === withSpacer,
                      "a moved width replaced the window's bar: a settle would restart the bar for every pixel of a drag")
        XCTAssertEqual(widthConstant(of: window.toolbar?.items.first) ?? -1, 183.5, accuracy: 0.0001,
                       "the spacer stayed \(String(describing: widthConstant(of: window.toolbar?.items.first))) after the pane moved to 260, not 183.5: the cache key knows only yes or no")

        toolbar.paneMoved(leading: 56, width: 1000)
        let rail = try XCTUnwrap(window.toolbar, "the window lost its toolbar at the rail")
        XCTAssertFalse(rail === withSpacer,
                       "the window kept the spacer bar at the rail: the name lands past where the bar could put it")
        XCTAssertNotEqual(rail.items.first?.itemIdentifier.rawValue, "helm.leadingSpacer",
                          "the bar at the rail still opens with the spacer")
    }

    /// The mutant this test must catch: `show()` no longer writing the current width into a cached bar's
    /// constraint. The bar of one page is cached while another page is on the window; the pane moves; the first
    /// page comes back. Total failure prints: "the cached bar came back with a spacer of <w>, not 183.5: the
    /// bar was built at sidebar 200 and nobody told it the pane moved while it was off the window".
    func testACachedBarComesBackWithTheSpacerOfNowNotOfWhenItWasLeft() throws {
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let toolbar = SettingsToolbar(model: model, channel: channel, lead: .spacer)
        let window = unshownWindow()
        defer { window.toolbar = nil }
        toolbar.window = window
        channel.declare(HelmPageToolbarContent(actions: [
            HelmToolbarAction(id: "other", title: "Other", symbol: "bolt") {}
        ]), token: "about", generation: channel.nextGeneration())

        toolbar.paneMoved(leading: 200, width: 856)
        let generalBar = try XCTUnwrap(window.toolbar, "no bar for General")
        XCTAssertEqual(widthConstant(of: generalBar.items.first) ?? -1, 123.5, accuracy: 0.0001,
                       "the fixture is wrong: General's bar has no spacer of 123.5")
        model.selection = .about
        let aboutBar = try XCTUnwrap(window.toolbar, "no bar for About")
        XCTAssertFalse(aboutBar === generalBar, "the fixture is wrong: About shows General's bar")
        toolbar.paneMoved(leading: 260, width: 796)
        model.selection = .general
        XCTAssertTrue(window.toolbar === generalBar, "the fixture is wrong: General's bar was not kept")
        XCTAssertEqual(widthConstant(of: window.toolbar?.items.first) ?? -1, 183.5, accuracy: 0.0001,
                       "the cached bar came back with a spacer of \(String(describing: widthConstant(of: window.toolbar?.items.first))), not 183.5: the bar was built at sidebar 200 and nobody told it the pane moved while it was off the window")
    }

    /// `readItemsStart()` reads only a window that is visible. On this one it never is, so
    /// `itemsStart` stays the seed after a flip, after a resize and after a layout, and the spacer is the seed's.
    /// (An unshown window's name view read 879.5; stored, it would make the spacer nil.) Total failure prints:
    /// "itemsStart moved to <x> on a window nobody showed: a toolbar nothing laid out answered" / "the spacer is
    /// <w>, not 183.5 from the seed".
    func testAnUnshownWindowNeverMovesWhereTheItemsStart() {
        let toolbar = SettingsToolbar(model: SettingsModel(host: ModuleHost.shared),
                                      channel: HelmWindowToolbarChannel(), lead: .spacer)
        let window = unshownWindow()
        defer { window.toolbar = nil }
        toolbar.window = window
        toolbar.paneMoved(leading: 200, width: 856)
        window.layoutIfNeeded()
        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: window)
        NotificationCenter.default.post(name: NSWindow.didEndLiveResizeNotification, object: window)
        toolbar.paneMoved(leading: 260, width: 796)
        XCTAssertEqual(toolbar.itemsStart, SettingsToolbar.itemsStartSeed, accuracy: 0.0001,
                       "itemsStart moved to \(toolbar.itemsStart) on a window nobody showed: a toolbar nothing laid out answered")
        XCTAssertEqual(toolbar.leadingSpacer ?? -1, 183.5, accuracy: 0.0001,
                       "the spacer is \(String(describing: toolbar.leadingSpacer)), not 183.5 from the seed")
    }

    /// A window that goes away between two reports: the report still stores and flips, and attaches nothing;
    /// the window that comes back takes the bar of now, and the shell is told once. Total failure prints:
    /// "barAttached was called <n> times in all, the report with no window told the shell of a bar nobody assigned" /
    /// "barAttached was called <n> times after the window came back, not twice: the shell was not told of the bar
    /// the window took".
    func testAReportWhileTheWindowIsGoneAttachesNothingAndTheReturnAttachesTheNewBarOnce() throws {
        var calls = 0
        let toolbar = SettingsToolbar(model: SettingsModel(host: ModuleHost.shared),
                                      channel: HelmWindowToolbarChannel(), lead: .spacer,
                                      barAttached: { calls += 1 })
        let window = unshownWindow()
        defer { window.toolbar = nil }
        toolbar.window = window
        XCTAssertEqual(calls, 1, "the fixture is wrong: the first bar was not announced")
        toolbar.window = nil
        XCTAssertTrue(toolbar.paneMoved(leading: 200, width: 856), "a report with no window was refused")
        XCTAssertTrue(toolbar.hasSpacer, "a report with no window did not flip the bar")
        XCTAssertEqual(calls, 1,
                       "barAttached was called \(calls) times in all, the report with no window told the shell of a bar nobody assigned")
        toolbar.window = window
        XCTAssertEqual(calls, 2,
                       "barAttached was called \(calls) times after the window came back, not twice: the shell was not told of the bar the window took")
        let bar = try XCTUnwrap(window.toolbar, "the returning window took no bar")
        XCTAssertEqual(bar.items.first?.itemIdentifier.rawValue, "helm.leadingSpacer",
                       "the returning window kept the bar built before the report")
    }

    /// A receiver that reaches the pane synchronously, from inside `barAttached`.
    private final class Receiver {
        weak var toolbar: SettingsToolbar?
        var calls = 0
        var onCall: ((SettingsToolbar, Int) -> Void)?
    }

    private func toolbar(lead: SettingsToolbar.Lead = .spacer, receiver: Receiver,
                         model: SettingsModel = SettingsModel(host: ModuleHost.shared),
                         channel: HelmWindowToolbarChannel = HelmWindowToolbarChannel()) -> SettingsToolbar {
        let made = SettingsToolbar(model: model, channel: channel, lead: lead, barAttached: { [unowned receiver] in
            receiver.calls += 1
            if let toolbar = receiver.toolbar { receiver.onCall?(toolbar, receiver.calls) }
        })
        receiver.toolbar = made
        return made
    }

    /// The first report arrives from inside the first `barAttached` and flips the bar. Total failure prints:
    /// "the first bar was never announced" / "barAttached was called <n> times, the nesting did not end" /
    /// "the window took no toolbar" / "the window's bar opens with <id>, not the spacer: a report from inside barAttached left the window the bar
    /// built before it" / "the spacer item's width is <w>, not 123.5 at sidebar 200" / "a later report did not
    /// reach the bar on the window: the spacer is <w>, not 183.5" / "a later report replaced the window's bar".
    func testAReportFromInsideBarAttachedThatFlipsLeavesTheNewBarOnTheWindowAndLaterReportsReachIt() throws {
        let receiver = Receiver()
        receiver.onCall = { toolbar, call in
            if call == 1 { toolbar.paneMoved(leading: 200, width: 856) }
        }
        let toolbar = toolbar(receiver: receiver)
        let window = unshownWindow()
        defer { window.toolbar = nil }
        toolbar.window = window
        XCTAssertGreaterThan(receiver.calls, 0, "the first bar was never announced")
        XCTAssertLessThanOrEqual(receiver.calls, 2,
                                 "barAttached was called \(receiver.calls) times, the nesting did not end")
        let bar = try XCTUnwrap(window.toolbar, "the window took no toolbar")
        XCTAssertEqual(bar.items.first?.itemIdentifier.rawValue, "helm.leadingSpacer",
                       "the window's bar opens with \(String(describing: bar.items.first?.itemIdentifier.rawValue)), not the spacer: a report from inside barAttached left the window the bar built before it")
        XCTAssertEqual(widthConstant(of: bar.items.first) ?? -1, 123.5, accuracy: 0.0001,
                       "the spacer item's width is \(String(describing: widthConstant(of: bar.items.first))), not 123.5 at sidebar 200")
        toolbar.paneMoved(leading: 260, width: 796)
        XCTAssertTrue(window.toolbar === bar, "a later report replaced the window's bar")
        XCTAssertEqual(widthConstant(of: window.toolbar?.items.first) ?? -1, 183.5, accuracy: 0.0001,
                       "a later report did not reach the bar on the window: the spacer is \(String(describing: widthConstant(of: window.toolbar?.items.first))), not 183.5")
    }

    /// The bar is already spaced; a page switch takes a bar of another page, and from inside `barAttached` a
    /// report moves only the width. Total failure prints: "the bar on the window has a spacer of <w>, not 183.5:
    /// the report from inside barAttached reached the bar that was left" / "the bar that was left took the report: its
    /// spacer is <w>, not 123.5".
    func testAWidthReportFromInsideBarAttachedOnAPageSwitchLandsOnTheBarNowOnTheWindow() throws {
        let receiver = Receiver()
        let channel = HelmWindowToolbarChannel()
        let model = SettingsModel(host: ModuleHost.shared)
        let toolbar = toolbar(receiver: receiver, model: model, channel: channel)
        let window = unshownWindow()
        defer { window.toolbar = nil }
        toolbar.window = window
        channel.declare(HelmPageToolbarContent(actions: [
            HelmToolbarAction(id: "other", title: "Other", symbol: "bolt") {}
        ]), token: "about", generation: channel.nextGeneration())
        toolbar.paneMoved(leading: 200, width: 856)
        let generalBar = try XCTUnwrap(window.toolbar, "no bar for General")
        XCTAssertEqual(widthConstant(of: generalBar.items.first) ?? -1, 123.5, accuracy: 0.0001,
                       "the fixture is wrong: General's bar has no spacer of 123.5")
        let before = receiver.calls
        receiver.onCall = { toolbar, _ in toolbar.paneMoved(leading: 260, width: 796) }
        model.selection = .about
        let aboutBar = try XCTUnwrap(window.toolbar, "no bar for About")
        XCTAssertFalse(aboutBar === generalBar, "the fixture is wrong: About shows General's bar")
        XCTAssertGreaterThan(receiver.calls, before, "the fixture is wrong: the page switch announced nothing")
        XCTAssertEqual(widthConstant(of: aboutBar.items.first) ?? -1, 183.5, accuracy: 0.0001,
                       "the bar on the window has a spacer of \(String(describing: widthConstant(of: aboutBar.items.first))), not 183.5: the report from inside barAttached reached the bar that was left")
        XCTAssertEqual(widthConstant(of: generalBar.items.first) ?? -1, 123.5, accuracy: 0.0001,
                       "the bar that was left took the report: its spacer is \(String(describing: widthConstant(of: generalBar.items.first))), not 123.5")
    }

    /// A flip from inside `barAttached`, on a page switch: the bar is at the rail without a spacer, the page switches, and from inside
    /// `barAttached` the pane is told it is at 200. Total failure prints: "the fixture is wrong: the rail's bar
    /// has a spacer" / "the window took no toolbar" / "the window's bar opens with <id>, not the spacer: the flip from inside barAttached left
    /// the window the bar of the page switch" / "the spacer item's width is <w>, not 123.5 at sidebar 200" /
    /// "a later report did not reach the bar on the window: the spacer is <w>, not 183.5" / "barAttached was called
    /// <n> times for one page switch and one flip, the nesting did not end".
    func testAFlipFromInsideBarAttachedOnAPageSwitchLeavesTheNewBarOnTheWindow() throws {
        let receiver = Receiver()
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let toolbar = toolbar(receiver: receiver, model: model, channel: channel)
        let window = unshownWindow()
        defer { window.toolbar = nil }
        toolbar.window = window
        channel.declare(HelmPageToolbarContent(actions: [
            HelmToolbarAction(id: "other", title: "Other", symbol: "bolt") {}
        ]), token: "about", generation: channel.nextGeneration())
        toolbar.paneMoved(leading: 56, width: 1000)
        XCTAssertFalse(toolbar.hasSpacer, "the fixture is wrong: the rail's bar has a spacer")
        let before = receiver.calls
        receiver.onCall = { toolbar, _ in toolbar.paneMoved(leading: 200, width: 856) }
        model.selection = .about
        XCTAssertGreaterThan(receiver.calls, before, "the fixture is wrong: the page switch announced nothing")
        XCTAssertLessThanOrEqual(receiver.calls - before, 2,
                                 "barAttached was called \(receiver.calls - before) times for one page switch and one flip, the nesting did not end")
        let bar = try XCTUnwrap(window.toolbar, "the window took no toolbar")
        XCTAssertEqual(bar.items.first?.itemIdentifier.rawValue, "helm.leadingSpacer",
                       "the window's bar opens with \(String(describing: bar.items.first?.itemIdentifier.rawValue)), not the spacer: the flip from inside barAttached left the window the bar of the page switch")
        XCTAssertEqual(widthConstant(of: bar.items.first) ?? -1, 123.5, accuracy: 0.0001,
                       "the spacer item's width is \(String(describing: widthConstant(of: bar.items.first))), not 123.5 at sidebar 200")
        receiver.onCall = nil
        toolbar.paneMoved(leading: 260, width: 796)
        XCTAssertEqual(widthConstant(of: window.toolbar?.items.first) ?? -1, 183.5, accuracy: 0.0001,
                       "a later report did not reach the bar on the window: the spacer is \(String(describing: widthConstant(of: window.toolbar?.items.first))), not 183.5")
    }

    /// A pane whose leading edge is huge and finite. In a window the spacer is held to the window's own width, so
    /// it is never wider than the window; with no window there is no ceiling to hold it to, and the answer is
    /// still finite and the bar neither traps nor refuses. Total failure prints: "a huge finite pane gave a spacer
    /// of <w>, not the window's <W> + 16 - seed" / "a huge finite width was not kept as room: <x>" / "a pane
    /// leading at the window's own width was held at <w>" / "a 500 pt window gave a spacer of <w>: the ceiling is
    /// not the window's width" / "with no window a huge finite pane gave a spacer of <w>".
    func testALeadingPastTheWindowIsHeldAtItAndWithoutAWindowNothingTraps() throws {
        let toolbar = SettingsToolbar(model: SettingsModel(host: ModuleHost.shared),
                                      channel: HelmWindowToolbarChannel(), lead: .spacer)
        let window = unshownWindow()
        defer { window.toolbar = nil }
        toolbar.window = window
        let ceiling = window.frame.width
        XCTAssertGreaterThan(ceiling, 0, "the fixture is wrong: the window has no width")
        toolbar.paneMoved(leading: 1e9, width: CGFloat.greatestFiniteMagnitude)
        XCTAssertEqual(toolbar.leadingSpacer ?? -1, ceiling + 16 - SettingsToolbar.itemsStartSeed, accuracy: 0.0001,
                       "a huge finite pane gave a spacer of \(String(describing: toolbar.leadingSpacer)), not the window's \(ceiling) + 16 - seed")
        XCTAssertEqual(toolbar.offeredRoom(), CGFloat.greatestFiniteMagnitude,
                       "a huge finite width was not kept as room: \(toolbar.offeredRoom())")
        toolbar.paneMoved(leading: ceiling, width: 100)
        XCTAssertEqual(toolbar.leadingSpacer ?? -1, ceiling + 16 - SettingsToolbar.itemsStartSeed, accuracy: 0.0001,
                       "a pane leading at the window's own width was held at \(String(describing: toolbar.leadingSpacer))")
        window.setContentSize(NSSize(width: 500, height: 700))
        let narrow = window.frame.width
        XCTAssertLessThan(narrow, ceiling, "the fixture is wrong: the window did not narrow")
        toolbar.paneMoved(leading: 1e9, width: 100)
        XCTAssertEqual(toolbar.leadingSpacer ?? -1, narrow + 16 - SettingsToolbar.itemsStartSeed, accuracy: 0.0001,
                       "a \(narrow) pt window gave a spacer of \(String(describing: toolbar.leadingSpacer)): the ceiling is not the window's width")
        window.layoutIfNeeded()

        let loose = SettingsToolbar(model: SettingsModel(host: ModuleHost.shared),
                                    channel: HelmWindowToolbarChannel(), lead: .spacer)
        XCTAssertNil(loose.window, "the fixture is wrong: the toolbar has a window")
        loose.paneMoved(leading: 1e9, width: CGFloat.greatestFiniteMagnitude)
        XCTAssertEqual(loose.leadingSpacer ?? -1, 1e9 + 16 - SettingsToolbar.itemsStartSeed, accuracy: 1,
                       "with no window a huge finite pane gave a spacer of \(String(describing: loose.leadingSpacer))")
        XCTAssertEqual(loose.offeredRoom(), CGFloat.greatestFiniteMagnitude)
    }

    /// The count the settle's bound stands on: a report resets it, a flip counts one. (The gate itself, where a
    /// settle that keeps flipping stops reading, needs a visible window whose bar answers differently on each
    /// flip, which no window that is never shown can be made to do; the count is what can be driven.) Total
    /// failure prints: "a fresh toolbar counts <n> flips" / "a report that flipped the bar left the count at <n>,
    /// not 1" / "a report that flipped nothing left the count at <n>, not 0: a report does not re-arm the bound" /
    /// "a flip back left the count at <n>, not 1".
    func testAReportRearmsTheFlipCountAndAFlipCountsOne() {
        let toolbar = SettingsToolbar(model: SettingsModel(host: ModuleHost.shared),
                                      channel: HelmWindowToolbarChannel(), lead: .spacer)
        XCTAssertEqual(SettingsToolbar.flipCeiling, 4, "the ceiling moved from 4: the reason written above `flipCeiling` (one flip from the report, three from a read) no longer adds up to it")
        XCTAssertEqual(toolbar.flipsSinceReport, 0, "a fresh toolbar counts \(toolbar.flipsSinceReport) flips")
        toolbar.paneMoved(leading: 200, width: 856)
        XCTAssertTrue(toolbar.hasSpacer, "the fixture is wrong: the report gave no spacer")
        XCTAssertEqual(toolbar.flipsSinceReport, 1, "a report that flipped the bar left the count at \(toolbar.flipsSinceReport), not 1")
        toolbar.paneMoved(leading: 260, width: 796)
        XCTAssertEqual(toolbar.flipsSinceReport, 0,
                       "a report that flipped nothing left the count at \(toolbar.flipsSinceReport), not 0: a report does not re-arm the bound")
        toolbar.paneMoved(leading: 0, width: 1060)
        XCTAssertFalse(toolbar.hasSpacer, "the fixture is wrong: the report left the spacer")
        XCTAssertEqual(toolbar.flipsSinceReport, 1, "a flip back left the count at \(toolbar.flipsSinceReport), not 1")
    }
}
