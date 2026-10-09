import AppKit
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **A person's flip of the sidebar asks the shell for a fold that lasts `HelmMotion.sidebarFoldDuration`; a fold
/// set from code, a flip under Reduce Motion, a flip back to the width already standing and a window that opens
/// folded ask for none.** The controller is
/// built over a scratch store, never shown, and no row waits: what was ASKED is read from `onFold`, and the width
/// and `foldTarget` are read in the same turn. Whether the motion looks right is not asserted here.
///
/// A row that says nothing was asked also shows the same controller hearing a flip, before or after, so a seam
/// nobody calls cannot pass it.
@MainActor
final class TheSidebarsFoldTravelsOnlyOnAPersonsFlipTests: XCTestCase {

    private typealias Fold = ShellContentView.Fold

    /// What the shell was asked for, and whether Reduce Motion is on, both read by closures the shell holds.
    private final class Probe {
        var heard: [Fold] = []
        var reduce = false
    }

    /// The controller over `store`, its seams set before its view exists, the view loaded and given a size.
    private func controller(_ probe: Probe, store: NamespacedStore) -> SettingsShellViewController {
        let c = SettingsShellViewController(model: SettingsModel(host: ModuleHost.shared),
                                            toolbarChannel: HelmWindowToolbarChannel(), band: .onMacOS(27),
                                            bar: ShellPageBarView(), store: store)
        c.shell.reducesMotion = { [probe] in probe.reduce }
        c.shell.onFold = { [probe] in probe.heard.append($0) }
        c.loadViewIfNeeded()
        c.shell.frame = CGRect(x: 0, y: 0, width: 1000, height: 700)
        c.shell.layoutSubtreeIfNeeded()
        return c
    }

    private func scratch() -> NamespacedStore { AppSettings.store.over(InMemoryKeyValueStore()) }

    private let rail = ShellGeometry.railWidth
    private let open = ShellGeometry.defaultSidebarWidth

    /// Total failure prints: "the window did not open expanded: the fixture is wrong" / "the first flip was heard as
    /// <folds>, not one fold from 200.0 to 56.0 over the token's length" / "the flip did not fold the sidebar" /
    /// "the cut to the rail left the width at <w>" / "the flip back was heard as <folds>, not one fold from 56.0 to
    /// 200.0" / "the second flip did not unfold the sidebar".
    func testAPersonsFlipAsksForTheFoldWithTheTokensLength() {
        let probe = Probe()
        let c = controller(probe, store: scratch())
        XCTAssertEqual(c.shell.sidebarWidth, open, "the window did not open expanded: the fixture is wrong")
        XCTAssertFalse(c.sidebarCollapsed, "the window did not open expanded: the fixture is wrong")

        c.flipSidebar()
        XCTAssertEqual(probe.heard, [Fold(from: open, to: rail, duration: HelmMotion.sidebarFoldDuration)],
                       "the first flip was heard as \(probe.heard), not one fold from \(open) to \(rail) over the token's length")
        XCTAssertTrue(c.sidebarCollapsed, "the flip did not fold the sidebar")

        c.shell.fold(to: rail, animated: false)
        XCTAssertEqual(c.shell.sidebarWidth, rail, "the cut to the rail left the width at \(c.shell.sidebarWidth)")
        probe.heard = []
        c.flipSidebar()
        XCTAssertEqual(probe.heard, [Fold(from: rail, to: open, duration: HelmMotion.sidebarFoldDuration)],
                       "the flip back was heard as \(probe.heard), not one fold from \(rail) to \(open)")
        XCTAssertFalse(c.sidebarCollapsed, "the second flip did not unfold the sidebar")
    }

