import AppKit
import HelmRuntime
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// Every module page, drawn offscreen, as measurements rather than pictures.
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
        /// The view model the page was built on, so a test can ask what the page's
        /// *own* module model is holding rather than infer it from layer counts.
        /// A module's model reached through `<Module>ViewModel.shared(vm:)` with
        /// this is the same object the page draws — and asking a fresh one instead
        /// fails a precondition (`scanned` is false on a model nobody scanned),
        /// which is the direction a wrong assumption should fail in.
        let viewModel: ModuleViewModel
        /// The hosting view the page was drawn into, for the questions a layer
        /// walk cannot answer. Hit testing is one: which view a scroll wheel
        /// would be delivered to is a fact about the AppKit tree and shows up
        /// in no bitmap (`ThePaneTakesTheWheelAtItsEdgesTests`).
        let host: NSView
        /// Held so the objects behind the measurement outlive it.
        private let keepAlive: [AnyObject]

        init(id: String, layers: [Drawn], controls: [Control],
             transport: FixtureTransport, viewModel: ModuleViewModel,
             host: NSView, keepAlive: [AnyObject]) {
            self.id = id
            self.layers = layers
            self.controls = controls
            self.transport = transport
            self.viewModel = viewModel
            self.host = host
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
                      wiredBy wire: Wiring = answering,
                      primedBy prime: Priming = opened,
                      granting grants: HelmGrants = granted) -> [Page] {
        ModuleRegistry.all.map {
            page(for: $0, in: appearance, width: width,
                 seededBy: seed, wiredBy: wire, primedBy: prime, granting: grants)
        }
    }

    /// **The grants a reading is taken under, and the third weather this render
    /// had.** The first two were the appearance and the wire; this is the
    /// permission held by the process running the suite.
    ///
    /// It used to cost 45 layers — a `HelmPermissionNote` banner on the Keyboard
    /// page, drawn here because `AXIsProcessTrusted()` is false in a test process
    /// and not drawn on a Mac whose terminal holds the grant. It costs the whole
    /// page now: Keyboard replaced that banner with an empty state, correctly —
    /// 1867 pt of settings macOS ignores is not a page anybody should be shown —
    /// so an ungranted reading of it is 95 layers and a granted one is the module.
    /// Every ratchet built on this render would have become a fact about
    /// somebody's terminal, and `floors["layout"]` said as much before it could.
    ///
    /// Granted is the default, because the configured page is the one worth
    /// measuring, for the same reason `Seed` exists: a page drawn against an
    /// empty store draws a page nobody has. What it costs is stated plainly — the
    /// *withheld* screen is measured by nothing here unless a test asks for it,
    /// which is what `granting:` is for, and `TheKeyboardPageWithoutTheGrantTests`
    /// is the test that asks.
    /// **Both grants, because there were two weathers here and only one had been
    /// named.** `HelmGrants` knew `accessibility` alone, so Full Disk Access went
    /// on being asked of the process running the suite — and five pages draw a
    /// 61 pt banner off that answer (72 in French, where the sentence wraps and
    /// moves the list under it). A terminal that holds the grant and one that does
    /// not read three of these pages eight layers apart.
    ///
    /// Naming it granted lowered `floors` for the three pages whose recorded
    /// reading had that banner in it — see the note there. The withheld screen is
    /// measured by `PagesAreToldAboutTheDiskGrantTests`, the way the
    /// withheld Accessibility screen is measured by
    /// `TheKeyboardPageWithoutTheGrantTests`.
    static let granted = HelmGrants(accessibility: .granted, fullDisk: .granted)
    static let withheld = HelmGrants(accessibility: .denied, fullDisk: .denied)

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

    /// The question a page's own screen would have asked, for the pages that ask
    /// one — and nil for the eight that do not.
    ///
    /// **The wire is not enough on its own for a page nobody presses.** `Seed` is
    /// what a person has configured and `Wiring` is what their engine has already
    /// said; both arrive before the page is built. A page whose content comes from a
    /// *reply* has a third requirement, and Leftovers is the module that makes it
    /// visible: nothing calls `LeftoversViewModel.scan()` — not `.task`, not
    /// `onAppear` — so a fixture answering `LeftoversCommand.scan` reaches a page
    /// that never asks, and the render stays on the invitation whatever the table
    /// holds. That the module does not scan by itself is a decision with a reason
    /// (the only measurement of an auto-scan's cost runs against the owner's real
    /// home directory), so the harness presses the button instead of the module
    /// growing one.
    ///
    /// The work is `async` because every one of these is a request over a
    /// transport, and it is run to completion before the page is measured —
    /// `drive` below is what waits, by pumping the run loop rather than by
    /// sleeping, for the same reason `settle` does.
    typealias Priming = (String, ModuleViewModel) -> (@MainActor () async -> Void)?

    /// No page is asked anything: the harness as it was before the priming, kept
    /// for the same reason `unwired` is — every guard on the fixture is a
    /// comparison, and one side of it has to be the page that was never pressed.
    static let unprimed: Priming = { _, _ in nil }

    static func page(for descriptor: any ModuleDescriptor, in appearance: NSAppearance.Name,
                     width: CGFloat, seededBy seed: Seed = { _, _ in },
                     wiredBy wire: Wiring = answering,
                     primedBy prime: Priming = opened,
                     granting grants: HelmGrants = granted) -> Page {
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
        let view = NSHostingView(rootView: descriptor.settingsPage(viewModel)
            .frame(width: width)
            // Named, not inherited: see `granted` above. Nil inside would mean
            // «ask this Mac», which is the dependence this parameter removes.
            .environment(\.helmGrants, grants)
            // This window never orders in and the page must draw anyway —
            // without the declaration `helmIdlesOffScreen` (which every
            // settings page carries) unmounts the content of an off-screen
            // window, and every reading here would read an empty pane.
            .helmMeasuringBench())
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
        // Before the settling, and after the window: the work is a request whose
        // reply changes the tree, so `settle` has to be measuring the page that
        // holds the answer rather than the one still waiting for it.
        if let work = prime(id, viewModel) { drive(work, in: view) }
        settle(view)
        return Page(id: id, layers: layers(of: view), controls: controls(of: view, module: id),
                    transport: transport, viewModel: viewModel, host: view,
                    keepAlive: [engine, viewModel, view, window])
    }

    /// What a page drawn by the shell itself came to — the log, the general page,
    /// about. No module, no store and no wire, so none of `page(for:)`'s three
    /// weathers apply; the appearance still does, and is still named.
    struct Shell {
        /// The pane it was drawn at, so a reading carries the width it is about:
        /// every question asked of these layers — what is past the inset, what is
        /// a full-width rule — is a question about the pane.
        let width: CGFloat
        let layers: [Drawn]
        /// Held so the objects behind the measurement outlive it.
        private let keepAlive: [AnyObject]

        init(width: CGFloat, layers: [Drawn], keepAlive: [AnyObject]) {
            self.width = width
            self.layers = layers
            self.keepAlive = keepAlive
        }
    }

    /// The same host, settling and layer walk as a module page, for a view that
    /// is not one. Written rather than repeated: `settle` is the part that must
    /// not be re-derived, and a hand-rolled pump beside it is how two readings of
    /// the same window come to disagree.
    static func drawn(_ view: some View, in appearance: NSAppearance.Name,
                      width: CGFloat, height: CGFloat = pageHeight) -> Shell {
        // The same measuring-bench declaration as `page(for:)`, same reason.
        let host = NSHostingView(rootView: view.frame(width: width)
            .helmMeasuringBench())
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        host.appearance = NSAppearance(named: appearance)
        window.contentView = host
        settle(host)
        return Shell(width: width, layers: layers(of: host), keepAlive: [host, window])
    }

    /// A flag two isolated contexts share: the priming's task sets it, the pump
    /// below reads it. Both are the main actor, so this is a hand-off and never a
    /// race — spelled as a type so the compiler agrees.
    @MainActor private final class Turn { var finished = false }

    /// Run a page's opening question to completion, pumping the run loop the way
    /// `settle` does.
    ///
    /// **Bounded, and silent about running out.** A priming that never finishes
    /// leaves the page holding what it held before, which is the empty state — and
    /// that is caught where it should be, by `assertItDrewSomething` and by the
    /// structural guards in `TheWireFixtureReachesThePagesTests`, rather than by a
    /// message from inside the harness that no test is reading. 300 turns of 0.01 s
    /// against a fixture that answers from a table: the leftovers priming, which is
    /// two requests and two rescans, finishes in single digits.
    private static func drive(_ work: @MainActor @escaping () async -> Void, in view: NSView) {
        let turn = Turn()
        Task { @MainActor in
            await work()
            turn.finished = true
        }
        var turns = 0
        while !turn.finished, turns < 300 {
            turns += 1
            view.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }

    /// Pump the run loop until the drawn tree has stopped moving for twelve
    /// turns running.
    ///
    /// The signature is every layer's frame and radius, not the layer count: a
    /// page whose rows have settled their count while their geometry is still
    /// resolving answers differently the next time it is asked, and that is the
    /// state three of these pages were caught in.
    ///
    /// **And its opacity, which this was blind to.** A view SwiftUI is fading out
    /// keeps its frame for the whole 0.3 s of the fade, so the signature was
    /// already steady while a departing subtree was still in the tree — and
    /// `layers(of:)` counts it. Measured on the leftovers page, whose invitation
    /// gives way to a list: the same page read 233 layers in one render and 246 in
    /// the next, the thirteen being an empty state that was on its way out, and the
    /// comparison in `PagesAreToldAboutTheDiskGrantTests` — where the difference is
    /// supposed to be a permission banner and nothing else — came out even. A page
    /// that is still fading has not settled.
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
            out += ",\(layer.cornerRadius),\(layer.presentation()?.opacity ?? layer.opacity);"
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
        // The innermost of the three views AppKit stacks per control: the
        // platform host, the SwiftUI shim, and this. Counting all three reports
        // one squeezed segmented control as three. A prefix rather than
        // `everyView(named:)`, because the name is a generic and carries its
        // argument.
        view.everyView.filter { $0.appKitClassName.hasPrefix("_NSCoreHostingView<AppKit") }
            .map { Control(module: module, name: $0.appKitClassName, frame: $0.frame,
                           intrinsic: $0.intrinsicContentSize) }
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
    /// **Layout's stays 230, and the reason it stays is no longer the reason it
    /// was set.** It was set loose because the page carried a permission note
    /// whose presence depended on the **machine** — `AXIsProcessTrusted()` is
    /// false in this test process — and a floor 20 layers under a 45-layer
    /// machine dependence is a red CI for somebody else's grant. That dependence
    /// is gone: `granting:` names the grant, so this reading is the page a person
    /// who has granted Accessibility sees, on every Mac. The page is **276 layers
    /// in light and 279 in dark, three consecutive runs each, measured
    /// 2026-08-12**, and 95/98 with the grant withheld — the empty state that
    /// replaced 1867 pt of dead settings, measured by
    /// `TheKeyboardPageWithoutTheGrantTests`.
    ///
    /// 230 is a card's worth under the granted reading and well over twice the
    /// withheld one, so a page that has quietly fallen back to the empty state
    /// fails here by 135. What arrives over Layout's *wire* is still guarded by
    /// comparison in `TheWireFixtureReachesThePagesTests` rather than by this
    /// number: a `LayoutState` is worth about 20 layers, which is finer than any
    /// floor should try to resolve.
    /// **Three of these fell when the disk grant was named, and the eight layers
    /// they lost were never theirs.** `granted` above says why: until 2026-08-13
    /// this render asked the machine about Full Disk Access, this test process has
    /// not got it, so the recorded readings for the five pages that draw that
    /// banner each carried a notice a Mac with the grant does not draw. Measured
    /// after naming it, both appearances, three consecutive runs: **leftovers 24,
    /// duplicates 9, autopilot 9** — against 32, 17 and 17 with the banner, which
    /// is the same eight layers three times. Disk (42/43) and the uninstaller
    /// (48/49) stayed above their floors and are untouched.
    ///
    /// Duplicates' and Autopilot's 8 is not slack, it is the whole page: both draw
    /// an empty state until a folder is chosen, and the question their floor can
    /// answer is «did anything render at all». Duplicates has a fixture now, and
    /// its 8 stays anyway, because the folder is the **store's** half: this table
    /// is what a page draws wired but unseeded, which for that module is still
    /// the empty state. The configured page — seed, wire and three presses,
    /// ending on the removal — is **238 layers, nine readings across three suite
    /// launches, measured 2026-08-16** (228 while the press stopped short of the
    /// removal), and `TheWireFixtureReachesThePagesTests` carries its floor of
    /// 210 beside the structural guards, the way the leftovers press is guarded.
    ///
    /// **Leftovers is 210 from 2026-08-13, and it has been 24 and 28 in one day.**
    /// 24 was the invitation before it gained a verb; 28 the same invitation with the
    /// prominent button in it. Both were the *unscanned* page, because this module's
    /// whole screen is the answer to `LeftoversCommand.scan` and nothing asks for it
    /// by itself — so the fixture is two parts, a table (`answering`) and a press
    /// (`opened`), and the page with both reads **233 layers in light and 238 in
    /// dark, identical in all eight languages, three consecutive runs, measured
    /// 2026-08-13**: seven rows in five sections, a ticked selection, and the report
    /// of a partly-failed removal above the bar.
    ///
    /// 210 is a section's worth under the lowest of those. Losing the press or the
    /// table fails it by about 200, because the page without either is **12** — a
    /// wire that refuses, which this module reads as «nothing found», and the
    /// invitation both measure that since 2026-08-14. They were 23 and 28: a page
    /// with nothing on it drew a second Scan in the toolbar beside the invitation's
    /// own, and a bar of three buttons with nothing to select or move.
    /// **VPN is 100 from 2026-08-17, and it was 190 that morning.** Not a page
    /// that lost its content: the rules, the notices and the ring's two colours
    /// were three sections and about 800 pt of page, and they are two popovers on
    /// the card that owns them now — a popover is a window macOS orders in, so
    /// nothing it holds is in this render at all. Measured in two steps as they
    /// moved: 139 light / 142 dark with the rules and notices behind doors, then
    /// **116 light and 119 dark with the wire alone, 121 and 124 with the store
    /// seeded too, two consecutive runs of each** once the colours followed them.
    /// 100 is a card's worth under the lowest of those, and the page with no wire
    /// is 55 — which is what `TheWireFixtureReachesThePagesTests` holds the
    /// difference against.
    /// **And 124 from 2026-08-18, because the page grew a section the fixture had
    /// been withholding.** `VPNSettingsPage` draws its tunnel strip behind
    /// `if let facts`, and `ModulePageFixtures` carried no `facts:` — so the
    /// tile strip, its four wells and the verdict line under them were in no
    /// reading of this render, on a page whose floor of 100 would not have
    /// noticed them leaving either. With the tunnel in the fixture the page is
    /// **140 layers in light and 143 in dark with the wire alone, 145 and 148
    /// with the store seeded too — identical in all eight languages, three
    /// consecutive runs of each**, against 116/119 and 121/124 without it: the
    /// strip is 24 layers wherever it is measured.
    ///
    /// 124 is a card's worth (16, by this page's own arithmetic above) under the
    /// lowest of those, and it is the first floor here that the strip can fail:
    /// the page without it draws 116, which misses by eight. That is the whole
    /// reason the number moves — a floor of 100 would have gone on passing with
    /// the section gone.
    /// **Hosts carried 1 until its page landed, and 1 was never a measurement of
    /// a page** — it was the mark of a module whose `HostsSettingsPage` was an
    /// `EmptyView` while the module was built up task by task. The entry was
    /// removed rather than raised the day the page arrived, so the module falls
    /// back to the default floor of 9 and is measured like the rest: a real page
    /// under a floor of 1 is a page whose content can vanish entirely with
    /// nothing going red, which is the failure this floor exists to prevent.
    /// **Layout fell from 230 to 197 when two sections were cut**, and the
    /// number moved because the page really is smaller: «When to fix» (three
    /// switches, a heading and two footnotes) and «Abbreviations» (a list, two
    /// text fields, a button and an empty state) both went, along with the
    /// header's metric control. 197 is a card's worth under the 213 the page
    /// now draws, by the same arithmetic VPN's 124 uses — so the floor can
    /// still fail on a section disappearing rather than passing whatever is
    /// left. Lowered on the measurement, not to make a red test green.
    static let floors: [String: Int] = [
        "keep-awake": 250, "vpn": 124, "uninstaller": 45, "homebrew": 70,
        "leftovers": 210, "disk": 40, "duplicates": 8, "autopilot": 8, "layout": 197,
    ]
}
