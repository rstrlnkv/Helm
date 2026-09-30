import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
import HelmUI

/// **Why the system's scroll edge effect draws nothing under this window's
/// toolbar — measured, and the ingredient named: a window flag, not the pane's
/// content.**
///
/// The effect is `NSScrollPocket`: a view AppKit inserts over the top inset of
/// a pane's scroll view, whose drawing is a single layer — delegate
/// `_UIScrollEdgeEffectLayerDelegate` — carrying `ThinFilmContentBlurFill`,
/// `ThinFilmBackgroundReplay` and `Separator` when the effect is on. So «did it
/// draw» is answered by walking the tree for that pocket and reading its effect
/// layer, which is cheaper and stronger than a photograph — and it has to be,
/// because an offscreen render never composites a system material and would
/// report nothing drawn either way.
///
/// **Three states, and they do not look alike.** No pocket at all (the walk
/// found no such view, and the message says how many views it walked); a pocket
/// whose effect layer is at opacity 0 with no sublayers (attached and
/// withheld); a pocket whose effect layer is at opacity 1 with its three parts
/// (drawing).
///
/// # What was isolated
///
/// A probe built the same `Form` five ways and read the pocket three times per
/// arm, at rest and after 300 pt of scroll — the two readings were identical
/// every time:
///
/// - plain SwiftUI `WindowGroup`: **drawing**, 1060 × 52;
/// - `NSHostingController` with `sceneBridgingOptions = [.toolbars]`, no split:
///   withheld;
/// - `NSSplitViewController` with an AppKit toolbar and **no** bridge: withheld;
/// - Helm's construction, split *and* bridge: withheld — and in the same window
///   the sidebar's own pocket was drawing, so the window, the toolbar and the
///   split were all working;
/// - the same construction with `titlebarAppearsTransparent` off: **drawing**,
///   846 × 52, exactly the detail pane's width.
///
/// **The content type is not an ingredient.** The arms above are a `Form`
/// because the settings pages are; a tester read the same three states for a
/// `List` and for a bare `ScrollView` in this construction. An earlier note in
/// `helmToolbarBackdrop` blamed `Form`, and that sentence was wrong.
///
/// So neither the split nor the bridge withholds it. The factorial over the
/// three window flags settles which one does: with `.fullSizeContentView` and
/// an opaque title bar the effect attaches to the pane whatever
/// `titleVisibility` says, and `titlebarAppearsTransparent = true` zeroes it.
/// `SettingsWindow` sets that flag from the band decision —
/// `window.titlebarAppearsTransparent = band.titlebarAppearsTransparent` — on
/// the window it builds for the settings split: on for macOS 27, off for 26
/// (below).
///
/// `scrollEdgeEffectStyle(.hard)` is not a way round it and the probe says why
/// it «changed no pixel»: the modifier is honoured — the pocket gains
/// `HardPocketContentBlur`, `HardPocketBackgroundReplay` and `Separator` — and
/// the transparent title bar holds that same layer at opacity 0.
///
/// # What this refutes
///
/// **The two photographed defects are not one cause, and the hypothesis that
/// they were is wrong.** They are: the 2026-09-16 collision, where dropping the
/// pane's safe area ran the Homebrew list's heading through the segment
/// switcher, and the 2026-09-17 photograph, where Keep Awake's hero figure ran
/// through the window title with nothing between them. Releasing the pane's
/// safe area reproduces the 2026-09-16 collision **with the effect enabled**,
/// so the safe area is load-bearing independently of this flag and no change to
/// the flag can stand in for it — read in the same flag-off investigation these
/// arms come from; no case in this file re-takes it, and the tree keeps the
/// safe area either way. It is written down because the hypothesis was raised
/// out loud, and a belief nobody records as refuted is re-derived by the next
/// reader.
///
/// **And the effect, let through, has almost nothing to act on here**: with the
/// flag off and the safe area kept it contributed +7.7/255 in Dark and 0/255 in
/// Light — the same reading, and nothing here re-takes that either. The pane
/// keeps AppKit's safe area, so at rest no content is under the bar; scrolled,
/// content does pass beneath it, and that is what lights Helm's own strip
/// (`helmToolbarBackdrop`'s own header has the reading). An effect with nothing
/// to act on at rest is the reason Helm's own strip exists, and it is not that
/// the platform gives us nothing.
///
/// This file is the measurement, kept so the next reader does not re-derive it
/// and so a macOS that changes its mind fails here rather than in somebody's
/// screenshot. It builds its own windows deliberately: the subject is the
/// construction, and a check that could only speak through `SettingsWindow`
/// would go quiet the moment that file changed — the one case that does build
/// `SettingsWindow` is there to hold its two halves together, not to measure.
///
/// # Two systems, one decision
///
/// Which band the settings window wears is `HelmBandChoice`'s, per system:
/// macOS 27 keeps the transparent title bar and Helm's own band, macOS 26 an
/// opaque title bar and the system's own effect (the owner, 2026-09-27). The
/// windows below are built from `HelmBandChoice.onMacOS(_:)` for each of the
/// two, so both paths are read on this Mac — which runs 27.2. **What the 26
/// path reads here is 27's AppKit answering for 26's flag**: the inference the
/// decision rests on, not a reading of macOS 26, which the owner checks in a
/// virtual machine.
@MainActor
final class TheSystemsScrollEdgeEffectAttachesTests: XCTestCase {