    /// Total failure prints: "the instrument is dead: a flip with motion allowed was heard <n> times" / "the cut back
    /// to expanded left the width at <w>" / "a flip under Reduce Motion asked for <n> folds" / "the width was <w> in
    /// the turn of the flip, not 56.0" / "a cut left a fold target of <t>" / "the flip under Reduce Motion did not
    /// fold".
    func testUnderReduceMotionAFlipIsACut() {
        let probe = Probe()
        let c = controller(probe, store: scratch())
        c.flipSidebar()
        XCTAssertEqual(probe.heard.count, 1, "the instrument is dead: a flip with motion allowed was heard \(probe.heard.count) times")
        c.sidebarCollapsed = false
        c.shell.layoutSubtreeIfNeeded()
        XCTAssertEqual(c.shell.sidebarWidth, open, "the cut back to expanded left the width at \(c.shell.sidebarWidth)")

        probe.reduce = true
        let before = probe.heard.count
        c.flipSidebar()
        XCTAssertEqual(probe.heard.count, before, "a flip under Reduce Motion asked for \(probe.heard.count - before) folds")
        XCTAssertEqual(c.shell.sidebarWidth, rail, "the width was \(c.shell.sidebarWidth) in the turn of the flip, not \(rail)")
        XCTAssertNil(c.shell.foldTarget, "a cut left a fold target of \(String(describing: c.shell.foldTarget))")
        XCTAssertTrue(c.sidebarCollapsed, "the flip under Reduce Motion did not fold")
    }

    /// Total failure prints: "the instrument is dead: <folds> after a flip" / "setting the fold from code asked for
    /// <folds>" / "the width was <w> in the turn of the setter" / "the setter wrote <v> into the store".
    func testAFoldSetFromCodeIsACut() {
        let probe = Probe()
        let store = scratch()
        let c = controller(probe, store: store)
        c.sidebarCollapsed = true
        XCTAssertEqual(probe.heard, [], "setting the fold from code asked for \(probe.heard)")
        XCTAssertEqual(c.shell.sidebarWidth, rail, "the width was \(c.shell.sidebarWidth) in the turn of the setter, not \(rail)")
        XCTAssertNil(c.shell.foldTarget, "a cut left a fold target of \(String(describing: c.shell.foldTarget))")
        XCTAssertNil(store.object("sidebarCollapsed"),
                     "the setter wrote \(String(describing: store.object("sidebarCollapsed"))) into the store: only a person's flip is remembered")

        c.flipSidebar()
        XCTAssertEqual(probe.heard, [Fold(from: rail, to: open, duration: HelmMotion.sidebarFoldDuration)],
                       "the instrument is dead: \(probe.heard) after a flip")
    }

    /// Total failure prints: "a window that opens folded asked for <folds>" / "it opened <w> wide, not 56.0" /
    /// "the instrument is dead: <folds> after a flip".
    func testAWindowThatOpensFoldedAsksForNoFold() {
        let probe = Probe()
        let store = scratch()
        store.set(true, for: "sidebarCollapsed")
        let c = controller(probe, store: store)
        XCTAssertEqual(probe.heard, [], "a window that opens folded asked for \(probe.heard)")
        XCTAssertEqual(c.shell.sidebarWidth, rail, "it opened \(c.shell.sidebarWidth) wide, not \(rail)")
        XCTAssertNil(c.shell.foldTarget, "opening left a fold target of \(String(describing: c.shell.foldTarget))")
        XCTAssertTrue(c.sidebarCollapsed, "the window did not open folded")

        c.flipSidebar()
        XCTAssertEqual(probe.heard, [Fold(from: rail, to: open, duration: HelmMotion.sidebarFoldDuration)],
                       "the instrument is dead: \(probe.heard) after a flip")
    }

    /// Writing the width by hand stands for a frame of the run: the layout places the card at it, `foldTarget`
    /// stands until the target itself is written. Total failure prints: "no fold to <target> was asked: the fixture is
    /// wrong" / "at <w> the card started at <x>" / "the fold target was <t> at <w>, not <target>" / "the fold target
    /// outlived the end".
    func testTheWidthIsLaidOutAtEveryValueOnTheWay() {
        let probe = Probe()
        let c = controller(probe, store: scratch())
        let shell = c.shell

        func frames(towards target: CGFloat, via middle: CGFloat) {
            XCTAssertEqual(shell.foldTarget, target, "no fold to \(target) was asked: the fixture is wrong")
            shell.sidebarWidth = middle
            shell.layoutSubtreeIfNeeded()
            XCTAssertEqual(shell.card.frame.minX, middle, "at \(middle) the card started at \(shell.card.frame.minX)")
            XCTAssertEqual(shell.sidebarWidth, middle, "the width was \(shell.sidebarWidth) after writing \(middle)")
            XCTAssertEqual(shell.foldTarget, target, "the fold target was \(String(describing: shell.foldTarget)) at \(middle), not \(target)")
            shell.sidebarWidth = target
            shell.layoutSubtreeIfNeeded()
            XCTAssertEqual(shell.card.frame.minX, target, "at the end \(target) the card started at \(shell.card.frame.minX)")
            XCTAssertNil(shell.foldTarget, "the fold target outlived the end: \(String(describing: shell.foldTarget))")
        }

        c.flipSidebar()
        frames(towards: rail, via: 130)
        c.flipSidebar()
        frames(towards: open, via: 130)
    }

