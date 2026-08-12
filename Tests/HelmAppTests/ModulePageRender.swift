import AppKit
import HelmRuntime
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// The nine module pages, drawn offscreen, as measurements rather than pictures.
///
/// Two of the four v3 ladder ratchets are read off this render —
/// `RadiusLadderRatchetTests` and `LongStringGeometryRatchetTests`. The other
/// two are read off the source, and `UISources` says why.
///
/// **`NSHostingView`, never `ImageRenderer`.** `ImageRenderer` silently drops
/// every bit of `Form` chrome and hands back a blank white image, which reads as
/// a bug in the page rather than in the capture — measured 2026-08-05, recorded
/// in `v2/migration.md` § "Шаг 0".
///
/// **A window, not a bare view.** A `List` is an AppKit table and draws nothing
/// without one — the reason `SidebarComposerHeightTests` builds one. The
/// uninstaller's page is a list.
///
/// **The engines are built and never activated, and they answer only from a
/// fixture.** `activate()` is where a module reaches the machine — Layout
/// installs a `CGEvent` tap — and a measurement has no business doing that. So
/// no page is drawn against a live engine: with the real transport, Homebrew's
/// page grew from 12 layers to 681 — this machine's package list — and the
/// numbers in the ratchets would then have been a fact about this Mac's
/// software, which is the measurement that is a report and not a gate.
///
/// What replaced the live engine was silence, and silence turned out to be its
/// own kind of lie. A page whose whole content arrives over the wire draws its
/// empty state against a transport that never answers, and three modules are
/// that shape — so the ratchets were measuring a screen at first launch and
/// calling it the page. VPN made it visible: `hasConnections` put the rules
/// card, the notice cards and the spin section behind one question on
/// 2026-08-12, the render fell from 160-odd layers to 55, and nothing went red.
/// `ModulePageFixtures.swift` is the answer — a table of command→reply and a
/// list of events, per module, fixed and identical on every Mac. That is the
/// distinction the old comment here was missing: the hazard was never
/// *answering*, it was answering **out of the machine**.
///
/// **Settling is measured, not slept through.** A fixed pump gave 1374, 1371
/// and 1367 layers over three consecutive runs and the set of radii moved with
/// it, which is a ratchet that fires on the weather. `settle` pumps until the
/// tree stops moving; three consecutive runs then agreed to the layer.
///
/// **The appearance is named by the caller, and that is the second weather this
/// render had.** It used to inherit `NSApp.effectiveAppearance`, which in a test
/// process is whatever the person's Mac is set to that hour — and this Mac has
/// `AppleInterfaceStyleSwitchesAutomatically` on. At 04:34:58 on 2026-08-12 it
/// went from dark to light by itself and `RadiusLadderRatchetTests` went red with
/// nothing committed in between: SwiftUI draws a `Slider`'s knob as a 20 × 16
/// capsule layer of `cornerRadius` 8 in light and does not draw that layer at all
/// in dark, so the count of distinct off-ladder radii is 6 on one screen and 5 on
/// the other. Six of the nine pages are the same either way; the two that are not
/// are named in that file. So there is no default here: a reading has a screen,
/// and it says which.
@MainActor
enum ModulePageRender {

    /// One layer of a drawn page, in the root's coordinates.
    struct Drawn {
        let frame: CGRect
        let radius: CGFloat
        let hasContents: Bool
        /// The class of the `NSView` that owns this layer, or of the nearest
        /// ancestor that owns one.
        let owner: String

        /// True when macOS drew this, not Helm. A switch's 6.5 pt end cap and a
        /// pop-up's bezel are not decisions anybody in this repository can take
        /// back, so a ratchet that counted them would have a floor nothing can
        /// lower — and a ratchet with an unreachable floor stops being read.
        var isSystemDrawn: Bool { owner.contains("AppKit") }
    }

    /// An AppKit-backed control inside a page, with the width it asked for.
    struct Control {
        let module: String
        let name: String
        let frame: CGRect
        let intrinsic: CGSize

