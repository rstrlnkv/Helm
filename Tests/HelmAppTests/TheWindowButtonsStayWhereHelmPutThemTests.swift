import AppKit
import HelmTestSupport
import XCTest
@testable import HelmApp

/// **The window's three buttons have one owner that holds them down 6 and right 6 of where AppKit puts them,
/// and in the rail folds them so the page bar's name starts at the bar's leading.** The real
/// `SettingsWindow`, built and never ordered; the reference is a bare `NSWindow` of the same style mask, never
/// shown, so AppKit's own home is read and not written down here.
@MainActor
final class TheWindowButtonsStayWhereHelmPutThemTests: XCTestCase {

    private static let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

    /// Each button's top-left from the window's top-left, in window coordinates, keyed by the button's place
    /// in `types`: a missing button leaves its key out and the others keep theirs.
    private func topLeft(of window: NSWindow) -> [Int: CGPoint] {
        var found: [Int: CGPoint] = [:]
        for (i, type) in Self.types.enumerated() {
            guard let button = window.standardWindowButton(type) else { continue }
            let rect = button.convert(button.bounds, to: nil)
            found[i] = CGPoint(x: rect.minX, y: window.frame.height - rect.maxY)
        }
        return found
    }

    func testAfterAResizeAndAKeyChangeTheButtonsAreStillDownSixAndRightSix() throws {
        guard let rig = SettingsWindowRig.build(
            in: self, failure: "the window has no content view controller of the shell's type: no button was read")
        else { return }
        let reference = reference(like: rig)
        let home = topLeft(of: reference)
        XCTAssertEqual(home.count, 3,
                       "the reference window has \(home.count) standard buttons: 'not moved' was nil compared to nil")
        func check(_ when: String) {
            let held = topLeft(of: rig.window)
            XCTAssertEqual(held.count, 3,
                           "the window has \(held.count) standard buttons \(when): 'not moved' was nil compared to nil")
            for i in 0..<3 {
                guard let was = home[i], let now = held[i] else {
                    XCTFail("button \(i) is missing \(when): nothing was compared")
                    continue
                }
                XCTAssertEqual(now.x - was.x, ShellGeometry.buttonShift, accuracy: 0.5,
                               "button \(i) \(when): \(now.x - was.x) right of AppKit's home \(was.x), not \(ShellGeometry.buttonShift)")
                XCTAssertEqual(now.y - was.y, ShellGeometry.buttonDrop, accuracy: 0.5,
                               "button \(i) \(when): \(now.y - was.y) down from AppKit's home \(was.y), not \(ShellGeometry.buttonDrop)")
            }
        }
        settle(rig)
        check("after layout")
        for size in [NSSize(width: 880, height: 620), NSSize(width: 1200, height: 800)] {
            rig.window.setContentSize(size)
            settle(rig)
            check("after a resize to \(size)")
        }
        let name = { (n: Notification.Name) in Notification(name: n, object: rig.window) }
        rig.owner.windowDidResignKey(name(NSWindow.didResignKeyNotification))
        settle(rig)
        check("after the window resigned key")
        rig.owner.windowDidBecomeKey(name(NSWindow.didBecomeKeyNotification))
        settle(rig)
        check("after the window became key")
    }

    func testInTheRailTheNameStartsAtTheBarsLeading() throws {
        guard let rig = SettingsWindowRig.build(
            in: self, failure: "the window has no content view controller of the shell's type: no name was read")
        else { return }
        guard let bar = rig.pageBar?.view else {
            XCTFail("SettingsWindow holds no page bar: no name was read")
            return
        }
        rail(rig)
        guard let name = bar.frames?.name else {
            XCTFail("the bar has no name frame: nothing compared to leading")
            return
        }
        XCTAssertFalse(name.isNull || name.isEmpty, "the bar's name frame is \(name): nothing compared to leading")
        XCTAssertEqual(name.minX, ShellBarLayout.leading, accuracy: 0.5,
                       "the name starts at \(name.minX) in the rail, not at the bar's leading \(ShellBarLayout.leading)")
        XCTAssertFalse(bar.place.buttons.isNull, "the bar was handed no buttons: the obstacle is not tested")
        XCTAssertLessThan(bar.place.buttons.maxX, 0,
                          "the obstacle handed to the bar ends at \(bar.place.buttons.maxX), not left of the bar (< 0)")
    }

    // MARK: - the pure side (no window)

    func testTheCapsuleHidesNothingItCannotOpenOnto() {
        let place = ShellWindowButtons.placement
        for (name, home) in [("nil", nil), ("zero", CGRect.zero), ("null", CGRect.null), ("infinite", CGRect.infinite),
                             ("not-a-number x", CGRect(x: CGFloat.nan, y: 9, width: 60, height: 14)),
                             ("not-a-number height", CGRect(x: 9, y: 9, width: 60, height: CGFloat.nan))] as [(String, CGRect?)] {
            for rail in [false, true] {
                XCTAssertNil(place(home, rail), "a \(name) home (rail \(rail)) got a placement: the buttons would be moved or hidden")
            }
        }
        let home = CGRect(x: 9, y: 9, width: 60, height: 14)
        guard let expanded = place(home, false), let rail = place(home, true) else {
            XCTFail("no placement for \(home): nothing below was compared")
            return
        }
        XCTAssertNil(expanded.capsule, "expanded holds a capsule \(String(describing: expanded.capsule))")
        XCTAssertEqual(expanded.buttons, CGRect(x: 15, y: 15, width: 60, height: 14), "expanded buttons")
        XCTAssertEqual(expanded.offset, CGSize(width: 6, height: 6), "expanded offset")
        XCTAssertEqual(rail.buttons, CGRect(x: 19, y: 15, width: 60, height: 14), "rail buttons")
        XCTAssertEqual(rail.offset, CGSize(width: 10, height: 6), "rail offset")
        guard let capsule = rail.capsule else {
            XCTFail("the rail for \(home) holds no capsule: nothing was compared")
            return
        }
        XCTAssertEqual(capsule.closed, CGRect(x: 10, y: 13, width: 40, height: 18), "closed")
        XCTAssertEqual(capsule.open, CGRect(x: 10, y: 9, width: 78, height: 26), "open")
        XCTAssertEqual(capsule.hoverZone, CGRect(x: 0, y: 0, width: 94, height: 41), "hover zone")
        XCTAssertTrue(capsule.hoverZone.contains(capsule.closed) && capsule.hoverZone.contains(capsule.open),
                      "the hover zone \(capsule.hoverZone) does not hold both frames")
        guard let above = place(CGRect(x: 9, y: -7, width: 60, height: 14), true) else {
            XCTFail("a rail home above the content got no placement: it must still be moved, only no capsule")
            return
        }
        XCTAssertNil(above.capsule, "a rail whose buttons stand above the content got a capsule \(String(describing: above.capsule))")
        XCTAssertEqual(above.buttons.minY, -1, accuracy: 0.001, "the buttons above the content are still dropped by 6")
        XCTAssertNil(place(CGRect(x: 9, y: -7, width: 60, height: 14), false)?.capsule, "expanded above the content holds a capsule")
    }

