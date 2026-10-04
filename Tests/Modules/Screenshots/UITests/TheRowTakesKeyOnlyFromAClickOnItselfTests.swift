import AppKit
import CoreGraphics
import HelmTestSupport
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The after-shot panel becomes key only while the row is unfolded, and only from a left mouse press or release on
/// itself; the keys are taken once for a row, given back once, and never left behind.** Folded or single, a click on a
/// thumbnail must not take the typing from the app the person is in, and a panel that could be key at any time may be
/// offered key by AppKit when another window of Helm is ordered out (the engineer's reading of AppKit, not measured
/// here). Read here: the predicate `canBecomeKey` asks,
/// with the events of every kind handed in; the toast's two seams (`takeKey`, `yieldKey`) counted across every way a row
/// opens and ends; one real panel, ordered in on this screen for a moment, that is never key without a click and is
/// gone when the window ends.
///
/// That AppKit makes the panel key from a mouse-up on a non-activating panel while another application stays active is
/// not measured here: no event can be put in flight from a test, and the engineer's own note says the same.
///
/// Total failure of the subject prints: a panel that takes key from a key press, a hover, another window's click or a
/// folded pile's, a row opened twice that took the keys twice, a keys-given-back count that is not the take count.
@MainActor
final class TheRowTakesKeyOnlyFromAClickOnItselfTests: XCTestCase {

    private var taken = 0, given = 0
    private var toasts: [ShotToast] = []
    private var scenes: [PileScene] = []

    override func tearDown() {
        for toast in toasts { toast.dismiss() }
        for scene in scenes { scene.teardown() }
        toasts = []
        scenes = []
        super.tearDown()
    }