        /// Controls whose intrinsic width is set by the text inside them.
        ///
        /// A switch is 36 pt in every language, so asking whether its label fits
        /// is asking about a label it does not have — and a check that reports
        /// twelve switches a page reports the same non-finding twelve times,
        /// which is how a signal gets switched off by hand.
        var isTextBearing: Bool {
            ["SegmentedControl", "TextField", "SearchField", "PopUpButton",
             "Button", "ComboBox"].contains { name.contains($0) }
        }

        /// The class without AppKit's wrapper, for a message somebody reads.
        var shortName: String {
            name.replacingOccurrences(of: "_NSCoreHostingView<", with: "")
                .replacingOccurrences(of: ">", with: "")
        }
    }

    struct Page {
        let id: String
        let layers: [Drawn]
        let controls: [Control]
        /// The wire this page was drawn against, so a test can ask whether it is
        /// still live. A stream that has finished and one that never had anything
        /// to say draw the same page, and only one of those is a working harness.
        let transport: FixtureTransport
        /// Held so the objects behind the measurement outlive it.
        private let keepAlive: [AnyObject]

        init(id: String, layers: [Drawn], controls: [Control],
             transport: FixtureTransport, keepAlive: [AnyObject]) {
            self.id = id
            self.layers = layers
            self.controls = controls
            self.transport = transport
            self.keepAlive = keepAlive
        }
    }

    /// The form column every module page is drawn in today. Read from
    /// `HelmLayout.settingsColumn` rather than spelled again: a page measured at
    /// a width the app never uses is a measurement of nothing.
    static var pageWidth: CGFloat { HelmLayout.settingsColumn }

    /// Tall enough that a `ScrollView` realizes all of its content. A page
    /// measured at window height reports only what is above the fold — Disk went
    /// from 50 layers to 129 when this grew.
    static let pageHeight: CGFloat = 3000

    /// Every module page in `ModuleRegistry.all`, in registry order.
    ///
    /// The registry, not a list written here: a module added to the app has to
    /// arrive in these ratchets without anybody remembering to add it.
    static func pages(in appearance: NSAppearance.Name,
                      width: CGFloat = pageWidth,
                      seededBy seed: Seed = { _, _ in },
                      wiredBy wire: Wiring = answering) -> [Page] {
        ModuleRegistry.all.map {
            page(for: $0, in: appearance, width: width, seededBy: seed, wiredBy: wire)
        }
    }

    /// Settings a page is opened *on*, written into its store before it is built.
    ///
    /// **A page drawn against an empty store draws a page nobody has.** Every
    /// module's richest rows are the ones a person has configured — Keep Awake's
    /// app rules with a condition menu each, the battery slider under its own
    /// figure — and none of them existed in any of the 72 renders the string
    /// ratchet takes: the empty state draws one prominent button where the
    /// configured list draws three controls a row.
    ///
    /// What that buys, and what it does not: the seeded rows are now in the
    /// **render** — 296 layers to 322 on the Keep Awake page — so the layer floor
    /// and anything measured off pixels sees them. They are not in the *control*
    /// walk, because a SwiftUI `Picker(.menu)`, `Button` and `Slider` are not
    /// AppKit-backed views on macOS 26/27 at all; `LongStringGeometryRatchetTests`
    /// carries the measurement and one red test about it.
    ///
    /// A parameter with an empty default rather than a fixture applied to
    /// everything, because the other two ratchets built on this render carry
    /// recorded numbers of their own: what a seed does to a *radius* count is a
    /// separate measurement, taken by whoever wants it.
    typealias Seed = (String, NamespacedStore) -> Void