    /// The decision each system's settings window is built from.
    private static let macOS26 = HelmBandChoice.onMacOS(26)
    private static let macOS27 = HelmBandChoice.onMacOS(27)

    // MARK: - The two windows, alike but for one flag

    /// The settings window's construction: split view, sidebar item, a detail
    /// pane hosting a grouped `Form` whose toolbar is bridged into the window,
    /// `.fullSizeContentView`, hidden title — the window `SettingsWindow` builds
    /// in its initialiser. The probe sets `detail.sceneBridgingOptions =
    /// [.toolbars]` itself; `SettingsWindow` sets none any more — its toolbar
    /// is the app-owned `NSToolbar` `SettingsToolbar` builds — so the bridge
    /// here is the probe's own shape and not a copy of what ships. Never
    /// ordered on screen: the probe read the same three states for a window
    /// that was shown and one that was not.
    private func settingsShapedWindow(transparentTitleBar: Bool) -> NSWindow {
        settingsShapedWindow(transparentTitleBar: transparentTitleBar,
                             appearance: nil) { ScrollEdgeProbeForm() }
    }

    /// The same window with its title bar set from one system's decision —
    /// the flag `SettingsWindow` sets from the same value.
    private func settingsShapedWindow(on band: HelmBandChoice) -> NSWindow {
        settingsShapedWindow(transparentTitleBar: band.titlebarAppearsTransparent)
    }

    /// The same window, with the pane's root view and the appearance named by
    /// the caller.
    ///
    /// The two probes below need a different detail root — one of them carries
    /// `toolbarBackgroundVisibility` — and a *named* appearance: this Mac
    /// switches by the sun, so a window that inherits the application's
    /// appearance is read at whatever hour the suite ran. `nil` keeps exactly
    /// the inheritance the cases above were measured under.
    private func settingsShapedWindow<Detail: View>(
        transparentTitleBar: Bool,
        appearance: NSAppearance.Name?,
        @ViewBuilder detail root: () -> Detail
    ) -> NSWindow {
        _ = NSApplication.shared
        let split = NSSplitViewController()

        let sidebar = NSHostingController(rootView: ScrollEdgeProbeSidebar())
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.allowsFullHeightLayout = true
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = 214
        sidebarItem.maximumThickness = 320

        let detail = NSHostingController(rootView: root())
        detail.sceneBridgingOptions = [.toolbars]
        detail.sizingOptions = []
        let detailItem = NSSplitViewItem(viewController: detail)
        detailItem.minimumThickness = 420

        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(detailItem)

        let window = NSWindow(contentViewController: split)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        if let appearance { window.appearance = NSAppearance(named: appearance) }
        window.titlebarAppearsTransparent = transparentTitleBar
        window.titleVisibility = .hidden
        window.setContentSize(NSSize(width: 1060, height: 700))
        window.isReleasedWhenClosed = false
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        return window
    }

    // MARK: - Reading the pocket

