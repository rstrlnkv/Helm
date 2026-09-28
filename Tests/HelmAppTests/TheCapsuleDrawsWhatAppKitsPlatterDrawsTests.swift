import AppKit
import ObjectiveC
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The actions capsule — its glass, its `+` and the view-mode switcher inside
/// it — against AppKit's own toolbar platter, in the same window, in the same
/// state, read the same way.** The owner's report: the capsule stayed Liquid
/// Glass while the window was not in focus, where the centre tabs lost their
/// volume. The spec this answers says what AppKit draws per state (S1 active
/// and key, S2b another of the app's panels key while this window stays main,
/// S3 app inactive, S4 a sheet, S5 a window opened while another app is
/// active); this file does not carry its numbers. Every expectation below is
/// AppKit's own item, read off the live window beside the capsule.
///
/// **Two readings, one per half of the look.**
/// - Glass: the four values the spec found moving between the lit and the flat
///   look, and only those — the `CASDFLayer` whose effect is
///   `CASDFKeyFillHighlightEffect` (its opacity, the effect's key and fill
///   alpha), the `CASDFOutputEffect`'s `maximum`, and the `CABackdropLayer`
///   filtered `glassBackground` (`marginWidth`, `windowServerAware`). The
///   capsule's are read under its own hosting view; AppKit's under the
///   toolbar's `NSGlassContainerView`, with the capsule's subtree left out.
/// - Ink: the highest alpha the item draws, through `cacheDisplay` — glass does
///   not composite in a test process, so what the bitmap holds is the glyphs
///   and labels alone — taken as a fraction of the same item's own S1 reading.
///   AppKit's reference is the centre tabs' `NSSegmentedControl`; the capsule's
///   `+` and its view-mode switcher are each read in their own slot.
///
/// **What stands in for the window server.** A `swift test` process cannot
/// activate itself — `NSApp.activate()` is refused (measured: `isActive` stays
/// false) and no window of it ever becomes key or main — so only S5, and a
/// sheet on S5's window, are producible here as the person produces them. A real app, on every key or main
/// change, carries three things at once: the window's public `isKeyWindow` /
/// `isMainWindow`, AppKit's private key and main appearance (which is what its
/// platter, the centre tabs' ink and SwiftUI's `controlActiveState` follow), and
/// the notification the window posts. `Rig.setKey(_:)` and `Rig.setMain(_:)`
/// produce all three, in that order: the two getters answer for the rig's window
/// through `standInForTheWindowServer()`, AppKit's own `acquireKeyAppearance`,
/// `resignKeyAppearance`, `acquireMainAppearance` and `resignMainAppearance`
/// move the appearance, and the window's own notification is posted, which is
/// what reaches its delegate. Driving the appearance alone, as this file once
/// did, produced a window AppKit draws active while it reads neither key nor
/// main — a state no real app has: a fixture app driven through a real
/// nonactivating panel, a real sheet and a genuine hand-over of activation
/// between two processes read `isKeyWindow || isMainWindow` equal to AppKit's
/// private `_hasActiveAppearance` in every state it logged, including every one
/// with a sheet attached. Each step below produces only flag pairs that fixture
/// read: S1 key and main, S2b and S4 main only, S3 and S5 neither. If AppKit
/// stops answering one of the four selectors this file fails; it does not skip.
///
/// **Not producible here, and what that leaves unproved.** The owner's own
/// defect — the capsule's glass staying lit in Helm Dev — does not reproduce in
/// this process: here the capsule's glass follows the window by itself, with
/// no hosting view rebuilt at all (measured by taking the rebuild out: not one
/// glass reading below moved), and neither the `controlActiveState` nor the
/// `appearsActive` environment key set on the capsule moves its glass either
/// way (measured by pinning each). So the glass half of this file holds that
/// no rebuild lands a look AppKit is not drawing, and that the capsule's glass
/// is AppKit's glass; it does not reproduce the stuck glass, which only a
/// recording of Helm Dev shows. Also out of reach: the panel that holds key in
/// S2b (only its effect on this window is produced), the timing of a real
/// activation event (the spec's one-frame snap), and the Settings window's
/// close-and-reopen path, whose pane unmount (`helmIdlesOffScreen`) listens for
/// occlusion notifications a test process is never sent.
///
/// **The name zone, held to AppKit's own window title in the same window.**
/// The rig turns AppKit's title on beside `NameZoneView` and reads both in
/// every state above. AppKit's title does move here — 0.847 in S1, 0.278 Light
/// and 0.251 Dark in S3 and S5, the film's 37→177 and 222→92 — but only when
/// read through its own `draw(_:)`: `cacheDisplay` composites that field twice,
/// so it is the one item in this file not read through `ink(_:slot:)`.
///
/// **The first open's lit glass does not reproduce here either.** With
/// `SettingsToolbar.correctActionsGlassOnFirstAttach(_:)` emptied, the
/// window's first capsule read flat beside a flat platter after each of: a
/// bar built off screen and shown by `makeKeyAndOrderFront`; a stand-in key
/// panel held over the build; AppKit's private key and main appearance taken
/// during the build and dropped before the glass existed; a first capsule
/// built after S1 and S3; and `NSApp.isActive` answering true through the
/// build and first draw, then false with and without the resign notification.
/// What is left — `SettingsWindow.show(selecting:)`'s real activation request
/// and a real panel holding key — puts a Dock icon on the screen or takes the
/// keyboard, so it stays with the recording of Helm Dev.
@MainActor
final class TheCapsuleDrawsWhatAppKitsPlatterDrawsTests: XCTestCase {

    // MARK: - The window server's answer

    /// `isKeyWindow` and `isMainWindow` for a window a rig registered, while
    /// installed; every other window gets AppKit's own answer.
    nonisolated(unsafe) static var answers: [ObjectIdentifier: (key: Bool, main: Bool)] = [:]

    /// Installed by the test's first rig, once — XCTest makes a new instance per test.
    private var standingIn = false

