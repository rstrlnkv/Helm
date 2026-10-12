import AppKit
@testable import HelmUI
import XCTest
@testable import HelmApp

/// **A `SettingsToolbar` calls `barAttached` when the window takes a bar it was not showing, and only then;
/// a report of the pane's place replaces no bar on the window, it moves the inset the bar's name is held off
/// its item's edge by.** The window here is never ordered front or back, made key or activated
/// (`NSWindow(contentRect:styleMask:backing:defer: true)`, `isReleasedWhenClosed = false`), and its toolbar
/// is taken off at the end of each test.
///
/// A moved items start (`learnStartOfItems(_:)` answering true, called by the settle and by a resize, never by a
/// report of the pane) is fed through a window that claims to be shown: `ClaimedWindow` answers `isVisible` as told
/// and is otherwise an unshown window, so the toolbar learns whatever number the name item's container gives there.
/// The rows that use it assert the toolbar's own coherence (the inset written is the arithmetic over the items start it
/// holds for the placement told; `itemsStartMoves` counts the reads that moved the start by a point or more, is cleared by a stored report
/// and stops the reads at `itemsStartMoveCeiling`), never the number AppKit gave, which in a window nobody ordered is not
/// the owner's. In this window nothing is laid out, and the container's left edge follows the inset one for one
/// (756.0 at an inset of 123.5, 879.5 at 0: its right edge stands), where in a laid-out toolbar it follows by a half point.
///
/// The negative, a toolbar with no window never calling `barAttached`, is in
/// `TheToolbarLeadsWithWhatItsShellGivesTests`.
@MainActor
final class TheBarTellsItsShellWhenItIsAttachedTests: XCTestCase {

    /// An unshown window that answers `isVisible` as told, one of the gates `learnStartOfItems(_:)` asks of the window.
    /// A `SettingsWindow` builds its own `NSWindow` and cannot be given this subclass; the rows of
    /// `TheWindowWearsTheToolbarTests` that need the same gate answer it for a settings window with `whileShown`, which
    /// replaces `NSWindow.isVisible`'s implementation for the span of a call; hence the two seams.
    private final class ClaimedWindow: NSWindow {
        var claimsShown = false
        override var isVisible: Bool { claimsShown }
    }

