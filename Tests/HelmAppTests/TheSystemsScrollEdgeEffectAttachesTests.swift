import AppKit
import HelmTestSupport
import SwiftUI
import XCTest

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
/// `SettingsWindow` sets that flag — `window.titlebarAppearsTransparent = true`
/// — on the window it builds for the settings split.
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
/// keeps AppKit's safe area, so a page's content never passes beneath the bar.
/// That is the reason Helm's own strip exists, and it is not that the platform
/// gives us nothing.
///
/// This file is the measurement, kept so the next reader does not re-derive it
/// and so a macOS that changes its mind fails here rather than in somebody's
/// screenshot. It builds its own windows deliberately: the subject is the
/// construction, and a check that could only speak through `SettingsWindow`
/// would go quiet the moment that file changed.
@MainActor
final class TheSystemsScrollEdgeEffectAttachesTests: XCTestCase {

    // MARK: - The two windows, alike but for one flag

    /// The settings window's construction: split view, sidebar item, a detail
    /// pane hosting a grouped `Form` whose toolbar is bridged into the window,
    /// `.fullSizeContentView`, hidden title — the window `SettingsWindow` builds
    /// in its initialiser, and the `detail.sceneBridgingOptions = [.toolbars]`
    /// its split view controller sets. Never ordered on screen: the probe read
    /// the same three states for a window that was shown and one that was not.
    private func settingsShapedWindow(transparentTitleBar: Bool) -> NSWindow {
        _ = NSApplication.shared
        let split = NSSplitViewController()

        let sidebar = NSHostingController(rootView: ScrollEdgeProbeSidebar())
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.allowsFullHeightLayout = true
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = 214
        sidebarItem.maximumThickness = 320

        let detail = NSHostingController(rootView: ScrollEdgeProbeForm())
        detail.sceneBridgingOptions = [.toolbars]
        detail.sizingOptions = []
        let detailItem = NSSplitViewItem(viewController: detail)
        detailItem.minimumThickness = 420

        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(detailItem)

        let window = NSWindow(contentViewController: split)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
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
        guard let content = window.contentView else {
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
        let opaque = settingsShapedWindow(transparentTitleBar: false)
        let transparent = settingsShapedWindow(transparentTitleBar: true)
        _ = turnTheRunLoop(until: { self.readPocket(in: opaque).pocketFrame != nil
                                    && self.readPocket(in: transparent).pocketFrame != nil },
                           forAtMost: 10)

        for (name, window) in [("opaque", opaque), ("transparent", transparent)] {
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

    // MARK: - The verdict

    /// The effect **can** attach to this `Form` in this construction, and
    /// `titlebarAppearsTransparent` is the one thing withholding it.
    ///
    /// Both windows are built and turned together; the assertion on the
    /// withheld one is only reached once the drawing one has actually drawn.
    func testOnlyTheTransparentTitleBarWithholdsTheEffect() {
        let opaque = settingsShapedWindow(transparentTitleBar: false)
        let transparent = settingsShapedWindow(transparentTitleBar: true)

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

        let transparentReading = readPocket(in: transparent)
        XCTAssertNotNil(transparentReading.pocketFrame, """
            transparent title bar: \(transparentReading.sentence) — the pocket is missing rather \
            than withheld, which is a different finding from the one this file records
            """)
        XCTAssertEqual(transparentReading.effectOpacity, 0, """
            transparent title bar: the effect is no longer withheld — \
            \(transparentReading.sentence). Helm's own toolbar strip has lost its reason to exist
            """)
        XCTAssertTrue(transparentReading.effectParts.isEmpty, """
            transparent title bar: the effect layer has parts to draw — \
            \(transparentReading.sentence)
            """)

        opaque.close()
        transparent.close()
    }

    // MARK: - The two halves of the decision stay together

    /// Helm's own strip and the flag that withholds the system's are one
    /// decision: the window may wear a transparent title bar **and** draw
    /// `helmToolbarBackdrop`, or neither. Half of that change is a page with
    /// two strips or a page with none.
    ///
    /// The predicate is exercised on planted text first, so a green run here is
    /// never the scan silently matching nothing.
    func testTheStripAndTheTransparentTitleBarAgree() throws {
        let path = "Sources/HelmApp/SettingsWindow.swift"
        let source = SwiftSource.code(try RepoSource.text(of: path))

        func transparentTitleBar(_ text: String) -> Bool {
            text.contains("titlebarAppearsTransparent = true")
        }
        func helmsOwnStrip(_ text: String) -> Bool {
            text.contains(".helmToolbarBackdrop()")
        }

        let planted = """
            window.titlebarAppearsTransparent = true
            let detail = NSHostingController(rootView: SettingsDetail(model: model))
            """
        XCTAssertTrue(transparentTitleBar(planted),
                      "the flag scan does not match the line it exists to find")
        XCTAssertFalse(helmsOwnStrip(planted),
                       "the strip scan matches a pane that does not wear the strip")
        XCTAssertTrue(helmsOwnStrip(planted + "\n    .helmToolbarBackdrop()\n"),
                      "the strip scan does not match the call it exists to find")

        XCTAssertEqual(transparentTitleBar(source), helmsOwnStrip(source), """
            \(path) sets a transparent title bar \(transparentTitleBar(source)) and draws Helm's \
            own toolbar strip \(helmsOwnStrip(source)). The transparent title bar is what holds \
            the system's scroll edge effect at opacity 0 — measured in this file — so the two \
            belong to one decision: keep both, or drop both
            """)
    }
}

// MARK: - The subject

/// The grouped `Form` the question is about, tall enough to go under the bar,
/// with the fixed navigation spacer every page carries
/// (`ToolbarSpacer(.fixed, placement: .navigation)`, in `SettingsWindow`) so
/// the window has a toolbar at all.
private struct ScrollEdgeProbeForm: View {
    var body: some View {
        Form {
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