    /// Answers the two getters from `answers` until the test's teardown puts
    /// AppKit's implementation back — see this file's header.
    private func standInForTheWindowServer() throws {
        Self.answers = [:]
        for (selector, isKey) in [(#selector(getter: NSWindow.isKeyWindow), true),
                                  (#selector(getter: NSWindow.isMainWindow), false)] {
            let method = try XCTUnwrap(class_getInstanceMethod(NSWindow.self, selector),
                                       "NSWindow has no \(selector) to answer for")
            let original = method_getImplementation(method)
            typealias Getter = @convention(c) (NSWindow, Selector) -> Bool
            let call = unsafeBitCast(original, to: Getter.self)
            let answering: @convention(block) (NSWindow) -> Bool = { window in
                guard let answer = TheCapsuleDrawsWhatAppKitsPlatterDrawsTests.answers[ObjectIdentifier(window)] else {
                    return call(window, selector)
                }
                return isKey ? answer.key : answer.main
            }
            method_setImplementation(method, imp_implementationWithBlock(answering))
            addTeardownBlock { method_setImplementation(method, original) }
        }
        addTeardownBlock { TheCapsuleDrawsWhatAppKitsPlatterDrawsTests.answers = [:] }
    }

    /// **The name zone is `moduleName`'s**, the default every reading here
    /// was taken under; with `windowTitle` left in the test tool's own
    /// domain the bar had no name zone and both name-zone cases ran red
    /// (2026-09-28). Kept raw and put back by the test's own teardown, so a
    /// key the domain did not hold is removed again.
    private func holdThePageBarStyle() {
        let store = AppSettings.store
        let found = store.object(PageBarStyle.storageKey)
        addTeardownBlock { @MainActor in store.set(found, for: PageBarStyle.storageKey) }
        AppSettings.pageBarStyle = .moduleName
    }

    // MARK: - Readings

    struct Glass: CustomStringConvertible {
        let highlightOpacity: Float
        let keyAlpha: CGFloat
        let fillAlpha: CGFloat
        let outputMaximum: Double
        let backdropMargin: Double
        let windowServerAware: Bool

        var isLit: Bool { highlightOpacity > 0.5 }

        func matches(_ other: Glass) -> Bool {
            abs(highlightOpacity - other.highlightOpacity) < 0.01
                && abs(keyAlpha - other.keyAlpha) < 0.01
                && abs(fillAlpha - other.fillAlpha) < 0.01
                && abs(outputMaximum - other.outputMaximum) < 0.01
                && abs(backdropMargin - other.backdropMargin) < 0.01
                && windowServerAware == other.windowServerAware
        }

        var description: String {
            String(format: "highlight %.2f key %.2f fill %.2f max %.3f margin %.2f wsa %@",
                   highlightOpacity, keyAlpha, fillAlpha, outputMaximum, backdropMargin,
                   windowServerAware ? "1" : "0")
        }
    }

    /// One glass group under `root` — exactly one of each of the three layers,
    /// or nil, so a tree that holds two groups (a second glass nobody expected)
    /// or none (the capsule drew no glass) is a failure and not a pick.
    private static func glass(under root: CALayer, skipping skipped: CALayer? = nil) -> Glass? {
        var highlights: [(Float, CGFloat, CGFloat)] = []
        var maxima: [Double] = []
        var backdrops: [(Double, Bool)] = []
        func alpha(_ value: Any?) -> CGFloat? {
            guard let value, CFGetTypeID(value as CFTypeRef) == CGColor.typeID else { return nil }
            return (value as! CGColor).alpha   // swiftlint:disable:this force_cast
        }
        func walk(_ layer: CALayer) {
            if let skipped, layer === skipped { return }
            let cls = String(cString: class_getName(object_getClass(layer)))
            if cls == "CASDFLayer", layer.responds(to: NSSelectorFromString("effect")),
               let effect = layer.value(forKey: "effect") as? NSObject {
                let effectClass = String(cString: class_getName(object_getClass(effect)))
                if effectClass == "CASDFKeyFillHighlightEffect",
                   let key = alpha(effect.value(forKey: "keyColor")),
                   let fill = alpha(effect.value(forKey: "fillColor")) {
                    highlights.append((layer.opacity, key, fill))
                } else if effectClass == "CASDFOutputEffect",
                          let maximum = (effect.value(forKey: "maximum") as? NSNumber)?.doubleValue {
                    maxima.append(maximum)
                }
            }
            if cls == "CABackdropLayer", let filters = layer.filters as? [NSObject],
               filters.contains(where: { "\($0)" == "glassBackground" }),
               let margin = (layer.value(forKey: "marginWidth") as? NSNumber)?.doubleValue,
               let aware = (layer.value(forKey: "windowServerAware") as? NSNumber)?.boolValue {
                backdrops.append((margin, aware))
            }
            for sub in layer.sublayers ?? [] { walk(sub) }
        }
        walk(root)
        guard highlights.count == 1, maxima.count == 1, backdrops.count == 1 else { return nil }
        return Glass(highlightOpacity: highlights[0].0, keyAlpha: highlights[0].1, fillAlpha: highlights[0].2,
                     outputMaximum: maxima[0], backdropMargin: backdrops[0].0, windowServerAware: backdrops[0].1)
    }

    /// The highest alpha `view` draws inside the horizontal slot `slot` (in its
    /// own points, full height) — a glyph at 25 % opacity reads 0.25 wherever it
    /// sits, which is what makes the reading comparable across items.
    private static func ink(_ view: NSView, slot: ClosedRange<CGFloat>? = nil) -> CGFloat? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / max(view.bounds.width, 1)
        let range = slot ?? 0...view.bounds.width
        let from = max(0, Int((range.lowerBound * scale).rounded(.down)))
        let to = min(rep.pixelsWide, Int((range.upperBound * scale).rounded(.up)))
        guard from < to else { return nil }
        var best: CGFloat = 0
        for y in 0..<rep.pixelsHigh {
            for x in from..<to {
                if let a = rep.colorAt(x: x, y: y)?.alphaComponent, a > best { best = a }
            }
        }
        return best
    }

    // MARK: - The window

    /// The real `SettingsWindow` — its own `window`, `model` and
    /// `toolbarChannel` — reached through `Mirror`, since all three are
    /// private there. Never `show(selecting:)`: that asks to activate the app.
    @MainActor private final class Rig {
        let owner: SettingsWindow
        let window: NSWindow
        let model: SettingsModel
        let channel: HelmWindowToolbarChannel
        private var sheets: [NSWindow] = []

        /// `band` is the system whose settings window this is — never this
        /// Mac's own: the title bar it sets is what AppKit's title and the
        /// name zone are both drawn under.
        init(appearance: NSAppearance.Name, band: HelmBandChoice) throws {
            owner = SettingsWindow(host: ModuleHost.shared, band: band)
            let fields = Mirror(reflecting: owner).children
            func field<T>(_ name: String, as type: T.Type) throws -> T {
                try XCTUnwrap(fields.first { $0.label == name }?.value as? T,
                              "SettingsWindow no longer holds `\(name)` as \(T.self) — this rig reads it by name")
            }
            window = try field("window", as: NSWindow.self)
            model = try field("model", as: SettingsModel.self)
            channel = try field("toolbarChannel", as: HelmWindowToolbarChannel.self)
            window.appearance = NSAppearance(named: appearance)
        }

        func show(page: String, segmented: Bool = true, search: Bool = false) {
            model.selection = .module(page)
            var actions: [HelmToolbarAction] = [HelmToolbarAction(id: "plus", title: "Add", symbol: "plus") {}]
            if segmented {
                actions.insert(HelmToolbarAction(id: "mode", title: "View", options: [
                    HelmToolbarTab(id: "table", title: "Table", symbol: "tablecells"),
                    HelmToolbarTab(id: "text", title: "Text", symbol: "text.alignleft"),
                ], selection: .constant("table")), at: 0)
            }
            channel.declare(HelmPageToolbarContent(
                tabs: [HelmToolbarTab(id: "a", title: "Alpha", symbol: "star"),
                       HelmToolbarTab(id: "b", title: "Beta", symbol: "heart")],
                selectedTab: .constant("a"), actions: actions,
                search: search ? HelmToolbarSearch(prompt: "Search", text: .constant("")) : nil),
                token: page, generation: channel.nextGeneration())
        }

        func item(_ id: String) -> NSToolbarItem? {
            window.toolbar?.items.first { $0.itemIdentifier.rawValue == id }
        }
        var capsule: NSHostingView<HelmToolbarActionsCapsule>? {
            item("helm.actions")?.view as? NSHostingView<HelmToolbarActionsCapsule>
        }
        var tabs: NSView? { item("helm.tabs")?.view }

        func settle(_ seconds: TimeInterval = 0.3) {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end {
                // A pool per pass: layout hands views back autoreleased, and a
                // replaced hosting view held by this test's own pool would read
                // as one the change left alive.
                autoreleasepool {
                    window.layoutIfNeeded()
                    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
                }
            }
        }

        /// AppKit's own key/main appearance entry points — see this file's header.
        func appKit(_ selectors: String...) {
            for name in selectors {
                let selector = NSSelectorFromString(name)
                guard let method = class_getInstanceMethod(type(of: window), selector) else {
                    XCTFail("NSWindow no longer answers \(name): this file's stand-in for the window server is gone")
                    return
                }
                typealias Call = @convention(c) (AnyObject, Selector) -> Void
                unsafeBitCast(method_getImplementation(method), to: Call.self)(window, selector)
            }
        }
        func flag(_ name: String) -> Bool? {
            let selector = NSSelectorFromString(name)
            guard let method = class_getInstanceMethod(type(of: window), selector) else { return nil }
            typealias Read = @convention(c) (AnyObject, Selector) -> Bool
            return unsafeBitCast(method_getImplementation(method), to: Read.self)(window, selector)
        }

        // MARK: The window server, as a real app has it — see this file's header

        private(set) var isKey = false
        private(set) var isMain = false

        /// One key change: the flag, AppKit's own appearance, the notification.
        func setKey(_ on: Bool, file: StaticString = #filePath, line: UInt = #line) {
            isKey = on
            answer(file: file, line: line)
            appKit(on ? "acquireKeyAppearance" : "resignKeyAppearance")
            NotificationCenter.default.post(
                name: on ? NSWindow.didBecomeKeyNotification : NSWindow.didResignKeyNotification, object: window)
        }
        /// One main change, the same three in the same order.
        func setMain(_ on: Bool, file: StaticString = #filePath, line: UInt = #line) {
            isMain = on
            answer(file: file, line: line)
            appKit(on ? "acquireMainAppearance" : "resignMainAppearance")
            NotificationCenter.default.post(
                name: on ? NSWindow.didBecomeMainNotification : NSWindow.didResignMainNotification, object: window)
        }
        private func answer(file: StaticString, line: UInt) {
            TheCapsuleDrawsWhatAppKitsPlatterDrawsTests.answers[ObjectIdentifier(window)] = (isKey, isMain)
            // The stand-in is what every later reading rests on: it must hold.
            XCTAssertEqual(window.isKeyWindow, isKey, "the window server stand-in does not answer isKeyWindow",
                           file: file, line: line)
            XCTAssertEqual(window.isMainWindow, isMain, "the window server stand-in does not answer isMainWindow",
                           file: file, line: line)
        }

        /// Main first, then key — the order a real reactivation posts them in.
        func toS1() { setMain(true); setKey(true) }
        func toS3() { setKey(false); setMain(false) }
        /// S2b: another of the app's windows took key, this one stays main.
        func toS2b() { setKey(false) }
        /// A real sheet. An active app's sheet takes key from the window, which
        /// stays main (S4); an inactive app's window has no key to give up.
        func beginSheet() {
            let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
                                 styleMask: [.titled], backing: .buffered, defer: false)
            sheets.append(sheet)
            window.beginSheet(sheet)
            if isKey { setKey(false) }
        }
        /// Ends the sheet for real. An active app hands key back to the window
        /// (the sheet's Cancel); an inactive one has none to hand back.
        func endSheet() {
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
            if isMain, !isKey { setKey(true) }
        }

        func drop() {
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
            TheCapsuleDrawsWhatAppKitsPlatterDrawsTests.answers[ObjectIdentifier(window)] = nil
            window.orderOut(nil)
            window.toolbar = nil
            // `SettingsWindow.init` names the window's frame for autosave; keep
            // the test process's own defaults as they were.
            NSWindow.removeFrame(usingName: "HelmSettingsWindow.v4")
        }
    }

