import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **On macOS 26 the settings pane asks the system's scroll edge effect for
/// its soft style over the top edge; on macOS 27 it asks for nothing** — read
/// from what AppKit's pocket was actually handed, not from the source text.
///
/// `helmToolbarBackdrop` has two arms, chosen by `HelmBandChoice`: on 27 Helm
/// draws its own band, on 26 it hands the edge to the system and asks for
/// `ScrollEdgeEffectStyle.soft` over `.top` (the owner: content behind the
/// toolbar should blur slightly).
///
/// # The instrument
///
/// SwiftUI exposes no reading of the style it was asked for, and on this Mac
/// the *drawing* does not tell soft from automatic either (the last case below
/// is that measurement). What does tell them apart is the `NSScrollPocket`
/// AppKit puts over the pane's scroll view: its `style` property reads one
/// value under no modifier, another under `.soft` and a third under `.hard`
/// (measured 2026-09-29, macOS 27.2: 0, 1, 2). The cases below never write
/// those numbers down as expectations — each run reads all three from control
/// windows built beside the subject, asserts the three differ (so an
/// instrument that answers the same thing for everything fails first), and
/// judges the subject against the controls. The property is private AppKit;
/// if it goes away the reader fails naming it rather than trapping.
///
/// # What this proves, and what it does not
///
/// It proves that the 26 arm's request reaches the pocket over the pane in the
/// shipping construction — split view, app-owned `NSToolbar`, no
/// `sceneBridgingOptions` — and that the 27 arm's does not. **It proves
/// nothing about how macOS 26 draws that request.** Every reading here is
/// macOS 27.2's AppKit answering; what soft looks like on 26, and whether 26's
/// automatic would have looked any different, is the owner's to see in a 26
/// virtual machine.
@MainActor
final class On26TheBandAsksTheSystemForASoftEdgeTests: XCTestCase {

    // MARK: - The window: the shipping construction, built by hand

