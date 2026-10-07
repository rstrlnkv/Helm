import AppKit
import SwiftUI
import XCTest
import HelmTestSupport
@testable import HelmApp
@testable import HelmUI

/// **The page bar's search zone (`ShellBarSearch`) rests as its magnifier when the setting says so and the
/// field is empty, and holds the field otherwise.**
///
/// No window is ordered or made key. The first two rows are measurements of AppKit that the zone stands on,
/// each asserting what it read, in an unshown window or a bare bitmap: that a search field takes an editor
/// and gives it up, and ends its editing, in a window that was never shown; and what a search field draws
/// in a 283 by 36 frame.
@MainActor
final class TheSearchRestsAsItsMagnifierTests: XCTestCase {

    // MARK: - What an unshown window does to a field

    private final class Ender: NSObject, NSSearchFieldDelegate {
        var ended = 0
        /// For each end heard, whether the field still had its editor at that moment.
        var editorAttachedAtEnd: [Bool] = []
        weak var field: NSSearchField?
        func controlTextDidEndEditing(_ obj: Notification) {
            ended += 1
            editorAttachedAtEnd.append(field?.currentEditor() != nil)
        }
    }

    /// Measured on 27.2: in a window built and never ordered front a search field takes first responder and
    /// has an editor at once; `makeFirstResponder(nil)` removes the editor and delivers
    /// `controlTextDidEndEditing` inside the call, not a turn later.
    func testAFieldTakesAndGivesUpItsEditorInAWindowThatWasNeverShown() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let field = NSSearchField(frame: NSRect(x: 10, y: 10, width: 283, height: 36))
        let ender = Ender()
        field.delegate = ender
        ender.field = field
        window.contentView?.addSubview(field)
        XCTAssertFalse(window.isVisible, "precondition: the window was shown")
        XCTAssertFalse(window.isKeyWindow, "precondition: the window is key")

        XCTAssertTrue(window.makeFirstResponder(field), "an unshown window refused the field")
        XCTAssertNotNil(field.currentEditor(), "the field has no editor right after it took first responder")
        XCTAssertEqual(ender.ended, 0, "editing ended before it was asked to")

        XCTAssertTrue(window.makeFirstResponder(nil), "an unshown window refused to resign the field")
        XCTAssertNil(field.currentEditor(), "the editor outlived the resignation")
        XCTAssertEqual(ender.ended, 1, "the delegate did not hear the end of editing inside the call")
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
        XCTAssertEqual(ender.ended, 1, "the end of editing was delivered again a turn later")
        XCTAssertEqual(ender.editorAttachedAtEnd, [true],
                       "the field had no editor inside the notification: it arrives with the editor still attached")