    /// One window's answer, kept as the three parts a reader has to tell apart.
    private struct PocketReading {
        /// Views walked, so «found nothing» and «could not reach the tree» read
        /// differently in a failure message.
        let viewsWalked: Int
        /// The pocket over the `Form`'s own scroll view, if AppKit made one.
        let pocketFrame: NSRect?
        /// `nil` when there is a pocket but no effect layer under it.
        let effectOpacity: Float?
        /// The named layers the effect is built from, empty when it is withheld.
        let effectParts: [String]

        var drawing: Bool { effectOpacity == 1 && !effectParts.isEmpty }

        var sentence: String {
            guard let pocketFrame else {
                return "walked \(viewsWalked) views and found no NSScrollPocket over the form"
            }
            guard let effectOpacity else {
                return "pocket \(pocketFrame) has no scroll-edge effect layer under it"
            }
            return "pocket \(pocketFrame) effect opacity \(effectOpacity) parts \(effectParts)"
        }
    }

    private func readPocket(in window: NSWindow) -> PocketReading {
        readPocket(under: window.contentView)
    }

    /// The same reading, under one view — the real settings window's detail
    /// pane, so its sidebar's own pocket is never the one read.
    private func readPocket(under content: NSView?) -> PocketReading {
        guard let content else {
            return PocketReading(viewsWalked: 0, pocketFrame: nil, effectOpacity: nil,
                                 effectParts: [])
        }
        let tree = content.everyViewWithAncestry
        let overTheForm = tree.first { entry in
            entry.view.appKitClassName.hasSuffix("NSScrollPocket")
                && entry.ancestry.contains { $0.appKitClassName.contains("HostingScrollView") }
        }
        guard let pocket = overTheForm?.view else {
            return PocketReading(viewsWalked: tree.count, pocketFrame: nil, effectOpacity: nil,
                                 effectParts: [])
        }
        let effect = (pocket.layer?.sublayers ?? []).first { layer in
            guard let delegate = layer.delegate else { return false }
            return "\(type(of: delegate))".contains("ScrollEdgeEffectLayerDelegate")
        }
        return PocketReading(
            viewsWalked: tree.count,
            pocketFrame: pocket.convert(pocket.bounds, to: nil),
            effectOpacity: effect?.opacity,
            effectParts: (effect?.sublayers ?? []).map { $0.name ?? "\(type(of: $0))" })
    }

    /// Turns the run loop for both windows until the one that is expected to
    /// light has lit, so the withheld one is never judged on less time than the
    /// drawing one had — the rule about asserting the subject happened before
    /// asserting an absence, applied to two windows in one process.
    private func turnTheRunLoop(until lit: () -> Bool, forAtMost seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if lit() { return true }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        return lit()
    }

    // MARK: - The reading is possible at all

    /// Before either verdict: the tree was reachable, the toolbar took its
    /// inset, and AppKit made a pocket over the form in **both** windows.
    ///
    /// Without this, a macOS that stopped making pockets altogether would sail
    /// through the «withheld» assertion below, which is an absence.
    func testBothWindowsPutAPocketOverTheForm() {
        let opaque = settingsShapedWindow(on: Self.macOS26)
        let transparent = settingsShapedWindow(on: Self.macOS27)
        _ = turnTheRunLoop(until: { self.readPocket(in: opaque).pocketFrame != nil
                                    && self.readPocket(in: transparent).pocketFrame != nil },
                           forAtMost: 10)

        for (name, window) in [("macOS 26's", opaque), ("macOS 27's", transparent)] {
            let reading = readPocket(in: window)
            XCTAssertGreaterThan(reading.viewsWalked, 50,
                                 "\(name): could not reach the view tree — \(reading.sentence)")
            XCTAssertNotNil(reading.pocketFrame,
                            "\(name): \(reading.sentence)")
            let inset = window.contentView?.safeAreaInsets.top ?? 0
            XCTAssertEqual(inset, 52, accuracy: 0.5,
                           "\(name): the toolbar took \(inset) pt of inset from the pane, not 52")
        }
        XCTAssertEqual(readPocket(in: opaque).pocketFrame, readPocket(in: transparent).pocketFrame,
                       """
                       the two windows differ in more than the title-bar flag: their pockets are \
                       not even the same rectangle, so nothing below compares like with like
                       """)
        opaque.close()
        transparent.close()
    }

    // MARK: - The verdict, per system