    /// Hands the probe window's toolbar one item, so the toolbar is a real
    /// 52 pt bar the way `SettingsToolbar`'s is, and nothing else.
    private final class OneItemToolbar: NSObject, NSToolbarDelegate {
        static let item = NSToolbarItem.Identifier("helm.test.softEdge.item")
        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            [.flexibleSpace, Self.item]
        }
        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            [.flexibleSpace, Self.item]
        }
        func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                     willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
            let item = NSToolbarItem(itemIdentifier: id)
            item.label = "Probe"
            item.image = NSImage(systemSymbolName: "gear", accessibilityDescription: "Probe")
            return item
        }
    }

    /// The toolbar's delegate is weak, so the case keeps it.
    private var toolbarDelegates: [OneItemToolbar] = []

    /// `SettingsWindow`'s shape — sidebar and detail in a split, an
    /// app-owned `NSToolbar`, **no** `sceneBridgingOptions` on the detail,
    /// `.fullSizeContentView`, hidden title — with an **opaque** title bar,
    /// which is 26's (`HelmBandChoice.titlebarAppearsTransparent`) and the one
    /// under which the pane's pocket draws at all. The title bar is opaque in
    /// every arm, the 27 subject's included, so the only thing that differs
    /// between arms is the detail's root view.
    private func window<Detail: View>(title: String? = nil,
                                      @ViewBuilder detail root: () -> Detail) -> NSWindow {
        _ = NSApplication.shared
        let split = NSSplitViewController()
        let sidebar = NSHostingController(rootView: SoftEdgeProbeSidebar())
        sidebar.sizingOptions = []
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.allowsFullHeightLayout = true
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = 214
        sidebarItem.maximumThickness = 320
        let detail = NSHostingController(rootView: root())
        detail.sizingOptions = []
        let detailItem = NSSplitViewItem(viewController: detail)
        detailItem.minimumThickness = 420
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(detailItem)

        let window = NSWindow(contentViewController: split)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = false
        // Hidden unless a title is named — the two shapes `SettingsWindow`
        // wears: `PageBarStyle.moduleName` hides it, `.windowTitle` shows it.
        window.title = title ?? ""
        window.titleVisibility = title == nil ? .hidden : .visible
        window.setContentSize(SettingsWindow.defaultSize)
        window.isReleasedWhenClosed = false
        let delegate = OneItemToolbar()
        toolbarDelegates.append(delegate)
        let toolbar = NSToolbar(identifier: "helm.test.softEdge.\(UUID().uuidString)")
        toolbar.delegate = delegate
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        return window
    }

    private func detailPane(of window: NSWindow) -> NSView? {
        (window.contentViewController as? NSSplitViewController)?.splitViewItems.last?.viewController.view
    }

    // MARK: - Reading the pocket

    /// One pocket over a SwiftUI scroll view under the pane: where it is,
    /// what style AppKit was handed, and what its effect layer is drawing.
    private struct Pocket {
        let frame: NSRect
        /// `NSScrollPocket.style`; `nil` when the pocket no longer answers it.
        let style: Int?
        let effectOpacity: Float?
        /// The effect layer's parts, name and opacity — the same layer
        /// `TheSystemsScrollEdgeEffectAttachesTests` reads.
        let parts: [String]
        var sentence: String {
            "pocket \(frame) style \(style.map(String.init) ?? "unreadable") "
                + "effect opacity \(effectOpacity.map { "\($0)" } ?? "none") parts \(parts)"
        }
    }

    /// Every pocket over a SwiftUI scroll view under `pane` whose top edge is
    /// the pane's top — the one under the toolbar, whatever page is showing.
    private func topPockets(under pane: NSView?) -> (walked: Int, pockets: [Pocket]) {
        guard let pane, let window = pane.window else { return (0, []) }
        let top = window.contentView?.frame.maxY ?? 0
        let tree = pane.everyViewWithAncestry
        let pockets = tree.compactMap { entry -> Pocket? in
            guard entry.view.appKitClassName.hasSuffix("NSScrollPocket"),
                  entry.ancestry.contains(where: { $0.appKitClassName.contains("HostingScrollView") })
            else { return nil }
            let frame = entry.view.convert(entry.view.bounds, to: nil)
            guard frame.height > 0, abs(frame.maxY - top) < 1 else { return nil }
            let style = entry.view.responds(to: Selector(("style")))
                ? (entry.view.value(forKey: "style") as? NSNumber)?.intValue : nil
            let effect = (entry.view.layer?.sublayers ?? []).first { layer in
                guard let delegate = layer.delegate else { return false }
                return "\(type(of: delegate))".contains("ScrollEdgeEffectLayerDelegate")
            }
            let parts = (effect?.sublayers ?? []).map { layer in
                "\(layer.name ?? "\(type(of: layer))")@\(layer.opacity)"
            }
            return Pocket(frame: frame, style: style, effectOpacity: effect?.opacity, parts: parts)
        }
        return (tree.count, pockets)
    }

    /// The pane's one top pocket, waited for until it reads `until` — so an
    /// absence is only judged once the subject has had every chance to appear.
    private func settledPocket(under pane: @autoclosure () -> NSView?, until wanted: (Pocket) -> Bool,
                               forAtMost seconds: TimeInterval = 10) -> (walked: Int, pockets: [Pocket]) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            let reading = topPockets(under: pane())
            if reading.pockets.count == 1, wanted(reading.pockets[0]) { return reading }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        return topPockets(under: pane())
    }

    private func drawing(_ pocket: Pocket) -> Bool {
        pocket.style != nil && pocket.effectOpacity == 1 && !pocket.parts.isEmpty
    }

    /// The three controls, each read once it draws: the pocket's style under
    /// no modifier, under `.soft` and under `.hard` — this run's values, never
    /// literals.
    private func controlStyles(file: StaticString = #filePath, line: UInt = #line)
        throws -> (automatic: Int, soft: Int, hard: Int) {
        var styles: [Int] = []
        for (name, window) in [("no modifier", window { SoftEdgeProbeForm() }),
                               (".soft", window { SoftEdgeProbeForm().scrollEdgeEffectStyle(.soft, for: .top) }),
                               (".hard", window { SoftEdgeProbeForm().scrollEdgeEffectStyle(.hard, for: .top) })] {
            defer { window.close() }
            let reading = settledPocket(under: self.detailPane(of: window), until: drawing)
            XCTAssertGreaterThan(reading.walked, 50, "control \(name): could not reach the view tree",
                                 file: file, line: line)
            let pocket = try XCTUnwrap(reading.pockets.first, """
                control \(name): no pocket over the form's top edge after walking \(reading.walked) views — \
                the construction no longer attaches the system's effect under an opaque title bar
                """, file: file, line: line)
            let style = try XCTUnwrap(pocket.style, """
                control \(name): NSScrollPocket no longer answers `style`, so this file's instrument \
                is gone — \(pocket.sentence)
                """, file: file, line: line)
            XCTAssertTrue(drawing(pocket), "control \(name): not drawing — \(pocket.sentence)",
                          file: file, line: line)
            styles.append(style)
        }
        XCTAssertEqual(Set(styles).count, 3, """
            the pocket's style reads \(styles) for no modifier, .soft and .hard — the instrument does not \
            tell the three requests apart, so nothing below it can say which one the pane made
            """, file: file, line: line)
        return (styles[0], styles[1], styles[2])
    }

    // MARK: - 1. The decision, read through the modifier itself

    /// **`helmToolbarBackdrop` under 26's decision hands the pocket the style
    /// `.soft` hands it; under 27's it hands the pocket what no modifier
    /// does.** Both are read under the same opaque title bar, so 27's arm is
    /// judged on what it asks for and not on the transparent title bar that
    /// withholds the effect in its own window.
    func testTheBackdropAsksForSoftOn26AndForNothingOn27() throws {
        let control = try controlStyles()

        for (system, band, expected, meaning) in [
            ("macOS 26", HelmBandChoice.onMacOS(26), control.soft, "the soft style"),
            ("macOS 27", HelmBandChoice.onMacOS(27), control.automatic, "no style at all"),
        ] {
            let subject = window {
                SoftEdgeProbeForm()
                    .helmToolbarBackdrop()
                    .environment(\.helmBandChoice, band)
            }
            defer { subject.close() }
            let reading = settledPocket(under: self.detailPane(of: subject), until: { $0.style == expected })
            let pocket = try XCTUnwrap(reading.pockets.first, """
                \(system): no pocket over the pane's top edge after walking \(reading.walked) views
                """)
            XCTAssertEqual(pocket.style, expected, """
                \(system): `helmToolbarBackdrop` under this system's band decision hands the pane's \
                scroll-edge pocket style \(pocket.style.map(String.init) ?? "unreadable"); it should ask \
                for \(meaning) (controls this run: none \(control.automatic), soft \(control.soft), \
                hard \(control.hard)) — \(pocket.sentence)
                """)
        }
    }

    // MARK: - 2. The shipping window, and the states it passes through

    /// **The real `SettingsWindow`, built on 26's decision: its pane's top
    /// pocket carries the soft style on General, after moving to another page
    /// and back, after a language change rebuilds the pane, and after the
    /// window is hidden — which unmounts the pane (`helmIdlesOffScreen`) — and
    /// shown again.** Built on 27's decision it carries none, and its effect
    /// stays withheld.
    ///
    /// The window is ordered in behind everything and never asked to show,
    /// which would activate the app.
    func testTheShippingWindowKeepsAskingThroughEveryRebuild() throws {
        let control = try controlStyles()

        let frameKey = "NSWindow Frame HelmSettingsWindow.v4"
        let splitKey = "NSSplitView Subview Frames HelmSettingsSidebar.v1"
        let foundFrame = UserDefaults.standard.string(forKey: frameKey)
        let foundSplit = UserDefaults.standard.stringArray(forKey: splitKey)
        addTeardownBlock {
            UserDefaults.standard.set(foundFrame, forKey: frameKey)
            UserDefaults.standard.set(foundSplit, forKey: splitKey)
        }

        let foundStyle = AppSettings.store.object(PageBarStyle.storageKey)
        addTeardownBlock { @MainActor in
            AppSettings.store.set(foundStyle, for: PageBarStyle.storageKey)
        }

        for pageBar in [PageBarStyle.moduleName, .windowTitle] {
        AppSettings.pageBarStyle = pageBar
        for (system, band, expected) in [("macOS 26", HelmBandChoice.onMacOS(26), control.soft),
                                         ("macOS 27", HelmBandChoice.onMacOS(27), control.automatic)] {
            let owner = SettingsWindow(host: ModuleHost.shared, band: band)
            let fields = Mirror(reflecting: owner).children
            let window = try XCTUnwrap(fields.first { $0.label == "window" }?.value as? NSWindow,
                                       "SettingsWindow no longer holds `window` — this case reads it by name")
            let model = try XCTUnwrap(fields.first { $0.label == "model" }?.value as? SettingsModel,
                                      "SettingsWindow no longer holds `model` — this case reads it by name")
            window.appearance = NSAppearance(named: .darkAqua)
            window.orderBack(nil)
            defer {
                window.toolbar = nil
                window.close()
            }
            let pane = { (window.contentViewController as? NSSplitViewController)?
                .splitViewItems.last?.viewController.view }

            let steps: [(String, () -> Void)] = [
                ("General", { model.selection = .general }),
                ("About, a ScrollView rather than a Form", { model.selection = .about }),
                ("back on General", { model.selection = .general }),
                ("after a language change rebuilt the pane", {
                    NotificationCenter.default.post(name: .helmLanguageChanged, object: nil)
                }),
                ("after the window was hidden and shown again", {
                    // A test process is not told about occlusion reliably
                    // (`WindowSeenReader`), and a window ordered back behind
                    // everything may not change occlusion at all — so the
                    // reader is asked by hand, as its own tests do, and the
                    // unmount is proved before the remount is judged.
                    window.orderOut(nil)
                    self.askTheWindowReaders(in: window)
                    let deadline = Date().addingTimeInterval(10)
                    while Date() < deadline, !self.topPockets(under: pane()).pockets.isEmpty {
                        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
                    }
                    XCTAssertTrue(self.topPockets(under: pane()).pockets.isEmpty, """
                        \(system): the pane's page was not unmounted while the window was ordered out, \
                        so «after it was shown again» would read the page that never left
                        """)
                    window.orderBack(nil)
                    self.askTheWindowReaders(in: window)
                }),
            ]
            for (bareStep, act) in steps {
                let step = "\(pageBar.rawValue), \(bareStep)"
                act()
                let reading = settledPocket(under: pane(), until: { $0.style == expected })
                print("SOFT-EDGE SHIPPING \(system), \(step): title "
                      + "\(window.titleVisibility == .visible ? "shown «\(window.title)»" : "hidden"): "
                      + "\(reading.pockets.map(\.sentence))")
                XCTAssertEqual(reading.pockets.count, 1, """
                    \(system), \(step): \(reading.pockets.count) pockets over the pane's top edge after \
                    walking \(reading.walked) views — \(reading.pockets.map(\.sentence))
                    """)
                guard let pocket = reading.pockets.first else { continue }
                XCTAssertEqual(pocket.style, expected, """
                    \(system), \(step): the shipping window's pane hands its top pocket style \
                    \(pocket.style.map(String.init) ?? "unreadable"), not \(expected) (controls this run: \
                    none \(control.automatic), soft \(control.soft), hard \(control.hard)) — \(pocket.sentence)
                    """)
                XCTAssertEqual(pocket.effectOpacity, band.titlebarAppearsTransparent ? 0 : 1, """
                    \(system), \(step): the effect's opacity is not what this system's title bar \
                    decides — \(pocket.sentence)
                    """)
            }
        }
        }
    }

    /// Every `WindowSeenReader` under the window asks again whether the
    /// window is visible — what an occlusion notification would do in the app.
    private func askTheWindowReaders(in window: NSWindow) {
        let readers = (window.contentView?.everyView ?? []).compactMap { $0 as? WindowSeenReader.Reader }
        XCTAssertFalse(readers.isEmpty, "no WindowSeenReader under the settings window — nothing idles it")
        readers.forEach { $0.report() }
    }

    // MARK: - 3. What 27.2 draws for each — a reading, not a verdict about 26

    /// **On macOS 27.2, in the shipping construction with the opaque title bar,
    /// `.soft` and no modifier draw the same effect**: at rest and after
    /// 300 pt of scroll both pockets carry `ThinFilmBackgroundReplay` at 0.6,
    /// `ThinFilmContentBlurFill` (a variable blur) at 1 and `Separator` at 1,
    /// while `.hard` carries `HardPocketContentBlur`, `HardPocketBackgroundReplay`
    /// at 0.8245 and `Separator` (read 2026-09-29). The same holds with the
    /// window's title shown, the shape `PageBarStyle.windowTitle` gives the
    /// window — 27's automatic style did not turn hard for a visible title
    /// here. So on this Mac the 26 arm's request changes the pocket's `style`
    /// and not one layer it draws.
    ///
    /// **This proves nothing about macOS 26's look.** Whether 26 resolves no
    /// modifier to the hard pocket — which is what the 26 arm's own comment
    /// reads out of Apple's documentation — is not answerable on 27.2; it is
    /// the owner's to see in a 26 virtual machine. The case skips below 27
    /// rather than pretend to read 26 here.
    func testOn27SoftAndNoModifierDrawTheSameParts() throws {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        try XCTSkipIf(major < 27, "measured on macOS 27.2; on \(major) the reading is the owner's, by eye")

        var parts: [String: [String]] = [:]
        for (name, window) in [
            ("no modifier", window { SoftEdgeProbeForm() }),
            ("soft", window { SoftEdgeProbeForm().scrollEdgeEffectStyle(.soft, for: .top) }),
            ("hard", window { SoftEdgeProbeForm().scrollEdgeEffectStyle(.hard, for: .top) }),
            ("no modifier, title shown", window(title: "General") { SoftEdgeProbeForm() }),
            ("soft, title shown", window(title: "General") {
                SoftEdgeProbeForm().scrollEdgeEffectStyle(.soft, for: .top) }),
        ] {
            defer { window.close() }
            let rest = settledPocket(under: self.detailPane(of: window), until: drawing)
            let atRest = try XCTUnwrap(rest.pockets.first, "\(name): no pocket after walking \(rest.walked) views")
            XCTAssertTrue(drawing(atRest), "\(name) at rest: \(atRest.sentence)")

            let scroll = try XCTUnwrap(detailPane(of: window)?.everyView(ofType: NSScrollView.self)
                .first { $0.appKitClassName.contains("HostingScrollView") }, "\(name): no scroll view")
            scroll.contentView.scroll(to: NSPoint(x: 0, y: scroll.contentView.bounds.origin.y + 300))
            scroll.reflectScrolledClipView(scroll.contentView)
            _ = settledPocket(under: self.detailPane(of: window), until: { _ in false }, forAtMost: 0.5)
            let scrolled = try XCTUnwrap(topPockets(under: detailPane(of: window)).pockets.first,
                                         "\(name): the pocket went away under a scroll")
            XCTAssertEqual(scrolled.parts, atRest.parts, """
                \(name): the effect's parts moved under a 300 pt scroll — at rest \(atRest.parts), \
                scrolled \(scrolled.parts); a reading at rest no longer speaks for the scrolled pane
                """)
            parts[name] = atRest.parts
            print("SOFT-EDGE READING macOS \(ProcessInfo.processInfo.operatingSystemVersionString) "
                  + "\(name): at rest \(atRest.parts); scrolled \(scrolled.parts)")
        }

        XCTAssertNotEqual(parts["hard"], parts["soft"], """
            .hard and .soft draw the same parts (\(parts["soft"] ?? [])) — this reading cannot tell \
            styles apart, so its «same as no modifier» below would mean nothing
            """)
        XCTAssertEqual(parts["soft"], parts["no modifier"], """
            macOS 27 now draws .soft differently from no modifier (soft \(parts["soft"] ?? []), none \
            \(parts["no modifier"] ?? [])). This file's reading that the 26 arm's request is invisible on \
            27 is out of date; it still says nothing about 26
            """)
        XCTAssertEqual(parts["soft, title shown"], parts["no modifier, title shown"], """
            with the window's title shown — `PageBarStyle.windowTitle` — macOS 27 now draws .soft \
            differently from no modifier (soft \(parts["soft, title shown"] ?? []), none \
            \(parts["no modifier, title shown"] ?? [])); the request is no longer invisible on 27 in \
            that shape. It still says nothing about 26
            """)
        XCTAssertTrue(parts["soft"]?.contains { $0.hasPrefix("ThinFilmContentBlurFill@") } ?? false, """
            the soft pocket no longer carries ThinFilmContentBlurFill — \(parts["soft"] ?? [])
            """)
    }
}

// MARK: - The subject

/// A grouped `Form` tall enough to go under the bar, as the settings pages are.
private struct SoftEdgeProbeForm: View {
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
    }
}

/// The split is part of the construction: the pane's pocket is sized from the
/// divider.
private struct SoftEdgeProbeSidebar: View {
    var body: some View {
        List { ForEach(0..<8, id: \.self) { Text("Item \($0)") } }
            .listStyle(.sidebar)
    }
}