    static func page(for descriptor: any ModuleDescriptor, in appearance: NSAppearance.Name,
                     width: CGFloat, seededBy seed: Seed = { _, _ in },
                     wiredBy wire: Wiring = answering) -> Page {
        let id = type(of: descriptor).id.rawValue
        let store = NamespacedStore(namespace: id, backing: InMemoryKeyValueStore())
        // Before the engine and before the page: both read the store as they are
        // built, which is what a page opened on somebody's existing settings does.
        seed(id, store)
        // Built for its type and its lifetime, and never asked anything: the
        // module's *own* engine plays no part in what the page sees. What the page
        // sees is the fixture, which is on the wire before the view model
        // subscribes — the state a page opened during a running session finds
        // waiting for it. The store is in memory, so nothing here reaches
        // `UserDefaults.standard`.
        let engine = descriptor.makeEngine(store: store)
        let transport = FixtureTransport(wire(id))
        let viewModel = ModuleViewModel(transport: transport)
        let view = NSHostingView(rootView: descriptor.settingsPage(viewModel).frame(width: width))
        view.frame = NSRect(x: 0, y: 0, width: width, height: pageHeight)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled],
                              backing: .buffered, defer: false)
        // Both, and neither is redundant: the window's appearance is what the
        // hosting view's environment resolves against, and the view's own is what
        // a layer drawn by AppKit inside it reads. Pinned before the content is
        // installed, so nothing is laid out twice.
        window.appearance = NSAppearance(named: appearance)
        view.appearance = NSAppearance(named: appearance)
        window.contentView = view
        settle(view)
        return Page(id: id, layers: layers(of: view), controls: controls(of: view, module: id),
                    transport: transport, keepAlive: [engine, viewModel, view, window])
    }

    /// Pump the run loop until the drawn tree has stopped moving for twelve
    /// turns running.
    ///
    /// The signature is every layer's frame and radius, not the layer count: a
    /// page whose rows have settled their count while their geometry is still
    /// resolving answers differently the next time it is asked, and that is the
    /// state three of these pages were caught in.
    private static func settle(_ view: NSView) {
        var previous = ""
        var same = 0
        for _ in 0..<120 {
            view.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            let now = signature(of: view)
            same = now == previous ? same + 1 : 0
            previous = now
            if same >= 12 { return }
        }
    }

    private static func signature(of view: NSView) -> String {
        guard let root = view.layer else { return "" }
        var out = ""
        func walk(_ layer: CALayer) {
            let frame = root.convert(layer.bounds, from: layer)
            out += "\(frame.origin.x),\(frame.origin.y),\(frame.width),\(frame.height)"
            out += ",\(layer.cornerRadius);"
            for sub in layer.sublayers ?? [] { walk(sub) }
        }
        walk(root)
        return out
    }

    private static func layers(of view: NSView) -> [Drawn] {
        guard let root = view.layer else { return [] }
        var out: [Drawn] = []
        func walk(_ layer: CALayer, owner: String) {
            let mine = (layer.delegate as? NSView).map { String(describing: type(of: $0)) } ?? owner
            out.append(Drawn(frame: root.convert(layer.bounds, from: layer),
                             radius: layer.cornerRadius,
                             hasContents: layer.contents != nil,
                             owner: mine))
            for sub in layer.sublayers ?? [] { walk(sub, owner: mine) }
        }
        walk(root, owner: String(describing: type(of: view)))
        return out
    }

    private static func controls(of view: NSView, module: String) -> [Control] {
        var out: [Control] = []
        func walk(_ subject: NSView) {
            let name = String(describing: type(of: subject))
            // The innermost of the three views AppKit stacks per control: the
            // platform host, the SwiftUI shim, and this. Counting all three
            // reports one squeezed segmented control as three.
            if name.hasPrefix("_NSCoreHostingView<AppKit") {
                out.append(Control(module: module, name: name, frame: subject.frame,
                                   intrinsic: subject.intrinsicContentSize))
            }
            subject.subviews.forEach(walk)
        }
        walk(view)
        return out
    }
}

extension ModulePageRender.Page {

    /// The floor every ratchet built on this asserts first.
    ///
    /// A run with no window server draws nothing, and the count of off-ladder
    /// anything is then zero — which passes a `lessThanOrEqual` ratchet for ever
    /// while measuring an empty bitmap. An assertion about an absence passes
    /// when the subject never happened, so each page says how much it drew
    /// before anybody counts what is wrong with it.
    ///
    /// The floors are per module and measured: the thinnest page draws nine
    /// layers and the richest nearly three hundred, and a page that has lost its
    /// own content should say so rather than sit under one shared number chosen
    /// for the emptiest of them.
    /// - Parameter atLeast: a floor for this reading rather than the module's own.
    ///   The table below is what a page draws **wired**, which is what every
    ///   ratchet renders; a test that deliberately renders one `unwired` is
    ///   measuring a different screen and has to say which floor it means, or it
    ///   fails a guard about content while proving the point of the guard.
    func assertItDrewSomething(atLeast: Int? = nil,
                               file: StaticString = #filePath, line: UInt = #line) {
        let floor = atLeast ?? Self.floors[id] ?? 9
        XCTAssertGreaterThanOrEqual(layers.count, floor, """
            \(id) drew \(layers.count) layers where it drew at least \(floor) when this was \
            measured. Either the page has lost its content or nothing rendered at all — and in \
            the second case every count taken from this page is zero by default.
            """, file: file, line: line)
    }

