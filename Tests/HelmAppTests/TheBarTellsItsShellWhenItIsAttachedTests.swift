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
/// A moved items start (`readItemsStart()` answering true) is fed through a window that claims to be shown:
/// `ClaimedWindow` answers `isVisible` as told and is otherwise an unshown window, so the toolbar reads whatever
/// number the name item's container gives there. The rows that use it assert the toolbar's own coherence (the
/// inset written is the arithmetic over the items start it stored; `itemsStartMoves` counts the reads that moved the start, is cleared by a stored report and stops the reads at `itemsStartMoveCeiling`), never the number AppKit gave, which in a
/// window nobody ordered is not the owner's.
///
/// The negative, a toolbar with no window never calling `barAttached`, is in
/// `TheToolbarLeadsWithWhatItsShellGivesTests`.
@MainActor
final class TheBarTellsItsShellWhenItIsAttachedTests: XCTestCase {

    /// An unshown window that answers `isVisible` as told, the one gate `readItemsStart()` asks the window.
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

    /// `readItemsStart()` reads only a window that is visible. On this one it never is, so
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

    /// A report read the items start of a window that claims to be shown and the inset it wrote comes from it.
    /// Total failure prints: "the report read no items start: …" / "the inset after a report that moved the items
    /// start is <w>, not <x> from the items start <s> it stored".
    func testAReportThatMovesTheItemsStartWritesTheInsetFromTheNewStart() {
        guard let (toolbar, window) = toolbarOnAnUnclaimedWindow() else { return }
        defer { window.toolbar = nil }
        window.claimsShown = true
        toolbar.paneMoved(leading: 260, width: 796)
        XCTAssertNotEqual(toolbar.itemsStart, SettingsToolbar.itemsStartSeed,
                          "the report read no items start: the window claims to be shown, so nothing under test happened")
        let want = SettingsToolbar.nameInset(paneLeading: 260, itemsStart: toolbar.itemsStart)
        XCTAssertNotEqual(want, 183.5, accuracy: 0.0001, "the fixture is wrong: the moved start leaves the inset where the seed had it")
        XCTAssertEqual(nameInset(of: window.toolbar) ?? -1, want, accuracy: 0.0001,
                       "the inset after a report that moved the items start is \(String(describing: nameInset(of: window.toolbar))), not \(want) from the items start \(toolbar.itemsStart) it stored")
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

    /// A read, a write and a read again end: with the window claiming to be shown from the first report on,
    /// the items start and the inset stand still over the settles that follow, each the arithmetic of the
    /// other. A cycle (the container's edge following the inset) would show as a start that moves between
    /// samples. Not seen red: no run made the edge follow the inset. Total failure prints: "no items start was read: …" / "the items start moved between samples:
    /// <samples>" / "the inset is not the arithmetic over the items start in sample <i>: <samples>".
    func testAReadThatFollowsItsOwnWriteStandsStill() {
        let toolbar = SettingsToolbar(model: SettingsModel(host: ModuleHost.shared),
                                      channel: HelmWindowToolbarChannel(), lead: .spacer)
        let window = claimedWindow()
        window.claimsShown = true
        defer { window.toolbar = nil }
        toolbar.window = window
        window.layoutIfNeeded()
        toolbar.paneMoved(leading: 200, width: 856)
        var samples: [(start: CGFloat, inset: CGFloat)] = []
        for _ in 0..<8 {
            window.layoutIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            samples.append((toolbar.itemsStart, nameInset(of: window.toolbar) ?? -1))
        }
        XCTAssertNotEqual(samples.last?.start, SettingsToolbar.itemsStartSeed,
                          "no items start was read: the window claims to be shown, so nothing under test happened: \(samples)")
        XCTAssertEqual(Set(samples.map(\.start)).count, 1, "the items start moved between samples: \(samples)")
        for (index, sample) in samples.enumerated() {
            let want = SettingsToolbar.nameInset(paneLeading: 200, itemsStart: sample.start)
            XCTAssertEqual(sample.inset, want, accuracy: 0.0001,
                           "the inset is not the arithmetic over the items start in sample \(index): \(samples)")
        }
    }

    /// The name item's container, the view `readItemsStart()` reads the items start off.
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
    /// report that moved the start raised the count by one, and the reads that follow are taken until one leaves
    /// the start where it stood. Then two resizes read the same start. Total failure prints: "the report read no items start: …" / "the report that
    /// moved the items start left itemsStartMoves at <n>, not 1: …" / "six reads still moved the items start: the
    /// fixture is wrong" / "<k> reads of the start already stored raised itemsStartMoves from <a> to <b>" / "the
    /// items start moved from <a> to <b> between reads of an unmoved container".
    func testAReadOfTheStartAlreadyStoredRaisesTheCountByNothing() {
        guard let (toolbar, window) = toolbarOnAnUnclaimedWindow() else { return }
        defer { window.toolbar = nil }
        window.claimsShown = true
        toolbar.paneMoved(leading: 260, width: 796)
        XCTAssertNotEqual(toolbar.itemsStart, SettingsToolbar.itemsStartSeed,
                          "the report read no items start: the window claims to be shown, so nothing under test happened")
        XCTAssertEqual(toolbar.itemsStartMoves, 1,
                       "the report that moved the items start left itemsStartMoves at \(toolbar.itemsStartMoves), not 1: it counts the reads that moved it")
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

    /// A stored `paneMoved` clears `itemsStartMoves`. The subject comes first: the count is above zero before the
    /// pane is told again. Total failure prints: "the report that moved the items start left itemsStartMoves at
    /// <n>, not 1: …" / "the items start moved from <a> to <b> on the second report: the fixture is wrong" /
    /// "a stored report left itemsStartMoves at <n>, not 0".
    func testAStoredReportClearsTheCount() {
        guard let (toolbar, window) = toolbarOnAnUnclaimedWindow() else { return }
        defer { window.toolbar = nil }
        window.claimsShown = true
        toolbar.paneMoved(leading: 260, width: 796)
        XCTAssertEqual(toolbar.itemsStartMoves, 1,
                       "the report that moved the items start left itemsStartMoves at \(toolbar.itemsStartMoves), not 1: there is nothing for the next report to clear")
        let stored = toolbar.itemsStart
        XCTAssertTrue(toolbar.paneMoved(leading: 300, width: 756), "the second report was refused: the fixture is wrong")
        XCTAssertEqual(toolbar.itemsStart, stored, accuracy: 0.0001,
                       "the items start moved from \(stored) to \(toolbar.itemsStart) on the second report: the fixture is wrong")
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