        // Return ends an editing session and the field has an editor again within the same turn.
        XCTAssertTrue(window.makeFirstResponder(field), "an unshown window refused the field a second time")
        XCTAssertNotNil(field.currentEditor(), "precondition: the second session has no editor")
        XCTAssertTrue(sendReturn(to: field), "precondition: Return found no editor")
        XCTAssertEqual(ender.ended, 2, "Return did not deliver the end of editing")
        XCTAssertEqual(ender.editorAttachedAtEnd, [true, true], "the editor was gone inside the notification Return delivered")
        XCTAssertNotNil(field.currentEditor(), "after Return the field has no editor")
    }

    // MARK: - What a search field draws

    /// Where a view's pixels have any alpha, from one bitmap of it: as runs of columns in points from its
    /// left, and where its own ink starts and ends, in points from its top: the rows that hold any pixel
    /// with alpha above zero (`top`, `bottom`); and the alpha at its middle. The shared `RenderedInk.read`
    /// weighs a band and cannot say where; this says where.
    private struct Ink {
        var runs: [ClosedRange<Int>]
        var top: CGFloat
        var bottom: CGFloat
        var middleAlpha: UInt8
        func touches(_ columns: ClosedRange<Int>) -> Bool { runs.contains { $0.overlaps(columns) } }
    }

    private func ink(of view: NSView, in appearance: NSAppearance.Name) -> Ink? {
        view.appearance = NSAppearance(named: appearance)
        guard view.bounds.width > 0, view.bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.bitmapData, rep.samplesPerPixel == 4, rep.bitsPerSample == 8 else { return nil }
        let width = rep.pixelsWide, height = rep.pixelsHigh, stride = rep.bytesPerRow
        let across = CGFloat(width) / view.bounds.width, down = CGFloat(height) / view.bounds.height
        var runs: [ClosedRange<Int>] = []
        var start: Int?
        for x in 0...width {
            var on = false
            if x < width { for y in 0..<height where data[y * stride + x * 4 + 3] > 0 { on = true; break } }
            if on, start == nil { start = x }
            if !on, let first = start {
                runs.append(Int(CGFloat(first) / across)...Int(CGFloat(x - 1) / across))
                start = nil
            }
        }
        var first: Int?, last: Int?
        for y in 0..<height {
            var on = false
            for x in 0..<width where data[y * stride + x * 4 + 3] > 0 { on = true; break }
            if on { if first == nil { first = y }; last = y }
        }
        guard let first, let last else { return nil }
        return Ink(runs: runs, top: CGFloat(first) / down, bottom: CGFloat(last + 1) / down,
                   middleAlpha: data[(height / 2) * stride + (width / 2) * 4 + 3])
    }

    private func searchField(bezeled: Bool, size: NSControl.ControlSize) -> NSSearchField {
        let field = NSSearchField(frame: NSRect(x: 0, y: 0, width: 283, height: 36))
        field.controlSize = size
        field.isBezeled = bezeled
        field.drawsBackground = false
        field.focusRingType = .none
        return field
    }

    /// Measured on 27.2, both appearances, the empty field drawn twice. Unbezeled, a search field draws its
    /// magnifier at the left (ink within columns 8 to 20), a clear button at the right (ink within columns
    /// 253 to 283) once it holds a string and not before, and nothing at its middle: no fill. Its intrinsic
    /// height is 16 at every control size, so a 36 high field is a frame the caller sets. Bezeled it is 36
    /// high at `.extraLarge` and paints a fill with `drawsBackground` off, so a plate cannot sit behind it.
    func testAnUnbezeledFieldDrawsTheMagnifierAndTheClearButtonAndNoFill() {
        let sizes: [NSControl.ControlSize] = [.mini, .small, .regular, .large, .extraLarge]
        for size in sizes {
            XCTAssertEqual(searchField(bezeled: false, size: size).intrinsicContentSize.height, 16,
                           "the unbezeled height moved at control size \(size.rawValue)")
        }
        for appearance in RenderedInk.bothAppearances {
            let label = RenderedInk.label(of: appearance)
            let field = searchField(bezeled: false, size: .extraLarge)

            field.stringValue = ""
            guard let empty = ink(of: field, in: appearance), let again = ink(of: field, in: appearance) else {
                XCTFail("\(label): the field rendered nothing"); continue
            }
            XCTAssertEqual(empty.runs, again.runs, "\(label): two renders of one field differ")
            XCTAssertTrue(empty.touches(8...20), "\(label): no magnifier at the left of an empty field")
            XCTAssertFalse(empty.touches(253...283), "\(label): an empty field draws a clear button")
            XCTAssertEqual(empty.middleAlpha, 0, "\(label): the field paints a fill")

            field.stringValue = "wget"
            guard let full = ink(of: field, in: appearance) else {
                XCTFail("\(label): the field with a string rendered nothing"); continue
            }
            XCTAssertTrue(full.touches(253...283), "\(label): no clear button once the field holds a string")
            XCTAssertTrue(full.touches(8...20), "\(label): the magnifier went when the string arrived")
            XCTAssertEqual(full.middleAlpha, 0, "\(label): the field with a string paints a fill")

            let bezeled = searchField(bezeled: true, size: .extraLarge)
            XCTAssertEqual(bezeled.intrinsicContentSize.height, 36, "\(label): the bezeled height moved")
            XCTAssertGreaterThan(ink(of: bezeled, in: appearance)?.middleAlpha ?? 0, 0,
                                 "\(label): a bezeled field with drawsBackground off paints nothing")
        }
    }

    // MARK: - The zone on a real bar

    private var savedCollapse: Any?
    private var savedPageBar: Any?
    private var savedBarAppearance: Any?

    override func setUp() {
        super.setUp()
        savedCollapse = AppSettings.store.object("alwaysCollapseSearch")
        savedPageBar = AppSettings.store.object(PageBarStyle.storageKey)
        savedBarAppearance = AppSettings.store.object(HelmBarAppearance.storageKey)
        AppSettings.pageBarStyle = .windowTitle
        AppSettings.barAppearance = .flat
        AppSettings.alwaysCollapseSearch = false
    }

    override func tearDown() {
        AppSettings.store.set(savedCollapse, for: "alwaysCollapseSearch")
        AppSettings.store.set(savedPageBar, for: PageBarStyle.storageKey)
        AppSettings.store.set(savedBarAppearance, for: HelmBarAppearance.storageKey)
        super.tearDown()
    }

    private func runMain(until deadline: TimeInterval, _ done: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(deadline)
        while Date() < end {
            if done() { return true }
            RunLoop.main.run(mode: .default, before: min(end, Date().addingTimeInterval(0.01)))
        }
        return done()
    }

    /// Whether the zone holds exactly one of its field and its magnifier, with a view to place at all.
    @discardableResult
    private func holdsOne(_ zone: ShellBarSearch, _ label: String,
                          file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard zone.view != nil else {
            XCTFail("\(label): precondition: the zone has no view to place", file: file, line: line)
            return false
        }
        let shown = [zone.field.isHidden, zone.magnifier.isHidden].filter { !$0 }.count
        XCTAssertEqual(shown, 1, "\(label): the zone shows \(shown) of its field and its magnifier, not one",
                       file: file, line: line)
        return shown == 1
    }

    func testWithTheSettingOffAndRoomTheFieldRestsOpenAndWithItOnItRestsAsTheMagnifier() {
        let rig = makeRig(page: Page(), setting: false, inWindow: false)
        let zone = rig.zone, bar = rig.bar

        guard holdsOne(zone, "setting off") else { return }
        XCTAssertFalse(zone.field.isHidden, "with the setting off and room the zone holds the magnifier")
        XCTAssertTrue(zone.magnifier.isHidden)
        XCTAssertEqual(zone.plate.frame.width, 283, "the open field's plate is not 283 wide")

        AppSettings.alwaysCollapseSearch = true
        let rested = runMain(until: 2) {
            bar.view.layoutSubtreeIfNeeded()
            return zone.plate.frame.width == 36
        }
        XCTAssertTrue(rested, "the bar never narrowed the plate to the magnifier's 36")
        guard holdsOne(zone, "setting on") else { return }
        XCTAssertFalse(zone.magnifier.isHidden, "with the setting on and the field empty the zone holds the field")
        XCTAssertTrue(zone.field.isHidden, "with the setting on and the field empty the zone holds the field")

        AppSettings.alwaysCollapseSearch = false
        let reopened = runMain(until: 2) {
            bar.view.layoutSubtreeIfNeeded()
            return zone.plate.frame.width == 283
        }
        XCTAssertTrue(reopened, "the bar never widened the plate back to 283")
        guard holdsOne(zone, "setting off again") else { return }
        XCTAssertFalse(zone.field.isHidden, "with the setting off again the zone holds the magnifier")
    }

    // MARK: - The rig the rows below share

    /// What a page keeps behind its search: the text its binding reads and writes, how often the binding was
    /// written, and the texts its `onSubmit` ran with.
    private final class Page {
        var text: String
        var writes = 0
        var submits: [String] = []
        init(_ text: String = "") { self.text = text }
    }

    /// An object only a page's `onSubmit` closure captures.
    private final class Held {}

    /// A tabs zone with a width, so the bar has something to fold.
    @MainActor
    private final class TabsZone: ShellBarZone {
        var view: NSView? = NSView()
        var measuresMoved: (() -> Void)?
        func show(_ state: ShellBarZoneState) {}
        func measure(into measures: inout ShellPageBarView.Measures) {
            measures.tabs = 310
            measures.tabsFolded = 136
        }
        func apply(_ verdicts: ShellPageBarView.Verdicts) {}
    }

    @MainActor
    private struct Rig {
        let model: SettingsModel
        let channel: HelmWindowToolbarChannel
        let zone: ShellBarSearch
        let bar: ShellPageBar
        /// nil: the bar's view stands alone. Otherwise built, never ordered front, never made key.
        let window: NSWindow?
        var plate: ShellBarPlate { zone.plate }
    }

    /// The bar over a zone, page "general" declared with a search holding `page`, laid out at 856 by 52.
    private func makeRig(page: Page, setting: Bool, inWindow: Bool, tabs: Bool = false) -> Rig {
        AppSettings.alwaysCollapseSearch = setting
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let zone = ShellBarSearch(titlebarIsTransparent: true)
        let tabsZone: any ShellBarZone = tabs ? TabsZone() : MuteBarZone()
        let bar = ShellPageBar(model: model, channel: channel, tabs: tabsZone, actions: MuteBarZone(),
                               search: zone, titlebarIsTransparent: true)
        bar.graceInterval = 30
        var window: NSWindow?
        if inWindow {
            let made = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 856, height: 52),
                                styleMask: [.titled], backing: .buffered, defer: false)
            made.isReleasedWhenClosed = false
            made.contentView = bar.view
            window = made
        } else {
            bar.view.frame = NSRect(x: 0, y: 0, width: 856, height: 52)
        }
        let rig = Rig(model: model, channel: channel, zone: zone, bar: bar, window: window)
        declare(rig, page: page)
        bar.view.place = ShellPageBarView.Place(cardMinX: 200, windowWidth: 1060, buttons: .null)
        bar.view.layoutSubtreeIfNeeded()
        return rig
    }

    /// Declares `token`'s content: a search over `page`, or no search at all when `page` is nil.
    @discardableResult
    private func declare(_ rig: Rig, token: String = "general", page: Page?, holding: Held? = nil) -> Int {
        let generation = rig.channel.nextGeneration()
        let content: HelmPageToolbarContent
        if let page {
            content = HelmPageToolbarContent(search: HelmToolbarSearch(
                prompt: "Search",
                text: Binding(get: { page.text }, set: { page.writes += 1; page.text = $0 }),
                onSubmit: { [holding] in _ = holding; page.submits.append(page.text) }))
        } else {
            content = HelmPageToolbarContent()
        }
        rig.channel.declare(content, token: token, generation: generation)
        return generation
    }

    /// Lays the bar out and gives the main queue a few turns.
    private func settle(_ rig: Rig, turns: Int = 4) {
        for _ in 0..<turns {
            rig.bar.view.layoutSubtreeIfNeeded()
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        rig.bar.view.layoutSubtreeIfNeeded()
    }

    private func wait(_ rig: Rig, _ done: () -> Bool) -> Bool {
        runMain(until: 2) {
            rig.bar.view.layoutSubtreeIfNeeded()
            return done()
        }
    }

    /// Opens the field by the magnifier's press and lays the bar out until the plate is the field's.
    @discardableResult
    private func open(_ rig: Rig) -> Bool {
        rig.zone.magnifier.performClick(nil)
        return wait(rig) { rig.zone.plate.frame.width == 283 && rig.zone.field.currentEditor() != nil }
    }

    /// Types through the field editor, so the field's delegate hears it the way it hears a key.
    @discardableResult
    private func type(_ text: String, into field: NSSearchField) -> Bool {
        guard let editor = field.currentEditor() as? NSTextView else { return false }
        editor.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        return true
    }

    @discardableResult
    private func sendReturn(to field: NSSearchField) -> Bool {
        guard let window = field.window, let editor = field.currentEditor() as? NSTextView,
              let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                           windowNumber: window.windowNumber, context: nil, characters: "\r",
                                           charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)
        else { return false }
        editor.keyDown(with: event)
        return true
    }

    private func pressClear(_ field: NSSearchField) -> Bool {
        guard let cancel = (field.cell as? NSSearchFieldCell)?.cancelButtonCell else { return false }
        cancel.performClick(nil)
        return true
    }

    // MARK: - What re-showing the zone does to its rest

    func testAnEmptyFieldRestsAsTheMagnifierThroughEveryReshow() {
        let page = Page(), second = Page()
        let rig = makeRig(page: page, setting: true, inWindow: false)
        declare(rig, token: "about", page: second)
        declare(rig, token: "log", page: nil)
        settle(rig)

        func rests(_ step: String) {
            settle(rig)
            guard holdsOne(rig.zone, step) else { return }
            XCTAssertTrue(rig.zone.field.isHidden,
                          "after \(step) the zone holds the field: nothing told it the verdict again")
            XCTAssertFalse(rig.zone.magnifier.isHidden,
                           "after \(step) the zone holds the field: nothing told it the verdict again")
            XCTAssertEqual(rig.zone.plate.frame.width, 36, "after \(step) the plate is not the magnifier's 36")
        }

        rests("the start")

        rig.model.selection = .about
        rests("a page change to the second page")
        rig.model.selection = .general
        rests("a page change back")

        rig.model.selection = .log
        settle(rig)
        XCTAssertNil(rig.zone.view, "precondition: a page with no search left the zone a view")
        rig.model.selection = .general
        rests("a page without search and back")

        rig.bar.view.place = ShellPageBarView.Place(cardMinX: 56, windowWidth: 1060, buttons: .null)
        rig.bar.view.frame = NSRect(x: 0, y: 0, width: 1004, height: 52)
        rests("a change of place")

        AppSettings.barAppearance = .liquidGlass
        XCTAssertTrue(runMain(until: 2) { rig.zone.plate.barAppearance == .liquidGlass },
                      "precondition: the bar never told the plate the look moved")
        rests("the look turning to liquid glass")
        AppSettings.barAppearance = .flat
        XCTAssertTrue(runMain(until: 2) { rig.zone.plate.barAppearance == .flat },
                      "precondition: the bar never told the plate the look moved back")
        rests("the look turning flat again")

        rig.bar.setWindowAppearsActive(false)
        XCTAssertFalse(rig.zone.plate.isActive, "precondition: the plate never heard the window go inactive")
        rests("the window going inactive")
        rig.bar.setWindowAppearsActive(true)
        XCTAssertTrue(rig.zone.plate.isActive, "precondition: the plate never heard the window go active")
        rests("the window going active")
    }

    // MARK: - Pressing the magnifier, leaving the field

    func testThePressOnTheMagnifierOpensTheFieldInOneBarPass() {
        let rig = makeRig(page: Page(), setting: true, inWindow: true, tabs: true)
        guard holdsOne(rig.zone, "setting on"), let window = rig.window else { return }
        XCTAssertFalse(window.isVisible, "precondition: the window was shown")
        XCTAssertEqual(rig.zone.plate.frame.width, 36, "precondition: the zone did not rest")
        XCTAssertFalse(rig.bar.view.verdicts.tabsFolded, "precondition: tabs were folded before the press")

        var changes = 0
        let original = rig.bar.view.verdictsChanged
        rig.bar.view.verdictsChanged = { verdicts in changes += 1; original?(verdicts) }

        rig.zone.magnifier.performClick(nil)
        XCTAssertNotNil(rig.zone.field.currentEditor(), "the press opened no editor")
        XCTAssertFalse(rig.zone.field.isHidden, "the press left the field hidden")
        XCTAssertTrue(rig.zone.magnifier.isHidden, "the press left the magnifier up beside the field")

        var passes = 0
        while rig.zone.plate.frame.width != 283, passes < 5 {
            rig.bar.view.layoutSubtreeIfNeeded()
            passes += 1
        }
        XCTAssertEqual(rig.zone.plate.frame.width, 283, "the bar never widened the plate after the press")
        XCTAssertEqual(passes, 1, "opened in \(passes) passes")
        XCTAssertEqual(changes, 1, "the press changed the bar's verdict \(changes) times")
        XCTAssertFalse(rig.bar.view.verdicts.tabsFolded, "the open field folded the tabs at 1060")
        XCTAssertFalse(rig.bar.view.verdicts.searchFolded, "the bar still holds the search folded")
    }

    func testAFieldClosedEmptyRestsAsTheMagnifierAgainAndATurnLater() {
        let rig = makeRig(page: Page(), setting: true, inWindow: true)
        XCTAssertTrue(open(rig), "precondition: the press did not open the field")

        XCTAssertTrue(rig.window?.makeFirstResponder(nil) == true, "precondition: the window kept the field")
        XCTAssertNil(rig.zone.field.currentEditor(), "precondition: the editor outlived the resignation")
        XCTAssertFalse(rig.zone.field.isHidden, "the zone folded inside the call that ended the editing")

        let rested = wait(rig) { rig.zone.plate.frame.width == 36 }
        XCTAssertTrue(rested, "closed empty, the zone still holds the field")
        guard holdsOne(rig.zone, "closed empty") else { return }
        XCTAssertFalse(rig.zone.magnifier.isHidden, "closed empty, the zone still holds the field")
        XCTAssertTrue(rig.zone.field.isHidden, "closed empty, the zone still holds the field")
    }

    func testAQueryLeftInTheFieldIsNotFoldedAndItsClearButtonRestsTheZone() {
        let page = Page()
        let rig = makeRig(page: page, setting: true, inWindow: true)
        XCTAssertTrue(open(rig), "precondition: the press did not open the field")
        XCTAssertTrue(type("wget", into: rig.zone.field), "precondition: the field has no editor to type into")
        XCTAssertEqual(page.text, "wget", "precondition: typing did not reach the binding")
        XCTAssertEqual(page.submits, [], "typing ran onSubmit")

        _ = rig.window?.makeFirstResponder(nil)
        settle(rig)
        XCTAssertEqual(page.submits, [], "leaving the field ran onSubmit")
        XCTAssertTrue(rig.zone.plate.frame.width == 283 && !rig.zone.field.isHidden,
                      "a query left in was folded behind the magnifier")
        XCTAssertEqual(rig.zone.field.stringValue, "wget", "a query left in was folded behind the magnifier")
        XCTAssertEqual(page.text, "wget", "a query left in was folded behind the magnifier")
        guard holdsOne(rig.zone, "a query left in") else { return }

        XCTAssertTrue(pressClear(rig.zone.field), "precondition: the field has no clear button")
        let rested = wait(rig) { rig.zone.plate.frame.width == 36 }
        XCTAssertEqual(page.text, "", "cleared by its button, the field does not rest: the binding kept the query")
        XCTAssertNil(rig.zone.field.currentEditor(), "cleared by its button, the field does not rest: an editor stays")
        XCTAssertTrue(rested, "cleared by its button, the field does not rest")
        guard holdsOne(rig.zone, "cleared by its button") else { return }
        XCTAssertFalse(rig.zone.magnifier.isHidden, "cleared by its button, the field does not rest")
    }

    // MARK: - The page writes to the field

    func testThePagesTextReachesTheFieldAndAFilledFieldIsOpenWithTheSettingOn() {
        let page = Page("old")
        let rig = makeRig(page: page, setting: true, inWindow: false)
        XCTAssertEqual(rig.zone.field.stringValue, "old", "precondition: the field did not take the first text")
        XCTAssertEqual(rig.zone.plate.frame.width, 283, "precondition: a filled field rests as the magnifier")

        page.text = ""
        declare(rig, page: page)
        XCTAssertEqual(rig.zone.field.stringValue, "", "the field kept the page's old text «old»")
        XCTAssertTrue(wait(rig) { rig.zone.plate.frame.width == 36 }, "the emptied field did not rest")

        page.text = "foo"
        declare(rig, page: page)
        XCTAssertEqual(rig.zone.field.stringValue, "foo", "the field kept the page's old text «»")
        XCTAssertTrue(wait(rig) { rig.zone.plate.frame.width == 283 }, "the field the page filled is not open")
        guard holdsOne(rig.zone, "filled by the page") else { return }
        XCTAssertFalse(rig.zone.field.isHidden, "the field the page filled is not open")
        XCTAssertEqual(page.writes, 0, "the page's own write came back through the field")
    }

    // MARK: - A press elsewhere, focus, a frozen page

    func testAPressOutsideTheBarEndsAnEmptyFieldsSessionAndNoOtherPressDoes() {
        let page = Page()
        let rig = makeRig(page: page, setting: true, inWindow: true)
        guard let window = rig.window else { return }
        let outside = NSPoint(x: 900, y: 20)
        XCTAssertTrue(open(rig), "precondition: the press did not open the field")
        let plateCentre = rig.bar.view.convert(NSPoint(x: rig.plate.frame.midX, y: rig.plate.frame.midY), to: nil)
        let besidePlate = NSPoint(x: 5, y: 26)
        XCTAssertFalse(rig.plate.frame.contains(rig.bar.view.convert(besidePlate, from: nil)),
                       "precondition: the point beside the plate is on it")
        XCTAssertTrue(rig.bar.view.bounds.contains(rig.bar.view.convert(besidePlate, from: nil)),
                      "precondition: the point beside the plate is outside the bar")
        XCTAssertFalse(rig.bar.view.bounds.contains(rig.bar.view.convert(outside, from: nil)),
                       "precondition: the outside point is in the bar")

        rig.zone.pressed(at: plateCentre, in: window)
        XCTAssertNotNil(rig.zone.field.currentEditor(), "a press on the plate ended the session")
        rig.zone.pressed(at: besidePlate, in: window)
        XCTAssertNotNil(rig.zone.field.currentEditor(), "a press inside the bar ended the session")
        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
                             styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        rig.zone.pressed(at: outside, in: other)
        XCTAssertNotNil(rig.zone.field.currentEditor(), "a press in another window ended the session")
        rig.zone.pressed(at: outside, in: nil)
        XCTAssertNotNil(rig.zone.field.currentEditor(), "a press with no window ended the session")

        rig.zone.pressed(at: outside, in: window)
        XCTAssertNil(rig.zone.field.currentEditor(), "a press elsewhere left the empty field open: the editor stays")
        XCTAssertTrue(wait(rig) { rig.zone.plate.frame.width == 36 }, "a press elsewhere left the empty field open")
        guard holdsOne(rig.zone, "a press elsewhere") else { return }
        XCTAssertFalse(rig.zone.magnifier.isHidden, "a press elsewhere left the empty field open")

        XCTAssertTrue(open(rig), "precondition: the second press did not open the field")
        XCTAssertTrue(type("wget", into: rig.zone.field), "precondition: no editor to type into")
        rig.zone.pressed(at: outside, in: window)
        XCTAssertNil(rig.zone.field.currentEditor(), "a press elsewhere left the filled field in its session")
        settle(rig)
        XCTAssertEqual(page.submits, [], "the end of a session holding «wget» ran onSubmit")
        XCTAssertFalse(rig.zone.field.isHidden, "a press elsewhere folded a field holding «wget»")
        XCTAssertEqual(rig.zone.plate.frame.width, 283, "a press elsewhere narrowed a field holding «wget»")
    }

    func testTheFoldTakesNoFocusFromAnotherFieldWhenTheClearButtonIsPressed() {
        let page = Page("wget")
        let rig = makeRig(page: page, setting: true, inWindow: true)
        guard let window = rig.window else { return }
        let second = NSTextField(frame: NSRect(x: 2, y: 2, width: 100, height: 20))
        window.contentView?.addSubview(second)
        XCTAssertTrue(window.makeFirstResponder(second), "precondition: the second field refused focus")
        guard let secondEditor = second.currentEditor() else {
            XCTFail("precondition: the second field has no editor"); return
        }
        XCTAssertTrue(window.firstResponder === secondEditor, "precondition: the second field is not first responder")
        XCTAssertNil(rig.zone.field.currentEditor(), "precondition: the zone's field has an editor")

        XCTAssertTrue(pressClear(rig.zone.field), "precondition: the field has no clear button")
        XCTAssertEqual(page.text, "", "precondition: the clear button did not reach the binding")
        let rested = wait(rig) { rig.zone.plate.frame.width == 36 }
        XCTAssertTrue(rested, "precondition: the emptied field did not fold")
        XCTAssertTrue(window.firstResponder === secondEditor,
                      "the fold took first responder from \(String(describing: window.firstResponder))")
        XCTAssertNotNil(second.currentEditor(), "the fold ended the second field's editing")
    }

    /// The state that lasts the grace after a return to a page: the zone shows `page`'s text, frozen (the
    /// page's closures are let go) and lit (not dimmed), the page not yet redeclared.
    private func makeFrozenLitRig(page: Page) -> Rig {
        let away = Page("away")
        let back = makeRig(page: page, setting: false, inWindow: true)
        let own = declare(back, page: page)
        declare(back, token: "about", page: away)
        back.model.selection = .about
        settle(back)
        back.channel.withdraw(token: "general", generation: own)
        back.model.selection = .general
        XCTAssertEqual(back.bar.presentation, .page(key: "general", isLive: false, isDimmed: false),
                       "precondition: the bar did not show the page frozen and lit")
        settle(back, turns: 2)
        XCTAssertFalse(back.zone.field.isHidden, "precondition: the lit frozen field is not shown")
        XCTAssertTrue(back.zone.field.isEnabled, "precondition: the lit frozen field is dimmed")
        XCTAssertEqual(back.zone.field.stringValue, page.text, "precondition: the field lost the page's text")
        return back
    }

    func testAFrozenZonesClearButtonLeavesTheFieldWithThePagesText() {
        let page = Page("old")
        let rig = makeFrozenLitRig(page: page)
        XCTAssertNil(rig.zone.field.currentEditor(), "precondition: the field has an editor")
        XCTAssertTrue(pressClear(rig.zone.field), "precondition: the field has no clear button")
        settle(rig)
        XCTAssertEqual(page.writes, 0, "the frozen zone wrote the page's binding")
        XCTAssertEqual(page.submits, [], "the frozen zone ran onSubmit")
        XCTAssertEqual(rig.zone.field.stringValue, "old",
                       "a frozen zone's clear button emptied the field while the page still holds «old»")
    }

    func testAZoneThatIsNotLiveIgnoresInputWithThePagesClosuresStillInIt() {
        let page = Page("old")
        let zone = ShellBarSearch(titlebarIsTransparent: true)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let content = HelmPageToolbarContent(search: HelmToolbarSearch(
            prompt: "Search",
            text: Binding(get: { page.text }, set: { page.writes += 1; page.text = $0 }),
            onSubmit: { page.submits.append(page.text) }))
        zone.show(ShellBarZoneState(content: content, isLive: false, isDimmed: false, appearsActive: true,
                                    appearance: .flat, animated: false))
        guard let plate = zone.view else { XCTFail("precondition: the zone has no view"); return }
        plate.frame = NSRect(x: 0, y: 8, width: 283, height: 36)
        window.contentView?.addSubview(plate)
        plate.layoutSubtreeIfNeeded()
        XCTAssertFalse(window.isVisible, "precondition: the window was shown")
        zone.apply(ShellPageBarView.Verdicts(tabsFolded: false, searchFolded: true))
        guard holdsOne(zone, "folded") else { return }
        XCTAssertTrue(zone.field.isHidden, "precondition: the folded zone shows the field")
        XCTAssertTrue(zone.magnifier.isEnabled, "precondition: the magnifier is dimmed")

        zone.magnifier.performClick(nil)
        XCTAssertTrue(zone.field.isHidden, "a zone that is not live opened its field at the magnifier's press")
        XCTAssertNil(zone.field.currentEditor(), "a zone that is not live gave its field an editor at the magnifier's press")

        zone.apply(ShellPageBarView.Verdicts(tabsFolded: false, searchFolded: false))
        guard holdsOne(zone, "unfolded") else { return }
        XCTAssertFalse(zone.field.isHidden, "precondition: the unfolded zone hides the field")
        zone.field.stringValue = "wget"
        zone.field.sendAction(zone.field.action, to: zone.field.target)
        XCTAssertEqual(page.writes, 0, "the field's action in a zone that is not live wrote the page's binding")
        XCTAssertEqual(zone.field.stringValue, "old",
                       "the field's action in a zone that is not live left the field apart from the page's text")
        XCTAssertEqual(page.submits, [], "the field's action in a zone that is not live ran onSubmit")
        zone.field.stringValue = "wget"
        XCTAssertTrue(pressClear(zone.field), "precondition: the field has no clear button")
        XCTAssertEqual(page.writes, 0, "the clear button of a zone that is not live wrote the page's binding")
        XCTAssertEqual(page.submits, [], "the clear button of a zone that is not live ran onSubmit")
        XCTAssertEqual(zone.field.stringValue, "old",
                       "the clear button of a zone that is not live left the field apart from the page's text")
    }

    func testAFrozenZoneRunsNoHandlerAndTakesNoInput() {
        // Withdrawn while selected: dimmed, and the page's closures are let go.
        let page = Page()
        let rig = makeRig(page: page, setting: true, inWindow: false)
        XCTAssertEqual(rig.zone.plate.frame.width, 36, "precondition: the empty zone did not rest")
        weak var weakHeld: Held?
        var generation = 0
        do {
            let held = Held()
            weakHeld = held
            generation = declare(rig, page: page, holding: held)
        }
        XCTAssertNotNil(weakHeld, "precondition: the declared closure does not hold the object")
        rig.channel.withdraw(token: "general", generation: generation)
        XCTAssertEqual(rig.bar.presentation, .page(key: "general", isLive: false, isDimmed: true),
                       "precondition: the bar did not freeze the page")
        settle(rig)
        XCTAssertNil(weakHeld, "the bar kept the closure of a page left frozen")
        XCTAssertFalse(rig.zone.field.isEnabled, "the dimmed zone left its field enabled")
        XCTAssertFalse(rig.zone.magnifier.isEnabled, "the dimmed zone left its magnifier enabled")
        rig.zone.magnifier.performClick(nil)
        rig.zone.pressedMagnifier(nil)
        settle(rig)
        XCTAssertTrue(rig.zone.field.isHidden, "a frozen zone's magnifier press opened the field")
        XCTAssertEqual(rig.zone.plate.frame.width, 36, "a frozen zone's magnifier press moved the plate")
        XCTAssertEqual(page.writes, 0, "a frozen zone ran a page's handler: the page's binding was written")
        XCTAssertEqual(page.submits, [], "a frozen zone ran a page's handler")

        // Left and come back to before the page redeclares: not live, not dimmed.
        let kept = Page("old")
        let back = makeFrozenLitRig(page: kept)
        _ = back.window?.makeFirstResponder(back.zone.field)
        XCTAssertNotNil(back.zone.field.currentEditor(), "precondition: the lit frozen field takes no editor")
        type("xyz", into: back.zone.field)
        XCTAssertEqual(back.zone.field.stringValue, "old", "typing changed a frozen zone's field")
        XCTAssertEqual(kept.text, "old", "a frozen zone ran a page's handler: typing reached the binding")
        XCTAssertEqual(kept.writes, 0, "a frozen zone ran a page's handler: the binding was written")
        sendReturn(to: back.zone.field)
        settle(back)
        XCTAssertEqual(kept.submits, [], "a frozen zone ran a page's handler: Return ran onSubmit")
    }

    func testThePagesWriteNeverMovesTheTextUnderTheCaretAndAnotherPageEndsTheSession() {
        let page = Page()
        let rig = makeRig(page: page, setting: false, inWindow: true)
        _ = rig.window?.makeFirstResponder(rig.zone.field)
        XCTAssertNotNil(rig.zone.field.currentEditor(), "precondition: the field took no editor")
        XCTAssertTrue(type("ab", into: rig.zone.field), "precondition: no editor to type into")
        XCTAssertEqual(page.text, "ab", "precondition: typing did not reach the binding")

        page.text = "zzz"
        declare(rig, page: page)
        settle(rig)
        XCTAssertEqual(rig.zone.field.stringValue, "ab", "the page's write moved the text under the caret")
        XCTAssertNotNil(rig.zone.field.currentEditor(), "the page's write ended the session under the caret")

        let other = Page("other")
        declare(rig, token: "about", page: other)
        rig.model.selection = .about
        settle(rig)
        XCTAssertNil(rig.zone.field.currentEditor(), "another page's field kept the first page's session")
        XCTAssertEqual(rig.zone.field.stringValue, "other", "another page's text did not reach the field")
        XCTAssertEqual(page.submits, [], "ending the first page's session ran its onSubmit")
        XCTAssertEqual(other.writes, 0, "ending the first page's session wrote the other page's binding")
        XCTAssertEqual(other.submits, [], "ending the first page's session ran the other page's onSubmit")
    }

    func testAnEditSurvivesTheWindowsActivityChangeAfterThePageRewroteItsOwnText() {
        let page = Page()
        let rig = makeRig(page: page, setting: false, inWindow: true)
        _ = rig.window?.makeFirstResponder(rig.zone.field)
        XCTAssertNotNil(rig.zone.field.currentEditor(), "precondition: the field took no editor")
        XCTAssertTrue(type("ab", into: rig.zone.field), "precondition: no editor to type into")
        XCTAssertEqual(page.text, "ab", "precondition: typing did not reach the binding")

        page.text = "zzz"
        declare(rig, page: page)
        settle(rig)
        XCTAssertNotNil(rig.zone.field.currentEditor(), "precondition: the page's write ended the session")
        XCTAssertEqual(rig.zone.field.stringValue, "ab", "precondition: the page's write moved the text")

        rig.bar.setWindowAppearsActive(false)
        rig.bar.setWindowAppearsActive(true)
        settle(rig)
        XCTAssertNotNil(rig.zone.field.currentEditor(), "the window's activity change ended the session")
        XCTAssertEqual(rig.zone.field.stringValue, "ab", "the window's activity change overwrote what was typed")
        XCTAssertEqual(page.submits, [], "the window's activity change ran onSubmit")
    }

    func testTheSettingTurnedOnMidEditLeavesTheFieldUntilTheEditEnds() {
        let rig = makeRig(page: Page(), setting: false, inWindow: true)
        _ = rig.window?.makeFirstResponder(rig.zone.field)
        XCTAssertNotNil(rig.zone.field.currentEditor(), "precondition: the field took no editor")
        settle(rig)

        AppSettings.alwaysCollapseSearch = true
        XCTAssertTrue(runMain(until: 2) { rig.bar.view.measures.alwaysCollapseSearch },
                      "precondition: the bar never heard the setting")
        settle(rig)
        XCTAssertNotNil(rig.zone.field.currentEditor(), "turned on mid-edit, the editor was taken away")
        XCTAssertFalse(rig.zone.field.isHidden, "turned on mid-edit, the field folded under the person typing")
        XCTAssertEqual(rig.zone.plate.frame.width, 283, "turned on mid-edit, the field folded under the person typing")

        _ = rig.window?.makeFirstResponder(nil)
        XCTAssertTrue(wait(rig) { rig.zone.plate.frame.width == 36 }, "the edit ended and the zone did not rest")
        guard holdsOne(rig.zone, "the edit ended") else { return }
        XCTAssertFalse(rig.zone.magnifier.isHidden, "the edit ended and the zone did not rest")

        AppSettings.alwaysCollapseSearch = false
        XCTAssertTrue(wait(rig) { rig.zone.plate.frame.width == 283 }, "turned off, the field did not come back")
        guard holdsOne(rig.zone, "turned off") else { return }
        XCTAssertFalse(rig.zone.field.isHidden, "turned off, the field did not come back")
    }

    // MARK: - Names, menu, passes, Return, ink

    func testTheMagnifierAndTheFieldNameThemselvesInEveryLanguageAfterASecondShow() {
        let rig = makeRig(page: Page(), setting: true, inWindow: false)
        var seen = Set<String>()
        var active = true
        AppLanguage.each { language in
            active.toggle()
            rig.bar.setWindowAppearsActive(active)
            let expected = HelmA11y.searchField
            seen.insert(expected)
            XCTAssertEqual(rig.zone.magnifier.accessibilityLabel(), expected,
                           "the magnifier names itself «\(rig.zone.magnifier.accessibilityLabel() ?? "")» in \(language)")
            XCTAssertEqual(rig.zone.magnifier.toolTip, expected,
                           "the magnifier's tooltip is «\(rig.zone.magnifier.toolTip ?? "")» in \(language)")
            XCTAssertEqual(rig.zone.field.accessibilityLabel(), expected,
                           "the field names itself «\(rig.zone.field.accessibilityLabel() ?? "")» in \(language)")
        }
        XCTAssertGreaterThan(seen.count, 1, "precondition: the word is the same in every language, so no row could see a stale name")
    }

    func testARestingFieldAnswersTheBarsMenuAndAnEditedOneAnswersItsOwn() {
        let rig = makeRig(page: Page(), setting: false, inWindow: true)
        guard let window = rig.window, let barMenu = rig.bar.view.menu,
              let event = NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: 10, y: 10),
                                             modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                             context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        else { XCTFail("precondition: no menu on the bar or no event"); return }
        XCTAssertNil(rig.zone.field.currentEditor(), "precondition: the field was edited")
        XCTAssertTrue(rig.zone.field.menu(for: event) === barMenu, "a resting field answers a menu that is not the bar's")

        _ = window.makeFirstResponder(rig.zone.field)
        XCTAssertNotNil(rig.zone.field.currentEditor(), "precondition: the field took no editor")
        XCTAssertFalse(rig.zone.field.menu(for: event) === barMenu,
                       "an edited field answers the bar's menu")
    }

    func testFoldingAndUnfoldingAskForNoPassInsideThePass() {
        let zone = ShellBarSearch(titlebarIsTransparent: true)
        var asked = 0
        zone.measuresMoved = { asked += 1 }
        let page = Page()
        let content = HelmPageToolbarContent(search: HelmToolbarSearch(
            prompt: "Search", text: Binding(get: { page.text }, set: { page.text = $0 })))
        zone.show(ShellBarZoneState(content: content, isLive: true, isDimmed: false, appearsActive: true,
                                    appearance: .flat, animated: false))
        zone.pressedMagnifier(nil)
        XCTAssertEqual(asked, 1, "precondition: a press did not reach measuresMoved, so the counter cannot see it")

        asked = 0
        zone.apply(ShellPageBarView.Verdicts(tabsFolded: false, searchFolded: true))
        zone.apply(ShellPageBarView.Verdicts(tabsFolded: false, searchFolded: false))
        XCTAssertEqual(asked, 0, "the zone asked for a pass inside the pass")
    }

    func testReturnRunsOnSubmitOnceWithTheTextAndNeverWithNone() {
        let page = Page()
        let rig = makeRig(page: page, setting: true, inWindow: true)
        XCTAssertTrue(open(rig), "precondition: the press did not open the field")
        XCTAssertTrue(sendReturn(to: rig.zone.field), "precondition: Return found no editor")
        settle(rig)
        XCTAssertGreaterThan(page.writes, 0, "precondition: Return never reached the zone's action")
        XCTAssertEqual(page.submits, [], "Return with «» ran onSubmit \(page.submits.count) times")

        XCTAssertNotNil(rig.zone.field.currentEditor(), "Return left the field without an editor")
        _ = rig.window?.makeFirstResponder(nil)
        XCTAssertTrue(wait(rig) { rig.zone.plate.frame.width == 36 }, "precondition: the emptied field did not rest")
        XCTAssertTrue(open(rig), "precondition: the second press did not open the field")
        XCTAssertTrue(type("wget", into: rig.zone.field), "precondition: no editor to type into")
        XCTAssertEqual(page.submits, [], "typing ran onSubmit")
        XCTAssertTrue(sendReturn(to: rig.zone.field), "precondition: Return found no editor")
        settle(rig)
        XCTAssertEqual(page.submits, ["wget"], "Return with «wget» ran onSubmit \(page.submits.count) times")
        XCTAssertFalse(rig.zone.field.isHidden, "Return with «wget» folded the field")
        XCTAssertEqual(rig.zone.plate.frame.width, 283, "Return with «wget» narrowed the plate")
    }

    func testTheInkOfTheFilledFieldSitsAtThePlatesMiddle() {
        let rig = makeRig(page: Page("wget"), setting: false, inWindow: false)
        rig.zone.plate.frame = NSRect(x: 0, y: 0, width: 283, height: 36)
        rig.zone.plate.layoutSubtreeIfNeeded()
        guard let content = rig.zone.plate.content else { XCTFail("precondition: the plate holds nothing"); return }
        content.layoutSubtreeIfNeeded()
        XCTAssertFalse(rig.zone.field.isHidden, "precondition: the field is not the shown one")
        XCTAssertEqual(rig.zone.field.stringValue, "wget", "precondition: the field holds no text")
        for appearance in RenderedInk.bothAppearances {
            let label = RenderedInk.label(of: appearance)
            guard let span = ink(of: content, in: appearance),
                  let again = ink(of: content, in: appearance) else {
                XCTFail("\(label): the plate's content drew nothing"); continue
            }
            XCTAssertEqual(span.top, again.top, "\(label): two renders differ")
            XCTAssertEqual(span.bottom, again.bottom, "\(label): two renders differ")
            let middle = (span.top + span.bottom) / 2
            let off = middle - content.bounds.height / 2
            XCTAssertLessThanOrEqual(abs(off), 1,
                "\(label): the field's ink sits \(off) pt off the plate's middle (ink \(span.top) to \(span.bottom))")
        }
    }
}