    /// Measured 2026-08-11 over two runs in each of the eight languages —
    /// sixteen readings a page — and set below the lowest of them, so a page
    /// that legitimately loses a row does not fail a test about ladders.
    ///
    /// **Disk's is low on purpose, and it is the exception worth naming.** 49,
    /// 129, 170, 172 and 50 layers were all measured on this Mac in one
    /// afternoon, and the reason is not the one written here first. The volume
    /// list *does* come through the transport (`DiskCommand.volumes`), and no
    /// fixture answers it, so it is empty and the same on every Mac — and it must
    /// stay that way: a fixture of volumes here would be inventing hardware.
    /// What is not the same on every Mac is
    /// the **person's last scan**: `DiskSettingsPage` builds its view model
    /// through `DiskViewModel.shared(vm:)`, which has no store parameter, so
    /// `restoreLastScan()` reads `~/Library/Application Support/Helm/Disk/last-scan.json`
    /// — 8 MB here — on a detached task that races `settle`. 172 layers at
    /// 17:59:50 and 50 at 17:59:59, one commit, nine seconds apart; and the
    /// dependence switched itself off at 18:00:41, which is 86 400 s after the
    /// scan that wrote the file. `TheSuiteDoesNotReadTheUsersLastScanTests` is
    /// the guard and carries the seam that ends it. Until that lands the floor
    /// here asks only whether the page drew at all, which is the question this
    /// guard exists for.
    ///
    /// **VPN's is 190, and it has been 45 and 160 in one day.** 160 was the page a
    /// Mac with no VPN was shown before 2026-08-12 — 800 pt of automation for
    /// events that cannot happen. 45 was the empty state that correctly replaced
    /// it, drawn because connections arrive as an **event** and this render
    /// answered nothing: 55 layers in light, 58 in dark, and three cards measured
    /// by nobody. 190 is the page with `Wire.answering` in it — **211 in light and
    /// 214 in dark unseeded, 247 seeded, identical in all eight languages, three
    /// consecutive runs each, measured 2026-08-12** — set a card's worth below the
    /// lowest of those. The fixture is fixed, so a reading that falls is a page
    /// that changed and not a Mac that differs, and this floor can afford to be
    /// tight: the empty state is 55, so losing the wire fails by 135.
    ///
    /// **Homebrew's is 70 for the same reason and a smaller number.**
    /// `HomebrewSettingsPage.body` branches on `hb.status.installed`, which is a
    /// *reply*, so every reading before the fixture was of the «not installed»
    /// screen: 12 layers in both appearances, on a Mac that has brew. Wired it is
    /// **79 in light and 80 in dark, all eight languages, three consecutive
    /// runs**, and the four fixture packages are about 12 layers a row — so 70
    /// says «the manager screen, with at most one row missing» and 12 fails it by
    /// a mile.
    ///
    /// **Layout's stays 230, and that is a decision rather than an oversight.**
    /// Its wire is fixtured too, but a `LayoutState` is worth only 20 layers there
    /// (275 → 295 in light, 278 → 298 in dark, three runs) and this page carries a
    /// permission note that depends on the **machine**: `AXIsProcessTrusted()` is
    /// false in this test process, so the note is drawn here and would not be on a
    /// Mac whose terminal holds Accessibility. A floor placed in a 20-layer band
    /// under a 45-layer machine dependence is a red CI for somebody else's grant.
    /// What arrives over Layout's wire is guarded by comparison instead, in
    /// `TheWireFixtureReachesThePagesTests`, where both sides are rendered in the
    /// same process and the machine cancels out.
    static let floors: [String: Int] = [
        "keep-awake": 250, "vpn": 190, "uninstaller": 45, "homebrew": 70,
        "leftovers": 25, "disk": 40, "duplicates": 12, "autopilot": 12, "layout": 230,
    ]
}