    private func mouse(_ type: NSEvent.EventType, window: Int) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window,
                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private func key(_ type: NSEvent.EventType, window: Int) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window, context: nil,
                         characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53)!
    }

    private func entered(window: Int) -> NSEvent {
        NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window,
                               context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
    }

    // MARK: The predicate

    func testOnlyALeftPressOrReleaseOnThePanelItselfWhileUnfoldedTakesKey() {
        XCTAssertTrue(ShotPanel.takesKey(from: mouse(.leftMouseDown, window: 7), windowNumber: 7, unfolded: true))
        XCTAssertTrue(ShotPanel.takesKey(from: mouse(.leftMouseUp, window: 7), windowNumber: 7, unfolded: true),
                      "the click that opens the row is over when the row exists: the keys are taken at its release")
        let others: [(String, NSEvent)] = [
            ("right down", mouse(.rightMouseDown, window: 7)), ("right up", mouse(.rightMouseUp, window: 7)),
            ("other down", mouse(.otherMouseDown, window: 7)), ("moved", mouse(.mouseMoved, window: 7)),
            ("dragged", mouse(.leftMouseDragged, window: 7)), ("key down", key(.keyDown, window: 7)),
            ("key up", key(.keyUp, window: 7)), ("entered", entered(window: 7)),
        ]
        for (name, event) in others {
            XCTAssertFalse(ShotPanel.takesKey(from: event, windowNumber: 7, unfolded: true), "\(name) took the keys")
        }
        XCTAssertFalse(ShotPanel.takesKey(from: nil, windowNumber: 7, unfolded: true), "keys with no event under way")
    }

    func testAClickOnAnotherWindowOrOnAFoldedPanelTakesNothing() {
        for window in [8, 0, -1, Int.max] {
            XCTAssertFalse(ShotPanel.takesKey(from: mouse(.leftMouseDown, window: window), windowNumber: 7, unfolded: true),
                           "a click on window \(window) made panel 7 key")
        }
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            XCTAssertFalse(ShotPanel.takesKey(from: mouse(type, window: 7), windowNumber: 7, unfolded: false),
                           "a folded pile or a single shot took the keys from a click on it")
        }
        XCTAssertFalse(ShotPanel.takesKey(from: nil, windowNumber: 7, unfolded: false))
    }

    /// A panel that was never ordered in has a number no event carries.
    func testAPanelThatIsNotOnTheScreenIsNotTheWindowOfAnEventWithNoWindow() {
        let panel = ShotPanel(contentRect: NSRect(x: 0, y: 0, width: 50, height: 50),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        XCTAssertFalse(ShotPanel.takesKey(from: mouse(.leftMouseDown, window: 0), windowNumber: panel.windowNumber, unfolded: true),
                       "a click with no window is a click on a panel that has no number (\(panel.windowNumber))")
    }

    func testAPanelOfferedKeyWithNoClickRefusesItAndIsNeverTheMainWindow() {
        let panel = ShotPanel(contentRect: NSRect(x: 0, y: 0, width: 50, height: 50),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        XCTAssertFalse(panel.canBecomeKey, "folded")
        panel.isUnfolded = { true }
        XCTAssertFalse(panel.canBecomeKey, "unfolded, with no click in flight: key from nothing")
        XCTAssertFalse(panel.canBecomeMain)
    }

    // MARK: The toast's seams

    private func quiet() -> ShotToast {
        let toast = ShotToast(tick: { _ in try await Task.sleep(for: .seconds(1_000_000)) }, windowed: false)
        toast.takeKey = { [unowned self] in taken += 1 }
        toast.yieldKey = { [unowned self] in given += 1 }
        toasts.append(toast)
        return toast
    }

    private func shots(_ toast: ShotToast, _ count: Int) throws {
        for i in 1...count { toast.showDone(try ShotToastRig.picture(), caption: "c\(i)", file: nil) }
    }

    func testTheKeysAreTakenOnlyByTheClickThatOpensARowAndNeverByWhatDoesNot() throws {
        let toast = quiet()
        try shots(toast, 1)
        toast.unfold()
        toast.model.clicked(toast.model.shot(0)?.id ?? -1)
        toast.setHover(true)
        toast.setHover(false)
        XCTAssertEqual(taken, 0, "a single shot took the keys")
        try shots(toast, 2)
        toast.setHover(true)
        toast.model.pointer(over: true, shot: toast.model.shots.last?.id ?? -1, view: nil)
        toast.model.pointer(over: false, shot: toast.model.shots.last?.id ?? -1, view: nil)
        toast.scroll(by: 100)
        toast.showOldest()
        toast.fold()
        XCTAssertEqual(taken, 0, "a folded pile took the keys by a hover, a scroll or an Esc")
        XCTAssertEqual(given, 0)

        toast.model.clicked(toast.model.shots.last?.id ?? -1)
        XCTAssertTrue(toast.model.unfolded)
        XCTAssertEqual(taken, 1, "the click on the pile did not ask for the keys")
        // Everything that happens inside an open row: a click on a shot is Edit, a hover moves the capsule, a scroll.
        toast.model.pointer(over: true, shot: toast.model.shot(0)?.id ?? -1, view: nil)
        toast.model.clicked(toast.model.shot(0)?.id ?? -1)
        toast.model.clicked(toast.model.shot(1)?.id ?? -1)
        toast.scroll(by: 10)
        toast.showOldest()
        toast.unfold()
        XCTAssertEqual(taken, 1, "an open row took the keys again")
        XCTAssertEqual(given, 0)
        toast.fold()
        XCTAssertEqual(given, 1)
        XCTAssertEqual(taken, 1)
    }

    func testANewShotWhileTheRowIsOpenAndOneWhileFoldedTakeAndGiveNothing() throws {
        let toast = quiet()
        try shots(toast, 3)
        toast.unfold()
        try shots(toast, 1)
        XCTAssertEqual(taken, 1)
        XCTAssertEqual(given, 0, "a new shot gave the keys back from an open row")
        toast.fold()
        try shots(toast, 1)
        toast.showRefusal(.pasteboard)
        toast.model.say(nil)
        XCTAssertEqual(taken, 1)
        XCTAssertEqual(given, 1)
    }

    /// An open row's ends: each gives the keys back once, and a second end gives nothing.
    func testEveryEndOfARowGivesTheKeysBackOnceAndASecondEndGivesNothing() throws {
        let ends: [(String, (ShotToast) -> Void)] = [
            ("Esc", { $0.fold() }),
            ("the clock", { _ = $0.advance(by: 1) }),
            ("a refusal", { $0.showRefusal(.pasteboard) }),
            ("the editor", { $0.takeForEditing($0.model.shot(1)?.id ?? -1) }),
            ("the close of one of two", { $0.remove($0.model.shot(0)?.id ?? -1) }),
        ]
        for (name, end) in ends {
            taken = 0
            given = 0
            let toast = quiet()
            try shots(toast, name == "the close of one of two" ? 2 : 3)
            toast.unfold()
            XCTAssertEqual(taken, 1, name)
            end(toast)
            XCTAssertFalse(toast.model.unfolded, name)
            XCTAssertEqual(given, 1, "\(name): the keys were not given back, or twice")
            toast.fold()
            _ = toast.advance(by: 5)
            XCTAssertEqual(given, 1, "\(name): a second end gave them back again")
        }
    }

    /// The window's end with the row open: the row is not open any more, and no state of it is left to be keyed by.
    func testTheEndOfTheWindowAndTheModuleSwitchedOffTakeTheRowAndEverythingItHeld() async throws {
        let s = try PileScene(self, name: "key-off")
        scenes.append(s)
        for width in [400, 420, 440] { try await s.take(width: width) }
        s.toast.unfold()
        s.toast.model.focus = s.toast.model.shot(0)?.id ?? -1
        XCTAssertTrue(s.toast.model.unfolded)
        s.controller.cancel()
        XCTAssertFalse(s.toast.model.unfolded, "the module is off and its row is open")
        XCTAssertNil(s.toast.model.focus)
        XCTAssertTrue(s.toast.model.shots.isEmpty)
        XCTAssertTrue(s.toast.holds.isEmpty)
        XCTAssertFalse(s.toast.model.shown)
        s.toast.unfold()
        XCTAssertFalse(s.toast.model.unfolded, "a dead window unfolded")
    }

    // MARK: One real panel

    func testARealPanelIsNeverKeyWithoutAClickAndIsGoneWhenTheWindowEnds() throws {
        let toast = ShotToast(tick: { _ in try await Task.sleep(for: .seconds(1_000_000)) }, windowed: true)
        toasts.append(toast)
        let known = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
        try shots(toast, 3)
        let panels = NSApplication.shared.windows.filter { $0 is ShotPanel && !known.contains(ObjectIdentifier($0)) }.compactMap { $0 as? ShotPanel }
        XCTAssertEqual(panels.count, 1, "the toast has one panel")
        let panel = try XCTUnwrap(panels.first)
        XCTAssertTrue(panel.isVisible, "the control: the window is on the screen")
        XCTAssertFalse(panel.isKeyWindow)
        toast.unfold()
        XCTAssertTrue(panel.isUnfolded(), "the panel is not asked whether the row is open")
        XCTAssertFalse(panel.isKeyWindow, "the row took the keys with no click in flight")
        toast.fold()
        XCTAssertFalse(panel.isUnfolded())
        XCTAssertTrue(panel.isVisible, "giving the keys back took the window away")
        toast.unfold()
        toast.dismiss()
        XCTAssertFalse(panel.isVisible, "the window ended and its panel stays on the screen")
        XCTAssertFalse(panel.isKeyWindow)
    }
}