    /// **macOS 27: the effect can attach to this `Form` in this construction,
    /// and the transparent title bar 27's decision sets is the one thing
    /// withholding it.**
    ///
    /// The control is an opaque window built by hand rather than 26's, so this
    /// case speaks for 27's decision alone. Both windows are built and turned
    /// together; the assertion on the withheld one is only reached once the
    /// drawing one has actually drawn.
    func testOnMacOS27TheTransparentTitleBarWithholdsTheEffect() {
        let opaque = settingsShapedWindow(transparentTitleBar: false)
        let transparent = settingsShapedWindow(on: Self.macOS27)

        let lit = turnTheRunLoop(until: { self.readPocket(in: opaque).drawing }, forAtMost: 10)
        let opaqueReading = readPocket(in: opaque)
        XCTAssertTrue(lit, """
            the scroll edge effect never drew for a Form in a split view with a bridged \
            toolbar and an opaque title bar: \(opaqueReading.sentence). If this is the only \
            message here that failed, the effect cannot attach in this construction after all \
            and Helm's own strip is the answer
            """)
        XCTAssertEqual(opaqueReading.effectOpacity, 1,
                       "opaque title bar: \(opaqueReading.sentence)")
        XCTAssertFalse(opaqueReading.effectParts.isEmpty, """
            opaque title bar: the effect layer is opaque but empty, so nothing is drawn by it — \
            \(opaqueReading.sentence)
            """)

        XCTAssertTrue(transparent.titlebarAppearsTransparent, """
            macOS 27's decision no longer asks for a transparent title bar, so nothing withholds \
            the system's effect under Helm's own band
            """)
        let transparentReading = readPocket(in: transparent)
        XCTAssertNotNil(transparentReading.pocketFrame, """
            macOS 27: \(transparentReading.sentence) — the pocket is missing rather than \
            withheld, which is a different finding from the one this file records
            """)
        XCTAssertEqual(transparentReading.effectOpacity, 0, """
            macOS 27: the effect is no longer withheld — \(transparentReading.sentence). Helm's \
            own toolbar strip has lost its reason to exist
            """)
        XCTAssertTrue(transparentReading.effectParts.isEmpty, """
            macOS 27: the effect layer has parts to draw — \(transparentReading.sentence)
            """)

        opaque.close()
        transparent.close()
    }

    /// **macOS 26: the title bar 26's decision sets lets the system's own
    /// effect draw over the pane** — the behaviour the owner asked back, and
    /// the whole reason Helm draws no band there. Read on this Mac's 27.2,
    /// so what it proves is the flag and 27's answer to it; that 26 answers
    /// the same is the inference `HelmBandChoice` states.
    func testOnMacOS26TheSystemsOwnEffectDraws() {
        let window = settingsShapedWindow(on: Self.macOS26)
        XCTAssertFalse(window.titlebarAppearsTransparent, """
            macOS 26's decision asks for a transparent title bar, which holds the system's \
            effect at opacity 0 — and Helm draws no band there, so the pane has none at all
            """)
        let lit = turnTheRunLoop(until: { self.readPocket(in: window).drawing }, forAtMost: 10)
        let reading = readPocket(in: window)
        XCTAssertTrue(lit, """
            macOS 26: the system's own scroll edge effect never drew over the pane — \
            \(reading.sentence). Helm draws no band on 26, so this pane is left with none
            """)
        XCTAssertEqual(reading.effectOpacity, 1, "macOS 26: \(reading.sentence)")
        XCTAssertFalse(reading.effectParts.isEmpty, """
            macOS 26: the effect layer is opaque but empty, so nothing is drawn by it — \
            \(reading.sentence)
            """)
        window.close()
    }

    // MARK: - The two halves of the decision stay together

