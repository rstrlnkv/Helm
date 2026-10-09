import AppKit
@testable import HelmUI
import SwiftUI
import XCTest
@testable import HelmApp

/// **The stretch of time between `.helmModuleDisabled` and the page's teardown.**
///
/// `ModuleHost.disable` posts `.helmModuleDisabled` inside the switch itself, and the page's own mount
/// withdraws from the channel when SwiftUI next updates or dismantles it: later by reading, not measured. The
/// rows hold the state in which, at the notification, the page on screen still names the switched-off module,
/// the selection has not moved, and the channel still holds the page's last declaration. By reading, a
/// switch-off through `ModuleHost` does not reach that state: `SettingsModel`'s watch of the host's live
/// modules moves the selection to General before the notification is posted, and no row runs that route. What
/// a correct bar owes in that state: no press, submit or typed character reaches the page's closures, because
/// they close over the switched-off module's view model.
///
/// Each row builds a bar with the REAL zone (`ShellBarTabs`, `ShellBarActions` or `ShellBarSearch`), selects a
/// module's page, declares a page whose closures capture a sentinel, and asserts first that the page IS live
/// and that a press reaches the sentinel. Then it posts the notification the way `ModuleHost.disable` does
/// (`NotificationCenter.default.post(name: .helmModuleDisabled, object: key)`), turns the run loop, and
/// presses again.
///
/// **Seam missing, not added:** a module that is live in `ModuleHost` and then switched off for real needs a
/// host or descriptor made for a test; `ModuleHost.disable` is private and `setEnabled` would start a real
/// engine. Here the host holds no engine for the id (`liveModule(id) == nil`, asserted), which is the state
/// `disable` leaves; what is not reproduced is the module's engine having run, the stored flag written off,
/// and the model's watch moving the selection.
///
/// Not measured: a bar in a window that is shown; the real mount's dismantle order; a switch-off through
/// `ModuleHost.setEnabled`.
@MainActor
final class ThePageBarAfterItsModuleIsSwitchedOffTests: XCTestCase {

    @MainActor private final class Rig {
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let tabs = ShellBarTabs(titlebarIsTransparent: true, labelStyle: { .text })
        let actions = ShellBarActions(titlebarIsTransparent: true)
        let search = ShellBarSearch(titlebarIsTransparent: true)
        var bar: ShellPageBar!
        weak var sentinel: PageSentinel?
        var token = ""
        var generation = 0
    }


    private func turn(_ seconds: TimeInterval = 0.15) { SettingsWindowRig.pump(seconds) }

    /// A bar showing a module's page live. The subject is asserted here, so a row that reaches the
    /// notification has proved the page was live and a press reached its closure.
    private func rig(_ kind: PageKind, file: StaticString = #filePath, line: UInt = #line) -> Rig {
        let r = Rig()
        let id = type(of: ModuleRegistry.all[0]).id.rawValue
        XCTAssertNil(r.model.host.liveModule(id), "the host holds no engine for \(id): the state disable leaves",
                     file: file, line: line)
        r.model.selection = .module(id)
        r.bar = ShellPageBar(model: r.model, channel: r.channel, tabs: r.tabs, actions: r.actions,
                             search: r.search, titlebarIsTransparent: true)
        r.bar.graceInterval = 0.05
        r.bar.view.frame = NSRect(x: 0, y: 0, width: 856, height: 52)
        let s = PageSentinel()
        r.sentinel = s
        r.token = ShellPageBar.pageKey(for: r.model.selection)
        r.generation = r.channel.nextGeneration()
        r.channel.declare(pageContent(kind, s), token: r.token, generation: r.generation)
        r.bar.view.layoutSubtreeIfNeeded()
        r.tabs.apply(ShellPageBarView.Verdicts(tabsFolded: false))
        XCTAssertEqual(r.bar.presentation, .page(key: r.token, isLive: true, isDimmed: false),
                       "\(kind): the page is live before the notification", file: file, line: line)
        let before = s.hits
        press(kind, r, file: file, line: line)
        XCTAssertEqual(s.hits, before + 1, "\(kind): before the notification a press reaches the page",
                       file: file, line: line)
        return r
    }