    func testTheObstacleIsTheClosedCapsuleInTheRailAndTheButtonsOtherwise() {
        let home = CGRect(x: 9, y: 9, width: 60, height: 14)
        let rail = ShellWindowButtons.obstacle(ShellWindowButtons.placement(home: home, rail: true))
        let expanded = ShellWindowButtons.obstacle(ShellWindowButtons.placement(home: home, rail: false))
        XCTAssertFalse(rail.isNull || expanded.isNull, "no placement: null compared to null (rail \(rail), expanded \(expanded))")
        XCTAssertEqual(rail, CGRect(x: 10, y: 13, width: 40, height: 18), "the rail's obstacle is not the closed capsule")
        XCTAssertEqual(expanded, CGRect(x: 15, y: 15, width: 60, height: 14), "the expanded obstacle is not the buttons' union")
        XCTAssertTrue(ShellWindowButtons.obstacle(nil).isNull, "no placement must hold the bar to nothing (null)")
        let above = ShellWindowButtons.obstacle(ShellWindowButtons.placement(home: CGRect(x: 9, y: -7, width: 60, height: 14), rail: true))
        XCTAssertEqual(above, CGRect(x: 19, y: -1, width: 60, height: 14), "a capsule-less rail's obstacle is the buttons")
    }

    func testTheRailBeginsAtTheRailsWidthAndNotBefore() {
        let rail = ShellGeometry.railWidth
        XCTAssertTrue(ShellGeometry.isRail(sidebarWidth: rail), "the rail's own width \(rail) is not the rail")
        XCTAssertTrue(ShellGeometry.isRail(sidebarWidth: rail - 0.01), "just under the rail is not the rail")
        XCTAssertFalse(ShellGeometry.isRail(sidebarWidth: rail + 0.01), "just over the rail is the rail")
        XCTAssertFalse(ShellGeometry.isRail(sidebarWidth: CGFloat.nan), "not-a-number is the rail: a bad number would fold the buttons away")
        XCTAssertFalse(ShellGeometry.isRail(sidebarWidth: ShellGeometry.defaultSidebarWidth), "the default width is the rail")
    }

    // MARK: - with the real window

    /// The owner the shell holds, read by `Mirror`; the failure says what total failure would have printed.
    private func owner(of rig: SettingsWindowRig) -> ShellWindowButtons? {
        let found = Mirror(reflecting: rig.shell.shell).children.first { $0.label == "buttons" }?.value as? ShellWindowButtons
        if found == nil { XCTFail("the shell holds no ShellWindowButtons: nothing opened, nothing was held") }
        return found
    }

    private func settle(_ rig: SettingsWindowRig) {
        rig.window.contentView?.layoutSubtreeIfNeeded()
        SettingsWindowRig.pump(0.2)
        rig.window.contentView?.layoutSubtreeIfNeeded()
    }

    private func buttons(of window: NSWindow) -> [NSButton] {
        Self.types.compactMap { window.standardWindowButton($0) }
    }

