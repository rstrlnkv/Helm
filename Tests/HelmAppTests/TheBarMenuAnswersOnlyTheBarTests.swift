import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import SwiftUI
import XCTest
import Module_KeepAwake_Engine
import Module_KeepAwake_UI
@testable import HelmApp
@testable import HelmUI

/// **Which views answer a right-click with the page bar's menu, and which must not.**
///
/// The menu is the bar view's own `NSView.menu`. AppKit asks the view under the press for `menu(for:)` and,
/// where that answers nothing, the view's superview, up the chain; so every row here does what AppKit does:
/// it hit-tests a point in the real `SettingsWindow` from the window's frame view (the titlebar's views
/// included), builds a right-mouse event at that point and asks each view from the hit upward, stopping at the
/// first menu. Nothing is asserted on a property nobody consults. The pop-up itself is modal and is not
/// raised here.
///
/// Every point is read off what the window laid out (a zone's frame, the card's frame, a window button's
/// own frame), and every row first asserts which view the point landed on, so a moved view moves the press
/// with it rather than leaving it on a place that happens to answer the same way. The places that open the
/// bar's menu are the name, the tabs, the actions, the search field resting open, the magnifier it rests
/// as, the status word and the empty space between the zones. The places that must not are the sidebar,
/// the glass round the card, the window's buttons (also in the rail, where they sit over the bar's own
/// frame) and the titlebar strip above the sidebar. In the rail the capsule's view is its hover zone, and
/// the right part of that zone lies over the bar's frame: the bar withholds its menu inside it
/// (`ShellPageBarView.menu(for:)`), opens it just right of it, and opens it where a hidden capsule's frame
/// lies. While the search field holds an editor, a press in the field lands on the field editor, whose
/// menu is the text menu.
///
/// Not held here: Control-click and a plain click. AppKit turns a Control-click into a context-menu press
/// before any view sees it, and only a real event through `NSWindow.sendEvent(_:)` would show that, which
/// raises the pop-up and blocks; a plain click on the bar is a window drag (`ShellPageBarView.mouseDown`),
/// which a test window that is never ordered cannot show.
@MainActor
final class TheBarMenuAnswersOnlyTheBarTests: XCTestCase {

    private static let collapseKey = "alwaysCollapseSearch"
    private static let keepAwake = KeepAwakeDescriptor.id.rawValue
    private static let enabledKey = "module.\(keepAwake).enabled"

    /// Raw, so a key the domain did not hold is removed again rather than written back as the typed
    /// getter's default.
    private var savedPageBar: Any?
    private var savedCollapse: Any?
    private var savedSidebar: Any?
    private var savedAppearance: Any?
    private var savedEnabled: Any?
    private var startedKeepAwake = false

    override func setUp() async throws {
        savedPageBar = AppSettings.store.object(PageBarStyle.storageKey)
        savedCollapse = AppSettings.store.object(Self.collapseKey)
        savedSidebar = AppSettings.store.object(SidebarStyle.storageKey)
        savedAppearance = AppSettings.store.object(HelmBarAppearance.storageKey)
        savedEnabled = UserDefaults.standard.object(forKey: Self.enabledKey)
        AppSettings.pageBarStyle = .moduleName
        AppSettings.alwaysCollapseSearch = false
        AppSettings.sidebarStyle = .colour
        AppSettings.barAppearance = .flat
    }

    override func tearDown() async throws {
        if startedKeepAwake {
            ModuleHost.shared.shutdown()
            if let savedEnabled { UserDefaults.standard.set(savedEnabled, forKey: Self.enabledKey) }
            else { UserDefaults.standard.removeObject(forKey: Self.enabledKey) }
        }
        AppSettings.store.set(savedPageBar, for: PageBarStyle.storageKey)
        AppSettings.store.set(savedCollapse, for: Self.collapseKey)
        AppSettings.store.set(savedSidebar, for: SidebarStyle.storageKey)
        AppSettings.store.set(savedAppearance, for: HelmBarAppearance.storageKey)
    }