    /// One press of the kind's zone, the way its control sends it. `again` is the press after the notification:
    /// it would write a value DIFFERENT from the first press's ("one" where the first wrote "two", "typed
    /// again" where the first wrote "typed"), so a write that gets through is seen against the value the
    /// page held just before the notification, and not against the sentinel's initial one.
    private func press(_ kind: PageKind, _ r: Rig, again: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        switch kind {
        case .tabs:
            guard let strip = (r.tabs.view as? ShellBarPlate)?.content?.everyView(ofType: NSSegmentedControl.self).first
            else { return XCTFail("tabs: no segmented control", file: file, line: line) }
            strip.selectedSegment = again ? 0 : 1
            strip.sendAction(strip.action, to: strip.target)
        case .actions:
            r.actions.model.press("go")
        case .search:
            let field = r.search.field
            field.stringValue = again ? "typed again" : "typed"
            r.search.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
            field.sendAction(field.action, to: field.target)
        }
    }

    private func disable(_ r: Rig) {
        NotificationCenter.default.post(name: .helmModuleDisabled, object: r.token)
        turn()
    }

    // MARK: - Before the page withdraws

    /// What the zones are told before the page withdraws. A correct bar does not call the page live.
    private func checkShown(_ kind: PageKind) {
        let r = rig(kind)
        disable(r)
        XCTAssertNotNil(r.sentinel, "\(kind): the channel still holds the page, so the sentinel is alive")
        XCTAssertNotNil(r.channel.content(for: AnyHashable(r.token)), "\(kind): the page has not withdrawn")
        if case .page(_, let isLive, let isDimmed) = r.bar.presentation {
            XCTAssertFalse(isLive, "\(kind): before the page withdraws the zones are told isLive=\(isLive) isDimmed=\(isDimmed)")
        }
    }

    private func checkReach(_ kind: PageKind) {
        let r = rig(kind)
        let s = r.sentinel!
        // What the rig's own press wrote, captured just before the notification.
        let before = s.hits
        let selected = s.selected
        let text = s.text
        if kind == .tabs { XCTAssertEqual(selected, "two", "tabs: the rig's own press wrote the selection") }
        if kind == .search { XCTAssertEqual(text, "typed", "search: the rig's own press wrote the text") }
        disable(r)
        press(kind, r, again: true)
        XCTAssertEqual(s.hits, before,
                       "\(kind): a press after the module is switched off, before the page withdraws, reached the page's closure (hits \(s.hits - before))")
        if kind == .tabs { XCTAssertEqual(s.selected, selected, "tabs: the page's selection was written after the switch-off") }
        if kind == .search { XCTAssertEqual(s.text, text, "search: the page's text was written after the switch-off") }
    }

    /// The control of `checkReach`: with NO notification the same second press writes a different value, so the
    /// reach rows above can see a write.
    private func checkTheSecondPressWrites(_ kind: PageKind) {
        let r = rig(kind)
        let s = r.sentinel!
        let selected = s.selected
        let text = s.text
        let before = s.hits
        press(kind, r, again: true)
        XCTAssertEqual(s.hits, before + 1, "\(kind): the second press reaches a live page")
        if kind == .tabs { XCTAssertNotEqual(s.selected, selected, "tabs: the second press writes a different selection") }
        if kind == .search { XCTAssertNotEqual(s.text, text, "search: the second press writes a different text") }
    }

    func testTabsSecondPressOnALivePageWritesSomethingDifferent() { checkTheSecondPressWrites(.tabs) }
    func testSearchSecondPressOnALivePageWritesSomethingDifferent() { checkTheSecondPressWrites(.search) }

    func testTabsShownBeforeThePageWithdraws() { checkShown(.tabs) }
    func testActionsShownBeforeThePageWithdraws() { checkShown(.actions) }
    func testSearchShownBeforeThePageWithdraws() { checkShown(.search) }

    func testTabsPressBeforeThePageWithdrawsDoesNotReachThePage() { checkReach(.tabs) }
    func testActionsPressBeforeThePageWithdrawsDoesNotReachThePage() { checkReach(.actions) }
    func testSearchSubmitBeforeThePageWithdrawsDoesNotReachThePage() { checkReach(.search) }

    // MARK: - After the withdraw, and after the grace

    private func checkAfter(_ kind: PageKind) {
        let r = rig(kind)
        disable(r)
        r.channel.withdraw(token: r.token, generation: r.generation)
        turn(0.01)
        XCTAssertNil(r.sentinel, "\(kind): after the withdraw the bar still holds the page's closures")
        turn(0.4)   // the grace is 0.05 s
        XCTAssertNil(r.sentinel, "\(kind): after the grace the bar still holds the page's closures")
        XCTAssertEqual(r.bar.presentation, .nameOnly, "\(kind): the grace fell back to the name")
    }