    private func reference(like rig: SettingsWindowRig) -> NSWindow {
        let reference = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 760),
                                 styleMask: rig.window.styleMask, backing: .buffered, defer: true)
        reference.isReleasedWhenClosed = false
        return reference
    }

    /// Fails loudly, once, unless the window and the reference each hold all three buttons.
    private func threeButtons(_ rig: SettingsWindowRig, _ reference: NSWindow) -> (own: [NSButton], home: [NSButton])? {
        let own = buttons(of: rig.window), home = buttons(of: reference)
        guard own.count == 3, home.count == 3 else {
            XCTFail("the window has \(own.count) buttons and the reference \(home.count): 'not moved' was nil compared to nil")
            return nil
        }
        return (own, home)
    }

    private func rail(_ rig: SettingsWindowRig) {
        rig.shell.sidebarCollapsed = true
        XCTAssertTrue(rig.shell.sidebarCollapsed, "the sidebar did not fold: nothing is in the rail")
        settle(rig)
    }

    /// **Fold, unfold, fold: each of the three buttons stands where Helm puts it at every step, the zoom
    /// button included.** A fresh window folded straight to the rail does not show the defect, so the row
    /// folds a settled expanded window: there the zoom button stayed at AppKit's origin.
    func testFoldingASettledExpandedWindowMovesAllThreeButtonsToTheRail() throws {
        guard let rig = SettingsWindowRig.build(in: self, failure: "no shell: nothing was folded"),
              let owner = owner(of: rig) else { return }
        owner.reducesMotion = { true }
        let reference = reference(like: rig)
        guard let (own, homeButtons) = threeButtons(rig, reference) else { return }
        let home = topLeft(of: reference)
        guard home.count == 3 else {
            XCTFail("the reference holds \(home.count) buttons by top-left: nothing was compared")
            return
        }
        let union = homeButtons.reduce(CGRect.null) { $0.union($1.convert($1.bounds, to: nil)) }
        XCTAssertFalse(union.isNull || union.isEmpty, "the reference's union is \(union): the rail's offset was not computed")
        let railOffset = ShellGeometry.buttonsOffset(home: union, rail: true)
        let names = ["close", "miniaturize", "zoom"]

        func check(_ step: String, dx: CGFloat, dy: CGFloat, alpha: CGFloat) {
            let held = topLeft(of: rig.window)
            XCTAssertEqual(held.count, 3, "\(step): the window has \(held.count) buttons by top-left: nothing was compared")
            for i in 0..<3 {
                guard let was = home[i], let now = held[i] else {
                    XCTFail("\(step): the \(names[i]) button is missing (home \(String(describing: home[i])), now \(String(describing: held[i])))")
                    continue
                }
                let want = CGPoint(x: was.x + dx, y: was.y + dy)
                XCTAssertEqual(now.x, want.x, accuracy: 0.5, "\(step): the \(names[i]) button stands at \(now), should be at \(want) (home \(was))")
                XCTAssertEqual(now.y, want.y, accuracy: 0.5, "\(step): the \(names[i]) button stands at \(now), should be at \(want) (home \(was))")
                XCTAssertEqual(own[i].alphaValue, alpha, "\(step): the \(names[i]) button's alpha is \(own[i].alphaValue), not \(alpha)")
            }
        }
        func expanded(_ step: String) {
            rig.shell.sidebarCollapsed = false
            settle(rig)
            check(step, dx: ShellGeometry.buttonShift, dy: ShellGeometry.buttonDrop, alpha: 1)
        }
        func folded(_ step: String) {
            rail(rig)
            check(step, dx: railOffset.width, dy: railOffset.height, alpha: 0)
        }
        expanded("expanded, settled")
        folded("first fold")
        expanded("unfolded")
        folded("second fold")
    }

    func testInTheRailTheRealButtonsOpenOutOfTheCapsule() throws {
        guard let rig = SettingsWindowRig.build(in: self, failure: "no shell: nothing opened"),
              let owner = owner(of: rig) else { return }
        owner.reducesMotion = { true }
        let reference = reference(like: rig)
        guard let (own, _) = threeButtons(rig, reference) else { return }
        let homeTop = topLeft(of: reference)
        rail(rig)
        let capsule = owner.capsule
        XCTAssertFalse(capsule.isHidden, "no capsule in the rail: nothing opened")
        XCTAssertFalse(owner.isOpen, "the capsule is open without a pointer")
        let closed = owner.plateFrame
        XCTAssertEqual(closed.size, ShellGeometry.capsuleSize, "the closed plate is \(closed), not \(ShellGeometry.capsuleSize)")
        let held = topLeft(of: rig.window)
        for i in 0..<3 {
            XCTAssertEqual(held[i]?.x ?? -999, 19 + CGFloat(i) * ((homeTop[1]?.x ?? 0) - (homeTop[0]?.x ?? 0)), accuracy: 0.5,
                           "button \(i) in the rail stands at \(String(describing: held[i])), the first at x 19")
            XCTAssertEqual(held[i]?.y ?? -999, (homeTop[i]?.y ?? 0) + ShellGeometry.buttonDrop, accuracy: 0.5,
                           "button \(i) in the rail is not on the dropped row")
        }
        let union = owner.buttonsFrame
        XCTAssertFalse(union.isNull, "the owner reads no buttons: midY compared to nothing")
        XCTAssertEqual(union.midY, capsule.frame.minY + closed.midY, accuracy: 0.5,
                       "the buttons' row midY \(union.midY) is not the closed capsule's \(capsule.frame.minY + closed.midY)")
        XCTAssertEqual(own.map(\.alphaValue), [0, 0, 0], "the real buttons in the closed rail are not at alpha 0")

        owner.hover(true)
        XCTAssertTrue(owner.isOpen, "hover(true) in the rail did not open the capsule")
        XCTAssertEqual(own.map(\.alphaValue), [1, 1, 1], "after hover(true) the real buttons are not shown")
        let open = owner.plateFrame
        XCTAssertGreaterThan(open.width, closed.width, "the open plate \(open) is not wider than the closed \(closed)")
        let inPlate = owner.buttonsFrame.offsetBy(dx: -capsule.frame.minX, dy: -capsule.frame.minY)
        XCTAssertTrue(open.contains(inPlate), "the open plate \(open) does not contain the buttons \(inPlate)")
        owner.hover(false)
        XCTAssertFalse(owner.isOpen, "hover(false) left the capsule open")
        XCTAssertEqual(owner.plateFrame, closed, "after hover(false) the plate is not closed again")
        XCTAssertEqual(own.map(\.alphaValue), [0, 0, 0], "after hover(false) the real buttons still show")
    }

    /// **In a rail folded from a settled expanded window, opening and closing the capsule leaves each of
    /// the three buttons at the origin the fold placed it, with alpha 1 when open and 0 when closed.**
    func testOpeningAndClosingTheCapsuleLeavesAllThreeButtonsWhereTheyWerePlaced() throws {
        guard let rig = SettingsWindowRig.build(in: self, failure: "no shell: nothing opened"),
              let owner = owner(of: rig) else { return }
        owner.reducesMotion = { true }
        let reference = reference(like: rig)
        guard let (own, homeButtons) = threeButtons(rig, reference) else { return }
        let union = homeButtons.reduce(CGRect.null) { $0.union($1.convert($1.bounds, to: nil)) }
        XCTAssertFalse(union.isNull || union.isEmpty, "the reference's union is \(union): the rail's offset was not computed")
        let railOffset = ShellGeometry.buttonsOffset(home: union, rail: true)
        let names = ["close", "miniaturize", "zoom"]
        settle(rig)
        rail(rig)
        func check(_ step: String, alpha: CGFloat) {
            for i in 0..<3 {
                let want = CGPoint(x: homeButtons[i].frame.origin.x + railOffset.width,
                                   y: homeButtons[i].frame.origin.y - railOffset.height)
                let now = own[i].frame.origin
                XCTAssertEqual(now.x, want.x, accuracy: 0.5, "\(step): the \(names[i]) button stands at \(now), should be at \(want)")
                XCTAssertEqual(now.y, want.y, accuracy: 0.5, "\(step): the \(names[i]) button stands at \(now), should be at \(want)")
                XCTAssertEqual(own[i].alphaValue, alpha, "\(step): the \(names[i]) button's alpha is \(own[i].alphaValue), not \(alpha)")
            }
        }
        check("closed rail", alpha: 0)
        owner.hover(true)
        XCTAssertTrue(owner.isOpen, "the capsule did not open: nothing was read after it")
        check("after hover(true)", alpha: 1)
        owner.hover(false)
        XCTAssertFalse(owner.isOpen, "the capsule did not close: nothing was read after it")
        check("after hover(false)", alpha: 0)
    }

    /// **An animation open when the placement is given up writes no origin when it completes.** The rail,
    /// a hover change with Reduce Motion off, then `place(rail:)` gives the placement up, then the run loop
    /// runs past `HelmMotion.interfaceDuration` and the animation's completion lands. Full screen is not
    /// entered: no row here enters it, so the release is reached by another exit of `place(rail:)`, a button
    /// missing: the zoom button hidden, two buttons of three. That full screen's exit reaches the same
    /// `release()` is read, not run.
    /// AppKit's move of the buttons is made by hand, as the other rows make it: each button is put at the
    /// reference window's home. Each must still stand there after the completion, on both axes. The plate,
    /// wider than closed at the end, says only that the hover opened the capsule; that a completion lands and
    /// has something to write is shown by taking `wanted = [:]` out of `release()`: the row goes red.
    func testAnAnimationsEndWritesNoOriginOnceThePlacementIsGivenUp() throws {
        guard let rig = SettingsWindowRig.build(in: self, failure: "no shell: no animation was opened"),
              let owner = owner(of: rig) else { return }
        owner.reducesMotion = { false }
        let reference = reference(like: rig)
        guard let (own, homeButtons) = threeButtons(rig, reference),
              let zoom = rig.window.standardWindowButton(.zoomButton) else { return }
        let names = ["close", "miniaturize", "zoom"]
        settle(rig)
        rail(rig)
        let placed = own.map(\.frame.origin)
        let closedWidth = owner.plateFrame.width
        owner.hover(true)
        XCTAssertTrue(owner.isOpen, "the capsule did not open with animation on: no animation was open")

        zoom.isHidden = true
        owner.place(rail: true)
        XCTAssertFalse(owner.isOpen, "after the release the capsule is still open")
        XCTAssertTrue(owner.capsule.isHidden, "after the release the capsule is shown")

        for (i, button) in own.enumerated() { button.setFrameOrigin(homeButtons[i].frame.origin) }
        for i in 0..<3 {
            XCTAssertNotEqual(placed[i].x, homeButtons[i].frame.origin.x,
                              "the \(names[i]) button's placed x equals its home: a stale write would be invisible")
            XCTAssertEqual(own[i].frame.origin.x, homeButtons[i].frame.origin.x, accuracy: 0.01,
                           "the \(names[i]) button was not put at home by hand: it stands at \(own[i].frame.origin)")
        }
        let left = own.map(\.frame.origin)

        SettingsWindowRig.pump(0.6)
        XCTAssertGreaterThan(owner.plateFrame.width, closedWidth + 10,
                             "the plate stands \(owner.plateFrame.width) wide, as closed (\(closedWidth)): the hover opened nothing, so no animation was started")
        for i in 0..<3 {
            XCTAssertEqual(own[i].frame.origin.x, left[i].x, accuracy: 0.01,
                           "the \(names[i]) button stands at \(own[i].frame.origin) after the animation's completion; it was left at \(left[i]) (AppKit's home \(homeButtons[i].frame.origin), the stale placement \(placed[i]))")
            XCTAssertEqual(own[i].frame.origin.y, left[i].y, accuracy: 0.01,
                           "the \(names[i]) button stands at \(own[i].frame.origin) after the animation's completion; it was left at \(left[i]) (AppKit's home \(homeButtons[i].frame.origin), the stale placement \(placed[i]))")
        }
    }

    func testWithReduceMotionTheCapsuleChangesSizeInTheSameTurn() throws {
        guard let rig = SettingsWindowRig.build(in: self, failure: "no shell: nothing opened"),
              let owner = owner(of: rig) else { return }
        owner.reducesMotion = { true }
        guard threeButtons(rig, reference(like: rig)) != nil else { return }
        rail(rig)
        let closed = owner.plateFrame
        owner.hover(true)
        // No pump between the call and the reads: with Reduce Motion the size and the alpha are already the open ones.
        XCTAssertTrue(owner.isOpen, "the capsule did not open: no size could change")
        XCTAssertGreaterThan(owner.plateFrame.width, closed.width, "plate is \(owner.plateFrame) in the same turn, closed was \(closed)")
        XCTAssertEqual(buttons(of: rig.window).map(\.alphaValue), [1, 1, 1], "the real buttons' alpha did not change in the same turn")
        owner.hover(false)
        XCTAssertEqual(owner.plateFrame, closed, "closing took more than the same turn")
        XCTAssertEqual(buttons(of: rig.window).map(\.alphaValue), [0, 0, 0], "the real buttons' alpha did not close in the same turn")
    }

    func testNothingInTheBarMovesWhenTheCapsuleOpens() throws {
        guard let rig = SettingsWindowRig.build(in: self, failure: "no shell: nothing opened"),
              let owner = owner(of: rig) else { return }
        guard let bar = rig.pageBar?.view else {
            XCTFail("SettingsWindow holds no page bar: nothing was compared")
            return
        }
        owner.reducesMotion = { true }
        rig.open("homebrew", search: true)
        rail(rig)
        guard let before = bar.frames else {
            XCTFail("the bar has no frames in the rail: nothing was compared")
            return
        }
        let placeBefore = bar.place
        XCTAssertFalse(placeBefore.buttons.isNull, "the bar was handed no obstacle: null compared to null")
        owner.hover(true)
        XCTAssertTrue(owner.isOpen, "the capsule did not open: nothing could move")
        // The layout that would hand the bar a new obstacle is asked for, not waited for.
        rig.shell.shell.needsLayout = true
        settle(rig)
        XCTAssertEqual(bar.place, placeBefore, "the bar was handed another place when the capsule opened")
        XCTAssertEqual(bar.frames, before, "the bar's frames moved when the capsule opened")
    }

    func testAfterAResizeInTheRailTheButtonsAreStillUnderTheCapsule() throws {
        guard let rig = SettingsWindowRig.build(in: self, failure: "no shell: nothing resized"),
              let owner = owner(of: rig) else { return }
        owner.reducesMotion = { true }
        let reference = reference(like: rig)
        guard let (own, _) = threeButtons(rig, reference) else { return }
        let homeTop = topLeft(of: reference)
        rail(rig)
        for size in [NSSize(width: 880, height: 620), NSSize(width: 1200, height: 800)] {
            rig.window.setContentSize(size)
            settle(rig)
            let held = topLeft(of: rig.window)
            XCTAssertEqual(held[0]?.x ?? -999, 19, accuracy: 0.5, "after a resize to \(size) the close button is at \(String(describing: held[0])), not x 19")
            XCTAssertEqual(held[0]?.y ?? -999, (homeTop[0]?.y ?? 0) + ShellGeometry.buttonDrop, accuracy: 0.5,
                           "after a resize to \(size) the close button is off its row")
            XCTAssertEqual(own.map(\.alphaValue), [0, 0, 0], "after a resize to \(size) the buttons are not at alpha 0")
            XCTAssertFalse(owner.capsule.isHidden, "after a resize to \(size) the capsule is hidden")
        }
    }

    func testLeavingTheRailOrTheWindowGivesTheButtonsBack() throws {
        guard let rig = SettingsWindowRig.build(in: self, failure: "no shell: nothing was given back"),
              let owner = owner(of: rig) else { return }
        owner.reducesMotion = { true }
        let reference = reference(like: rig)
        guard let (own, homeButtons) = threeButtons(rig, reference) else { return }
        let home = topLeft(of: reference)
        rail(rig)
        owner.hover(true)
        XCTAssertTrue(owner.isOpen, "the capsule did not open: leaving it was not tested")
        rig.shell.sidebarCollapsed = false
        settle(rig)
        XCTAssertFalse(owner.isOpen, "expanded again, the capsule is still open")
        XCTAssertTrue(owner.capsule.isHidden, "expanded again, the capsule is still shown")
        XCTAssertEqual(own.map(\.alphaValue), [1, 1, 1], "expanded again, the buttons are not at alpha 1")
        owner.hover(true)
        XCTAssertFalse(owner.isOpen, "hover(true) when expanded opened a capsule that is not there")
        XCTAssertEqual(own.map(\.alphaValue), [1, 1, 1], "hover(true) when expanded changed the buttons' alpha")
        let held = topLeft(of: rig.window)
        XCTAssertEqual(held[0]?.x ?? -999, (home[0]?.x ?? 0) + 6, accuracy: 0.5, "expanded again, the close button is not 6 right of home")
        XCTAssertEqual(held[0]?.y ?? -999, (home[0]?.y ?? 0) + 6, accuracy: 0.5, "expanded again, the close button is not 6 down from home")

        rail(rig)
        owner.hover(true)
        owner.attach(to: nil)
        XCTAssertFalse(owner.isOpen, "after attach(to: nil) the capsule is still open")
        XCTAssertTrue(owner.capsule.isHidden, "after attach(to: nil) the capsule is shown")
        XCTAssertEqual(own.map(\.alphaValue), [1, 1, 1], "after attach(to: nil) the buttons are not at alpha 1")
        for i in 0..<3 {
            XCTAssertEqual(own[i].frame.origin.x, homeButtons[i].frame.origin.x, accuracy: 0.01, "after attach(to: nil) button \(i) is not at AppKit's home (x)")
            XCTAssertEqual(own[i].frame.origin.y, homeButtons[i].frame.origin.y, accuracy: 0.01, "after attach(to: nil) button \(i) is not at AppKit's home (y)")
        }
        let aside = CGPoint(x: homeButtons[0].frame.origin.x + 31, y: homeButtons[0].frame.origin.y - 3)
        own[0].setFrameOrigin(aside)
        settle(rig)
        XCTAssertEqual(own[0].frame.origin.x, aside.x, accuracy: 0.01, "a button knocked aside after attach(to: nil) was moved again (x)")
        XCTAssertEqual(own[0].frame.origin.y, aside.y, accuracy: 0.01, "a button knocked aside after attach(to: nil) was moved again (y)")
        XCTAssertEqual(own.map(\.alphaValue), [1, 1, 1], "after attach(to: nil) a layout hid the buttons")
    }

    func testDetachingFromAClosedRailShowsTheButtonsAtHome() throws {
        guard let rig = SettingsWindowRig.build(in: self, failure: "no shell: nothing was detached"),
              let owner = owner(of: rig) else { return }
        owner.reducesMotion = { true }
        guard let (own, homeButtons) = threeButtons(rig, reference(like: rig)) else { return }
        rail(rig)
        XCTAssertEqual(own.map(\.alphaValue), [0, 0, 0], "the closed rail did not hide the buttons: detaching it was not tested")
        owner.attach(to: nil)
        XCTAssertEqual(own.map(\.alphaValue), [1, 1, 1], "detached from the closed rail the buttons stay invisible")
        for i in 0..<3 {
            XCTAssertEqual(own[i].frame.origin.x, homeButtons[i].frame.origin.x, accuracy: 0.01, "detached from the rail button \(i) is not home (x)")
            XCTAssertEqual(own[i].frame.origin.y, homeButtons[i].frame.origin.y, accuracy: 0.01, "detached from the rail button \(i) is not home (y)")
        }
    }

    func testAButtonWrittenBackByHandIsPutBackInTheSameTurn() throws {
        guard let rig = SettingsWindowRig.build(in: self, failure: "no shell: nothing was knocked aside"),
              let owner = owner(of: rig) else { return }
        owner.reducesMotion = { true }
        let reference = reference(like: rig)
        guard let (own, homeButtons) = threeButtons(rig, reference) else { return }
        settle(rig)
        let homeMinX = homeButtons.map(\.frame.origin.x).min() ?? 0
        for inRail in [false, true] {
            if inRail { rail(rig) }
            // The superview is not flipped, so down is minus. The rail's x offset brings the union's left to 19.
            let shift = inRail ? 19 - homeMinX : ShellGeometry.buttonShift
            let alpha: CGFloat = inRail ? 0 : 1
            for (round, dy) in [CGFloat(0), -2].enumerated() {
                // Round 0: the row writes AppKit's home back by hand. Round 1: it writes another origin, 2 lower, as a new home.
                for (i, button) in own.enumerated() {
                    let home = CGPoint(x: homeButtons[i].frame.origin.x, y: homeButtons[i].frame.origin.y + dy)
                    button.setFrameOrigin(home)
                    let what = "\(inRail ? "rail" : "expanded"), round \(round), button \(i)"
                    // No layout and no pump between the write and the read: the same turn.
                    XCTAssertEqual(button.frame.origin.x, home.x + shift, accuracy: 0.5,
                                   "\(what): after the row wrote \(home) it stands at \(button.frame.origin), not x \(home.x + shift)")
                    XCTAssertEqual(button.frame.origin.y, home.y - ShellGeometry.buttonDrop, accuracy: 0.5,
                                   "\(what): after the row wrote \(home) it stands at \(button.frame.origin), not y \(home.y - ShellGeometry.buttonDrop)")
                    XCTAssertEqual(button.alphaValue, alpha, "\(what): alpha is \(button.alphaValue), not \(alpha)")
                }
            }
        }
        XCTAssertFalse(owner.buttonsFrame.isNull, "the owner reads no buttons: nothing above was a placement")
    }

    func testInputsNobodyFedTheOwner() throws {
        // Before attach: no window, no superview, nothing held.
        let alone = ShellWindowButtons()
        XCTAssertTrue(alone.place(rail: true).isNull, "place before attach answered an obstacle")
        XCTAssertTrue(alone.place(rail: false).isNull, "place before attach (expanded) answered an obstacle")
        alone.hover(true)
        XCTAssertFalse(alone.isOpen, "hover(true) before attach opened a capsule")
        alone.attach(to: nil)
        XCTAssertTrue(alone.buttonsFrame.isNull, "an owner without a window reads buttons")

        guard let rig = SettingsWindowRig.build(in: self, failure: "no shell: nothing was attached twice"),
              let owner = owner(of: rig) else { return }
        owner.reducesMotion = { true }
        let reference = reference(like: rig)
        guard let (own, homeButtons) = threeButtons(rig, reference) else { return }
        settle(rig)
        // Attach twice more, to the same window: still held down 6 right 6. How many observers are left is not read.
        owner.attach(to: rig.window)
        owner.attach(to: rig.window)
        // attach itself places nothing: it puts the buttons home and waits for a layout, so the layout is asked for.
        rig.shell.shell.needsLayout = true
        settle(rig)
        let home = topLeft(of: reference), held = topLeft(of: rig.window)
        for i in 0..<3 {
            XCTAssertEqual((held[i]?.x ?? -999) - (home[i]?.x ?? 0), 6, accuracy: 0.5, "after attaching twice button \(i) is not 6 right of home")
            XCTAssertEqual((held[i]?.y ?? -999) - (home[i]?.y ?? 0), 6, accuracy: 0.5, "after attaching twice button \(i) is not 6 down from home")
        }
        // Then nil: the buttons are home, and a knock moves nothing any more.
        owner.attach(to: nil)
        for i in 0..<3 {
            XCTAssertEqual(own[i].frame.origin.x, homeButtons[i].frame.origin.x, accuracy: 0.01, "after attach twice and nil button \(i) is not home (x)")
            XCTAssertEqual(own[i].frame.origin.y, homeButtons[i].frame.origin.y, accuracy: 0.01, "after attach twice and nil button \(i) is not home (y)")
            XCTAssertEqual(own[i].postsFrameChangedNotifications, homeButtons[i].postsFrameChangedNotifications,
                           "after attach(to: nil) button \(i) still posts frame changes the reference does not")
        }
        let aside = CGPoint(x: homeButtons[1].frame.origin.x + 17, y: homeButtons[1].frame.origin.y)
        own[1].setFrameOrigin(aside)
        XCTAssertEqual(own[1].frame.origin.x, aside.x, accuracy: 0.01, "a button knocked aside after attach(to: nil) was moved again")
    }

    /// **In the rail the pointer over the closed capsule, and over the hover zone outside its plate, reaches
    /// what lies under the capsule and never the capsule.** The frame view's `hitTest` is asked; the class
    /// of the answer is in the message, and printed (`CAPSULEHIT`). That a real click lands is not stated.
    func testThePointerOverTheCapsuleAnswersWhatLiesUnderIt() throws {
        guard let rig = SettingsWindowRig.build(in: self, failure: "no shell: nothing was pressed"),
              let owner = owner(of: rig) else { return }
        guard let frameView = rig.window.contentView?.superview else {
            XCTFail("the window has no frame view: nothing was pressed")
            return
        }
        rail(rig)
        let capsule = owner.capsule
        XCTAssertFalse(capsule.isHidden, "no capsule in the rail: nothing was pressed")
        XCTAssertFalse(owner.isOpen, "the capsule is open without a pointer")
        let plate = owner.plateFrame
        XCTAssertFalse(plate.isEmpty, "the closed plate is \(plate): nothing was pressed")
        let bounds = capsule.bounds
        let outside = [CGPoint(x: bounds.maxX - 2, y: bounds.maxY - 2), CGPoint(x: bounds.maxX - 2, y: bounds.minY + 2),
                       CGPoint(x: bounds.minX + 2, y: bounds.maxY - 2), CGPoint(x: bounds.minX + 2, y: bounds.minY + 2)]
            .first { !plate.contains($0) }
        var points: [(String, CGPoint)] = [("plate centre", CGPoint(x: plate.midX, y: plate.midY))]
        if let outside { points.append(("zone outside the plate", outside)) } else {
            XCTFail("every corner of the hover zone \(bounds) is on the plate \(plate): no point outside it was pressed")
        }
        for (label, local) in points {
            let at = capsule.convert(local, to: nil)
            let hit = frameView.hitTest(at)
            let name = hit.map { String(describing: type(of: $0)) } ?? "nil"
            print("CAPSULEHIT \(label) window \(at) -> \(name)")
            XCTAssertFalse(hit === capsule, "\(label) at \(at) answered the capsule itself")
            if let hit {
                XCTAssertFalse(hit.isDescendant(of: capsule), "\(label) at \(at) answered \(name), a view inside the capsule")
            }
        }
        XCTAssertEqual(points.count, 2, "\(points.count) of 2 points were pressed")
    }

    /// **With the sidebar expanded, and with the rail's capsule open, the frame view's `hitTest` at the centre
    /// of each real button answers that button.** Run in an unshown window. In the rail with the capsule
    /// closed (buttons at alpha 0) the row asserts nothing about who answers: it prints the answer's class
    /// (`BUTTONHIT`, for all nine points, with each button's frame in window coordinates from the window's
    /// top-left) and, for each of the three dots, which button's frame holds its centre (`DOTHIT`), and
    /// asserts nothing about that either. It asserts that all nine points were asked.
    func testWhatAnswersAtEachButtonsCentreInTheRailClosedAndOpen() throws {
        guard let rig = SettingsWindowRig.build(in: self, failure: "no shell: nothing was pressed"),
              let owner = owner(of: rig) else { return }
        owner.reducesMotion = { true }
        guard let frameView = rig.window.contentView?.superview else {
            XCTFail("the window has no frame view: nothing was pressed")
            return
        }
        guard let (own, _) = threeButtons(rig, reference(like: rig)) else { return }
        let names = ["close", "miniaturize", "zoom"]
        let windowHeight = rig.window.frame.height
        var asked = 0
        func ask(_ state: String, mustBeTheButton: Bool) {
            for (i, button) in own.enumerated() {
                let rect = button.convert(button.bounds, to: nil)
                let centre = CGPoint(x: rect.midX, y: rect.midY)
                let hit = frameView.hitTest(centre)
                let name = hit.map { String(describing: type(of: $0)) } ?? "nil"
                asked += 1
                print("BUTTONHIT \(state) \(names[i]) frame x \(rect.minX) y \(windowHeight - rect.maxY) w \(rect.width) h \(rect.height) alpha \(button.alphaValue) centre \(centre) -> \(name)")
                if mustBeTheButton {
                    XCTAssertTrue(hit === button, "\(state): at the centre \(centre) of the \(names[i]) button the answer is \(name), not the button")
                }
            }
        }
        settle(rig)
        XCTAssertEqual(own.map(\.alphaValue), [1, 1, 1], "the expanded buttons are not at alpha 1: the control is not one")
        ask("expanded", mustBeTheButton: true)
        rail(rig)
        XCTAssertEqual(own.map(\.alphaValue), [0, 0, 0], "the closed rail's buttons are not at alpha 0")
        ask("closed", mustBeTheButton: false)
        let buttonRects = own.map { $0.convert($0.bounds, to: nil) }
        let capsule = owner.capsule
        let dots = capsule.subviews.filter { abs($0.frame.width - 6) < 0.01 && abs($0.frame.height - 6) < 0.01 }
        XCTAssertEqual(dots.count, 3, "the capsule holds \(dots.count) dots of 6 pt, not 3: nothing was compared")
        for (i, dot) in dots.enumerated() {
            let r = dot.convert(dot.bounds, to: nil)
            let centre = CGPoint(x: r.midX, y: r.midY)
            let holder = buttonRects.firstIndex { $0.contains(centre) }
            print("DOTHIT dot \(i) centre x \(centre.x) y \(windowHeight - centre.y) lies in "
                  + (holder.map { "\(names[$0]) button's frame" } ?? "no button's frame"))
        }
        owner.hover(true)
        XCTAssertTrue(owner.isOpen, "the capsule did not open: the open state was not asked")
        XCTAssertEqual(own.map(\.alphaValue), [1, 1, 1], "the open capsule's buttons are not at alpha 1")
        ask("open", mustBeTheButton: true)
        XCTAssertEqual(asked, 9, "\(asked) of 9 points were asked")
    }

    // MARK: The dots' ink follows the system's control tint and the appearance the capsule draws under

    /// One dot's ink as sRGB components.
    private struct DotInk: CustomStringConvertible {
        let r: Double, g: Double, b: Double, a: Double
        var spread: Double { max(r, g, b) - min(r, g, b) }
        var description: String { String(format: "(%.2f %.2f %.2f a%.2f)", r, g, b, a) }
        func matches(_ o: DotInk, within e: Double = 0.01) -> Bool {
            abs(r - o.r) <= e && abs(g - o.g) <= e && abs(b - o.b) <= e && abs(a - o.a) <= e
        }
    }

    /// The red, yellow and green the dots draw in a non-graphite tint while the window is active.
    private static let colouredInks = [DotInk(r: 1.0, g: 0.37, b: 0.34, a: 1), DotInk(r: 1.0, g: 0.74, b: 0.18, a: 1),
                                       DotInk(r: 0.16, g: 0.78, b: 0.25, a: 1)]

    /// The capsule's three dots, left to right, in the rail; the tint seam answers `tint`, the window
    /// appears `active`. Nil, after a failure, when the dots are not three, or one has no layer colour or
    /// not one an sRGB reading can make: three equal nothings must not pass as three equal inks.
    private func dotInks(_ rig: SettingsWindowRig, _ owner: ShellWindowButtons, tint: NSControlTint,
                         active: Bool) -> [DotInk]? {
        owner.reducesMotion = { true }
        owner.controlTint = { tint }
        rail(rig)
        owner.setWindowAppearsActive(active)
        settle(rig)
        return readDots(owner)
    }

    /// What the three dots hold now.
    private func readDots(_ owner: ShellWindowButtons) -> [DotInk]? {
        let dots = owner.capsule.subviews.filter { abs($0.frame.width - 6) < 0.01 && abs($0.frame.height - 6) < 0.01 }
            .sorted { $0.frame.minX < $1.frame.minX }
        guard dots.count == 3 else {
            XCTFail("the capsule holds \(dots.count) dots of 6 pt, not 3: no ink was read")
            return nil
        }
        var read: [DotInk] = []
        for (i, dot) in dots.enumerated() {
            guard let cg = dot.layer?.backgroundColor, let ink = NSColor(cgColor: cg)?.usingColorSpace(.sRGB) else {
                XCTFail("dot \(i) has no readable layer colour: no ink was read")
                return nil
            }
            read.append(DotInk(r: Double(ink.redComponent), g: Double(ink.greenComponent), b: Double(ink.blueComponent),
                               a: Double(ink.alphaComponent)))
        }
        return read
    }

    /// **With the system on Graphite and the window active, the three dots are one neutral ink, each at an
    /// alpha of 0.5 or more and unsaturated, and not the inactive grey.** The tint the row asserts on comes
    /// through the owner's seam, set before the reading; the machine's own setting is never written, and
    /// what it answered while the shell was built is replaced by the redraw `setWindowAppearsActive` makes.
    func testWithGraphiteAndAnActiveWindowTheThreeDotsAreOneNeutralInk() throws {
        guard let rig = SettingsWindowRig.build(in: self, failure: "no shell: no dot was read"),
              let owner = owner(of: rig),
              let graphite = dotInks(rig, owner, tint: .graphiteControlTint, active: true) else { return }
        for (i, ink) in graphite.enumerated() {
            XCTAssertGreaterThanOrEqual(ink.a, 0.5, "graphite, active: dot \(i) is \(ink), its alpha under 0.5")
            XCTAssertLessThan(ink.spread, 0.02, "graphite, active: dot \(i) is \(ink), saturated (spread \(ink.spread))")
            XCTAssertTrue(ink.matches(graphite[0]), "graphite, active: dot \(i) is \(ink), dot 0 is \(graphite[0]): the three are not equal")
        }
        owner.setWindowAppearsActive(false)
        settle(rig)
        guard let inactive = readDots(owner) else { return }
        XCTAssertFalse(graphite[0].matches(inactive[0]),
                       "graphite active \(graphite[0]) and inactive \(inactive[0]) are the same ink: the window's state shows nowhere")
    }

    /// **Under the blue and the default tint and an active window the dots are red, yellow and green.**
    func testWithAnyOtherTintAndAnActiveWindowTheDotsAreRedYellowGreen() throws {
        for tint in [NSControlTint.blueControlTint, .defaultControlTint] {
            guard let rig = SettingsWindowRig.build(in: self, failure: "no shell: no dot was read"),
                  let owner = owner(of: rig),
                  let inks = dotInks(rig, owner, tint: tint, active: true) else { return }
            for i in 0..<3 {
                XCTAssertTrue(inks[i].matches(Self.colouredInks[i]),
                              "tint \(tint.rawValue), active: dot \(i) is \(inks[i]), not \(Self.colouredInks[i])")
            }
        }
    }

    /// **An inactive window draws one grey whatever the tint answers.**
    func testAnInactiveWindowDrawsOneGreyWhateverTheTintAnswers() throws {
        var seen: [[DotInk]] = []
        for tint in [NSControlTint.graphiteControlTint, .blueControlTint] {
            guard let rig = SettingsWindowRig.build(in: self, failure: "no shell: no dot was read"),
                  let owner = owner(of: rig),
                  let inks = dotInks(rig, owner, tint: tint, active: false) else { return }
            for (i, ink) in inks.enumerated() {
                XCTAssertGreaterThan(ink.a, 0, "tint \(tint.rawValue), inactive: dot \(i) is \(ink), not drawn")
                XCTAssertLessThan(ink.spread, 0.02, "tint \(tint.rawValue), inactive: dot \(i) is \(ink), not grey")
                XCTAssertTrue(ink.matches(inks[0]), "tint \(tint.rawValue), inactive: dot \(i) is \(ink), dot 0 is \(inks[0])")
            }
            seen.append(inks)
        }
        guard seen.count == 2 else { return }
        XCTAssertTrue(seen[0][0].matches(seen[1][0]),
                      "inactive under graphite is \(seen[0][0]) and under blue \(seen[1][0]): the tint reaches an inactive window")
    }

    /// **When the system's colours change the dots are read again, without the window's state changing.**
    /// The owner's `systemColorsDidChange()` is what the observer of the change calls; the row calls it
    /// after the seam's answer moved, in both directions.
    func testWhenTheSystemsColoursChangeTheDotsAreReadAgain() throws {
        guard let rig = SettingsWindowRig.build(in: self, failure: "no shell: no dot was read"),
              let owner = owner(of: rig),
              let coloured = dotInks(rig, owner, tint: .blueControlTint, active: true) else { return }
        XCTAssertTrue(coloured[0].matches(Self.colouredInks[0]), "blue, active: dot 0 is \(coloured[0]): the start is not coloured")
        owner.controlTint = { .graphiteControlTint }
        owner.systemColorsDidChange()
        guard let grey = readDots(owner) else { return }
        XCTAssertLessThan(grey[0].spread, 0.02, "after the change to graphite dot 0 is \(grey[0]), still saturated")
        XCTAssertTrue(grey[1].matches(grey[0]) && grey[2].matches(grey[0]), "after the change to graphite the dots are \(grey), not equal")
        owner.controlTint = { .blueControlTint }
        owner.systemColorsDidChange()
        guard let back = readDots(owner) else { return }
        XCTAssertTrue(back[0].matches(Self.colouredInks[0]), "after the change back to blue dot 0 is \(back[0]), not coloured")
    }

    /// **Under Graphite and an active window the dots' ink follows the appearance the capsule draws under:
    /// light on dark, dark on light, in either order.** A graphite ink made once and kept for the process
    /// would be right only under the appearance that made it first: the row goes dark, light, dark and asserts
    /// each step, so a row run against such an ink is red whatever ran before it. Total failure: the
    /// window's appearance never took (asserted first, from the capsule's own effective appearance), or the
    /// dots hold no readable colour (`readDots`); neither is allowed to pass as an ink.
    func testTheGraphiteInkFollowsTheAppearanceTheCapsuleDrawsUnder() throws {
        guard let rig = SettingsWindowRig.build(in: self, failure: "no shell: no dot was read"),
              let owner = owner(of: rig),
              dotInks(rig, owner, tint: .graphiteControlTint, active: true) != nil else { return }
        let steps: [(NSAppearance.Name, String)] = [(.darkAqua, "dark"), (.aqua, "light"), (.darkAqua, "dark")]
        for (n, (name, label)) in steps.enumerated() {
            rig.window.appearance = NSAppearance(named: name)
            owner.setWindowAppearsActive(true)
            settle(rig)
            let drawn = owner.capsule.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
            XCTAssertEqual(drawn, name, "step \(n): the capsule draws under \(drawn?.rawValue ?? "nothing"), not \(label): the appearance never took")
            guard drawn == name, let inks = readDots(owner) else { return }
            for (i, ink) in inks.enumerated() {
                let light = (ink.r + ink.g + ink.b) / 3 > 0.5
                XCTAssertEqual(light, name == .darkAqua,
                               "step \(n), graphite, active, \(label) appearance: dot \(i) is \(ink), \(light ? "light" : "dark") ink on a \(label) capsule")
            }
        }
    }

    /// **On a change of the window's appearance alone, with nothing else called, the dots' ink follows it.**
    /// Nothing calls `setWindowAppearsActive` on a change of theme; the redraw rests on the capsule's
    /// `viewDidChangeEffectiveAppearance`. The graphite tint and the active window are set before the first
    /// change (under light), then only `window.appearance` moves: dark, light, dark. Total failure: the
    /// appearance never took (asserted first from the capsule's own effective appearance), or the dots hold
    /// no readable colour (`readDots`).
    func testAChangeOfTheWindowsAppearanceAloneRedrawsTheGraphiteInk() throws {
        guard let rig = SettingsWindowRig.build(in: self, failure: "no shell: no dot was read"),
              let owner = owner(of: rig) else { return }
        rig.window.appearance = NSAppearance(named: .aqua)
        guard dotInks(rig, owner, tint: .graphiteControlTint, active: true) != nil else { return }
        let steps: [(NSAppearance.Name, String)] = [(.darkAqua, "dark"), (.aqua, "light"), (.darkAqua, "dark")]
        for (n, (name, label)) in steps.enumerated() {
            rig.window.appearance = NSAppearance(named: name)
            settle(rig)
            let drawn = owner.capsule.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
            XCTAssertEqual(drawn, name, "step \(n): the capsule draws under \(drawn?.rawValue ?? "nothing"), not \(label): the appearance never took")
            guard drawn == name, let inks = readDots(owner) else { return }
            for (i, ink) in inks.enumerated() {
                let light = (ink.r + ink.g + ink.b) / 3 > 0.5
                XCTAssertEqual(light, name == .darkAqua,
                               "step \(n), only the window's appearance changed, \(label): dot \(i) is \(ink), \(light ? "light" : "dark") ink on a \(label) capsule")
            }
        }
    }

    // MARK: The dots follow the notification itself

    /// A count of the questions the tint seam was asked; a box, so a closure the owner holds can bump it.
    private final class Asked { var count = 0 }

    private func postSystemColorsChanged() {
        NotificationCenter.default.post(name: NSColor.systemColorsDidChangeNotification, object: nil)
    }

    /// **The notification itself, posted through the default centre, makes the dots read the tint again; the
    /// row does not call `systemColorsDidChange()`, the observer does.** A dot that stays red under a
    /// graphite answer, or an answer never asked, is the total failure: after the post the count is
    /// asserted first, then the colours.
    func testPostingTheSystemsColoursNotificationRereadsTheDots() throws {
        guard let rig = SettingsWindowRig.build(in: self, failure: "no shell: no dot was read"),
              let owner = owner(of: rig),
              let coloured = dotInks(rig, owner, tint: .blueControlTint, active: true) else { return }
        XCTAssertTrue(coloured[0].matches(Self.colouredInks[0]), "blue, active: dot 0 is \(coloured[0]): the start is not coloured")
        let asked = Asked()
        owner.controlTint = { asked.count += 1; return .graphiteControlTint }
        postSystemColorsChanged()
        XCTAssertGreaterThanOrEqual(asked.count, 1, "the notification was posted and the tint was not asked: nobody observes it")
        guard let grey = readDots(owner) else { return }
        XCTAssertLessThan(grey[0].spread, 0.02, "after the post under graphite dot 0 is \(grey[0]), still saturated")
        XCTAssertTrue(grey[1].matches(grey[0]) && grey[2].matches(grey[0]), "after the post under graphite the dots are \(grey), not equal")
        owner.controlTint = { .blueControlTint }
        postSystemColorsChanged()
        guard let back = readDots(owner) else { return }
        for i in 0..<3 {
            XCTAssertTrue(back[i].matches(Self.colouredInks[i]), "after the post back under blue dot \(i) is \(back[i]), not \(Self.colouredInks[i])")
        }
    }

    /// **Once the buttons are detached the notification asks nothing; attached again, it asks once per post,
    /// not once per attach.** The count is the seam's questions, with a counted post before as the positive
    /// control: a count that never moved would pass "asks nothing" for the wrong reason.
    func testAfterDetachingThePostedNotificationRereadsNothing() throws {
        guard let rig = SettingsWindowRig.build(in: self, failure: "no shell: nothing was detached"),
              let owner = owner(of: rig) else { return }
        let asked = Asked()
        owner.controlTint = { asked.count += 1; return .graphiteControlTint }
        postSystemColorsChanged()
        XCTAssertEqual(asked.count, 1, "attached: one post asked the tint \(asked.count) times, not 1: the control did not run")
        owner.attach(to: nil)
        let before = asked.count
        postSystemColorsChanged()
        XCTAssertEqual(asked.count, before, "detached: a post asked the tint \(asked.count - before) more times: the observer survived the detach")
        owner.attach(to: rig.window)
        owner.attach(to: rig.window)
        asked.count = 0
        postSystemColorsChanged()
        XCTAssertEqual(asked.count, 1, "attached twice: one post asked the tint \(asked.count) times, not 1: observers piled up or none was added")
    }

    /// **A released owner is not reached by the notification.** The weak reference is nil first (the owner
    /// really died), then a post asks nothing and does not crash. Only read: a token left behind by `deinit`
    /// is hidden by the observer's weak capture, so this row cannot tell it from a removed one.
    func testAfterTheOwnerIsReleasedThePostedNotificationReachesNothing() throws {
        let asked = Asked()
        weak var gone: ShellWindowButtons?
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: true)
        autoreleasepool {
            let owner = ShellWindowButtons()
            owner.controlTint = { asked.count += 1; return .graphiteControlTint }
            owner.attach(to: window)
            let base = asked.count
            postSystemColorsChanged()
            XCTAssertEqual(asked.count, base + 1, "alive: a post asked the tint \(asked.count - base) times, not 1: the control did not run")
            gone = owner
        }
        XCTAssertNil(gone, "the owner is still alive after its last reference went: the release was not shown")
        let before = asked.count
        postSystemColorsChanged()
        XCTAssertEqual(asked.count, before, "released: a post asked the tint \(asked.count - before) more times")
    }
}