    // MARK: - Rig

    /// The real window, laid out wide. By default a page of tabs, an action and a search is declared, and at
    /// that width the search rests open; with `keepAwake` Keep Awake is switched on and its own page is
    /// selected, and this rig declares nothing for it.
    private func mount(keepAwake: Bool = false) -> SettingsWindowRig? {
        if keepAwake {
            startedKeepAwake = true
            ModuleHost.shared.shutdown()
            ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
        }
        guard let rig = SettingsWindowRig.build(
            in: self, failure: "the window has no content view controller of the shell's type: no press was made")
        else { return nil }
        rig.window.setContentSize(NSSize(width: 1280, height: 760))
        if keepAwake {
            rig.model.selection = .module(Self.keepAwake)
        } else {
            rig.open("probe.menu", search: true)
        }
        settle(rig)
        rig.pageBar?.setWindowAppearsActive(true)
        settle(rig)
        return rig
    }

    private func settle(_ rig: SettingsWindowRig, _ seconds: TimeInterval = 0.4) {
        rig.window.contentView?.layoutSubtreeIfNeeded()
        SettingsWindowRig.pump(seconds)
        rig.window.contentView?.layoutSubtreeIfNeeded()
    }

    /// What AppKit would do with a right-click at `point` (window coordinates): the view under it, asked
    /// from the window's frame view down as `NSWindow.sendEvent(_:)` does, then `menu(for:)` of that view
    /// and of each superview in turn, the first menu winning.
    private struct Answer {
        let hit: NSView?
        let menu: NSMenu?
        /// The view whose `menu(for:)` produced the menu.
        let owner: NSView?
    }

    private func answer(_ rig: SettingsWindowRig, at point: NSPoint) -> Answer {
        guard let frameView = rig.window.contentView?.superview else { return Answer(hit: nil, menu: nil, owner: nil) }
        return answer(rig, at: point, hit: frameView.hitTest(frameView.convert(point, from: nil)))
    }

