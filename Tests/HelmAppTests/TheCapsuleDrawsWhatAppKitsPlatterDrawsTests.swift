import AppKit
import HelmTestSupport
import ObjectiveC
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The Settings window's page bar — the actions capsule's glass, its `+` and the view-mode
/// switcher inside it, the plates under the tabs and the search, and the name zone — against
/// what AppKit draws in a window of its own, in the same state, read the same way.** The
/// owner's report: the capsule stayed Liquid Glass while the window was not in focus, where
/// the centre tabs lost their volume.
///
/// **The subject** is the `.pageBar` build of the real `SettingsWindow`, its own `ShellPageBar` reached through
/// `Mirror`, and the zones read off the bar's view. **The reference** is a window this file
/// builds with a real `NSToolbar`: AppKit draws its platter, a stock `NSSegmentedControl`
/// (one with nothing selected, one with a selected segment) and a visible title in it. The subject has no toolbar, so nothing else in these rows says what AppKit draws.
/// Every state step drives both windows. The glass comparisons and the Flat row first assert that the two windows draw active alike and that AppKit's platter reads the state the step meant; the name-zone rows first assert that AppKit's title reads the state the step meant.
///
/// **Compared under Liquid Glass**, in S1 active and key, S2b another of the app's panels
/// key while this window stays main, S3 app inactive, S4 a sheet, S5 a window opened while
/// another app is active:
/// - Glass: six values of one glass group — the `CASDFLayer` whose effect is
///   `CASDFKeyFillHighlightEffect` (its opacity, the effect's key and fill alpha), the
///   `CASDFOutputEffect`'s `maximum`, and the `CABackdropLayer` filtered `glassBackground`
///   (`marginWidth`, `windowServerAware`) — read under the capsule's view and under the
///   reference toolbar's `NSGlassContainerView`. The plates hold exactly one
///   `NSGlassEffectView` equal to AppKit's platter when the platter is lit, and none when it
///   is flat.
/// - Ink: the highest alpha a control draws through `cacheDisplay` (glass does not composite
///   in a test process, so the bitmap holds the glyphs and labels alone), as a fraction of
///   the same control's own S1 reading. The `+` and the tabs plate against the reference
///   control with nothing selected; the switcher against the one with a selected segment,
///   in a row of its own. Outside `testASheetOnAnActiveWindowDimsThePlusAndTheTabsAsAppKitsDisabledToolbarItems`, ink is not compared while a sheet hangs from the reference
///   window, where AppKit draws its toolbar items disabled.
/// - The name zone: its name, and the zone whole, as a share of their S1 ink against the
///   reference title's, within 0.01, under each system's title bar. The title is read
///   through its own `draw(_:)`, once; `nameBaseline` holds that reading equal to the zone's name in S1 under the transparent title bar.
///
/// **Compared under Flat**, in one row: the bar has no AppKit counterpart for its drawing,
/// and none is invented. With the look pinned to Flat there is no glass layer and no glass
/// view anywhere under the bar's view, after the plates are shown to exist and to hold a
/// fill, and each plate's `alphaValue` is 1 exactly when AppKit's platter is lit and below 1
/// when it is flat. The amount of the dimming is held by
/// `ThePlateDrawsByAppearanceAndActivityTests`.
///
/// **What stands in for the window server.** A `swift test` process cannot activate itself
/// and no window of it becomes key or main, so only S5, and a sheet on S5's window, are
/// produced as a person meets them. On every key or main change a real app carries three
/// things at once: the window's public `isKeyWindow` / `isMainWindow`, AppKit's private key
/// and main appearance (which the platter and the reference title follow), and the
/// notification the window posts. `Rig.setKey(_:)` and `Rig.setMain(_:)` produce all three,
/// in that order, on both windows: the two getters answer for the registered windows through
/// `standInForTheWindowServer()`, AppKit's own `acquireKeyAppearance`, `resignKeyAppearance`,
/// `acquireMainAppearance` and `resignMainAppearance` move the appearance, and the
/// notification reaches the window's delegate. Every state a comparison is read in has a flag pair a running
/// app has: S1 key and main, S2b and S4 main only, S3 and S5 neither. `testLeavingAndReturningNeverLeavesTheCapsuleOnTheOldLook` also passes through key without main for one turn, between two readings. If AppKit stops
/// answering one of the four selectors this file fails; it does not skip.
///
/// **Total failure.** A reference window that draws no `NSToolbarPlatterView`, or whose
/// `NSGlassContainerView` holds other than exactly one glass group, fails every row with
/// "the reference window has no platter view: the capsule was compared with nothing" (an
/// empty toolbar still has the container, so the container alone proves nothing); a
/// reference title that is not drawn fails the name-zone rows with "AppKit's own title is not
/// drawn in the reference window — nothing to compare the zone with".
///
/// **Left red on purpose**, each a difference between the bar and AppKit that this file
/// states and does not bend:
/// - `testASheetOnAnActiveWindowDimsThePlusAndTheTabsAsAppKitsDisabledToolbarItems`: AppKit disables
///   its toolbar items under a sheet; the `+` and the tabs stay at full ink. It goes green
///   when the bar's controls draw as the reference's do, and whether they should is the
///   owner's.
/// - `testTheCapsulesSwitcherDimsInAnInactiveWindowAsAppKitsOwnControlDoes`: the `+` dims
///   as AppKit's control does and the switcher does not. It goes green when the switcher
///   dims as the reference control with a selected segment does.
/// - `testTheNameZoneDrawsAppKitsTitleInkUnderTheOpaqueTitleBar`: under the opaque title bar
///   the zone's name and the reference title read different ink in S1. It goes green when
///   the two read alike, and whether the zone should is the owner's.
///
/// **What an unshown, never-key test window cannot compare**, and what this file therefore
/// leaves to a key window and the owner's eye:
/// - The glass-look plate while inactive (a fill at the name zone's dimming) against AppKit's
///   flat platter as drawn. By layers they differ by design: the platter keeps its glass
///   group at highlight 0, the plate has none. The rows hold only that the plate has glass
///   exactly when the platter is lit.
/// - The lit rim and volume of the glass as composited, and any pixel of glass: the rows
///   compare layer values.
/// - An inactive window under Liquid Glass, where the tabs plate is a dimmed fill beside the
///   capsule's flat glass: the two drawings side by side.
/// - The Flat bar's fill against anything of AppKit's.
/// - The ink of the search plate, and of any control under a sheet outside the red row above.
/// - The capsule's glass staying lit in Helm Dev: it is not reproduced here.
/// - A panel that really holds key in S2b (only its effect on this window is produced), the
///   timing of a real activation event, and the Settings window's close-and-reopen path,
///   whose pane unmount (`helmIdlesOffScreen`) listens for occlusion notifications a test
///   process is never sent.
/// - The window-level dimming a sheet adds over every item alike.
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
    /// is taken under; with `windowTitle` left in the test tool's own
    /// domain the zone draws the name without its plate, and `zoneNameStart` no longer marks where the name starts. Kept raw and put back by the test's own teardown, so a
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

    /// What one walk over a layer tree found of glass: the layers of each of the three kinds,
    /// counted whether or not their values can be read, and the readable values of each.
    private struct GlassWalk {
        var highlightLayers = 0
        var outputLayers = 0
        var backdropLayers = 0
        var walked = 0
        var highlights: [(Float, CGFloat, CGFloat)] = []
        var maxima: [Double] = []
        var backdrops: [(Double, Bool)] = []
    }

    /// The one walk every glass reading here stands on: `glass(under:)` takes the values from it
    /// and demands exactly one group, the Flat row takes the layer counts and demands none.
    private static func walkGlass(under root: CALayer) -> GlassWalk {
        var found = GlassWalk()
        func alpha(_ value: Any?) -> CGFloat? {
            guard let value, CFGetTypeID(value as CFTypeRef) == CGColor.typeID else { return nil }
            return (value as! CGColor).alpha   // swiftlint:disable:this force_cast
        }
        func walk(_ layer: CALayer) {
            found.walked += 1
            let cls = String(cString: class_getName(object_getClass(layer)))
            if cls == "CASDFLayer", layer.responds(to: NSSelectorFromString("effect")),
               let effect = layer.value(forKey: "effect") as? NSObject {
                let effectClass = String(cString: class_getName(object_getClass(effect)))
                if effectClass == "CASDFKeyFillHighlightEffect" {
                    found.highlightLayers += 1
                    if let key = alpha(effect.value(forKey: "keyColor")),
                       let fill = alpha(effect.value(forKey: "fillColor")) {
                        found.highlights.append((layer.opacity, key, fill))
                    }
                } else if effectClass == "CASDFOutputEffect" {
                    found.outputLayers += 1
                    if let maximum = (effect.value(forKey: "maximum") as? NSNumber)?.doubleValue {
                        found.maxima.append(maximum)
                    }
                }
            }
            if cls == "CABackdropLayer", let filters = layer.filters as? [NSObject],
               filters.contains(where: { "\($0)" == "glassBackground" }) {
                found.backdropLayers += 1
                if let margin = (layer.value(forKey: "marginWidth") as? NSNumber)?.doubleValue,
                   let aware = (layer.value(forKey: "windowServerAware") as? NSNumber)?.boolValue {
                    found.backdrops.append((margin, aware))
                }
            }
            for sub in layer.sublayers ?? [] { walk(sub) }
        }
        walk(root)
        return found
    }

    /// One glass group under `root` — exactly one of each of the three layers,
    /// or nil, so a tree that holds two groups (a second glass nobody expected)
    /// or none (the capsule drew no glass) is a failure and not a pick.
    private static func glass(under root: CALayer) -> Glass? {
        let found = walkGlass(under: root)
        guard found.highlights.count == 1, found.maxima.count == 1, found.backdrops.count == 1 else { return nil }
        return Glass(highlightOpacity: found.highlights[0].0, keyAlpha: found.highlights[0].1, fillAlpha: found.highlights[0].2,
                     outputMaximum: found.maxima[0], backdropMargin: found.backdrops[0].0, windowServerAware: found.backdrops[0].1)
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

    // MARK: - The windows

    /// **The sentence a reference with nothing to compare against prints.**
    nonisolated static let referenceHasNoPlatter = "the reference window has no platter view: the capsule was compared with nothing"

    /// A thrown reference failure; the sentence is also reported through `XCTFail`.
    struct ReferenceHasNoPlatter: Error, CustomStringConvertible {
        var description: String { TheCapsuleDrawsWhatAppKitsPlatterDrawsTests.referenceHasNoPlatter }
    }

    /// **The reference: a window of this file's own with a real `NSToolbar`** holding two stock
    /// `NSSegmentedControl` items (one with nothing selected, one with a selected segment), a visible title and no other part of Helm. AppKit draws the
    /// toolbar's platter and the title in it; the subject has no toolbar, so nothing else in these rows can say what AppKit draws in each state.
    @MainActor private final class Reference: NSObject, NSToolbarDelegate {
        static let itemID = NSToolbarItem.Identifier("probe.reference.mode")
        static let selectedItemID = NSToolbarItem.Identifier("probe.reference.selected")
        let window: NSWindow
        /// Nothing selected: AppKit's ink for a control with glyphs alone, which the `+` and the tabs plate are.
        let control: NSSegmentedControl
        /// Segment 0 selected: AppKit's ink for a control with a selection pill, which the view-mode switcher is.
        let selectedControl: NSSegmentedControl
        private let toolbar: NSToolbar

        init(appearance: NSAppearance.Name, transparentTitleBar: Bool) {
            control = NSSegmentedControl(images: [NSImage(systemSymbolName: "tablecells", accessibilityDescription: nil)!,
                                                  NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: nil)!],
                                         trackingMode: .selectOne, target: nil, action: nil)
            // No segment selected: the selection pill draws more ink than the glyphs do
            // when the window is inactive (measured in Dark, inactive: 0.373 of its S1 ink against 0.292), and the
            // capsule's `+` and the tabs plate are read as glyph ink alone.
            control.selectedSegment = -1
            selectedControl = NSSegmentedControl(images: [NSImage(systemSymbolName: "tablecells", accessibilityDescription: nil)!,
                                                          NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: nil)!],
                                                 trackingMode: .selectOne, target: nil, action: nil)
            selectedControl.selectedSegment = 0
            toolbar = NSToolbar(identifier: "probe.reference")
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 420),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
            super.init()
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            window.toolbar = toolbar
            window.title = "Probe Title"
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = transparentTitleBar
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: appearance)
        }

        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [Self.itemID, Self.selectedItemID] }
        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [Self.itemID, Self.selectedItemID] }
        func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                     willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
            guard itemIdentifier == Self.itemID || itemIdentifier == Self.selectedItemID else { return nil }
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.view = itemIdentifier == Self.itemID ? control : selectedControl
            return item
        }

        func drop() {
            window.orderOut(nil)
            window.toolbar = nil
            toolbar.delegate = nil
        }
    }

    /// The real `SettingsWindow` — its own `window`, `model`, `toolbarChannel` and `pageBar` —
    /// reached through `Mirror`, since all four are private there, and beside it the reference.
    /// Every state step drives both windows. Never `show(selecting:)`: that asks to activate the app.
    @MainActor private final class Rig {
        let owner: SettingsWindow
        let window: NSWindow
        let model: SettingsModel
        let channel: HelmWindowToolbarChannel
        let bar: ShellPageBar
        let reference: Reference
        private var sheets: [NSWindow] = []

        /// `band` is the system whose settings window this is — never this
        /// Mac's own: the title bar it sets is what AppKit's title and the
        /// name zone are both drawn under.
        init(appearance: NSAppearance.Name, band: HelmBandChoice) throws {
            owner = SettingsWindow(host: ModuleHost.shared, band: band, bar: .pageBar)
            let fields = Mirror(reflecting: owner).children
            func field<T>(_ name: String, as type: T.Type) throws -> T {
                try XCTUnwrap(fields.first { $0.label == name }?.value as? T,
                              "SettingsWindow no longer holds `\(name)` as \(T.self) — this rig reads it by name")
            }
            window = try field("window", as: NSWindow.self)
            model = try field("model", as: SettingsModel.self)
            channel = try field("toolbarChannel", as: HelmWindowToolbarChannel.self)
            bar = try field("pageBar", as: ShellPageBar.self)
            window.appearance = NSAppearance(named: appearance)
            reference = Reference(appearance: appearance, transparentTitleBar: band.titlebarAppearsTransparent)
            reference.window.orderFront(nil)
        }

        private var windows: [NSWindow] { [window, reference.window] }

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

        /// The bar's zones, read off the bar's own view.
        var capsule: NSView? { bar.view.view(for: .actions) }
        var tabs: NSView? { bar.view.view(for: .tabs) }
        var search: NSView? { bar.view.view(for: .search) }
        var nameZone: NSView? { bar.view.view(for: .name) }
        /// The capsule's model, held by the bar's actions zone, which the bar keeps private.
        var actionsModel: HelmToolbarActionsModel? {
            (Mirror(reflecting: bar).children.first { $0.label == "actions" }?.value as? ShellBarActions)?.model
        }

        func settle(_ seconds: TimeInterval = 0.3) {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end {
                windows.forEach { $0.layoutIfNeeded() }
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            }
        }

        /// AppKit's own key/main appearance entry points — see this file's header — on both windows.
        func appKit(_ selectors: String...) {
            for name in selectors {
                let selector = NSSelectorFromString(name)
                for window in windows {
                    guard let method = class_getInstanceMethod(type(of: window), selector) else {
                        XCTFail("NSWindow no longer answers \(name): this file's stand-in for the window server is gone")
                        return
                    }
                    typealias Call = @convention(c) (AnyObject, Selector) -> Void
                    unsafeBitCast(method_getImplementation(method), to: Call.self)(window, selector)
                }
            }
        }
        func flag(_ name: String, of window: NSWindow? = nil) -> Bool? {
            let window = window ?? self.window
            let selector = NSSelectorFromString(name)
            guard let method = class_getInstanceMethod(type(of: window), selector) else { return nil }
            typealias Read = @convention(c) (AnyObject, Selector) -> Bool
            return unsafeBitCast(method_getImplementation(method), to: Read.self)(window, selector)
        }

        // MARK: The window server, as a real app has it — see this file's header

        private(set) var isKey = false
        private(set) var isMain = false

        /// One key change: the flag, AppKit's own appearance, the notification — on both windows.
        func setKey(_ on: Bool, file: StaticString = #filePath, line: UInt = #line) {
            isKey = on
            answer(file: file, line: line)
            appKit(on ? "acquireKeyAppearance" : "resignKeyAppearance")
            for window in windows {
                NotificationCenter.default.post(
                    name: on ? NSWindow.didBecomeKeyNotification : NSWindow.didResignKeyNotification, object: window)
            }
        }
        /// One main change, the same three in the same order.
        func setMain(_ on: Bool, file: StaticString = #filePath, line: UInt = #line) {
            isMain = on
            answer(file: file, line: line)
            appKit(on ? "acquireMainAppearance" : "resignMainAppearance")
            for window in windows {
                NotificationCenter.default.post(
                    name: on ? NSWindow.didBecomeMainNotification : NSWindow.didResignMainNotification, object: window)
            }
        }
        private func answer(file: StaticString, line: UInt) {
            for window in windows {
                TheCapsuleDrawsWhatAppKitsPlatterDrawsTests.answers[ObjectIdentifier(window)] = (isKey, isMain)
                // The stand-in is what every later reading rests on: it must hold.
                XCTAssertEqual(window.isKeyWindow, isKey, "the window server stand-in does not answer isKeyWindow",
                               file: file, line: line)
                XCTAssertEqual(window.isMainWindow, isMain, "the window server stand-in does not answer isMainWindow",
                               file: file, line: line)
            }
        }

        /// Main first, then key — the order a real reactivation posts them in.
        func toS1() { setMain(true); setKey(true) }
        func toS3() { setKey(false); setMain(false) }
        /// S2b: another of the app's windows took key, this one stays main.
        func toS2b() { setKey(false) }
        /// A real sheet on each window. An active app's sheet takes key from the window, which
        /// stays main (S4); an inactive app's window has no key to give up.
        func beginSheet() {
            for window in windows {
                let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
                                     styleMask: [.titled], backing: .buffered, defer: false)
                sheets.append(sheet)
                window.beginSheet(sheet)
            }
            if isKey { setKey(false) }
        }
        /// Ends the sheets for real. An active app hands key back to the window
        /// (the sheet's Cancel); an inactive one has none to hand back.
        func endSheet() {
            for window in windows {
                if let sheet = window.attachedSheet { window.endSheet(sheet) }
            }
            if isMain, !isKey { setKey(true) }
        }

        func drop() {
            for window in windows {
                if let sheet = window.attachedSheet { window.endSheet(sheet) }
                TheCapsuleDrawsWhatAppKitsPlatterDrawsTests.answers[ObjectIdentifier(window)] = nil
            }
            window.orderOut(nil)
            reference.drop()
            // `SettingsWindow.init` names the window's frame for autosave; keep
            // the test process's own defaults as they were.
            NSWindow.removeFrame(usingName: "HelmSettingsWindow.v4")
        }
    }

    private var rigs: [Rig] = []
    /// The settings window's autosaved frame as the test tool's own domain
    /// held it before the first rig, put back after the last one drops —
    /// `Rig.drop()` removes the frame whether or not it was there.
    private var foundFrame: String?
    private var frameHeld = false
    private static let frameKey = "NSWindow Frame HelmSettingsWindow.v4"

    override func tearDown() {
        rigs.forEach { $0.drop() }
        rigs = []
        if frameHeld {
            UserDefaults.standard.set(foundFrame, forKey: Self.frameKey)
        }
        super.tearDown()
    }

    /// macOS 27's window unless a case names another system — the capsule's
    /// readings were taken under its transparent title bar. Throws, and says
    /// so, when the reference window draws no platter: every row passes here,
    /// so a reference that lost its toolbar fails them all and not one of them
    /// compares the capsule with nothing.
    private func rig(_ appearance: NSAppearance.Name, band: HelmBandChoice = .onMacOS(27),
                     look: HelmBarAppearance = .liquidGlass) throws -> Rig {
        if !standingIn {
            try standInForTheWindowServer()
            holdThePageBarStyle()
            holdTheBarLook(look)
            foundFrame = UserDefaults.standard.string(forKey: Self.frameKey)
            frameHeld = true
            standingIn = true
        }
        let rig = try Rig(appearance: appearance, band: band)
        rigs.append(rig)
        rig.settle()
        guard Self.platter(of: rig.reference.window) != nil else {
            XCTFail(Self.referenceHasNoPlatter)
            throw ReferenceHasNoPlatter()
        }
        return rig
    }

    /// **The bar's look is pinned by the row's first rig** (Liquid Glass unless the row names
    /// Flat), before the window is built because the bar reads it then, and put back raw by the
    /// test's own teardown, so a key the domain did not hold is removed again.
    private func holdTheBarLook(_ look: HelmBarAppearance) {
        let store = AppSettings.store
        let found = store.object(HelmBarAppearance.storageKey)
        addTeardownBlock { @MainActor in
            store.set(found, for: HelmBarAppearance.storageKey)
            NotificationCenter.default.post(name: .helmBarAppearanceChanged, object: nil)
        }
        AppSettings.barAppearance = look
    }

    // MARK: - The comparison

    /// Per-item S1 ink, the denominator every later ink reading is a fraction of.
    /// `reference` is AppKit's own segmented control in the reference window.
    private struct Baseline { let plus: CGFloat; let mode: CGFloat; let tabs: CGFloat; let reference: CGFloat; let referenceSelected: CGFloat }

    /// The `+` and the view-mode switcher's slots inside the capsule — the
    /// capsule's own reserve read off the live model, laid end to end from the
    /// trailing edge (the bar's layout owns the margin, so the zone's width is
    /// the reserve).
    private func slots(_ rig: Rig) -> (plus: ClosedRange<CGFloat>, mode: ClosedRange<CGFloat>?)? {
        guard let host = rig.capsule, let model = rig.actionsModel else { return nil }
        let declared = model.declared
        let reserve = HelmToolbarActionsCapsule.reserveWidth(of: declared)
        let inset = host.bounds.width - reserve
        let plusEnd = host.bounds.width - inset
        let plus = (plusEnd - HelmToolbarActionsCapsule.side)...plusEnd
        guard let mode = declared.first(where: { $0.id == "mode" }) else { return (plus, nil) }
        let modeEnd = plus.lowerBound
        return (plus, (modeEnd - HelmToolbarActionsCapsule.reserveWidth(of: [mode]))...modeEnd)
    }

    private func baseline(_ rig: Rig, _ label: String) throws -> Baseline {
        let host = try XCTUnwrap(rig.capsule, "\(label): no capsule on the bar")
        let tabs = try XCTUnwrap(rig.tabs, "\(label): no centre tabs on the bar")
        let slot = try XCTUnwrap(slots(rig), "\(label): no actions model on the bar")
        let plus = try XCTUnwrap(Self.ink(host, slot: slot.plus), "\(label): the + drew nothing")
        let mode = try XCTUnwrap(slot.mode.flatMap { Self.ink(host, slot: $0) }, "\(label): the switcher drew nothing")
        let tabInk = try XCTUnwrap(Self.ink(tabs), "\(label): the centre tabs drew nothing")
        let reference = try XCTUnwrap(Self.ink(rig.reference.control), "\(label): the reference control drew nothing")
        let referenceSelected = try XCTUnwrap(Self.ink(rig.reference.selectedControl), "\(label): the reference control with a selection drew nothing")
        // Both sides exist: each of the bar's items and each of AppKit's controls draws above half alpha in S1.
        XCTAssertGreaterThan(referenceSelected, 0.5, "\(label): AppKit's control with a selection is barely drawn in S1 — nothing below reads it")
        XCTAssertGreaterThan(plus, 0.5, "\(label): the + is barely drawn in S1 — nothing below reads it")
        XCTAssertGreaterThan(mode, 0.5, "\(label): the switcher is barely drawn in S1 — nothing below reads it")
        XCTAssertGreaterThan(tabInk, 0.5, "\(label): the tabs are barely drawn in S1 — nothing below reads them")
        XCTAssertGreaterThan(reference, 0.5, "\(label): AppKit's own control is barely drawn in S1 — nothing below reads it")
        return Baseline(plus: plus, mode: mode, tabs: tabInk, reference: reference, referenceSelected: referenceSelected)
    }

    /// AppKit's platter glass in the reference window: the one glass group under the toolbar's
    /// `NSGlassContainerView`, and only when the window draws an `NSToolbarPlatterView` at all.
    /// nil when there is no platter view or the glass under the container is not exactly one
    /// group — an empty toolbar still has the container, so the container alone proves nothing.
    private static func platter(of reference: NSWindow) -> Glass? {
        guard let theme = reference.contentView?.superview,
              let platterClass = NSClassFromString("NSToolbarPlatterView") else { return nil }
        let all = theme.everyView(ofType: NSView.self)
        guard all.contains(where: { $0.isKind(of: platterClass) }),
              let container = all.first(where: { NSStringFromClass(type(of: $0)) == "NSGlassContainerView" }),
              let layer = container.layer else { return nil }
        return glass(under: layer)
    }

    /// The capsule and the bar's plates against AppKit's platter, in whatever state the two
    /// windows are in now. `lit` is what AppKit's platter must itself read — the proof that
    /// the state was produced at all, before any equality is believed.
    private func assertCapsuleMatchesAppKit(_ rig: Rig, lit: Bool, baseline: Baseline?, _ label: String,
                                            file: StaticString = #filePath, line: UInt = #line) {
        rig.settle()
        guard let host = rig.capsule, let hostLayer = host.layer else {
            return XCTFail("\(label): no capsule on the bar", file: file, line: line)
        }
        guard let platter = Self.platter(of: rig.reference.window) else {
            return XCTFail("\(label): \(Self.referenceHasNoPlatter)", file: file, line: line)
        }
        guard let capsule = Self.glass(under: hostLayer) else {
            return XCTFail("\(label): the capsule's glass did not read as one group", file: file, line: line)
        }
        XCTAssertEqual(rig.flag("_hasActiveAppearance"), rig.flag("_hasActiveAppearance", of: rig.reference.window), """
            \(label): the two windows disagree on whether they draw active — one state was not driven
            """, file: file, line: line)
        XCTAssertEqual(platter.isLit, lit, """
            \(label): AppKit's own platter reads \(platter) — the state this step drives was not produced \
            (flags: active \(String(describing: rig.flag("_hasActiveAppearance", of: rig.reference.window))), \
            key \(String(describing: rig.flag("_hasKeyAppearance", of: rig.reference.window))))
            """, file: file, line: line)
        XCTAssertTrue(capsule.matches(platter), """
            \(label): the capsule's glass reads \(capsule), AppKit's platter \(platter)
            """, file: file, line: line)

        // The bar's plates: AppKit's glass exactly when AppKit's platter is lit, none when it is flat.
        var plates: [(String, ShellBarPlate)] = []
        if let plate = rig.tabs as? ShellBarPlate { plates.append(("tabs", plate)) }
        else { XCTFail("\(label): the tabs zone is not a plate", file: file, line: line) }
        if let plate = rig.search as? ShellBarPlate, !plate.isHidden { plates.append(("search", plate)) }
        for (zone, plate) in plates {
            let glasses = plate.subviews.compactMap { $0 as? NSGlassEffectView }
            if platter.isLit {
                guard glasses.count == 1, let layer = glasses[0].layer, let drawn = Self.glass(under: layer) else {
                    XCTFail("\(label): the \(zone) plate holds \(glasses.count) glass views and not one that reads as a group, AppKit's platter is lit", file: file, line: line)
                    continue
                }
                XCTAssertTrue(drawn.matches(platter), """
                    \(label): the \(zone) plate's glass reads \(drawn), AppKit's platter \(platter)
                    """, file: file, line: line)
            } else {
                XCTAssertEqual(glasses.count, 0, """
                    \(label): the \(zone) plate holds glass while AppKit's platter is flat (\(platter))
                    """, file: file, line: line)
            }
        }

        guard let baseline else { return }
        guard let tabs = rig.tabs, let tabInk = Self.ink(tabs) else {
            return XCTFail("\(label): no ink read off the tabs plate", file: file, line: line)
        }
        guard let referenceInk = Self.ink(rig.reference.control) else {
            return XCTFail("\(label): no ink read off the reference control", file: file, line: line)
        }
        guard let slot = slots(rig) else {
            return XCTFail("\(label): no actions model on the bar", file: file, line: line)
        }
        // While a sheet hangs from the reference window AppKit draws its toolbar items disabled,
        // whatever the window's activity is; the bar's controls are not toolbar items and do not
        // follow, which `testASheetOnAnActiveWindowDimsThePlusAndTheTabsAsAppKitsDisabledToolbarItems` holds
        // on its own. The glass above is compared in every state; the ink only where the
        // reference item is enabled.
        if rig.reference.window.attachedSheet != nil { return }
        let referenceShare = referenceInk / baseline.reference
        XCTAssertEqual(tabInk / baseline.tabs, referenceShare, accuracy: 0.1, """
            \(label): the tabs plate draws at \(tabInk / baseline.tabs) of its S1 ink, AppKit's control at \(referenceShare) of its own
            """, file: file, line: line)
        if let plus = Self.ink(host, slot: slot.plus) {
            XCTAssertEqual(plus / baseline.plus, referenceShare, accuracy: 0.1, """
                \(label): the + draws at \(plus / baseline.plus) of its S1 ink, AppKit's control at \(referenceShare) of its own
                """, file: file, line: line)
        } else {
            XCTFail("\(label): no ink read off the +", file: file, line: line)
        }
    }

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
            let fresh = rig.capsule.flatMap { host in self.slots(rig).flatMap { Self.ink(host, slot: $0.plus) } }
            let freshTabs = rig.tabs.flatMap { Self.ink($0) }
            let freshReference = Self.ink(rig.reference.control)

            rig.toS1()
            rig.settle()
            let base = try baseline(rig, "\(name) S1 after S5")
            assertCapsuleMatchesAppKit(rig, lit: true, baseline: base, "\(name) S1 after S5")
            if let fresh, let freshTabs, let freshReference {
                let share = freshReference / base.reference
                XCTAssertEqual(fresh / base.plus, share, accuracy: 0.1, """
                    \(name) S5: the + drew at \(fresh / base.plus) of its S1 ink, AppKit's control at \
                    \(share) of its own (\(freshReference) of \(base.reference))
                    """)
                XCTAssertEqual(freshTabs / base.tabs, share, accuracy: 0.1, """
                    \(name) S5: the tabs plate drew at \(freshTabs / base.tabs) of its S1 ink, AppKit's control at \
                    \(share) of its own
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
    /// app's windows takes key (Helm's status panel); under a sheet (the `+`
    /// "New key" sheet) it keeps the glass lit and disables its toolbar items,
    /// which the bar's controls do not follow — so the S4 step here compares the
    /// glass alone, and `testASheetOnAnActiveWindowDimsThePlusAndTheTabsAsAppKitsDisabledToolbarItems`
    /// holds the ink. The dimming a sheet adds as a window-level view over every
    /// item alike is outside what either reading here sees.
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
    /// the app is away, a sheet that begins while it is away. AppKit's platter
    /// must read flat in all three (`_hasActiveAppearance` false, the window
    /// neither key nor main), and lit again on the return. The last
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

    // MARK: - Where the bar differs from AppKit's toolbar, and is left red

    /// **Left red on purpose.** A sheet on a window the app is active in (the window main, key
    /// gone to the sheet): AppKit's platter stays lit, as the rows above hold, and AppKit draws
    /// its toolbar items disabled, at the share of their ink an inactive window gives them.
    /// The bar's controls are not toolbar items, nothing in `Sources/HelmApp` or the bar reads a
    /// sheet, and the `+` and the tabs stay at full ink. Whether the bar should follow is the owner's; this
    /// row states what differs and goes green when the bar's controls draw as the reference's.
    func testASheetOnAnActiveWindowDimsThePlusAndTheTabsAsAppKitsDisabledToolbarItems() throws {
        for appearance in Self.appearances {
            let name = Self.named(appearance)
            let rig = try rig(appearance)
            rig.show(page: "probe.sheetdisables")
            rig.window.orderFront(nil)
            rig.toS1()
            rig.settle()
            let base = try baseline(rig, "\(name) S1")

            rig.beginSheet()
            rig.settle()
            XCTAssertNotNil(rig.window.attachedSheet, "\(name): no sheet attached")
            XCTAssertEqual(rig.flag("_hasActiveAppearance"), true, "\(name): the window is not active under the sheet")
            XCTAssertEqual(Self.platter(of: rig.reference.window)?.isLit, true, "\(name): AppKit's platter is not lit under the sheet")
            // The subject of the comparison happened: AppKit disabled its item and drew it dim.
            XCTAssertFalse(rig.reference.control.isEnabled, "\(name): AppKit left its toolbar item enabled under the sheet")
            let referenceInk = try XCTUnwrap(Self.ink(rig.reference.control), "\(name): no ink read off the reference control")
            let referenceShare = referenceInk / base.reference
            XCTAssertLessThan(referenceShare, 0.5, "\(name): AppKit's disabled item still draws at \(referenceShare) of its ink")

            let host = try XCTUnwrap(rig.capsule, "\(name): no capsule on the bar")
            let slot = try XCTUnwrap(slots(rig), "\(name): no actions model on the bar")
            let plus = try XCTUnwrap(Self.ink(host, slot: slot.plus), "\(name): no ink read off the +")
            let tabs = try XCTUnwrap(rig.tabs.flatMap { Self.ink($0) }, "\(name): no ink read off the tabs plate")
            XCTAssertEqual(plus / base.plus, referenceShare, accuracy: 0.1, """
                \(name) S4: the + draws at \(plus / base.plus) of its S1 ink under the sheet, AppKit's disabled item at \(referenceShare) of its own
                """)
            XCTAssertEqual(tabs / base.tabs, referenceShare, accuracy: 0.1, """
                \(name) S4: the tabs plate draws at \(tabs / base.tabs) of its S1 ink under the sheet, AppKit's disabled item at \(referenceShare) of its own
                """)
        }
    }

    /// **Left red on purpose.** Under Liquid Glass the view-mode switcher does not follow an
    /// inactive window as the `+` beside it does: the `+` reads the reference's share, the
    /// switcher keeps its S1 ink (the row's message prints both shares). Against AppKit's own
    /// control with the first segment selected, as the switcher has it. The switcher's cell,
    /// `HelmFlatSegmentedCell`, inks from fixed label colours and reads no window state;
    /// `Sources/HelmUI/DesignSystem/HelmToolbarActions.swift` dims by `inactiveGlyphOpacity` in
    /// `glyph(_:symbol:)`, which `entryControl(_:)` draws, and in the Flat branch of
    /// `backing(_:for:)`; a `.segmented` entry is `entryContent(_:)`'s other branch.
    func testTheCapsulesSwitcherDimsInAnInactiveWindowAsAppKitsOwnControlDoes() throws {
        for appearance in Self.appearances {
            let name = Self.named(appearance)
            let rig = try rig(appearance)
            rig.show(page: "probe.switcherdims")
            rig.window.orderFront(nil)
            rig.toS1()
            rig.settle()
            let base = try baseline(rig, "\(name) S1")

            rig.toS3()
            rig.settle()
            XCTAssertEqual(Self.platter(of: rig.reference.window)?.isLit, false, "\(name): AppKit's platter is not flat in S3")
            let host = try XCTUnwrap(rig.capsule, "\(name): no capsule on the bar")
            let slot = try XCTUnwrap(slots(rig), "\(name): no actions model on the bar")
            let modeSlot = try XCTUnwrap(slot.mode, "\(name): the capsule has no switcher")
            let referenceInk = try XCTUnwrap(Self.ink(rig.reference.selectedControl), "\(name): no ink read off the reference control")
            let referenceShare = referenceInk / base.referenceSelected
            // The subject of the comparison happened: AppKit's control dimmed, and the + beside the switcher with it.
            XCTAssertLessThan(referenceShare, 0.5, "\(name) S3: AppKit's control still draws at \(referenceShare) of its ink")
            let plus = try XCTUnwrap(Self.ink(host, slot: slot.plus), "\(name): no ink read off the +")
            XCTAssertEqual(plus / base.plus, Self.ink(rig.reference.control).map { $0 / base.reference } ?? -1, accuracy: 0.1,
                           "\(name) S3: the + beside the switcher does not dim as AppKit's control does")
            let mode = try XCTUnwrap(Self.ink(host, slot: modeSlot), "\(name): no ink read off the switcher")
            XCTAssertEqual(mode / base.mode, referenceShare, accuracy: 0.1, """
                \(name) S3: the view-mode switcher draws at \(mode / base.mode) of its S1 ink, \
                AppKit's control with a selected segment at \(referenceShare) of its own
                """)
        }
    }

    // MARK: - A bar built, or revisited, after the change

    /// The bar remembers the content of each page and shows one at a time: a page first built
    /// while the window is flat, and a page revisited after a change that landed while it was
    /// not shown, must each come back on the window's current look.
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

    // MARK: - The name zone against the title AppKit draws in a window with a toolbar

    /// The title the reference window shows. The subject keeps AppKit's own title
    /// hidden (`SettingsWindow.applyTitle`) and has no toolbar, and the title of a
    /// window without a toolbar is another field with other numbers, so it is no
    /// counterpart for the zone: the title AppKit draws in a window with a toolbar
    /// is, and that is the reference window's.
    private static let appKitTitleText = "Probe Title"

    /// Where the zone's name starts: `NameZoneView`'s leading padding, its
    /// 24 pt plate and the spacing after it. Read against the title in S1 before
    /// anything is believed — a slot that caught the plate would read the
    /// plate's full ink there, not the name's, and the S1 check below fails.
    private static let zoneNameStart = HelmSpace.s5 + 24 + HelmSpace.s5

    /// AppKit's own title field in the reference window, the one a window with a
    /// toolbar draws — exactly one visible field carrying the window's title, or nil.
    private func appKitTitle(_ rig: Rig) -> NSTextField? {
        let window = rig.reference.window
        guard let theme = window.contentView?.superview else { return nil }
        let fields = theme.everyView(ofType: NSTextField.self).filter {
            $0.stringValue == Self.appKitTitleText && !$0.isHiddenOrHasHiddenAncestor && $0.window === window
        }
        return fields.count == 1 ? fields[0] : nil
    }

    /// **The highest alpha `view` draws through its own `draw(_:)`, once**, at
    /// the window's scale. AppKit's title field is read this way and not through
    /// `ink(_:slot:)`. Under the transparent title bar `draw(_:)` reads 0.847 in
    /// S1, the same single composite `ink(_:slot:)` reads off the zone's own
    /// name, and `nameBaseline` holds the two equal there before any share is
    /// taken.
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
            XCTFail("\(label): AppKit's own title is not drawn in the reference window — nothing to compare the zone with",
                    file: file, line: line)
            return nil
        }
        guard let zone = rig.nameZone else {
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
    /// at no tolerance on this Mac (27.2), in every state both
    /// name-zone cases visit: the zone and AppKit's title part by at most
    /// 0.0057 (27's title bar, Dark, the zone whole: 0.3020 against 0.2963),
    /// about one step of an 8-bit alpha in the ratio. The Dark constant of
    /// the wrong title bar sits 0.016 (0.28 under 27's) and 0.021 (0.30 under
    /// 26's opaque one) from AppKit's reading, inside 0.03
    /// — so at 0.03 the Dark half of `NameZoneView.inactiveOpacity`
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

    /// The window with the zone, and beside it the reference window with AppKit's own
    /// title, both opened while the app is away (S5) and never keyed yet. The
    /// subject's own title stays hidden, as the app has it.
    private func nameRig(_ appearance: NSAppearance.Name, page: String, band: HelmBandChoice) throws -> Rig {
        let rig = try rig(appearance, band: band)
        rig.show(page: page, segmented: false)
        rig.window.orderFront(nil)
        rig.settle()
        return rig
    }

    /// The S1 reading every share is taken against, and, when `sameInk`, the check
    /// that both sides are one composite of the same ink there: AppKit's title and
    /// the zone's name read equal (0.847 on both sides, Light and Dark).
    /// Only the transparent title bar asks it: under the opaque one the reference
    /// title is another colour in S1 (see `testTheNameZoneDrawsAppKitsTitleInkUnderTheOpaqueTitleBar`),
    /// and the shares, which are all the zone's constants claim, stand without it.
    private func nameBaseline(_ rig: Rig, _ label: String, sameInk: Bool = true) throws -> NameReading {
        let base = try XCTUnwrap(nameReading(rig, label), "\(label): no S1 reading")
        XCTAssertGreaterThan(base.title, 0.5, "\(label): AppKit's title is barely drawn in S1 — nothing below reads it")
        if sameInk {
            XCTAssertEqual(base.zoneName, base.title, accuracy: 0.03, """
                \(label): the zone's name reads \(base.zoneName) in S1 and AppKit's title \(base.title) — \
                not one composite of the same ink, so no share below compares like with like
                """)
        }
        return base
    }

    /// **The owner's answer — «Да, как у AppKit» — held against AppKit's own
    /// title, drawn in the reference window under the same title bar and in the
    /// same state, read the same way, in every state.**
    /// S5 (opened while the app is away, never keyed), S1, S3, the return to
    /// S1, S2b (a panel takes key, the window stays main), a sheet (S4), and a
    /// run of returns: the zone's name, and the zone as a whole, draw the same
    /// share of their S1 ink as AppKit's title does. Measured under macOS 27's transparent title bar:
    /// title 0.278 / 0.847 Light, 0.251 / 0.847 Dark in S3 and S5; the zone's
    /// name 0.278 / 0.255, its row 0.329 / 0.302 of 1.000 — and 1.000 wherever
    /// AppKit's title stays at full ink. Read under each system's title bar
    /// (`systems`): under macOS 26's opaque one, as AppKit 27.2 draws it, the
    /// title keeps 0.399 Light and 0.279 Dark of its S1 ink where it keeps
    /// 0.329 and 0.296 under 27's transparent one.
    func testTheNameZoneDimsWhereAndAsFarAsAppKitsOwnTitle() throws {
        for (system, appearance) in Self.systemsByAppearance {
            let name = "\(system.name), \(Self.named(appearance))"
            let rig = try nameRig(appearance, page: "probe.nameZone", band: system.band)
            XCTAssertEqual(rig.flag("_hasActiveAppearance"), false, "\(name): this process's window is not in S5")
            let fresh = nameReading(rig, "\(name) S5")

            rig.toS1()
            rig.settle()
            let base = try nameBaseline(rig, "\(name) S1 after S5", sameInk: system.band.titlebarAppearsTransparent)
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
            let base = try nameBaseline(rig, "\(name) S1", sameInk: system.band.titlebarAppearsTransparent)

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

    /// **Left red on purpose: under the opaque title bar the zone's name does not
    /// read the ink of the title AppKit draws in a window with a toolbar.** In S1 the
    /// reference title keeps 0.698 Light and 0.898 Dark of full alpha where the
    /// zone's name draws 0.847 in both, off the 0.03 the transparent title bar holds
    /// (0.847 on both sides there). The shares the zone's constants are measured
    /// from (`NameZoneView.inactiveOpacityOpaqueLight` and `…Dark`) are held by the
    /// two rows above under this title bar too; what differs here is the S1 ink
    /// itself, which those constants do not claim, so whether the zone should match it
    /// is the owner's to say.
    func testTheNameZoneDrawsAppKitsTitleInkUnderTheOpaqueTitleBar() throws {
        for (system, appearance) in Self.systemsByAppearance where !system.band.titlebarAppearsTransparent {
            let name = "\(system.name), \(Self.named(appearance))"
            let rig = try nameRig(appearance, page: "probe.nameZoneInk", band: system.band)
            rig.toS1()
            rig.settle()
            let base = try nameBaseline(rig, "\(name) S1", sameInk: false)
            XCTAssertEqual(base.zoneName, base.title, accuracy: 0.03, """
                \(name) S1: the zone's name reads \(base.zoneName) and AppKit's title \(base.title) \
                under the opaque title bar
                """)
        }
    }

    // MARK: - Whatever lands between a bar's build and its first state

    /// The `+`, the switcher and the tabs, read now and judged later against a
    /// baseline taken on the same content in S1.
    private struct Inks { let plus: CGFloat; let mode: CGFloat; let tabs: CGFloat }

    private func inks(_ rig: Rig, _ label: String, file: StaticString = #filePath, line: UInt = #line) -> Inks? {
        guard let host = rig.capsule, let tabs = rig.tabs, let slot = slots(rig) else {
            XCTFail("\(label): no capsule, no actions model or no tabs on the bar", file: file, line: line)
            return nil
        }
        guard let plus = Self.ink(host, slot: slot.plus), let modeSlot = slot.mode,
              let mode = Self.ink(host, slot: modeSlot), let tabInk = Self.ink(tabs) else {
            XCTFail("\(label): no ink read", file: file, line: line)
            return nil
        }
        return Inks(plus: plus, mode: mode, tabs: tabInk)
    }

    /// The `+`'s share of its S1 ink equal to the tabs', and the switcher still drawn — a folded
    /// or evicted switcher reads close to nothing. A glyph left on the wrong look reads the other
    /// state's share, which the `+` shows. The switcher's own share is not held to the tabs': it does not dim as the `+` does in an inactive window, which
    /// `testTheCapsulesSwitcherDimsInAnInactiveWindowAsAppKitsOwnControlDoes` holds on its own.
    private func assertShares(_ inks: Inks?, base: Baseline, _ label: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        guard let inks else { return }
        let tabs = inks.tabs / base.tabs
        XCTAssertEqual(inks.plus / base.plus, tabs, accuracy: 0.1,
                       "\(label): the + draws at \(inks.plus / base.plus) of its S1 ink, the tabs at \(tabs)",
                       file: file, line: line)
        XCTAssertGreaterThan(inks.mode / base.mode, 0.5,
                             "\(label): the switcher draws at \(inks.mode / base.mode) of its S1 ink — folded or evicted",
                             file: file, line: line)
    }

    /// **Whatever lands between a page's content reaching the bar and the
    /// window's first key or main change.** Under Liquid Glass
    /// `ShellBarActions.show` builds a new capsule host when the window's
    /// activity changes, so each of these is fed before that first change: the
    /// window becoming key; the page switching away and back; the same page
    /// declaring again with search added; and, while the window is away, a
    /// page-bar style change and a language change, each of which shows every
    /// zone again (`ShellPageBar.heard`). Each must end on AppKit's current
    /// look — glass, glyphs and the tabs unfolded — and the key case on the lit
    /// glyph, which a host built from a reading taken before the change would dim.
    func testWhateverLandsBetweenABarsBuildAndItsFirstStateEndsOnTheWindowsCurrentLook() throws {
        for appearance in Self.appearances {
            let name = Self.named(appearance)

            // The window becomes key right after the page declares.
            do {
                let rig = try rig(appearance)
                rig.show(page: "probe.keyFirst")
                rig.window.orderFront(nil)
                rig.toS1()
                rig.settle()
                let base = try baseline(rig, "\(name) S1, keyed before the first state")
                assertCapsuleMatchesAppKit(rig, lit: true, baseline: base, "\(name) keyed before the first state")
                XCTAssertGreaterThan(base.plus, 0.9, "\(name): the + is dimmed in S1 — the bar kept the look from before key")
                rig.toS3()
                assertCapsuleMatchesAppKit(rig, lit: false, baseline: base, "\(name) S3 after that")
                rig.toS1()
                assertCapsuleMatchesAppKit(rig, lit: true, baseline: base, "\(name) S1 after that")
            }

            // The page switches away before the window was ever key, and comes back while still away.
            do {
                let rig = try rig(appearance)
                rig.show(page: "probe.switchedA")
                rig.window.orderFront(nil)
                rig.show(page: "probe.switchedB")
                assertCapsuleMatchesAppKit(rig, lit: false, baseline: nil, "\(name) the page switched before the first state")
                let onB = inks(rig, "\(name) on B")
                rig.show(page: "probe.switchedA")
                assertCapsuleMatchesAppKit(rig, lit: false, baseline: nil, "\(name) back on the page that was not shown meanwhile")
                let backOnA = inks(rig, "\(name) back on A")
                rig.toS1()
                rig.settle()
                let base = try baseline(rig, "\(name) S1 on A")
                assertCapsuleMatchesAppKit(rig, lit: true, baseline: base, "\(name) S1 on A")
                assertShares(onB, base: base, "\(name) on B while away")
                assertShares(backOnA, base: base, "\(name) back on A while away")
            }

            // The same page declares again, with search added, before the window was ever key.
            do {
                let rig = try rig(appearance)
                rig.show(page: "probe.torn")
                rig.window.orderFront(nil)
                rig.show(page: "probe.torn", segmented: true, search: true)
                assertCapsuleMatchesAppKit(rig, lit: false, baseline: nil, "\(name) the page declared again before the first state")
                let redeclared = inks(rig, "\(name) after the second declaration")
                rig.toS1()
                rig.settle()
                let base = try baseline(rig, "\(name) S1 after the second declaration")
                assertCapsuleMatchesAppKit(rig, lit: true, baseline: base, "\(name) S1 after the second declaration")
                assertShares(redeclared, base: base, "\(name) the redeclared page while away")
            }

            // While away: a page-bar style change, then a language change; each shows every zone again.
            do {
                let rig = try rig(appearance)
                rig.show(page: "probe.style")
                rig.window.orderFront(nil)
                rig.toS1()
                rig.settle()
                let base = try baseline(rig, "\(name) S1 before the style change")
                rig.toS3()
                rig.settle()
                AppSettings.pageBarStyle = .windowTitle
                assertCapsuleMatchesAppKit(rig, lit: false, baseline: base, "\(name) a page-bar style change while away")
                NotificationCenter.default.post(name: .helmLanguageChanged, object: nil)
                assertCapsuleMatchesAppKit(rig, lit: false, baseline: base, "\(name) a language change while away")
                AppSettings.pageBarStyle = .moduleName
                assertCapsuleMatchesAppKit(rig, lit: false, baseline: base, "\(name) the style change undone while away")
                rig.toS1()
                assertCapsuleMatchesAppKit(rig, lit: true, baseline: base, "\(name) S1 after the style changes")
            }
        }
    }

    // MARK: - The Flat look in the real window

    /// **Flat has no AppKit counterpart for its drawing, and this row invents none.** AppKit's
    /// platter is glass in the reference window; the Flat bar draws a fill where Liquid Glass
    /// draws glass, so no fill, colour or amount of dimming here is compared with the reference.
    /// What the row holds is the wiring in the real Settings window, in every state the other
    /// rows visit: with the look pinned to Flat there is no glass anywhere under the bar's view,
    /// and each plate is dimmed exactly when the reference platter is flat (`alphaValue` 1 when it
    /// is lit, below 1 when it is not) — AppKit decides when, not how much; the amount is held
    /// by `ThePlateDrawsByAppearanceAndActivityTests`. A plate that follows the window's
    /// activity wrongly (`SettingsWindow.updateWindowAppearsActive`) reads the wrong side here.
    func testAFlatBarDrawsNoGlassAndDimsItsPlatesExactlyWhenAppKitsPlatterIsFlat() throws {
        for appearance in Self.appearances {
            let name = Self.named(appearance)
            let rig = try rig(appearance, look: .flat)
            XCTAssertEqual(AppSettings.barAppearance, .flat, "\(name): the look this row pins is not Flat")
            rig.show(page: "probe.flat", segmented: true, search: true)
            rig.window.orderFront(nil)
            rig.settle()

            func check(_ label: String, lit: Bool) {
                rig.settle()
                let label = "\(name) \(label)"
                guard let platter = Self.platter(of: rig.reference.window) else {
                    return XCTFail("\(label): \(Self.referenceHasNoPlatter)")
                }
                XCTAssertEqual(platter.isLit, lit, "\(label): AppKit's own platter reads \(platter) — the state this step drives was not produced")
                XCTAssertEqual(rig.flag("_hasActiveAppearance"), rig.flag("_hasActiveAppearance", of: rig.reference.window),
                               "\(label): the two windows disagree on whether they draw active — one state was not driven")

                // The bar and its plates exist and hold a fill, so the absence of glass below is not the absence of the bar.
                var plates: [(String, ShellBarPlate)] = []
                if let plate = rig.tabs as? ShellBarPlate { plates.append(("tabs", plate)) }
                else { XCTFail("\(label): the tabs zone is not a plate") }
                if let plate = rig.search as? ShellBarPlate, !plate.isHidden { plates.append(("search", plate)) }
                else { XCTFail("\(label): the search zone is not a shown plate") }
                for (zone, plate) in plates {
                    XCTAssertNotNil(plate.layer?.backgroundColor, "\(label): the \(zone) plate holds no fill")
                    if lit {
                        XCTAssertEqual(plate.alphaValue, 1, accuracy: 0.0001, "\(label): the \(zone) plate is dimmed while AppKit's platter is lit")
                    } else {
                        XCTAssertLessThan(plate.alphaValue, 1, "\(label): the \(zone) plate is not dimmed while AppKit's platter is flat")
                    }
                }

                // No glass anywhere under the bar: in the layers, and in the views that carry glass.
                guard let layer = rig.bar.view.layer else { return XCTFail("\(label): the bar's view has no layer") }
                let counts = Self.walkGlass(under: layer)
                XCTAssertGreaterThan(counts.walked, 10, "\(label): only \(counts.walked) layers under the bar — the walk did not reach the bar")
                XCTAssertEqual(counts.highlightLayers, 0, "\(label): \(counts.highlightLayers) glass highlight layers under the Flat bar")
                XCTAssertEqual(counts.outputLayers, 0, "\(label): \(counts.outputLayers) glass output layers under the Flat bar")
                XCTAssertEqual(counts.backdropLayers, 0, "\(label): \(counts.backdropLayers) glass backdrop layers under the Flat bar")
                let glassViews = rig.bar.view.everyView(ofType: NSView.self).filter { $0 is NSGlassEffectView || NSStringFromClass(type(of: $0)) == "NSGlassContainerView" }
                XCTAssertEqual(glassViews.count, 0, "\(label): \(glassViews.count) glass views under the Flat bar")
            }

            check("S5", lit: false)
            rig.toS1(); check("S1", lit: true)
            rig.toS2b(); check("S2b", lit: true)
            rig.setKey(true); check("S1 after S2b", lit: true)
            rig.beginSheet(); check("S4", lit: true)
            rig.setMain(false); check("S3 with the sheet up", lit: false)
            rig.setMain(true); check("back with the sheet still up", lit: true)
            rig.endSheet(); check("S1 after the sheet", lit: true)
            rig.toS3(); check("S3", lit: false)
            rig.beginSheet(); check("S3 with a sheet begun while away", lit: false)
            rig.endSheet(); check("S3 after that sheet", lit: false)
            rig.toS1(); check("S1 after the last return", lit: true)
            for _ in 0..<5 { rig.toS3(); rig.toS1() }
            check("S1 after five same-turn round trips", lit: true)
            rig.toS3()
            rig.show(page: "probe.flatBuiltAway", segmented: true, search: true)
            check("a page built away", lit: false)
        }
    }
}