    func testTabsAfterTheWithdrawAndTheGraceHoldNothing() { checkAfter(.tabs) }
    func testActionsAfterTheWithdrawAndTheGraceHoldNothing() { checkAfter(.actions) }
    func testSearchAfterTheWithdrawAndTheGraceHoldNothing() { checkAfter(.search) }
    // MARK: - Switched off, then on again; and another module switched off

    private func enable(_ r: Rig) {
        NotificationCenter.default.post(name: .helmModuleEnabled, object: r.token)
        turn()
    }

    /// Off, on, then the page declares afresh (what a re-mounted page does): the bar lights it again and a
    /// press reaches the NEW page, and not the old one.
    private func checkFreshDeclareAfterOnAgain(_ kind: PageKind) {
        let r = rig(kind)
        let old = r.sentinel!
        disable(r)
        enable(r)
        let fresh = PageSentinel()
        r.generation = r.channel.nextGeneration()
        r.channel.declare(pageContent(kind, fresh), token: r.token, generation: r.generation)
        turn()
        r.tabs.apply(ShellPageBarView.Verdicts(tabsFolded: false))
        XCTAssertEqual(r.bar.presentation, .page(key: r.token, isLive: true, isDimmed: false),
                       "\(kind): after off, on and a fresh declare the page is live again")
        let oldHits = old.hits
        press(kind, r, again: true)
        XCTAssertEqual(fresh.hits, 1, "\(kind): a press reaches the fresh page")
        XCTAssertEqual(old.hits, oldHits, "\(kind): a press does not reach the old page")
    }

    func testTabsAfterOffOnAndAFreshDeclareLightTheBarAgain() { checkFreshDeclareAfterOnAgain(.tabs) }
    func testActionsAfterOffOnAndAFreshDeclareLightTheBarAgain() { checkFreshDeclareAfterOnAgain(.actions) }
    func testSearchAfterOffOnAndAFreshDeclareLightTheBarAgain() { checkFreshDeclareAfterOnAgain(.search) }

    /// Off, on, and the OLD content never withdrawn and nothing declared: PINNED. The strike on `.helmModuleEnabled`
    /// re-runs `refresh`, the channel still holds the old declaration, so the bar shows the OLD page live again and
    /// a press reaches the old closures. By reading, production withdraws before the module can be switched on
    /// again (the page's mount is gone once the module is off); no row runs a real mount. This row says what
    /// happens when that did not occur, and does not call it good.
    private func checkOldContentNotWithdrawn(_ kind: PageKind) {
        let r = rig(kind)
        let s = r.sentinel!
        disable(r)
        enable(r)
        XCTAssertNotNil(r.channel.content(for: AnyHashable(r.token)), "\(kind): the old content was never withdrawn")
        XCTAssertEqual(r.bar.presentation, .page(key: r.token, isLive: true, isDimmed: false),
                       "\(kind): PINNED: off then on with the old content still held shows the old page live")
        let before = s.hits
        press(kind, r, again: true)
        XCTAssertEqual(s.hits, before + 1, "\(kind): PINNED: a press reaches the old page's closure")
    }

    func testTabsOffOnWithTheOldContentStillHeldShowsTheOldPageLive() { checkOldContentNotWithdrawn(.tabs) }
    func testActionsOffOnWithTheOldContentStillHeldShowsTheOldPageLive() { checkOldContentNotWithdrawn(.actions) }
    func testSearchOffOnWithTheOldContentStillHeldShowsTheOldPageLive() { checkOldContentNotWithdrawn(.search) }

    /// `.helmModuleDisabled` naming another module leaves the page on screen live and pressable.
    private func checkAnotherModuleOff(_ kind: PageKind) {
        let r = rig(kind)
        let s = r.sentinel!
        let other = type(of: ModuleRegistry.all[1]).id.rawValue
        XCTAssertNotEqual(other, r.token)
        NotificationCenter.default.post(name: .helmModuleDisabled, object: other)
        turn(0.3)   // longer than the grace, 0.05 s
        XCTAssertEqual(r.bar.presentation, .page(key: r.token, isLive: true, isDimmed: false),
                       "\(kind): another module's switch-off leaves this page live")
        let before = s.hits
        press(kind, r, again: true)
        XCTAssertEqual(s.hits, before + 1, "\(kind): a press still reaches the page")
    }

    func testTabsAnotherModuleSwitchedOffLeavesThePageLive() { checkAnotherModuleOff(.tabs) }
    func testActionsAnotherModuleSwitchedOffLeavesThePageLive() { checkAnotherModuleOff(.actions) }
    func testSearchAnotherModuleSwitchedOffLeavesThePageLive() { checkAnotherModuleOff(.search) }
}