    private var rigs: [Rig] = []
    /// The settings window's autosaved frame and sidebar divider as the test
    /// tool's own domain held them before the first rig, put back after the
    /// last one drops — `Rig.drop()` removes the frame whether or not it was
    /// there, which took one another family had left out of the domain, and
    /// the divider was left behind by every run (2026-09-28).
    private var foundFrame: String?
    private var foundSplit: [String]?
    private var frameHeld = false
    private static let frameKey = "NSWindow Frame HelmSettingsWindow.v4"
    private static let splitKey = "NSSplitView Subview Frames HelmSettingsSidebar.v1"

    override func tearDown() {
        rigs.forEach { $0.drop() }
        rigs = []
        if frameHeld {
            UserDefaults.standard.set(foundFrame, forKey: Self.frameKey)
            UserDefaults.standard.set(foundSplit, forKey: Self.splitKey)
        }
        super.tearDown()
    }

    /// macOS 27's window unless a case names another system — the capsule's
    /// readings were taken under its transparent title bar.
    private func rig(_ appearance: NSAppearance.Name, band: HelmBandChoice = .onMacOS(27)) throws -> Rig {
        if !standingIn {
            try standInForTheWindowServer()
            holdThePageBarStyle()
            foundFrame = UserDefaults.standard.string(forKey: Self.frameKey)
            foundSplit = UserDefaults.standard.stringArray(forKey: Self.splitKey)
            frameHeld = true
            standingIn = true
        }
        let rig = try Rig(appearance: appearance, band: band)
        rigs.append(rig)
        return rig
    }

    // MARK: - The comparison

    /// Per-item S1 ink, the denominator every later ink reading is a fraction of.
    private struct Baseline { let plus: CGFloat; let mode: CGFloat; let tabs: CGFloat }

    /// The `+` and the view-mode switcher's slots inside the capsule — the
    /// capsule's own reserve (`reserveWidth(_:)`) read off the live model, so a
    /// trailing inset sits outside both.
    private func slots(_ host: NSHostingView<HelmToolbarActionsCapsule>)
        -> (plus: ClosedRange<CGFloat>, mode: ClosedRange<CGFloat>?) {
        let capsule = host.rootView
        let declared = capsule.model.declared
        let reserve = declared.reduce(CGFloat(0)) { $0 + capsule.reserveWidth($1) }
        let inset = host.bounds.width - reserve
        let plusEnd = host.bounds.width - inset
        let plus = (plusEnd - HelmToolbarActionsCapsule.side)...plusEnd
        guard let mode = declared.first(where: { $0.id == "mode" }) else { return (plus, nil) }
        let modeEnd = plus.lowerBound
        return (plus, (modeEnd - capsule.reserveWidth(mode))...modeEnd)
    }