    private func claimedWindow() -> ClaimedWindow {
        let window = ClaimedWindow(contentRect: CGRect(x: 0, y: 0, width: 1060, height: 700),
                                   styleMask: [.titled, .closable, .resizable],
                                   backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        return window
    }

    private func unshownWindow() -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1060, height: 700),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        return window
    }

    /// The inset the toolbar's name item holds its hosting view off its own leading edge by: the constant of the
    /// one constraint tying the container's first subview to the container's leading edge, nil where the toolbar
    /// has no name item or its view holds no such constraint.
    private func nameInset(of toolbar: NSToolbar?) -> CGFloat? {
        guard let container = toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "helm.name" })?.view,
              let host = container.subviews.first else { return nil }
        return container.constraints.first {
            $0.firstItem === host && $0.firstAttribute == .leading
                && $0.secondItem === container && $0.secondAttribute == .leading
        }?.constant
    }

    /// Total failure prints: "barAttached was called <n> times when the window took its first bar, not once: the
    /// shell is not told the window took a bar" / "barAttached was called again for the bar already on screen:
    /// <n> calls in all, the shell is told again for nothing" / "barAttached was called <n> times after the pane was
    /// told, not once: a report put a bar on the window".
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
        XCTAssertEqual(calls, 1,
                       "barAttached was called \(calls) times after the pane was told, not once: a report put a bar on the window")
    }

    /// Total failure prints: "the window took no toolbar" / "the window lost its toolbar when the pane was told" /
    /// "the pane's report replaced the window's bar" / "the name item's inset is <w>, not 123.5 at sidebar 200" /
    /// "a moved width replaced the window's bar: a settle would restart the bar for every pixel of a drag" / "the inset
    /// stayed <w> after the pane moved to 260, not 183.5" / "the pane's move to the rail replaced the window's bar" /
    /// "the inset at the rail is <w>, not 0".
    func testAMovedWidthReplacesNoBarAndTheInsetFollowsIt() throws {
        let model = SettingsModel(host: ModuleHost.shared)
        let toolbar = SettingsToolbar(model: model, channel: HelmWindowToolbarChannel(), lead: .spacer)
        let window = unshownWindow()
        defer { window.toolbar = nil }
        toolbar.window = window
        let before = try XCTUnwrap(window.toolbar, "the window took no toolbar")

        toolbar.paneMoved(leading: 200, width: 856)
        let told = try XCTUnwrap(window.toolbar, "the window lost its toolbar when the pane was told")
        XCTAssertTrue(told === before, "the pane's report replaced the window's bar")
        XCTAssertEqual(nameInset(of: told) ?? -1, 123.5, accuracy: 0.0001,
                       "the name item's inset is \(String(describing: nameInset(of: told))), not 123.5 at sidebar 200")

        toolbar.paneMoved(leading: 260, width: 796)
        XCTAssertTrue(window.toolbar === told,
                      "a moved width replaced the window's bar: a settle would restart the bar for every pixel of a drag")
        XCTAssertEqual(nameInset(of: window.toolbar) ?? -1, 183.5, accuracy: 0.0001,
                       "the inset stayed \(String(describing: nameInset(of: window.toolbar))) after the pane moved to 260, not 183.5")

        toolbar.paneMoved(leading: 56, width: 1000)
        XCTAssertTrue(window.toolbar === told, "the pane's move to the rail replaced the window's bar")
        XCTAssertEqual(nameInset(of: window.toolbar) ?? -1, 0, accuracy: 0.0001,
                       "the inset at the rail is \(String(describing: nameInset(of: window.toolbar))), not 0")
    }

    /// The mutant this test must catch: `show()` no longer writing the current inset into a cached bar's
    /// constraint. The bar of one page is cached while another page is on the window; the pane moves; the first
    /// page comes back. Total failure prints: "the cached bar came back with an inset of <w>, not 183.5: the
    /// bar was built at sidebar 200 and nobody told it the pane moved while it was off the window".
    func testACachedBarComesBackWithTheInsetOfNowNotOfWhenItWasLeft() throws {
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
        XCTAssertEqual(nameInset(of: generalBar) ?? -1, 123.5, accuracy: 0.0001,
                       "the fixture is wrong: General's bar has no inset of 123.5")
        model.selection = .about
        let aboutBar = try XCTUnwrap(window.toolbar, "no bar for About")
        XCTAssertFalse(aboutBar === generalBar, "the fixture is wrong: About shows General's bar")
        toolbar.paneMoved(leading: 260, width: 796)
        model.selection = .general
        XCTAssertTrue(window.toolbar === generalBar, "the fixture is wrong: General's bar was not kept")
        XCTAssertEqual(nameInset(of: window.toolbar) ?? -1, 183.5, accuracy: 0.0001,
                       "the cached bar came back with an inset of \(String(describing: nameInset(of: window.toolbar))), not 183.5: the bar was built at sidebar 200 and nobody told it the pane moved while it was off the window")
    }

    /// `learnStartOfItems(_:)` reads only a window that is visible. On this one it never is, so
    /// `itemsStart` stays the seed after a report, after a resize and after a layout, and the inset is the seed's.
    /// Total failure prints:
    /// "itemsStart moved to <x> on a window nobody showed: a toolbar nothing laid out answered" / "the inset is
    /// <w>, not 183.5 from the seed" / "the name item's inset is <w>, not 183.5 from the seed".
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
        XCTAssertEqual(toolbar.currentNameInset, 183.5, accuracy: 0.0001,
                       "the inset is \(toolbar.currentNameInset), not 183.5 from the seed")
        XCTAssertEqual(nameInset(of: window.toolbar) ?? -1, 183.5, accuracy: 0.0001,
                       "the name item's inset is \(String(describing: nameInset(of: window.toolbar))), not 183.5 from the seed")
    }

    /// A report while the window is gone: it still stores and attaches nothing; the window
    /// that comes back finds its bar still on it with the inset of the report, and the shell is not told again.
    /// Total failure prints: "barAttached was called <n> times in all, the report with no window told the shell of a
    /// bar nobody assigned" / "the returning window's bar is not the one it kept" / "the returning window's bar holds an
    /// inset of <w>, not 123.5" / "barAttached was called <n> times after the window came back, not once: the shell
    /// was told of a bar the window already wore".
    func testAReportWhileTheWindowIsGoneAttachesNothingAndTheReturnFindsTheBarWithTheInset() throws {
        var calls = 0
        let toolbar = SettingsToolbar(model: SettingsModel(host: ModuleHost.shared),
                                      channel: HelmWindowToolbarChannel(), lead: .spacer,
                                      barAttached: { calls += 1 })
        let window = unshownWindow()
        defer { window.toolbar = nil }
        toolbar.window = window
        XCTAssertEqual(calls, 1, "the fixture is wrong: the first bar was not announced")
        let kept = try XCTUnwrap(window.toolbar, "the fixture is wrong: the window took no bar")
        toolbar.window = nil
        XCTAssertTrue(toolbar.paneMoved(leading: 200, width: 856), "a report with no window was refused")
        XCTAssertEqual(toolbar.currentNameInset, 123.5, accuracy: 0.0001, "a report with no window was not stored")
        XCTAssertEqual(calls, 1,
                       "barAttached was called \(calls) times in all, the report with no window told the shell of a bar nobody assigned")
        toolbar.window = window
        let bar = try XCTUnwrap(window.toolbar, "the returning window took no bar")
        XCTAssertTrue(bar === kept, "the returning window's bar is not the one it kept")
        XCTAssertEqual(nameInset(of: bar) ?? -1, 123.5, accuracy: 0.0001,
                       "the returning window's bar holds an inset of \(String(describing: nameInset(of: bar))), not 123.5")
        XCTAssertEqual(calls, 1,
                       "barAttached was called \(calls) times after the window came back, not once: the shell was told of a bar the window already wore")
    }

    /// A toolbar on a window that does not yet claim to be shown, told the pane at 200: the control every row
    /// below starts from (the items start is the seed, the inset 123.5), returned with the window.
    private func toolbarOnAnUnclaimedWindow(file: StaticString = #filePath, line: UInt = #line) -> (SettingsToolbar, ClaimedWindow)? {
        let toolbar = SettingsToolbar(model: SettingsModel(host: ModuleHost.shared),
                                      channel: HelmWindowToolbarChannel(), lead: .spacer)
        let window = claimedWindow()
        toolbar.window = window
        toolbar.paneMoved(leading: 200, width: 856)
        window.layoutIfNeeded()
        guard toolbar.itemsStart == SettingsToolbar.itemsStartSeed,
              let inset = nameInset(of: window.toolbar), abs(inset - 123.5) < 0.0001 else {
            XCTFail("the fixture is wrong: before the window claims to be shown the items start at \(toolbar.itemsStart) and the inset is \(String(describing: nameInset(of: window.toolbar))), not the seed and 123.5",
                    file: file, line: line)
            window.toolbar = nil
            return nil
        }
        return (toolbar, window)
    }

    /// The left edge of the name item's container in window x, the number `learnStartOfItems(_:)` reads.
    private func containerEdge(_ window: NSWindow) -> CGFloat? {
        guard let container = nameContainer(of: window.toolbar), container.window != nil else { return nil }
        return container.convert(container.bounds, to: nil).minX
    }

    /// **A report of the pane reads nothing off the toolbar: the inset it writes comes from the start held for the
    /// placement told, the seed of that placement, or the start a settle or a resize learnt for it.** The window claims to be
    /// shown, and the container stands 663.5 points from the seed (756.0 against 92.5; that it stands 20 or more from it is asserted first), so a report
    /// that read the container would move the start and the row would see it. Three claims: a report at 260 leaves `itemsStart`
    /// the seed, `itemsStartMoves` 0 and the inset the seed's 183.5; a report told the rail (`rail: true`) holds the rail's seed
    /// 22.5 and writes 253.5; and after a resize has learnt a start for the rail's placement, a report at 300 in the rail writes the
    /// inset from that start (the learnt one is far enough from the seed that the two inset arithmetics differ, asserted) and
    /// clears the count. Total failure prints: "the container stands <x>, within 20 points of the seed: …" / "a report read
    /// the items start: it holds <x>, not the seed" / "a report moved itemsStartMoves to <n>" / "the inset after a report is <w>, not 183.5 from
    /// the seed" / "the rail's placement holds <x>, not the rail's seed" / "the resize learnt no start for the rail" / "the inset after a report is <w>, not <x> from the start learnt <s>".
    func testAReportWritesTheInsetFromTheStartHeldForThePlacementToldAndReadsNothing() {
        guard let (toolbar, window) = toolbarOnAnUnclaimedWindow() else { return }
        defer { window.toolbar = nil }
        window.claimsShown = true
        guard let edge = containerEdge(window), abs(edge - SettingsToolbar.itemsStartSeed) >= 20 else {
            XCTFail("the container stands \(String(describing: containerEdge(window))), within 20 points of the seed: a report that read it would move nothing, so the row judges nothing")
            return
        }
        toolbar.paneMoved(leading: 260, width: 796)
        XCTAssertEqual(toolbar.itemsStart, SettingsToolbar.itemsStartSeed, accuracy: 0.0001,
                       "a report read the items start: it holds \(toolbar.itemsStart), not the seed, though the container stands at \(edge)")
        XCTAssertEqual(toolbar.itemsStartMoves, 0, "a report moved itemsStartMoves to \(toolbar.itemsStartMoves)")
        XCTAssertEqual(nameInset(of: window.toolbar) ?? -1, SettingsToolbar.nameInset(paneLeading: 260, itemsStart: SettingsToolbar.itemsStartSeed), accuracy: 0.0001,
                       "the inset after a report is \(String(describing: nameInset(of: window.toolbar))), not 183.5 from the seed")

        toolbar.paneMoved(leading: 260, width: 796, rail: true)
        XCTAssertEqual(toolbar.itemsStart, SettingsToolbar.railItemsStartSeed, accuracy: 0.0001,
                       "the rail's placement holds \(toolbar.itemsStart), not the rail's seed \(SettingsToolbar.railItemsStartSeed)")
        XCTAssertEqual(nameInset(of: window.toolbar) ?? -1, 260 + 16 - 22.5, accuracy: 0.0001,
                       "the inset after a report told the rail is \(String(describing: nameInset(of: window.toolbar))), not 253.5 from the rail's seed")

        resize(window)
        let learnt = toolbar.itemsStart
        XCTAssertGreaterThanOrEqual(abs(learnt - SettingsToolbar.railItemsStartSeed), SettingsToolbar.itemsStartTolerance,
                                    "the resize learnt no start for the rail: it holds \(learnt) beside the rail's seed, so nothing under test happened")
        XCTAssertEqual(toolbar.itemsStartMoves, 1, "the resize that learnt a start left itemsStartMoves at \(toolbar.itemsStartMoves), not 1")
        let want = SettingsToolbar.nameInset(paneLeading: 300, itemsStart: learnt)
        XCTAssertGreaterThan(abs(want - SettingsToolbar.nameInset(paneLeading: 300, itemsStart: SettingsToolbar.railItemsStartSeed)), 1,
                             "the fixture is wrong: the learnt start \(learnt) leaves the inset where the rail's seed had it")
        XCTAssertTrue(toolbar.paneMoved(leading: 300, width: 756, rail: true), "the report was refused: the fixture is wrong")
        XCTAssertEqual(toolbar.itemsStart, learnt, accuracy: 0.0001, "a report changed the start held for the rail from \(learnt) to \(toolbar.itemsStart)")
        XCTAssertEqual(nameInset(of: window.toolbar) ?? -1, want, accuracy: 0.0001,
                       "the inset after a report is \(String(describing: nameInset(of: window.toolbar))), not \(want) from the start learnt \(learnt)")
        XCTAssertEqual(toolbar.itemsStartMoves, 0, "a stored report left itemsStartMoves at \(toolbar.itemsStartMoves), not 0")
    }

    /// A resize read the items start and wrote the inset again, in the turn of the notification and before the
    /// settle that it also arms can do it. Total failure prints: "the resize read no items start: …" / "the inset
    /// after a resize that moved the items start is <w>, not <x> from the items start <s> it stored".
    func testAResizeThatMovesTheItemsStartWritesTheInsetFromTheNewStart() {
        guard let (toolbar, window) = toolbarOnAnUnclaimedWindow() else { return }
        defer { window.toolbar = nil }
        window.claimsShown = true
        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: window)
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        XCTAssertLessThan(0.02, SettingsToolbar.settleInterval, "the fixture is wrong: the settle ran before the row looked")
        XCTAssertNotEqual(toolbar.itemsStart, SettingsToolbar.itemsStartSeed,
                          "the resize read no items start: the window claims to be shown, so nothing under test happened")
        let want = SettingsToolbar.nameInset(paneLeading: 200, itemsStart: toolbar.itemsStart)
        XCTAssertNotEqual(want, 123.5, accuracy: 0.0001, "the fixture is wrong: the moved start leaves the inset where the seed had it")
        XCTAssertEqual(nameInset(of: window.toolbar) ?? -1, want, accuracy: 0.0001,
                       "the inset after a resize that moved the items start is \(String(describing: nameInset(of: window.toolbar))), not \(want) from the items start \(toolbar.itemsStart) it stored")
    }

    /// The settle read the items start, wrote the inset again and armed the pass over the layout that follows.
    /// Nothing but the settle reads here: the pane was told while the window did not claim to be shown, which
    /// armed it. Total failure prints: "the settle read no items start: …" / "the inset after a settle that moved
    /// the items start is <w>, not <x> from the items start <s> it stored".
    func testASettleThatMovesTheItemsStartWritesTheInsetFromTheNewStart() {
        guard let (toolbar, window) = toolbarOnAnUnclaimedWindow() else { return }
        defer { window.toolbar = nil }
        window.claimsShown = true
        let end = Date().addingTimeInterval(SettingsToolbar.settleInterval + 0.15)
        while Date() < end, toolbar.itemsStart == SettingsToolbar.itemsStartSeed {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertNotEqual(toolbar.itemsStart, SettingsToolbar.itemsStartSeed,
                          "the settle read no items start: the window claims to be shown, so nothing under test happened")
        let want = SettingsToolbar.nameInset(paneLeading: 200, itemsStart: toolbar.itemsStart)
        XCTAssertNotEqual(want, 123.5, accuracy: 0.0001, "the fixture is wrong: the moved start leaves the inset where the seed had it")
        XCTAssertEqual(nameInset(of: window.toolbar) ?? -1, want, accuracy: 0.0001,
                       "the inset after a settle that moved the items start is \(String(describing: nameInset(of: window.toolbar))), not \(want) from the items start \(toolbar.itemsStart) it stored")
    }

    /// Eight samples of a toolbar on a window that claims to be shown from the start, told the pane at 200, 856 wide (the card of
    /// the full sidebar in a window 1060 wide): each is the items start held and the inset on the window, after a layout of the
    /// window and 0.1 s of the run loop (the settle's interval).
    private func samplesOfAShownToolbar()
        -> (toolbar: SettingsToolbar, window: ClaimedWindow, samples: [(start: CGFloat, inset: CGFloat)]) {
        let toolbar = SettingsToolbar(model: SettingsModel(host: ModuleHost.shared),
                                      channel: HelmWindowToolbarChannel(), lead: .spacer)
        let window = claimedWindow()
        window.claimsShown = true
        toolbar.window = window
        window.layoutIfNeeded()
        toolbar.paneMoved(leading: 200, width: 856)
        var samples: [(start: CGFloat, inset: CGFloat)] = []
        for _ in 0..<8 {
            window.layoutIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            samples.append((toolbar.itemsStart, nameInset(of: window.toolbar) ?? -1))
        }
        return (toolbar, window, samples)
    }

    /// **A read, a write and a read again end, in a toolbar whose item's edge follows the inset one for one: from the second sample on the
    /// start held and the inset stand still, each the arithmetic of the other, and the count did not end it.** In this window nothing
    /// is laid out, and the container's left edge follows the inset one for one (756.0 at an inset of 123.5, 879.5 at 0: the right edge
    /// stands, measured in this fixture), against the half point a laid-out toolbar gives. The pane at 200 gives an inset that reaches its
    /// floor of 0 (216 is left of the edge at 756), so the start learnt (756.0, then 879.5) is written back as an inset of 0 both
    /// times and the third read finds the same start: what ends the loop here is the inset's floor and the tolerance, and the first sample
    /// differs from the second because the edge moved between them. The count is asserted under its ceiling: a refusal of an equal read that
    /// had gone would keep learning the same number and be stopped by the count alone (read, not run). The last sample's start is not the seed, so a
    /// toolbar that learnt nothing does not pass. A pane at 884 (an inset that never reaches its floor) was tried for a loop only the count
    /// ends: the inset of 807.5 takes the item out of the window (its container has no window, nothing is learnt), so the ceiling is
    /// held by `testAtTheCeilingNoMoreStartsAreRead`, which writes the container's frame, and not by a natural loop. Total failure prints: "no items start was learnt: …" / "the items start moved between
    /// samples after the second: <samples>" / "itemsStartMoves is <n>: the reads were stopped by the ceiling, not by two reads agreeing" /
    /// "the inset is not the arithmetic over the items start in sample <i>: <samples>".
    func testAReadThatFollowsItsOwnWriteOneForOneStandsStillOnceTheInsetReachesItsFloor() {
        let (toolbar, window, samples) = samplesOfAShownToolbar()
        defer { window.toolbar = nil }
        XCTAssertNotEqual(samples.last?.start, SettingsToolbar.itemsStartSeed,
                          "no items start was learnt: the window claims to be shown, so nothing under test happened: \(samples)")
        XCTAssertEqual(Set(samples.dropFirst().map(\.start)).count, 1, "the items start moved between samples after the second: \(samples)")
        XCTAssertLessThan(toolbar.itemsStartMoves, SettingsToolbar.itemsStartMoveCeiling,
                          "itemsStartMoves is \(toolbar.itemsStartMoves): the reads were stopped by the ceiling, not by two reads agreeing: \(samples)")
        for (index, sample) in samples.enumerated() {
            let want = SettingsToolbar.nameInset(paneLeading: 200, itemsStart: sample.start)
            XCTAssertEqual(sample.inset, want, accuracy: 0.0001,
                           "the inset is not the arithmetic over the items start in sample \(index): \(samples)")
        }
    }

    /// The name item's container, the view `learnStartOfItems(_:)` reads the items start off.
    private func nameContainer(of toolbar: NSToolbar?) -> NSView? {
        toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "helm.name" })?.view
    }

    /// One resize notification, delivered: the toolbar reads the items start in its handler.
    private func resize(_ window: NSWindow) {
        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: window)
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }

    /// Lays the frame view out and resizes until a read leaves the items start where it stood, at most six
    /// times: the first read of a window that claims to be shown finds the container before AppKit has laid it
    /// out, and a later one after. False where six reads still moved it.
    private func settleTheStart(_ toolbar: SettingsToolbar, _ window: NSWindow) -> Bool {
        for _ in 0..<6 {
            window.contentView?.superview?.layoutSubtreeIfNeeded()
            let before = toolbar.itemsStart
            resize(window)
            if toolbar.itemsStart == before { return true }
        }
        return false
    }

    /// A read of the items start already stored raises `itemsStartMoves` by nothing. The subject comes first: the
    /// resize that moved the start raised the count by one, and the reads that follow are taken until one leaves
    /// the start where it stood. Then two resizes read the same start. Total failure prints: "the resize read no items start: …" / "the resize that
    /// moved the items start left itemsStartMoves at <n>, not 1: …" / "six reads still moved the items start: the
    /// fixture is wrong" / "<k> reads of the start already stored raised itemsStartMoves from <a> to <b>" / "the
    /// items start moved from <a> to <b> between reads of an unmoved container".
    func testAReadOfTheStartAlreadyStoredRaisesTheCountByNothing() {
        guard let (toolbar, window) = toolbarOnAnUnclaimedWindow() else { return }
        defer { window.toolbar = nil }
        window.claimsShown = true
        resize(window)
        XCTAssertNotEqual(toolbar.itemsStart, SettingsToolbar.itemsStartSeed,
                          "the resize read no items start: the window claims to be shown, so nothing under test happened")
        XCTAssertEqual(toolbar.itemsStartMoves, 1,
                       "the resize that moved the items start left itemsStartMoves at \(toolbar.itemsStartMoves), not 1: it counts the reads that moved it")
        guard settleTheStart(toolbar, window) else {
            XCTFail("six reads still moved the items start: the fixture is wrong")
            return
        }
        let stored = toolbar.itemsStart
        let counted = toolbar.itemsStartMoves
        for read in 1...2 {
            resize(window)
            XCTAssertEqual(toolbar.itemsStart, stored, accuracy: 0.0001,
                           "the items start moved from \(stored) to \(toolbar.itemsStart) between reads of an unmoved container")
            XCTAssertEqual(toolbar.itemsStartMoves, counted,
                           "\(read) reads of the start already stored raised itemsStartMoves from \(counted) to \(toolbar.itemsStartMoves)")
        }
    }

    /// A stored `paneMoved` clears `itemsStartMoves`. The subject comes first: a resize in a window that claims to be
    /// shown moved the start, so the count is above zero before the pane is told. Total failure prints: "the resize that
    /// moved the items start left itemsStartMoves at <n>, not 1: …" / "the items start moved from <a> to <b> on the
    /// report: the fixture is wrong" / "a stored report left itemsStartMoves at <n>, not 0".
    func testAStoredReportClearsTheCount() {
        guard let (toolbar, window) = toolbarOnAnUnclaimedWindow() else { return }
        defer { window.toolbar = nil }
        window.claimsShown = true
        resize(window)
        XCTAssertEqual(toolbar.itemsStartMoves, 1,
                       "the resize that moved the items start left itemsStartMoves at \(toolbar.itemsStartMoves), not 1: there is nothing for the next report to clear")
        let stored = toolbar.itemsStart
        XCTAssertNotEqual(stored, SettingsToolbar.itemsStartSeed, "the resize read no items start: the window claims to be shown, so nothing under test happened")
        XCTAssertTrue(toolbar.paneMoved(leading: 300, width: 756), "the report was refused: the fixture is wrong")
        XCTAssertEqual(toolbar.itemsStart, stored, accuracy: 0.0001,
                       "the items start moved from \(stored) to \(toolbar.itemsStart) on the report: the fixture is wrong")
        XCTAssertEqual(toolbar.itemsStartMoves, 0,
                       "a stored report left itemsStartMoves at \(toolbar.itemsStartMoves), not 0")
    }

    /// At `itemsStartMoveCeiling` the toolbar reads no more. The reads are taken until the start stands, then the
    /// container's frame is written to another x before each resize (absolute, from where the layout left it, so
    /// a layout between writes does not make two writes equal), so every read finds another start and raises the
    /// count by one. The read after the ceiling leaves the start stored and the count where it was. The count and
    /// the start are the toolbar's own; the log line it writes there is not read. Total failure prints: "six reads
    /// still moved the items start: …" / "the container did not move the items start at write <k>: …" /
    /// "itemsStartMoves is <n> after write <k>, not <m>" / "the ceiling was not reached in <k> writes: the count is <n>" / "a read at the ceiling moved the stored items start from
    /// <a> to <b>" / "a read at the ceiling raised itemsStartMoves to <n>".
    func testAtTheCeilingNoMoreStartsAreRead() {
        guard let (toolbar, window) = toolbarOnAnUnclaimedWindow() else { return }
        defer { window.toolbar = nil }
        guard let container = nameContainer(of: window.toolbar) else {
            XCTFail("the fixture is wrong: the toolbar lists no name item")
            return
        }
        window.claimsShown = true
        toolbar.paneMoved(leading: 260, width: 796)
        guard settleTheStart(toolbar, window) else {
            XCTFail("six reads still moved the items start: the fixture is wrong")
            return
        }
        let ceiling = SettingsToolbar.itemsStartMoveCeiling
        guard toolbar.itemsStartMoves < ceiling else {
            XCTFail("the fixture is wrong: the ceiling was reached by the reads before the writes, at \(toolbar.itemsStartMoves)")
            return
        }
        let x0 = container.frame.origin.x
        var write = 0
        while toolbar.itemsStartMoves < ceiling, write < 10 {
            write += 1
            let before = toolbar.itemsStart
            let counted = toolbar.itemsStartMoves
            container.frame.origin.x = x0 + 7 * CGFloat(write)
            resize(window)
            XCTAssertNotEqual(toolbar.itemsStart, before,
                              "the container did not move the items start at write \(write): the window gave back the frame it was written")
            XCTAssertEqual(toolbar.itemsStartMoves, counted + 1,
                           "itemsStartMoves is \(toolbar.itemsStartMoves) after write \(write), not \(counted + 1)")
            if toolbar.itemsStart == before { return }
        }
        XCTAssertEqual(toolbar.itemsStartMoves, ceiling, "the ceiling was not reached in \(write) writes: the count is \(toolbar.itemsStartMoves)")
        let stored = toolbar.itemsStart
        container.frame.origin.x = x0 + 7 * CGFloat(write + 1)
        resize(window)
        XCTAssertEqual(toolbar.itemsStart, stored, accuracy: 0.0001,
                       "a read at the ceiling moved the stored items start from \(stored) to \(toolbar.itemsStart)")
        XCTAssertEqual(toolbar.itemsStartMoves, ceiling, "a read at the ceiling raised itemsStartMoves to \(toolbar.itemsStartMoves)")
    }

    /// **A start a point or more from the one held is learnt, in either direction, and one nearer than a point is refused and raises nothing.** The
    /// start is learnt in a window that claims to be shown (the container 663.5 points from the seed), the count is cleared by a stored report, and then the
    /// container's frame is written by 0.75 (refused: the start and the count stand), by 1.0 from where it stood (learnt: the start is 1.0 more, the count is
    /// 1), by 0.75 back (refused), and by 1.0 back (learnt: the start is where it was). The half point a laid-out toolbar gives (0.5, measured) is inside the
    /// tolerance and 70 points (between the placements) outside it; this row reads the boundary itself, so a tolerance of 0.5 learns the 0.75, one of 2 refuses
    /// the 1.0, and a difference taken without its sign refuses the way back (read, not run). Total failure prints: "the container did not take
    /// the frame written, an edge of <x>: it stands at <y>; <which read>" / "<which read>: the start moved from <a> to <b>" / "<which read>:
    /// itemsStartMoves went from <a> to <b>" / "<which read>: the start is <a>, not <b> (it was <c>)" / "<which read>: itemsStartMoves is <n>, not <m>",
    /// where <which read> is one of "a read 0.75 from the start held", "a read 1.0 from the start held", "a read 0.75 below the start held",
    /// "a read 1.0 below the start held".
    func testAStartAPointAwayIsLearntInBothDirectionsAndOneNearerIsRefused() {
        guard let (toolbar, window) = toolbarOnAnUnclaimedWindow() else { return }
        defer { window.toolbar = nil }
        guard let container = nameContainer(of: window.toolbar) else {
            XCTFail("the fixture is wrong: the toolbar lists no name item")
            return
        }
        window.claimsShown = true
        toolbar.paneMoved(leading: 260, width: 796)
        guard settleTheStart(toolbar, window) else {
            XCTFail("six reads still moved the items start: the fixture is wrong")
            return
        }
        XCTAssertNotEqual(toolbar.itemsStart, SettingsToolbar.itemsStartSeed, "the fixture is wrong: nothing was learnt, so the row judges nothing")
        XCTAssertTrue(toolbar.paneMoved(leading: 300, width: 756), "the report was refused: the fixture is wrong")
        XCTAssertEqual(toolbar.itemsStartMoves, 0, "the fixture is wrong: a stored report left the count at \(toolbar.itemsStartMoves)")
        let x0 = container.frame.origin.x
        let held = toolbar.itemsStart

        func write(_ offset: CGFloat, learns expected: CGFloat?, _ why: String, line: UInt = #line) {
            let before = toolbar.itemsStart
            let counted = toolbar.itemsStartMoves
            container.frame.origin.x = x0 + offset
            guard let edge = containerEdge(window), abs(edge - (held + offset)) < 0.0001 else {
                XCTFail("the container did not take the frame written, an edge of \(held + offset): it stands at \(String(describing: containerEdge(window))); \(why)", line: line)
                return
            }
            resize(window)
            if let expected {
                XCTAssertEqual(toolbar.itemsStart, expected, accuracy: 0.0001, "\(why): the start is \(toolbar.itemsStart), not \(expected) (it was \(before))", line: line)
                XCTAssertEqual(toolbar.itemsStartMoves, counted + 1, "\(why): itemsStartMoves is \(toolbar.itemsStartMoves), not \(counted + 1)", line: line)
            } else {
                XCTAssertEqual(toolbar.itemsStart, before, accuracy: 0.0001, "\(why): the start moved from \(before) to \(toolbar.itemsStart)", line: line)
                XCTAssertEqual(toolbar.itemsStartMoves, counted, "\(why): itemsStartMoves went from \(counted) to \(toolbar.itemsStartMoves)", line: line)
            }
        }
        write(0.75, learns: nil, "a read 0.75 from the start held")
        write(1.0, learns: held + 1.0, "a read 1.0 from the start held")
        write(0.25, learns: nil, "a read 0.75 below the start held")
        write(0, learns: held, "a read 1.0 below the start held")
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

    /// The first report arrives from inside the first `barAttached` and reaches the bar the window now wears.
    /// Total failure prints: "the first bar was never announced" / "barAttached was called <n> times, not once" /
    /// "the window took no toolbar" / "the bar on the window holds an inset of <w>, not 123.5 at sidebar 200: a report
    /// from inside barAttached did not reach it" / "a later report replaced the window's bar" / "a later report did
    /// not reach the bar on the window: the inset is <w>, not 183.5".
    func testAReportFromInsideBarAttachedReachesTheBarOnTheWindowAndLaterReportsReachIt() throws {
        let receiver = Receiver()
        receiver.onCall = { toolbar, call in
            if call == 1 { toolbar.paneMoved(leading: 200, width: 856) }
        }
        let toolbar = toolbar(receiver: receiver)
        let window = unshownWindow()
        defer { window.toolbar = nil }
        toolbar.window = window
        XCTAssertGreaterThan(receiver.calls, 0, "the first bar was never announced")
        XCTAssertEqual(receiver.calls, 1, "barAttached was called \(receiver.calls) times, not once")
        let bar = try XCTUnwrap(window.toolbar, "the window took no toolbar")
        XCTAssertEqual(nameInset(of: bar) ?? -1, 123.5, accuracy: 0.0001,
                       "the bar on the window holds an inset of \(String(describing: nameInset(of: bar))), not 123.5 at sidebar 200: a report from inside barAttached did not reach it")
        toolbar.paneMoved(leading: 260, width: 796)
        XCTAssertTrue(window.toolbar === bar, "a later report replaced the window's bar")
        XCTAssertEqual(nameInset(of: window.toolbar) ?? -1, 183.5, accuracy: 0.0001,
                       "a later report did not reach the bar on the window: the inset is \(String(describing: nameInset(of: window.toolbar))), not 183.5")
    }

    /// The bar holds an inset; a page switch takes a bar of another page, and from inside `barAttached` a
    /// report moves the pane. Total failure prints: "the bar on the window holds an inset of <w>, not 183.5:
    /// the report from inside barAttached reached the bar that was left" / "the bar that was left took the report: its
    /// inset is <w>, not 123.5".
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
        XCTAssertEqual(nameInset(of: generalBar) ?? -1, 123.5, accuracy: 0.0001,
                       "the fixture is wrong: General's bar has no inset of 123.5")
        let before = receiver.calls
        receiver.onCall = { toolbar, _ in toolbar.paneMoved(leading: 260, width: 796) }
        model.selection = .about
        let aboutBar = try XCTUnwrap(window.toolbar, "no bar for About")
        XCTAssertFalse(aboutBar === generalBar, "the fixture is wrong: About shows General's bar")
        XCTAssertGreaterThan(receiver.calls, before, "the fixture is wrong: the page switch announced nothing")
        XCTAssertEqual(nameInset(of: aboutBar) ?? -1, 183.5, accuracy: 0.0001,
                       "the bar on the window holds an inset of \(String(describing: nameInset(of: aboutBar))), not 183.5: the report from inside barAttached reached the bar that was left")
        XCTAssertEqual(nameInset(of: generalBar) ?? -1, 123.5, accuracy: 0.0001,
                       "the bar that was left took the report: its inset is \(String(describing: nameInset(of: generalBar))), not 123.5")
    }

    /// A pane whose leading edge is huge and finite. In a window the inset is held to the window's own width, so
    /// it is never wider than the window; with no window there is no ceiling to hold it to, and the answer is
    /// still finite and the bar neither traps nor refuses. Total failure prints: "a huge finite pane gave an inset
    /// of <w>, not the window's <W> + 16 - seed" / "a huge finite width was not kept as room: <x>" / "a pane
    /// leading at the window's own width was held at <w>" / "a 500 pt window gave an inset of <w>: the ceiling is
    /// not the window's width" / "with no window a huge finite pane gave an inset of <w>".
    func testALeadingPastTheWindowIsHeldAtItAndWithoutAWindowNothingTraps() throws {
        let toolbar = SettingsToolbar(model: SettingsModel(host: ModuleHost.shared),
                                      channel: HelmWindowToolbarChannel(), lead: .spacer)
        let window = unshownWindow()
        defer { window.toolbar = nil }
        toolbar.window = window
        let ceiling = window.frame.width
        XCTAssertGreaterThan(ceiling, 0, "the fixture is wrong: the window has no width")
        toolbar.paneMoved(leading: 1e9, width: CGFloat.greatestFiniteMagnitude)
        XCTAssertEqual(toolbar.currentNameInset, ceiling + 16 - SettingsToolbar.itemsStartSeed, accuracy: 0.0001,
                       "a huge finite pane gave an inset of \(toolbar.currentNameInset), not the window's \(ceiling) + 16 - seed")
        XCTAssertEqual(toolbar.offeredRoom(), CGFloat.greatestFiniteMagnitude,
                       "a huge finite width was not kept as room: \(toolbar.offeredRoom())")
        toolbar.paneMoved(leading: ceiling, width: 100)
        XCTAssertEqual(toolbar.currentNameInset, ceiling + 16 - SettingsToolbar.itemsStartSeed, accuracy: 0.0001,
                       "a pane leading at the window's own width was held at \(toolbar.currentNameInset)")
        window.setContentSize(NSSize(width: 500, height: 700))
        let narrow = window.frame.width
        XCTAssertLessThan(narrow, ceiling, "the fixture is wrong: the window did not narrow")
        toolbar.paneMoved(leading: 1e9, width: 100)
        XCTAssertEqual(toolbar.currentNameInset, narrow + 16 - SettingsToolbar.itemsStartSeed, accuracy: 0.0001,
                       "a \(narrow) pt window gave an inset of \(toolbar.currentNameInset): the ceiling is not the window's width")
        window.layoutIfNeeded()

        let loose = SettingsToolbar(model: SettingsModel(host: ModuleHost.shared),
                                    channel: HelmWindowToolbarChannel(), lead: .spacer)
        XCTAssertNil(loose.window, "the fixture is wrong: the toolbar has a window")
        loose.paneMoved(leading: 1e9, width: CGFloat.greatestFiniteMagnitude)
        XCTAssertEqual(loose.currentNameInset, 1e9 + 16 - SettingsToolbar.itemsStartSeed, accuracy: 1,
                       "with no window a huge finite pane gave an inset of \(loose.currentNameInset)")
        XCTAssertEqual(loose.offeredRoom(), CGFloat.greatestFiniteMagnitude)
    }
}