    /// **The real `SettingsWindow`, built for each system on this one: exactly
    /// one band over its pane.** 27 — a transparent title bar, the system's
    /// effect withheld over General's `Form`, and Helm's band lit over the
    /// log, which declares that nothing scrolls under it. 26 — an opaque
    /// title bar, the system's effect drawing over General, and no band of
    /// Helm's over the log. Half of either is a page with two bands or none.
    ///
    /// The window is ordered in behind everything, because a hidden settings
    /// window unmounts its pane (`helmIdlesOffScreen`) and there would be no
    /// page to read; `SettingsWindow` itself is never asked to show, which
    /// would activate the app. Both appearances are named, since this Mac
    /// switches by the sun. The band is read the way
    /// `TheWindowsBandReadsTheDeclarationTests` reads it: the strip's surface
    /// against the last row of the safe area, where the rule is.
    func testEachSystemsSettingsWindowWearsExactlyOneBand() throws {
        // `SettingsWindow` autosaves its frame and its sidebar's divider into
        // the test tool's own defaults domain; what was found there is put
        // back, absent included — left there, both were every run's
        // (2026-09-28).
        let frameKey = "NSWindow Frame HelmSettingsWindow.v4"
        let splitKey = "NSSplitView Subview Frames HelmSettingsSidebar.v1"
        let foundFrame = UserDefaults.standard.string(forKey: frameKey)
        let foundSplit = UserDefaults.standard.stringArray(forKey: splitKey)
        addTeardownBlock {
            UserDefaults.standard.set(foundFrame, forKey: frameKey)
            UserDefaults.standard.set(foundSplit, forKey: splitKey)
        }
        // What each system should wear is written here, not read back off
        // the decision — a decision that gave 26 27's answer would otherwise
        // be checked against itself.
        for (system, band, helms) in [("macOS 26", Self.macOS26, false), ("macOS 27", Self.macOS27, true)] {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let where_ = "\(system), \(appearance.rawValue)"
                let owner = SettingsWindow(host: ModuleHost.shared, band: band)
                let fields = Mirror(reflecting: owner).children
                let window = try XCTUnwrap(fields.first { $0.label == "window" }?.value as? NSWindow,
                                           "SettingsWindow no longer holds `window` — this case reads it by name")
                let model = try XCTUnwrap(fields.first { $0.label == "model" }?.value as? SettingsModel,
                                          "SettingsWindow no longer holds `model` — this case reads it by name")
                window.appearance = NSAppearance(named: appearance)
                window.orderBack(nil)
                defer {
                    window.toolbar = nil
                    window.close()
                }

                XCTAssertEqual(window.titlebarAppearsTransparent, helms, """
                    \(where_): the settings window's title bar is \
                    \(window.titlebarAppearsTransparent ? "transparent" : "opaque")
                    """)

                model.selection = .general
                let pane = try XCTUnwrap((window.contentViewController as? NSSplitViewController)?
                    .splitViewItems.last?.viewController.view, "\(where_): no detail pane")
                _ = turnTheRunLoop(until: { self.readPocket(under: pane).effectOpacity == (helms ? 0 : 1) },
                                   forAtMost: 10)
                let general = readPocket(under: pane)
                XCTAssertNotNil(general.pocketFrame, "\(where_), General: \(general.sentence)")
                let wrong = helms ? "drawing beside Helm's band" : "withheld with no band of Helm's"
                XCTAssertEqual(general.effectOpacity, helms ? 0 : 1, """
                    \(where_), General: the system's effect is \(wrong) — \(general.sentence)
                    """)

                model.selection = .log
                _ = turnTheRunLoop(until: { false }, forAtMost: 1)
                let strip = try luma(pane, row: .strip, where_)
                let edge = try luma(pane, row: .edge, where_)
                let dark = appearance == .darkAqua
                if helms {
                    XCTAssertTrue(dark ? edge > strip + 3 : edge < strip - 3, """
                        \(where_), Log: Helm's band is not lit over a page that declares nothing \
                        scrolls under it (strip \(strip), edge \(edge))
                        """)
                } else {
                    XCTAssertEqual(edge, strip, accuracy: 1, """
                        \(where_), Log: Helm's band is drawn under the toolbar (strip \(strip), \
                        edge \(edge)) over the system's own effect
                        """)
                }
            }
        }
    }

    private enum BandRow { case strip, edge }

    /// The luma of one point of the pane's top band, composited over black
    /// where nothing was drawn — so «nothing there» reads 0 in both rows
    /// rather than as whatever colour a transparent pixel happens to carry.
    private func luma(_ pane: NSView, row: BandRow, _ what: String) throws -> CGFloat {
        let inset = pane.safeAreaInsets.top
        guard inset > 1 else {
            XCTFail("\(what): the pane's top safe area is \(inset) pt — there is no band to read")
            throw XCTSkip("no band to read")
        }
        let rep = try XCTUnwrap(pane.bitmapImageRepForCachingDisplay(in: pane.bounds),
                                "\(what): the pane would not cache its display")
        pane.cacheDisplay(in: pane.bounds, to: rep)
        let scale = CGFloat(rep.pixelsHigh) / pane.bounds.height
        let y = row == .edge ? Int(inset * scale) - 1 : Int(20 * scale)
        let x = Int(pane.bounds.width / 2 * scale)
        let colour = try XCTUnwrap(rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                                   "\(what): no pixel at \(x), \(y)")
        return (0.299 * colour.redComponent + 0.587 * colour.greenComponent
                + 0.114 * colour.blueComponent) * colour.alphaComponent * 255
    }

    // MARK: - Probe A — the system's own per-page toolbar background

    /// **`toolbarBackgroundVisibility(_:for: .windowToolbar)` does nothing in
    /// this construction**, and this case is the measurement.
    ///
    /// It is the one knob in the toolbar and scroll-edge surface that carries a
    /// «when» rather than a shape, and it is an ordinary `View` modifier, so it
    /// would be per-page — the shape a page that wants its band always on would
    /// need. Measured here: with it on the pane's root view, bridged out by
    /// `sceneBridgingOptions = [.toolbars]`, the title bar's whole layer census
    /// is line for line what it is without it, the pane's scroll-edge pocket
    /// reads the same, and `titlebarAppearsTransparent` reads back as the
    /// window set it — SwiftUI does not take that flag off the window.
    ///
    /// **Four things keep this negative from being vacuous.** Every arm has to
    /// reach a title bar with a `CABackdropLayer` in it, so a window that was
    /// never built fails first and says so. The census is shown seeing a layer
    /// planted under the bar and losing it again. The modifier is asked for
    /// `.hidden` as well as `.visible`, so «the state was already that» is out:
    /// a knob that did anything would have to move one of the two. And it is
    /// applied in both places a reader would try — outside the pane's root, and
    /// inside the body beside the `.toolbar` it speaks about.
    ///
    /// **Read under each system's title bar**, since the flag is the one thing
    /// the two decisions set differently and the knob is said to compose with
    /// it.
    func testTheSystemsToolbarBackgroundKnobDoesNothingHere() {
        for (system, band) in [("macOS 26", Self.macOS26), ("macOS 27", Self.macOS27)] {
        let flag = band.titlebarAppearsTransparent
        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            let where_ = "\(system), \(appearance.rawValue)"
            let control = settingsShapedWindow(transparentTitleBar: flag, appearance: appearance) {
                ScrollEdgeProbeForm()
            }
            let outside = settingsShapedWindow(transparentTitleBar: flag, appearance: appearance) {
                ScrollEdgeProbeForm().toolbarBackgroundVisibility(.visible, for: .windowToolbar)
            }
            let inside = settingsShapedWindow(transparentTitleBar: flag, appearance: appearance) {
                ScrollEdgeProbeForm(toolbarBackground: .visible)
            }
            let opposite = settingsShapedWindow(transparentTitleBar: flag, appearance: appearance) {
                ScrollEdgeProbeForm(toolbarBackground: .hidden)
            }
            let arms = [(name: "control", window: control),
                        (name: "knob .visible outside", window: outside),
                        (name: "knob .visible inside", window: inside),
                        (name: "knob .hidden inside", window: opposite)]

            for arm in arms {
                let reading = TitlebarCensus.read(in: arm.window)
                XCTAssertTrue(reading.readable, "\(where_) \(arm.name): \(reading.sentence)")
                XCTAssertGreaterThan(reading.layersWalked, 15, """
                    \(where_) \(arm.name): the title bar census is \(reading.layersWalked) layers \
                    deep, too few to be the bar this measurement was taken on — \
                    \(reading.sentence)
                    """)
                XCTAssertTrue(reading.census.contains { $0.contains("CABackdropLayer") }, """
                    \(where_) \(arm.name): no CABackdropLayer under the title bar, so this census \
                    is not reading the surface a background would be drawn on — \(reading.sentence)
                    """)
            }

            XCTAssertNil(TitlebarCensus.seesAPlantedLayer(in: control), """
                \(where_): the census cannot see a background arriving under the title bar, so \
                nothing it says about the modifier means anything
                """)

            let settled = TitlebarCensus.settled(arms, forAtMost: 10)
            XCTAssertTrue(settled.settled, """
                \(where_): the four title bars never read the same twice in \(settled.passes) \
                passes, so no comparison between them is a comparison about the modifier
                """)
            let reference = settled.censuses["control"] ?? []
            XCTAssertFalse(reference.isEmpty, "\(where_): the control window's census is empty")

            for arm in arms.dropFirst() {
                let census = settled.censuses[arm.name] ?? []
                XCTAssertEqual(census, reference, """
                    \(where_) \(arm.name): the title bar's layers are no longer what they are \
                    without the modifier. The system's per-page toolbar background knob has \
                    started doing something in this construction, and Helm may not need to draw \
                    the band itself after all — \(TitlebarCensus.difference(reference, census))
                    """)
                XCTAssertEqual(arm.window.titlebarAppearsTransparent, flag, """
                    \(where_) \(arm.name): SwiftUI's modifier moved titlebarAppearsTransparent \
                    away from the value SettingsWindow sets by hand in init — that is a fight \
                    over one flag rather than a knob that composes with it
                    """)
                XCTAssertEqual(readPocket(in: arm.window).effectOpacity,
                               readPocket(in: control).effectOpacity, """
                    \(where_) \(arm.name): the pane's scroll-edge pocket answers differently with \
                    the modifier on — \(readPocket(in: arm.window).sentence) against \
                    \(readPocket(in: control).sentence)
                    """)
            }
            arms.forEach { $0.window.close() }
        }
        }
    }

    // MARK: - Probe B — what the flag is load-bearing for

    /// **The title bar is one section over the whole window, and
    /// `titlebarAppearsTransparent` does not touch the surface a band would be
    /// drawn on** — what the flag moves is the *pane*, which is where the
    /// verdict above reads it.
    ///
    /// One `NSTitlebarView` spans the window over one full-width
    /// `NSToolbarView`; nothing under the bar is as wide as the sidebar, and
    /// the only view up there that knows about the split is a 5.5 pt
    /// `NSTitlebarContainerBlockingView` standing on the divider. So there is
    /// no per-section surface in the bar for either Helm or the system to
    /// light.
    ///
    /// macOS 27's window against macOS 26's — flagged against unflagged, both
    /// settled and read in one pass — the bar's census moves, but not at its
    /// `CABackdropLayer`, which is the bar's own background, while the pane's
    /// pocket goes from drawing on 26 to withheld on 27.
    ///
    /// The scan for a sidebar-wide section is exercised on a planted view
    /// first, so «there is no such section» is never this scan matching nothing.
    func testTheTitleBarIsOneSectionAndTheFlagDoesNotShowOnItsBackdrop() {
        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            let where_ = appearance.rawValue
            let opaque = settingsShapedWindow(transparentTitleBar: Self.macOS26.titlebarAppearsTransparent,
                                              appearance: appearance) {
                ScrollEdgeProbeForm()
            }
            let transparent = settingsShapedWindow(transparentTitleBar: Self.macOS27.titlebarAppearsTransparent,
                                                   appearance: appearance) {
                ScrollEdgeProbeForm()
            }
            let arms = [(name: "opaque", window: opaque), (name: "transparent", window: transparent)]
            _ = turnTheRunLoop(until: { self.readPocket(in: opaque).drawing }, forAtMost: 10)

            let bar = TitlebarCensus.read(in: opaque)
            XCTAssertTrue(bar.readable, "\(where_) opaque: \(bar.sentence)")
            XCTAssertEqual(bar.titlebarViewFrame?.width ?? 0, opaque.frame.width, accuracy: 0.5, """
                \(where_) opaque: the NSTitlebarView is \
                \(bar.titlebarViewFrame.map { "\($0.width)" } ?? "nil") pt wide against a window \
                \(opaque.frame.width) pt wide — the bar is in sections after all, which would be a \
                surface a per-page background could be asked for — \(bar.sentence)
                """)
            XCTAssertEqual(bar.blockingFrames.count, 1, """
                \(where_) opaque: \(bar.blockingFrames.count) NSTitlebarContainerBlockingView \
                under the bar, not the one that stands on the divider — \(bar.sentence)
                """)

            let sidebarWidth = (opaque.contentViewController as? NSSplitViewController)?
                .splitViewItems.first?.viewController.view.frame.width ?? 0
            XCTAssertGreaterThan(sidebarWidth, 100, """
                \(where_): the sidebar is \(sidebarWidth) pt wide, so «as wide as the sidebar» \
                measures nothing
                """)
            if let divider = bar.blockingFrames.first {
                XCTAssertEqual(divider.midX, sidebarWidth + divider.width / 2, accuracy: 4, """
                    \(where_) opaque: the blocking view is centred at \(divider.midX) where the \
                    sidebar ends at \(sidebarWidth) — it is not the divider it was read as
                    """)
            }
            XCTAssertEqual(bar.sidebarWideViews, [String](), """
                \(where_) opaque: the title bar carries a view exactly as wide as the sidebar — \
                \(bar.sidebarWideViews). There is a sidebar section up there after all, and this \
                measurement's answer changes
                """)

            let plant = NSView(frame: NSRect(x: 0, y: 0, width: sidebarWidth, height: 52))
            opaque.contentView?.superview?.everyView
                .first { $0.appKitClassName == "NSTitlebarView" }?.addSubview(plant)
            XCTAssertEqual(TitlebarCensus.read(in: opaque).sidebarWideViews.count, 1, """
                \(where_): a view planted at exactly the sidebar's width is not found by the scan \
                that reported none, so that report was the scan matching nothing
                """)
            plant.removeFromSuperview()

            let settled = TitlebarCensus.settled(arms, forAtMost: 10)
            XCTAssertTrue(settled.settled, """
                \(where_): the two title bars never read the same twice in \(settled.passes) \
                passes, so a difference between them is a difference of when they were read
                """)
            let difference = TitlebarCensus.difference(settled.censuses["opaque"] ?? [],
                                              settled.censuses["transparent"] ?? [])
            XCTAssertFalse(difference.contains { $0.contains("CABackdropLayer") }, """
                \(where_): titlebarAppearsTransparent now moves the bar's own backdrop layer — \
                \(difference). It moved everything but that when this was measured, which is why \
                the flag is read at the pane below and not here
                """)

            XCTAssertEqual(readPocket(in: opaque).effectOpacity, 1, """
                \(where_): macOS 26's window — opaque by its decision — is not drawing the \
                system's scroll edge effect over its pane — \(readPocket(in: opaque).sentence) — \
                so the comparison below has no difference to be about, and 26's pane has no band
                """)
            XCTAssertEqual(readPocket(in: transparent).effectOpacity, 0, """
                \(where_): macOS 27's window no longer withholds the pane's effect — \
                \(readPocket(in: transparent).sentence)
                """)

            opaque.close()
            transparent.close()
        }
    }
}