    private func baseline(_ rig: Rig, _ label: String) throws -> Baseline {
        let host = try XCTUnwrap(rig.capsule, "\(label): no capsule on the bar")
        let tabs = try XCTUnwrap(rig.tabs, "\(label): no centre tabs on the bar")
        let slot = slots(host)
        let plus = try XCTUnwrap(Self.ink(host, slot: slot.plus), "\(label): the + drew nothing")
        let mode = try XCTUnwrap(slot.mode.flatMap { Self.ink(host, slot: $0) }, "\(label): the switcher drew nothing")
        let tabInk = try XCTUnwrap(Self.ink(tabs), "\(label): the centre tabs drew nothing")
        // The subject exists: three items drawn at full strength in S1.
        XCTAssertGreaterThan(plus, 0.5, "\(label): the + is barely drawn in S1 — nothing below reads it")
        XCTAssertGreaterThan(mode, 0.5, "\(label): the switcher is barely drawn in S1 — nothing below reads it")
        XCTAssertGreaterThan(tabInk, 0.5, "\(label): the tabs are barely drawn in S1 — nothing below reads them")
        return Baseline(plus: plus, mode: mode, tabs: tabInk)
    }

    /// The capsule against AppKit's platter, in whatever state the window is in
    /// now. `lit` is what AppKit's platter must itself read — the proof that
    /// the state was produced at all, before any equality is believed.
    private func assertCapsuleMatchesAppKit(_ rig: Rig, lit: Bool, baseline: Baseline?, _ label: String,
                                            file: StaticString = #filePath, line: UInt = #line) {
        rig.settle()
        guard let host = rig.capsule, let hostLayer = host.layer else {
            return XCTFail("\(label): no capsule hosting view on the bar", file: file, line: line)
        }
        guard let theme = rig.window.contentView?.superview,
              let container = Self.views(theme).first(where: {
                  NSStringFromClass(type(of: $0)) == "NSGlassContainerView" && host.isDescendant(of: $0)
              }), let containerLayer = container.layer else {
            return XCTFail("\(label): no NSGlassContainerView holding the toolbar's items", file: file, line: line)
        }
        guard let platter = Self.glass(under: containerLayer, skipping: hostLayer) else {
            return XCTFail("\(label): AppKit's platter glass did not read as one group", file: file, line: line)
        }
        guard let capsule = Self.glass(under: hostLayer) else {
            return XCTFail("\(label): the capsule's glass did not read as one group", file: file, line: line)
        }
        XCTAssertEqual(platter.isLit, lit, """
            \(label): AppKit's own platter reads \(platter) — the state this step drives was not produced \
            (flags: active \(String(describing: rig.flag("_hasActiveAppearance"))), \
            key \(String(describing: rig.flag("_hasKeyAppearance"))))
            """, file: file, line: line)
        XCTAssertTrue(capsule.matches(platter), """
            \(label): the capsule's glass reads \(capsule), AppKit's platter beside it \(platter)
            """, file: file, line: line)

        guard let baseline else { return }
        guard let tabs = rig.tabs, let tabInk = Self.ink(tabs) else {
            return XCTFail("\(label): no ink read off the centre tabs", file: file, line: line)
        }
        let slot = slots(host)
        let tabsShare = tabInk / baseline.tabs
        if let plus = Self.ink(host, slot: slot.plus) {
            XCTAssertEqual(plus / baseline.plus, tabsShare, accuracy: 0.1, """
                \(label): the + draws at \(plus / baseline.plus) of its S1 ink, AppKit's tabs at \(tabsShare) of theirs
                """, file: file, line: line)
        } else {
            XCTFail("\(label): no ink read off the +", file: file, line: line)
        }
        if let modeSlot = slot.mode, let mode = Self.ink(host, slot: modeSlot) {
            XCTAssertEqual(mode / baseline.mode, tabsShare, accuracy: 0.1, """
                \(label): the view-mode switcher draws at \(mode / baseline.mode) of its S1 ink, \
                AppKit's tabs at \(tabsShare) of theirs
                """, file: file, line: line)
        } else {
            XCTFail("\(label): no ink read off the view-mode switcher", file: file, line: line)
        }
    }