    // MARK: - inputs nobody fed

    /// The view's move to another window, or out of every window, ends a fold in flight by a cut to its target.
    /// The window is made here and never ordered in. Total failure prints: "no fold was asked: the fixture is
    /// wrong" / "moved into a window the fold left the width at <w> with target <t>" / "moved out of every window ...".
    func testAViewMovedToAWindowFinishesTheFoldInFlight() {
        let probe = Probe()
        let c = controller(probe, store: scratch())
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 700),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        XCTAssertFalse(window.isVisible, "the window is on screen: the fixture is wrong")

        c.flipSidebar()
        XCTAssertEqual(c.shell.foldTarget, rail, "no fold was asked: the fixture is wrong")
        XCTAssertEqual(c.shell.sidebarWidth, open, "the width moved before any frame: the fixture is wrong")
        window.contentView = c.shell
        XCTAssertNotNil(c.shell.window, "the view did not reach the window: the fixture is wrong")
        XCTAssertEqual(c.shell.sidebarWidth, rail, "moved into a window the fold left the width at \(c.shell.sidebarWidth) with target \(String(describing: c.shell.foldTarget))")
        XCTAssertNil(c.shell.foldTarget, "moved into a window the fold target stayed at \(String(describing: c.shell.foldTarget))")

        c.flipSidebar()
        XCTAssertEqual(c.shell.foldTarget, open, "no unfold was asked: the fixture is wrong")
        window.contentView = NSView()
        XCTAssertNil(c.shell.window, "the view stayed in the window: the fixture is wrong")
        XCTAssertEqual(c.shell.sidebarWidth, open, "moved out of every window the fold left the width at \(c.shell.sidebarWidth) with target \(String(describing: c.shell.foldTarget))")
        XCTAssertNil(c.shell.foldTarget, "moved out of every window the fold target stayed at \(String(describing: c.shell.foldTarget))")
        window.close()
    }

    /// A second flip while the first is in flight (no frame has landed, then one has): the store holds the newer
    /// state, `foldTarget` is the new target, and the second fold starts from the width then standing.
    func testASecondFlipInFlightFoldsFromTheWidthThenStanding() {
        let probe = Probe()
        let store = scratch()
        let c = controller(probe, store: store)
        c.flipSidebar()
        c.shell.sidebarWidth = 130
        c.shell.layoutSubtreeIfNeeded()
        c.flipSidebar()
        XCTAssertEqual(probe.heard, [Fold(from: open, to: rail, duration: HelmMotion.sidebarFoldDuration),
                                     Fold(from: 130, to: open, duration: HelmMotion.sidebarFoldDuration)],
                       "the flips were heard as \(probe.heard)")
        XCTAssertEqual(store.object("sidebarCollapsed") as? Bool, false, "the store held \(String(describing: store.object("sidebarCollapsed"))), not the newer state false")
        XCTAssertEqual(c.shell.foldTarget, open, "the fold target was \(String(describing: c.shell.foldTarget)), not the new target \(open)")
        XCTAssertFalse(c.sidebarCollapsed, "the second flip left the rows folded")
    }

    /// A flip back to the width already standing (no frame landed yet) is a cut: nothing is asked, nothing is
    /// left claimed, and the store holds the newer state. Total failure prints: "the second flip was heard as ..."
    func testAFlipBackToTheWidthAlreadyStandingIsACut() {
        let probe = Probe()
        let store = scratch()
        let c = controller(probe, store: store)
        c.flipSidebar()
        c.flipSidebar()
        XCTAssertEqual(probe.heard.count, 1, "the second flip was heard as \(probe.heard): a width already standing was travelled to")
        XCTAssertNil(c.shell.foldTarget, "the flip back left a fold target of \(String(describing: c.shell.foldTarget))")
        XCTAssertEqual(c.shell.sidebarWidth, open, "the width was \(c.shell.sidebarWidth)")
        XCTAssertEqual(store.object("sidebarCollapsed") as? Bool, false, "the store held \(String(describing: store.object("sidebarCollapsed")))")
    }

    /// The store holds a folded window and a width that is not a number: the unfold goes to the default 200.
    func testAnUnfoldFromAFoldedWindowWithANotANumberWidthGoesToTheDefault() {
        let probe = Probe()
        let store = scratch()
        store.set(true, for: "sidebarCollapsed")
        store.set(Double.nan, for: "sidebarWidth")
        let c = controller(probe, store: store)
        XCTAssertEqual(c.shell.sidebarWidth, rail, "it opened \(c.shell.sidebarWidth) wide, not \(rail)")
        c.flipSidebar()
        XCTAssertEqual(probe.heard, [Fold(from: rail, to: open, duration: HelmMotion.sidebarFoldDuration)],
                       "the unfold was heard as \(probe.heard), not to \(open)")
        XCTAssertEqual(c.shell.foldTarget, open, "the fold target was \(String(describing: c.shell.foldTarget))")
    }

    /// A flip before the view is loaded (`view` never asked): the state is written, the later load opens as flipped.
    func testAFlipBeforeTheViewIsLoadedIsRemembered() {
        let store = scratch()
        let c = SettingsShellViewController(model: SettingsModel(host: ModuleHost.shared),
                                            toolbarChannel: HelmWindowToolbarChannel(), band: .onMacOS(27),
                                            bar: ShellPageBarView(), store: store)
        XCTAssertFalse(c.isViewLoaded, "the view is loaded: the fixture is wrong")
        c.flipSidebar()
        XCTAssertEqual(store.object("sidebarCollapsed") as? Bool, true, "the store held \(String(describing: store.object("sidebarCollapsed")))")
        XCTAssertTrue(c.sidebarCollapsed, "the flip left the rows expanded")
        c.loadViewIfNeeded()
        XCTAssertEqual(c.shell.sidebarWidth, rail, "the view loaded \(c.shell.sidebarWidth) wide after a flip to the rail")
        XCTAssertNil(c.shell.foldTarget, "the load left a fold target of \(String(describing: c.shell.foldTarget))")
    }

    /// `fold(to:animated:)` called directly with a width that is not finite is refused: after a flip is heard, the
    /// width and `foldTarget` stand as they were and nothing more is heard; that the run in flight still completes as its own
    /// (`foldRun` untouched) is read from the code, no row holds it. Total failure prints:
    /// "the instrument is dead: <folds> after a flip" / "<case> was travelled to" / "<case> was heard as <folds>" /
    /// "<case> left the width at <w>" / "<case> left a fold target of <t>" / "<case> left the card at <frame>".
    func testAFoldToAWidthThatIsNotFiniteIsRefused() {
        let probe = Probe()
        let c = controller(probe, store: scratch())
        c.flipSidebar()
        let flip = [Fold(from: open, to: rail, duration: HelmMotion.sidebarFoldDuration)]
        XCTAssertEqual(probe.heard, flip, "the instrument is dead: \(probe.heard) after a flip")
        for (name, width) in [("not-a-number", CGFloat.nan), ("+infinity", CGFloat.infinity), ("-infinity", -CGFloat.infinity)] {
            let asked = c.shell.fold(to: width, animated: true)
            XCTAssertFalse(asked, "\(name) was travelled to")
            XCTAssertEqual(probe.heard, flip, "\(name) was heard as \(probe.heard)")
            XCTAssertEqual(c.shell.sidebarWidth, open, "\(name) left the width at \(c.shell.sidebarWidth)")
            XCTAssertEqual(c.shell.foldTarget, rail, "\(name) left a fold target of \(String(describing: c.shell.foldTarget))")
            c.shell.layoutSubtreeIfNeeded()
            let f = c.shell.card.frame
            XCTAssertTrue(f.minX.isFinite && f.width.isFinite && f.minY.isFinite && f.height.isFinite, "\(name) left the card at \(f)")
        }
    }
}