// MARK: - The subject

/// The grouped `Form` the question is about, tall enough to go under the bar,
/// with the fixed navigation spacer every page carries
/// (`ToolbarSpacer(.fixed, placement: .navigation)`, in `SettingsWindow`) so
/// the window has a toolbar at all.
private struct ScrollEdgeProbeForm: View {
    /// What to ask `toolbarBackgroundVisibility(_:for: .windowToolbar)` for
    /// from *inside* the body, beside the `.toolbar` it speaks about — the
    /// other of the two places a reader would put it. `nil` is the form the
    /// cases above this were measured on, and leaves them untouched.
    var toolbarBackground: Visibility?

    var body: some View {
        let form = Form {
            ForEach(0..<12, id: \.self) { section in
                Section("Section \(section)") {
                    ForEach(0..<3, id: \.self) { row in
                        Toggle("Row \(section)-\(row)", isOn: .constant(true))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .toolbar { ToolbarSpacer(.fixed, placement: .navigation) }

        if let toolbarBackground {
            form.toolbarBackgroundVisibility(toolbarBackground, for: .windowToolbar)
        } else {
            form
        }
    }
}

/// The sidebar is here because the split is: the pane's pocket is sized from
/// the divider, and a detail pane measured without one is not the pane the
/// question is about.
private struct ScrollEdgeProbeSidebar: View {
    var body: some View {
        List { ForEach(0..<8, id: \.self) { Text("Item \($0)") } }
            .listStyle(.sidebar)
    }
}