    private static func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }

    private static let appearances: [NSAppearance.Name] = [.aqua, .darkAqua]
    /// Each system's settings window, by the title bar its band decision sets:
    /// macOS 27's transparent one and macOS 26's opaque one.
    private static let systems: [(name: String, band: HelmBandChoice)] = [
        ("macOS 27", .onMacOS(27)), ("macOS 26", .onMacOS(26)),
    ]
    private static var systemsByAppearance: [(system: (name: String, band: HelmBandChoice),
                                              appearance: NSAppearance.Name)] {
        systems.flatMap { system in appearances.map { (system, $0) } }
    }
    private static func named(_ appearance: NSAppearance.Name) -> String {
        appearance == .darkAqua ? "Dark" : "Light"
    }

    // MARK: - S5, and the return to key after it

    /// A window ordered in while the app is not active has never been key: this
    /// process is never active, so this is S5 as the person meets it, not a
    /// stand-in. Then key arrives.
    func testAFreshWindowAndTheReturnToKeyAfterItDrawWhatAppKitDraws() throws {
        for appearance in Self.appearances {
            let name = Self.named(appearance)
            let rig = try rig(appearance)
            rig.show(page: "probe.fresh")
            rig.window.orderFront(nil)
            rig.settle()
            XCTAssertEqual(rig.flag("_hasActiveAppearance"), false, "\(name): this process's window is not in S5")
            assertCapsuleMatchesAppKit(rig, lit: false, baseline: nil, "\(name) S5")
            let fresh = rig.capsule.flatMap { host in Self.ink(host, slot: self.slots(host).plus) }
            let freshTabs = rig.tabs.flatMap { Self.ink($0) }

            rig.toS1()
            rig.settle()
            let base = try baseline(rig, "\(name) S1 after S5")
            assertCapsuleMatchesAppKit(rig, lit: true, baseline: base, "\(name) S1 after S5")
            if let fresh, let freshTabs {
                XCTAssertEqual(fresh / base.plus, freshTabs / base.tabs, accuracy: 0.1, """
                    \(name) S5: the + drew at \(fresh / base.plus) of its S1 ink, AppKit's tabs at \
                    \(freshTabs / base.tabs) of theirs
                    """)
            } else {
                XCTFail("\(name) S5: no ink read")
            }
        }
    }

    // MARK: - S1 -> S3 -> S1, every order, and the stuck-after-return case

    func testLeavingAndReturningNeverLeavesTheCapsuleOnTheOldLook() throws {
        for appearance in Self.appearances {
            let name = Self.named(appearance)
            let rig = try rig(appearance)
            rig.show(page: "probe.cycle")
            rig.window.orderFront(nil)
            rig.toS1()
            rig.settle()
            let base = try baseline(rig, "\(name) S1")

            for round in 1...3 {
                rig.toS3()
                assertCapsuleMatchesAppKit(rig, lit: false, baseline: base, "\(name) S3, round \(round)")
                rig.toS1()
                assertCapsuleMatchesAppKit(rig, lit: true, baseline: base, "\(name) S1 return, round \(round)")
            }
            // A turn between the two halves, in both orders each way.
            rig.setKey(false); rig.settle(0.1); rig.setMain(false)
            assertCapsuleMatchesAppKit(rig, lit: false, baseline: base, "\(name) S3, key then main a turn apart")
            rig.setMain(true); rig.settle(0.1); rig.setKey(true)
            assertCapsuleMatchesAppKit(rig, lit: true, baseline: base, "\(name) S1, main then key a turn apart")
            rig.setMain(false); rig.settle(0.1); rig.setKey(false)
            assertCapsuleMatchesAppKit(rig, lit: false, baseline: base, "\(name) S3, main then key a turn apart")
            rig.setKey(true); rig.settle(0.1); rig.setMain(true)
            assertCapsuleMatchesAppKit(rig, lit: true, baseline: base, "\(name) S1, key then main a turn apart")
            // Rapid: many changes inside one turn, then many a frame apart.
            for _ in 0..<5 { rig.toS3(); rig.toS1() }
            assertCapsuleMatchesAppKit(rig, lit: true, baseline: base, "\(name) S1 after five same-turn round trips")
            for step in 0..<9 {
                if step.isMultiple(of: 2) { rig.toS3() } else { rig.toS1() }
                rig.settle(0.016)
            }
            assertCapsuleMatchesAppKit(rig, lit: false, baseline: base, "\(name) S3 after nine changes a frame apart")
            rig.toS1()
            assertCapsuleMatchesAppKit(rig, lit: true, baseline: base, "\(name) S1 after the rapid run")
        }
    }

    // MARK: - S2b and S4: key leaves, the window stays main

    /// AppKit keeps the platter lit, glass and labels both, when another of the
    /// app's windows takes key (Helm's status panel) and under a sheet (the `+`
    /// "New key" sheet); the dimming a sheet adds is a window-level view over
    /// every item alike, so it is outside what either reading here sees.
    func testAPanelOrASheetTakingKeyLeavesTheCapsuleAsLitAsAppKitsPlatter() throws {
        for appearance in Self.appearances {
            let name = Self.named(appearance)
            let rig = try rig(appearance)
            rig.show(page: "probe.keyleaves")
            rig.window.orderFront(nil)
            rig.toS1()
            rig.settle()
            let base = try baseline(rig, "\(name) S1")

            rig.toS2b()
            rig.settle()
            XCTAssertEqual(rig.flag("_hasActiveAppearance"), true, "\(name): S2b's flags were not produced")
            XCTAssertEqual(rig.flag("_hasKeyAppearance"), false, "\(name): S2b's flags were not produced")
            assertCapsuleMatchesAppKit(rig, lit: true, baseline: base, "\(name) S2b")
            rig.setKey(true)
            assertCapsuleMatchesAppKit(rig, lit: true, baseline: base, "\(name) S1 after S2b")

            rig.beginSheet()
            rig.settle()
            XCTAssertNotNil(rig.window.attachedSheet, "\(name): no sheet attached for S4")
            assertCapsuleMatchesAppKit(rig, lit: true, baseline: base, "\(name) S4")
            rig.endSheet()
            assertCapsuleMatchesAppKit(rig, lit: true, baseline: base, "\(name) S1 after S4")
        }
    }

    // MARK: - A sheet while the app is inactive

    /// A sheet attached to a window that is neither key nor main — the app left
    /// with the sheet up (Cmd-Tab over the `+` sheet), a sheet that ends while
    /// the app is away, a sheet that begins while it is away. The fixture app
    /// read AppKit's platter flat in all three (`_hasActiveAppearance` false,
    /// the window neither key nor main), and lit again on the return. The last
    /// case is the state this process is in for real — never active, its window
    /// neither key nor main, a real sheet attached — reached through the
    /// stand-in only so that an S1 baseline exists first.
    func testASheetWhileTheAppIsAwayLeavesTheCapsuleAsFlatAsAppKitsPlatter() throws {
        for appearance in Self.appearances {
            let name = Self.named(appearance)
            let rig = try rig(appearance)
            rig.show(page: "probe.sheetaway")
            rig.window.orderFront(nil)
            rig.toS1()
            rig.settle()
            let base = try baseline(rig, "\(name) S1")

            // Away with the sheet up, back, then Cancel.
            rig.beginSheet()
            assertCapsuleMatchesAppKit(rig, lit: true, baseline: base, "\(name) S4")
            rig.setMain(false)
            assertCapsuleMatchesAppKit(rig, lit: false, baseline: base, "\(name) S3 with the sheet up")
            rig.setMain(true)
            assertCapsuleMatchesAppKit(rig, lit: true, baseline: base, "\(name) back with the sheet still up")
            rig.endSheet()
            assertCapsuleMatchesAppKit(rig, lit: true, baseline: base, "\(name) S1 after the sheet's Cancel")

            // The sheet ends while the app is away.
            rig.beginSheet()
            rig.setMain(false)
            rig.endSheet()
            XCTAssertNil(rig.window.attachedSheet, "\(name): the sheet did not end")
            assertCapsuleMatchesAppKit(rig, lit: false, baseline: base, "\(name) S3 after the sheet ended while away")
            rig.toS1()
            assertCapsuleMatchesAppKit(rig, lit: true, baseline: base, "\(name) S1 after that return")

            // A sheet begins, and ends, while the app is away.
            rig.toS3()
            rig.beginSheet()
            XCTAssertNotNil(rig.window.attachedSheet, "\(name): no sheet attached while away")
            assertCapsuleMatchesAppKit(rig, lit: false, baseline: base, "\(name) S3 with a sheet begun while away")
            rig.endSheet()
            assertCapsuleMatchesAppKit(rig, lit: false, baseline: base, "\(name) S3 after that sheet ended while away")
            rig.toS1()
            assertCapsuleMatchesAppKit(rig, lit: true, baseline: base, "\(name) S1 after the last return")
        }
    }

    // MARK: - A bar built, or revisited, after the change

    /// Bars are cached per page and only one is attached: a page first built
    /// while the window is flat, and a page whose bar went through a change
    /// while it was detached, must each come back on the window's current look.
    func testABarBuiltOrRevisitedAfterAChangeDrawsTheWindowsCurrentLook() throws {
        for appearance in Self.appearances {
            let name = Self.named(appearance)
            let rig = try rig(appearance)
            rig.show(page: "probe.first")
            rig.window.orderFront(nil)
            rig.toS1()
            rig.settle()
            let base = try baseline(rig, "\(name) S1")

            rig.toS3()
            rig.settle()
            rig.show(page: "probe.builtFlat")
            assertCapsuleMatchesAppKit(rig, lit: false, baseline: base, "\(name) a page first built in S3")
            rig.show(page: "probe.first")
            assertCapsuleMatchesAppKit(rig, lit: false, baseline: base, "\(name) a page revisited in S3")
            rig.toS1()
            rig.settle()
            rig.show(page: "probe.builtFlat")
            assertCapsuleMatchesAppKit(rig, lit: true, baseline: base, "\(name) the flat-built page revisited in S1")
            rig.show(page: "probe.withSearch", segmented: true, search: true)
            assertCapsuleMatchesAppKit(rig, lit: true, baseline: nil, "\(name) a page with search, built in S1")
            rig.toS3()
            assertCapsuleMatchesAppKit(rig, lit: false, baseline: nil, "\(name) a page with search, in S3")
        }
    }

    // MARK: - What a change costs

    /// Each change swaps the capsule's hosting view: the bar must not move and
    /// the views it replaced must not stay behind. The frames every later
    /// reading is held to are the ones read in S5, off the hosting view
    /// `SettingsToolbar.makeActionsItem` built for the page — not off a view a
    /// change has already rebuilt, which would hold a rebuild only to itself.
    func testAChangeMovesNoItemAndLeavesNoReplacedCapsuleAlive() throws {
        let rig = try rig(.darkAqua)
        autoreleasepool {
            rig.show(page: "probe.cost")
            rig.window.orderFront(nil)
        }
        rig.settle()
        // Every reading of a hosting view goes through a pool of its own: a view
        // handed back autoreleased would otherwise live until this test returns
        // and read as a view the change left behind.
        func frames() -> [String] {
            autoreleasepool {
                ["helm.tabs", "helm.actions"].map { id in
                    rig.item(id)?.view.map { NSStringFromRect($0.convert($0.bounds, to: nil)) } ?? "\(id) missing"
                }
            }
        }
        final class Weak { weak var view: NSView?; init(_ view: NSView?) { self.view = view } }
        var seen: [Weak] = []
        func note() {
            autoreleasepool {
                if let host = rig.capsule, !seen.contains(where: { $0.view === host }) { seen.append(Weak(host)) }
            }
        }
        let built = frames()
        note()
        for _ in 0..<10 {
            autoreleasepool { rig.toS1() }
            rig.settle(0.05)
            note()
            XCTAssertEqual(frames(), built, "a change to S1 moved an item on the bar")
            autoreleasepool { rig.toS3() }
            rig.settle(0.05)
            note()
            XCTAssertEqual(frames(), built, "a change to S3 moved an item on the bar")
        }
        rig.settle(0.3)
        XCTAssertGreaterThan(seen.count, 10, "the capsule's hosting view was never replaced — nothing here was exercised")
        let alive = seen.filter { $0.view != nil }.count
        XCTAssertEqual(alive, 1, "\(alive) of \(seen.count) capsule hosting views are still alive after the changes")
    }

    // MARK: - The name zone against AppKit's own window title, in the same window

    /// Turned on in the rig's window beside the zone: the `.moduleName` layout
    /// keeps AppKit's own title hidden (`SettingsWindow.applyTitle`), and showing
    /// it here is what puts AppKit's reading and the zone's in one window, one
    /// state, one appearance.
    private static let appKitTitleText = "Probe Title"

    /// Where the zone's name starts: `NameZoneView`'s leading padding, its
    /// 24 pt plate and the spacing after it. Read against the title in S1 before
    /// anything is believed — a slot that caught the plate would read the
    /// plate's full ink there, not the name's, and the S1 check below fails.
    private static let zoneNameStart = HelmSpace.s5 + 24 + HelmSpace.s5

    /// AppKit's own title field in the rig's window — exactly one visible field
    /// carrying the window's title, or nil.
    private func appKitTitle(_ rig: Rig) -> NSTextField? {
        guard let theme = rig.window.contentView?.superview else { return nil }
        let fields = Self.views(theme).compactMap { $0 as? NSTextField }.filter {
            $0.stringValue == Self.appKitTitleText && !$0.isHiddenOrHasHiddenAncestor && $0.window === rig.window
        }
        return fields.count == 1 ? fields[0] : nil
    }

    /// **The highest alpha `view` draws through its own `draw(_:)`, once**, at
    /// the window's scale. AppKit's title field is read this way and not through
    /// `ink(_:slot:)`: `cacheDisplay` (and `CALayer.render(in:)`) composite that
    /// field's text twice — measured 0.976 in S1, which is 1 − (1 − 0.847)² for
    /// its `labelColor` at 0.847, and 0.478 / 0.439 for 0.278 / 0.251 in S3 — so
    /// every share taken from it would be bent. `draw(_:)` reads 0.847 in S1,
    /// the same single composite `ink(_:slot:)` reads off the zone's own name,
    /// and `nameReading` holds the two equal there before any share is taken.
    private static func drawnOnce(_ view: NSView) -> CGFloat? {
        let scale = view.window?.backingScaleFactor ?? 2
        let wide = Int((view.bounds.width * scale).rounded(.up))
        let high = Int((view.bounds.height * scale).rounded(.up))
        guard wide > 0, high > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: wide, pixelsHigh: high,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: scale, y: scale)
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        var best: CGFloat = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                if let a = rep.colorAt(x: x, y: y)?.alphaComponent, a > best { best = a }
            }
        }
        return best
    }

    /// AppKit's title, the zone's name alone, and the zone whole — plate, its
    /// shadow and any badge with the name.
    private struct NameReading { let title: CGFloat; let zoneName: CGFloat; let zoneRow: CGFloat }

    private func nameReading(_ rig: Rig, _ label: String,
                             file: StaticString = #filePath, line: UInt = #line) -> NameReading? {
        guard let field = appKitTitle(rig) else {
            XCTFail("\(label): AppKit's own title is not drawn in the window — nothing to compare the zone with",
                    file: file, line: line)
            return nil
        }
        guard let zone = rig.item("helm.name")?.view else {
            XCTFail("\(label): no name zone on the bar", file: file, line: line)
            return nil
        }
        guard let title = Self.drawnOnce(field),
              let name = Self.ink(zone, slot: Self.zoneNameStart...zone.bounds.width),
              let row = Self.ink(zone) else {
            XCTFail("\(label): no ink read off the title or the zone", file: file, line: line)
            return nil
        }
        return NameReading(title: title, zoneName: name, zoneRow: row)
    }

    /// The zone against AppKit's title: each as a share of its own S1 reading.
    /// `lit` is what AppKit's own title must itself read — the proof that the
    /// state was produced before any equality is believed.
    ///
    /// **Within 0.01, because the two Dark constants sit 0.02 apart.** Read
    /// at no tolerance on this Mac (27.2, 2026-09-28), in every state both
    /// name-zone cases visit: the zone and AppKit's title part by at most
    /// 0.0057 (27's title bar, Dark, the zone whole: 0.3020 against 0.2963),
    /// about one step of an 8-bit alpha in the ratio. The Dark constant of
    /// the wrong title bar sits 0.016 (0.28 under 27's) and 0.021 (0.30 under
    /// 26's opaque one) from AppKit's reading, inside the 0.03 this held
    /// before — so at 0.03 the Dark half of `NameZoneView.inactiveOpacity`
    /// could read either bar's constant and pass.
    private func assertZoneFollowsTitle(_ reading: NameReading?, base: NameReading, lit: Bool, _ label: String,
                                        file: StaticString = #filePath, line: UInt = #line) {
        guard let reading else { return }
        let titleShare = reading.title / base.title
        if lit {
            XCTAssertGreaterThan(titleShare, 0.95, "\(label): AppKit's own title reads \(titleShare) of its S1 ink — the lit state was not produced",
                                 file: file, line: line)
        } else {
            XCTAssertLessThan(titleShare, 0.5, "\(label): AppKit's own title reads \(titleShare) of its S1 ink — the inactive state was not produced",
                              file: file, line: line)
        }
        XCTAssertEqual(reading.zoneName / base.zoneName, titleShare, accuracy: 0.01, """
            \(label): the zone's name draws at \(reading.zoneName / base.zoneName) of its S1 ink, \
            AppKit's title beside it at \(titleShare) of its own
            """, file: file, line: line)
        XCTAssertEqual(reading.zoneRow / base.zoneRow, titleShare, accuracy: 0.01, """
            \(label): the zone as a whole — plate, shadow, name — draws at \(reading.zoneRow / base.zoneRow) \
            of its S1 ink, AppKit's title at \(titleShare) — the zone does not dim as one unit
            """, file: file, line: line)
    }

    /// A window with the zone and AppKit's own title side by side, opened while
    /// the app is away (S5) and never keyed yet.
    private func nameRig(_ appearance: NSAppearance.Name, page: String, band: HelmBandChoice) throws -> Rig {
        let rig = try rig(appearance, band: band)
        rig.show(page: page, segmented: false)
        rig.window.title = Self.appKitTitleText
        rig.window.titleVisibility = .visible
        rig.window.orderFront(nil)
        rig.settle()
        return rig
    }

    /// The S1 reading every share is taken against, and the check that both
    /// sides are one composite of the same ink there: AppKit's title and the
    /// zone's name read equal (the film: Dark 222 vs 222, Light 37 vs 38).
    private func nameBaseline(_ rig: Rig, _ label: String) throws -> NameReading {
        let base = try XCTUnwrap(nameReading(rig, label), "\(label): no S1 reading")
        XCTAssertGreaterThan(base.title, 0.5, "\(label): AppKit's title is barely drawn in S1 — nothing below reads it")
        XCTAssertEqual(base.zoneName, base.title, accuracy: 0.03, """
            \(label): the zone's name reads \(base.zoneName) in S1 and AppKit's title \(base.title) — \
            not one composite of the same ink, so no share below compares like with like
            """)
        return base
    }

    /// **The owner's answer — «Да, как у AppKit» — held against AppKit's own
    /// title, drawn in the same window, read the same way, in every state.**
    /// S5 (opened while the app is away, never keyed), S1, S3, the return to
    /// S1, S2b (a panel takes key, the window stays main), a sheet (S4), and a
    /// run of returns: the zone's name, and the zone as a whole, draw the same
    /// share of their S1 ink as AppKit's title does. Measured on this tree:
    /// title 0.278 / 0.847 Light, 0.251 / 0.847 Dark in S3 and S5; the zone's
    /// name 0.278 / 0.255, its row 0.329 / 0.302 of 1.000 — and 1.000 wherever
    /// AppKit's title stays at full ink. Read under each system's title bar
    /// (`systems`): under macOS 26's opaque one, as AppKit 27.2 draws it, the
    /// title keeps 0.399 Light and 0.279 Dark of its S1 ink where it keeps
    /// 0.329 and 0.296 under 27's transparent one (engineer, 2026-09-27).
    func testTheNameZoneDimsWhereAndAsFarAsAppKitsOwnTitleInTheSameWindow() throws {
        for (system, appearance) in Self.systemsByAppearance {
            let name = "\(system.name), \(Self.named(appearance))"
            let rig = try nameRig(appearance, page: "probe.nameZone", band: system.band)
            XCTAssertEqual(rig.flag("_hasActiveAppearance"), false, "\(name): this process's window is not in S5")
            let fresh = nameReading(rig, "\(name) S5")

            rig.toS1()
            rig.settle()
            let base = try nameBaseline(rig, "\(name) S1 after S5")
            assertZoneFollowsTitle(fresh, base: base, lit: false, "\(name) S5, opened unkeyed")

            let steps: [(String, Bool, () -> Void)] = [
                ("S3", false, { rig.toS3() }),
                ("S1 return", true, { rig.toS1() }),
                ("S2b", true, { rig.toS2b() }),
                ("S1 after S2b", true, { rig.setKey(true) }),
                ("S4", true, { rig.beginSheet() }),
                ("S1 after S4", true, { rig.endSheet() }),
                ("S3 again", false, { rig.toS3() }),
                ("S1 after five same-turn round trips", true, { for _ in 0..<5 { rig.toS3(); rig.toS1() } }),
                ("S3, key then main a turn apart", false, { rig.setKey(false); rig.settle(0.1); rig.setMain(false) }),
                ("S1, main then key a turn apart", true, { rig.setMain(true); rig.settle(0.1); rig.setKey(true) }),
            ]
            for (label, lit, step) in steps {
                step()
                rig.settle()
                assertZoneFollowsTitle(nameReading(rig, "\(name) \(label)"), base: base, lit: lit, "\(name) \(label)")
            }
        }
    }

    /// **The snap: the zone moves in the same turn AppKit's title does, and
    /// nothing moves after.** Read with no run-loop turn after each change — the
    /// signal crossing in from `SettingsWindow`'s `windowDid…` methods is
    /// synchronous, and so is AppKit's own title — then again once settled: the
    /// zone's first reading must already match AppKit's, and its settled one
    /// must equal its first, which an animation or a deferred update cannot do.
    func testTheNameZoneMovesInTheSameTurnAsAppKitsOwnTitle() throws {
        for (system, appearance) in Self.systemsByAppearance {
            let name = "\(system.name), \(Self.named(appearance))"
            let rig = try nameRig(appearance, page: "probe.nameZoneSnap", band: system.band)
            rig.toS1()
            rig.settle()
            let base = try nameBaseline(rig, "\(name) S1")

            let steps: [(String, Bool, () -> Void)] = [
                ("S3", false, { rig.toS3() }),
                ("S1", true, { rig.toS1() }),
                ("S3 by key then main", false, { rig.setKey(false); rig.setMain(false) }),
                ("S2b on the way back", true, { rig.setMain(true) }),
                ("S1 from S2b", true, { rig.setKey(true) }),
            ]
            for (label, lit, step) in steps {
                step()
                let first = nameReading(rig, "\(name) \(label), same turn")
                assertZoneFollowsTitle(first, base: base, lit: lit, "\(name) \(label), same turn")
                rig.settle()
                let settled = nameReading(rig, "\(name) \(label), settled")
                assertZoneFollowsTitle(settled, base: base, lit: lit, "\(name) \(label), settled")
                if let first, let settled {
                    XCTAssertEqual(settled.zoneRow, first.zoneRow, accuracy: 0.01, """
                        \(name) \(label): the zone read \(first.zoneRow) in the turn of the change and \
                        \(settled.zoneRow) once settled — it was still moving after AppKit's title had stopped
                        """)
                }
            }
        }
    }

    // MARK: - The first-attach correction, fed what can land before it runs

    /// The `+`, the switcher and the tabs, read now and judged later against a
    /// baseline taken on the same content in S1.
    private struct Inks { let plus: CGFloat; let mode: CGFloat; let tabs: CGFloat }

    private func inks(_ rig: Rig, _ label: String, file: StaticString = #filePath, line: UInt = #line) -> Inks? {
        guard let host = rig.capsule, let tabs = rig.tabs else {
            XCTFail("\(label): no capsule or no tabs on the bar", file: file, line: line)
            return nil
        }
        let slot = slots(host)
        guard let plus = Self.ink(host, slot: slot.plus), let modeSlot = slot.mode,
              let mode = Self.ink(host, slot: modeSlot), let tabInk = Self.ink(tabs) else {
            XCTFail("\(label): no ink read", file: file, line: line)
            return nil
        }
        return Inks(plus: plus, mode: mode, tabs: tabInk)
    }

    /// Each item's share of its S1 ink equal to the tabs' — a folded or evicted
    /// switcher reads close to nothing and a glyph left on the wrong look reads
    /// the other state's share, so either fails here.
    private func assertShares(_ inks: Inks?, base: Baseline, _ label: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        guard let inks else { return }
        let tabs = inks.tabs / base.tabs
        XCTAssertEqual(inks.plus / base.plus, tabs, accuracy: 0.1,
                       "\(label): the + draws at \(inks.plus / base.plus) of its S1 ink, the tabs at \(tabs)",
                       file: file, line: line)
        XCTAssertEqual(inks.mode / base.mode, tabs, accuracy: 0.1,
                       "\(label): the switcher draws at \(inks.mode / base.mode) of its S1 ink, the tabs at \(tabs)",
                       file: file, line: line)
    }

    /// **`SettingsToolbar.correctActionsGlassOnFirstAttach(_:)` spends its flag
    /// in `show(_:key:)` and rebuilds a turn later — so whatever lands in that
    /// turn lands first.** Fed here, each in the turn between the attach and
    /// the rebuild: the window becoming key; the page switching away (the
    /// rebuild then lands on a detached bar) and back; the bar torn down by a
    /// new shape on the same page; and, while the window is away, a page-bar
    /// style change that rebuilds the attached bar and a language change that
    /// does not. Each must end on AppKit's current look — glass, glyphs and the
    /// tabs unfolded — and the key case on the lit glyph, which a rebuild that
    /// acted on a reading taken before the hop would dim.
    func testTheFirstAttachCorrectionEndsOnTheWindowsCurrentLookWhateverLandsFirst() throws {
        for appearance in Self.appearances {
            let name = Self.named(appearance)

            // The window becomes key before the queued rebuild runs.
            do {
                let rig = try rig(appearance)
                rig.show(page: "probe.keyFirst")
                rig.window.orderFront(nil)
                rig.toS1()
                rig.settle()
                let base = try baseline(rig, "\(name) S1, keyed before the correction ran")
                assertCapsuleMatchesAppKit(rig, lit: true, baseline: base, "\(name) keyed before the correction ran")
                XCTAssertGreaterThan(base.plus, 0.9, "\(name): the + is dimmed in S1 — the correction acted on the look from before key")
                rig.toS3()
                assertCapsuleMatchesAppKit(rig, lit: false, baseline: base, "\(name) S3 after that")
                rig.toS1()
                assertCapsuleMatchesAppKit(rig, lit: true, baseline: base, "\(name) S1 after that")
            }

            // The page switches away before it runs, and comes back while still away.
            do {
                let rig = try rig(appearance)
                rig.show(page: "probe.switchedA")
                rig.window.orderFront(nil)
                rig.show(page: "probe.switchedB")
                assertCapsuleMatchesAppKit(rig, lit: false, baseline: nil, "\(name) the page switched before the correction ran")
                let onB = inks(rig, "\(name) on B")
                rig.show(page: "probe.switchedA")
                assertCapsuleMatchesAppKit(rig, lit: false, baseline: nil, "\(name) back on the page whose correction ran detached")
                let backOnA = inks(rig, "\(name) back on A")
                rig.toS1()
                rig.settle()
                let base = try baseline(rig, "\(name) S1 on A")
                assertCapsuleMatchesAppKit(rig, lit: true, baseline: base, "\(name) S1 on A")
                assertShares(onB, base: base, "\(name) on B while away")
                assertShares(backOnA, base: base, "\(name) back on A while away")
            }

            // The bar is torn down — a new shape on the same page — before it runs.
            do {
                let rig = try rig(appearance)
                rig.show(page: "probe.torn")
                rig.window.orderFront(nil)
                rig.show(page: "probe.torn", segmented: true, search: true)
                assertCapsuleMatchesAppKit(rig, lit: false, baseline: nil, "\(name) the bar rebuilt before the correction ran")
                let torn = inks(rig, "\(name) after the tear-down")
                rig.toS1()
                rig.settle()
                let base = try baseline(rig, "\(name) S1 after the tear-down")
                assertCapsuleMatchesAppKit(rig, lit: true, baseline: base, "\(name) S1 after the tear-down")
                assertShares(torn, base: base, "\(name) the rebuilt bar while away")
            }

            // While away: a page-bar style change rebuilds the attached bar, a language change does not.
            do {
                // Raw, so a key the domain did not hold is removed again
                // rather than written back as the typed getter's default.
                let found = AppSettings.store.object(PageBarStyle.storageKey)
                defer {
                    AppSettings.store.set(found, for: PageBarStyle.storageKey)
                    NotificationCenter.default.post(name: .helmPageBarStyleChanged, object: nil)
                }
                let saved = AppSettings.pageBarStyle
                let rig = try rig(appearance)
                rig.show(page: "probe.style")
                rig.window.orderFront(nil)
                rig.toS1()
                rig.settle()
                let base = try baseline(rig, "\(name) S1 before the style change")
                rig.toS3()
                rig.settle()
                AppSettings.pageBarStyle = saved == .windowTitle ? .moduleName : .windowTitle
                assertCapsuleMatchesAppKit(rig, lit: false, baseline: base, "\(name) a page-bar style change while away")
                NotificationCenter.default.post(name: .helmLanguageChanged, object: nil)
                assertCapsuleMatchesAppKit(rig, lit: false, baseline: base, "\(name) a language change while away")
                AppSettings.pageBarStyle = saved
                assertCapsuleMatchesAppKit(rig, lit: false, baseline: base, "\(name) the style change undone while away")
                rig.toS1()
                assertCapsuleMatchesAppKit(rig, lit: true, baseline: base, "\(name) S1 after the style changes")
            }
        }
    }
}