    /// The same walk from a view somebody else picked.
    private func answer(_ rig: SettingsWindowRig, at point: NSPoint, hit: NSView?) -> Answer {
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: 0,
                                       windowNumber: rig.window.windowNumber, context: nil, eventNumber: 0,
                                       clickCount: 1, pressure: 1)!
        var view = hit
        while let current = view {
            if let menu = current.menu(for: event) { return Answer(hit: hit, menu: menu, owner: current) }
            view = current.superview
        }
        return Answer(hit: hit, menu: nil, owner: nil)
    }

    private func windowPoint(_ rect: NSRect, in view: NSView) -> NSPoint {
        view.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
    }

    private func centre(of view: NSView) -> NSPoint { windowPoint(view.bounds, in: view) }

    /// The bar's own menu, or a failure: a bar with no menu would make every "must not" row pass.
    private func barMenu(_ rig: SettingsWindowRig) -> NSMenu? {
        guard let menu = rig.pageBar?.view.menu else {
            XCTFail("the page bar's view holds no menu: no press can be compared with it")
            return nil
        }
        return menu
    }

    private func describe(_ view: NSView?) -> String {
        var names: [String] = []
        var current = view
        while let v = current, names.count < 4 { names.append(String(String(describing: type(of: v)).prefix(60))); current = v.superview }
        return names.isEmpty ? "nothing" : names.joined(separator: " in ")
    }

    private func assertOpens(_ rig: SettingsWindowRig, _ place: String, at point: NSPoint, landing: (NSView) -> Bool,
                             file: StaticString = #filePath, line: UInt = #line) {
        guard let menu = barMenu(rig) else { return }
        let found = answer(rig, at: point)
        guard let hit = found.hit, landing(hit) else {
            return XCTFail("precondition: the press on \(place) at \(point) landed on \(describe(found.hit)), not on \(place)",
                           file: file, line: line)
        }
        XCTAssertTrue(found.menu === menu,
                      "a right-click on \(place) (\(describe(hit))) is answered by \(found.menu.map { _ in "the menu of \(describe(found.owner))" } ?? "no menu"), not by the bar's menu",
                      file: file, line: line)
    }

    private func assertStaysShut(_ rig: SettingsWindowRig, _ place: String, at point: NSPoint, landing: (NSView) -> Bool,
                                 file: StaticString = #filePath, line: UInt = #line) {
        guard let menu = barMenu(rig) else { return }
        let found = answer(rig, at: point)
        guard let hit = found.hit, landing(hit) else {
            return XCTFail("precondition: the press on \(place) at \(point) landed on \(describe(found.hit)), not on \(place)",
                           file: file, line: line)
        }
        XCTAssertFalse(found.menu === menu,
                       "a right-click on \(place) (\(describe(hit))) opens the bar's menu, through \(describe(found.owner))",
                       file: file, line: line)
    }

    /// Lands in the zone's view. The name and the status are the window's handle: a press on them answers
    /// the bar view itself (`ShellPageBarView.hitTest(_:)`), so for those two the bar view is the landing.
    private func inZone(_ rig: SettingsWindowRig, _ zone: ShellPageBarView.Zone) -> (NSView) -> Bool {
        { hit in
            guard let bar = rig.pageBar?.view, let view = bar.view(for: zone) else { return false }
            if zone == .name || zone == .status { return hit === bar }
            return hit === view || hit.isDescendant(of: view)
        }
    }

    private func zoneView(_ rig: SettingsWindowRig, _ zone: ShellPageBarView.Zone) -> NSView? {
        guard let view = rig.pageBar?.view.view(for: zone), !view.isHidden else {
            XCTFail("the bar shows no \(zone) zone: nothing is pressed there")
            return nil
        }
        return view
    }

    // MARK: - The bar's own places

    /// **The name, the tabs, the actions and the search resting open** each answer the bar's menu.
    func testTheNameTheTabsTheActionsAndTheOpenFieldAnswerTheBarsMenu() {
        guard let rig = mount() else { return }
        for zone in [ShellPageBarView.Zone.name, .tabs, .actions, .search] {
            guard let view = zoneView(rig, zone) else { continue }
            assertOpens(rig, "the \(zone) zone", at: centre(of: view), landing: inZone(rig, zone))
        }
        guard let field = rig.pageBar?.view.view(for: .search)?.everyView(ofType: NSSearchField.self).first
        else { return XCTFail("no search field in the search zone") }
        XCTAssertFalse(field.isHidden, "precondition: the search does not rest as an open field")
        assertOpens(rig, "the resting search field", at: centre(of: field), landing: { $0 === field || $0.isDescendant(of: field) })
    }

    /// **The magnifier the search rests as**, with Always Collapse Search on, answers the bar's menu; the
    /// press has to land on the magnifier's own button, not on the field it hides.
    func testTheRestingMagnifierAnswersTheBarsMenu() {
        guard let rig = mount() else { return }
        AppSettings.alwaysCollapseSearch = true
        NotificationCenter.default.post(name: .helmAlwaysCollapseSearchChanged, object: nil)
        settle(rig)
        guard let zone = zoneView(rig, .search),
              let field = zone.everyView(ofType: NSSearchField.self).first,
              let magnifier = field.superview?.subviews.compactMap({ $0 as? NSButton }).first
        else { return XCTFail("no magnifier in the search zone") }
        XCTAssertTrue(field.isHidden, "precondition: the field is not folded into its magnifier")
        XCTAssertFalse(magnifier.isHidden, "precondition: the magnifier is hidden")
        assertOpens(rig, "the resting magnifier", at: centre(of: magnifier), landing: { $0 === magnifier })
    }

    /// **The status word** a page with no tabs, actions or search shows beside its name answers the bar's
    /// menu. Keep Awake is idle in a test process, so its word is the quiet one.
    func testTheStatusAnswersTheBarsMenu() {
        guard let rig = mount(keepAwake: true) else { return }
        guard let status = zoneView(rig, .status) else { return }
        assertOpens(rig, "the status", at: centre(of: status), landing: inZone(rig, .status))
    }

    /// **The empty space between the zones, at the bar's own height**, answers the bar's menu: between the
    /// name and the tabs, and left of the name.
    func testTheEmptySpaceBetweenTheZonesAnswersTheBarsMenu() {
        guard let rig = mount() else { return }
        guard let bar = rig.pageBar?.view, let frames = bar.frames else { return XCTFail("the bar has no frames") }
        XCTAssertGreaterThan(frames.tabs.minX - frames.name.maxX, 16, "precondition: no room between the name and the tabs")
        let between = NSPoint(x: (frames.name.maxX + frames.tabs.minX) / 2, y: bar.bounds.midY)
        let left = NSPoint(x: frames.name.minX / 2, y: bar.bounds.midY)
        for (place, point) in [("the space between the name and the tabs", between), ("the space left of the name", left)] {
            assertOpens(rig, place, at: bar.convert(point, to: nil), landing: { $0 === bar })
        }
    }

    // MARK: - Where it must stay shut

    /// **The sidebar** answers no bar menu.
    func testTheSidebarDoesNotAnswerTheBarsMenu() {
        guard let rig = mount() else { return }
        let shell = rig.shell.shell
        let card = shell.card.frame
        let point = shell.convert(NSPoint(x: card.minX / 2, y: shell.bounds.midY), to: nil)
        assertStaysShut(rig, "the sidebar", at: point, landing: { !$0.isDescendant(of: shell.card) })
    }

    /// **The glass round the card** (the card's `ShellGeometry.inset` from the window's bottom and
    /// trailing edges)
    /// answers no bar menu. Asked from the window, a press that close to the edge lands on the window's
    /// own frame (its resize border), which answers none; asked of the shell's own hit test, the press lands
    /// on the glass view itself, and the glass and its ancestors answer none.
    func testTheGlassDoesNotAnswerTheBarsMenu() {
        guard let rig = mount() else { return }
        let shell = rig.shell.shell
        guard let glass = shell.subviews.first(where: { $0 is NSGlassEffectView }),
              let frameView = rig.window.contentView?.superview
        else { return XCTFail("the shell holds no glass view: nothing is pressed") }
        let spots = [("the glass under the card", NSPoint(x: shell.bounds.midX, y: shell.bounds.maxY - 2)),
                     ("the glass right of the card", NSPoint(x: shell.bounds.maxX - 2, y: shell.bounds.midY))]
        for (place, point) in spots {
            let inWindow = shell.convert(point, to: nil)
            assertStaysShut(rig, "\(place), from the window", at: inWindow,
                            landing: { $0 === frameView || $0.isDescendant(of: glass) })
            let direct = answer(rig, at: inWindow, hit: shell.hitTest(shell.convert(point, to: shell.superview)))
            XCTAssertTrue(direct.hit.map { $0 === glass || $0.isDescendant(of: glass) } ?? false,
                          "precondition: \(place) landed on \(describe(direct.hit)), not on the glass")
            XCTAssertNil(direct.menu, "a right-click on \(place) is answered by the menu of \(describe(direct.owner))")
        }
    }

    /// **The window's three buttons** answer no bar menu; the press has to land on the button.
    func testTheWindowButtonsDoNotAnswerTheBarsMenu() {
        guard let rig = mount() else { return }
        for (kind, name) in [(NSWindow.ButtonType.closeButton, "close"), (.miniaturizeButton, "minimise"), (.zoomButton, "zoom")] {
            guard let button = rig.window.standardWindowButton(kind) else {
                XCTFail("no \(name) button on the window"); continue
            }
            assertStaysShut(rig, "the \(name) button", at: centre(of: button), landing: { $0 === button })
        }
    }

    /// **In the rail the three buttons stand at alpha 0 under a closed capsule that answers no hit**, so
    /// the press lands on whatever lies under the capsule's view, whose frame is the hover zone. The right
    /// end of that zone lies over the bar's frame, where the press lands on `ShellPageBarView` and the bar
    /// withholds its menu (`ShellPageBarView.menu(for:)`); the zone's middle must answer no bar menu either.
    func testTheClosedCapsuleInTheRailDoesNotAnswerTheBarsMenu() {
        guard let rig = mount() else { return }
        rig.shell.sidebarCollapsed = true
        XCTAssertTrue(rig.shell.sidebarCollapsed, "precondition: the sidebar did not fold")
        settle(rig)
        let shell = rig.shell.shell
        guard let capsule = shell.subviews.last, capsule !== shell.card else {
            return XCTFail("the shell holds no capsule above the card: nothing is pressed")
        }
        XCTAssertFalse(capsule.isHidden, "precondition: the capsule is hidden in the rail")
        let frame = capsule.frame
        for (place, x) in [("the middle of the capsule's hover zone", frame.midX), ("the right end of the capsule's hover zone", frame.maxX - 2)] {
            assertStaysShut(rig, place, at: shell.convert(NSPoint(x: x, y: frame.midY), to: nil), landing: { _ in true })
        }
    }

    /// **A capsule that is hidden holds no ground**: in the rail, with the zoom button hidden, the
    /// shell releases the buttons and hides the capsule, which keeps the frame it had. A right click on the
    /// bar where that frame lies, the right end of what was the capsule, opens the bar's menu again. The
    /// expanded sidebar cannot show this: the hidden frame then lies left of the card, over no bar at all.
    func testAHiddenCapsuleLeavesTheBarsMenuWhereItWas() {
        guard let rig = mount() else { return }
        rig.shell.sidebarCollapsed = true
        XCTAssertTrue(rig.shell.sidebarCollapsed, "precondition: the sidebar did not fold")
        settle(rig)
        let shell = rig.shell.shell
        guard let capsule = shell.subviews.last, capsule !== shell.card else {
            return XCTFail("the shell holds no capsule above the card: nothing is pressed")
        }
        XCTAssertFalse(capsule.isHidden, "precondition: the capsule is hidden in the rail")
        let frame = capsule.frame
        let point = shell.convert(NSPoint(x: frame.maxX - 2, y: frame.midY), to: nil)
        assertStaysShut(rig, "the right end of the capsule's hover zone", at: point, landing: { _ in true })
        guard let zoom = rig.window.standardWindowButton(.zoomButton) else { return XCTFail("no zoom button") }
        zoom.isHidden = true
        defer { zoom.isHidden = false }
        rig.shell.shell.needsLayout = true
        settle(rig)
        XCTAssertTrue(capsule.isHidden, "precondition: the capsule still shows with a button hidden")
        assertOpens(rig, "the bar where the hidden capsule's frame lies", at: point,
                    landing: { $0 === rig.pageBar?.view })
    }

    /// **Just right of the capsule's hover zone in the rail, still at the zone's height, the bar's menu
    /// opens and the press lands on the bar.** The bar keeps its menu off the capsule's reach only, and that
    /// reach is handed over in the bar's coordinates (`ShellContentView.layout()` converts it); a reach
    /// handed over in the shell's coordinates, where the bar starts further right, would refuse the menu on
    /// this point too. The point is checked to lie outside the capsule's frame and inside the bar's frame
    /// before anything is asked of it.
    func testJustRightOfTheCapsulesHoverZoneInTheRailTheBarsMenuOpens() {
        guard let rig = mount() else { return }
        rig.shell.sidebarCollapsed = true
        XCTAssertTrue(rig.shell.sidebarCollapsed, "precondition: the sidebar did not fold")
        settle(rig)
        let shell = rig.shell.shell
        guard let capsule = shell.subviews.last, capsule !== shell.card, let bar = rig.pageBar?.view else {
            return XCTFail("the shell holds no capsule above the card, or no bar: nothing is pressed")
        }
        XCTAssertFalse(capsule.isHidden, "precondition: the capsule is hidden in the rail")
        let frame = capsule.frame
        let inShell = NSPoint(x: frame.maxX + 6, y: frame.midY)
        XCTAssertFalse(frame.contains(inShell), "precondition: the point \(inShell) lies inside the capsule's frame \(frame)")
        let inBar = bar.convert(inShell, from: shell)
        XCTAssertTrue(bar.bounds.contains(inBar), "precondition: the point lies outside the bar, at \(inBar) of \(bar.bounds)")
        XCTAssertTrue(bar.place.reach.contains(NSPoint(x: inBar.x - 12, y: inBar.y)),
                      "precondition: the bar's reach \(bar.place.reach) is not the capsule's: no menu is withheld anywhere")
        assertOpens(rig, "the bar just right of the capsule's hover zone", at: shell.convert(inShell, to: nil),
                    landing: { $0 === bar })
    }

    /// **The titlebar strip above the sidebar**, right of the buttons and above the page's top, answers no
    /// bar menu.
    func testTheTitlebarStripAboveTheSidebarDoesNotAnswerTheBarsMenu() {
        guard let rig = mount() else { return }
        guard let zoom = rig.window.standardWindowButton(.zoomButton) else { return XCTFail("no zoom button") }
        let shell = rig.shell.shell
        let right = zoom.convert(zoom.bounds, to: nil).maxX
        let edge = shell.card.frame.minX
        XCTAssertGreaterThan(edge - right, 12, "precondition: no strip between the buttons and the card at \(edge)")
        let point = NSPoint(x: (right + edge) / 2, y: zoom.convert(NSPoint(x: 0, y: zoom.bounds.midY), to: nil).y)
        XCTAssertGreaterThan(point.y, rig.window.contentLayoutRect.maxY,
                             "precondition: the point is below the titlebar, in the page's area")
        assertStaysShut(rig, "the titlebar strip above the sidebar", at: point, landing: { $0 !== zoom })
    }

    /// **Inside the search field while it holds an editor, the press lands on the field editor and its
    /// text menu wins; on the name the bar's menu still opens** — the exemption is the field, not the whole
    /// bar for as long as a search is open.
    func testTheFieldBeingEditedKeepsItsOwnMenuAndOnlyThere() {
        guard let rig = mount() else { return }
        guard let field = rig.pageBar?.view.view(for: .search)?.everyView(ofType: NSSearchField.self).first,
              let name = zoneView(rig, .name) else { return XCTFail("the bar is missing a zone") }
        XCTAssertTrue(rig.window.makeFirstResponder(field), "precondition: the window refused the field an editor")
        guard let editor = field.currentEditor() else { return XCTFail("precondition: no field editor arrived") }
        settle(rig)
        let inside = field.convert(NSPoint(x: 30, y: field.bounds.midY), to: nil)
        assertStaysShut(rig, "the field being edited", at: inside, landing: { $0 === editor || $0.isDescendant(of: field) })
        XCTAssertNotNil(answer(rig, at: inside).menu, "the field being edited answers no menu at all: no text menu")
        let asked = NSEvent.mouseEvent(with: .rightMouseDown, location: inside, modifierFlags: [], timestamp: 0,
                                       windowNumber: rig.window.windowNumber, context: nil, eventNumber: 0,
                                       clickCount: 1, pressure: 1)!
        XCTAssertFalse(field.menu(for: asked) === rig.pageBar?.view.menu,
                       "the field being edited answers the bar's menu itself")
        assertOpens(rig, "the name, while the field is being edited", at: centre(of: name), landing: inZone(rig, .name))
        rig.window.makeFirstResponder(nil)
    }
}
