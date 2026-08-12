import AppKit
import HelmContract
import HelmRuntime
import Module_KeepAwake_Engine
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
/// **The engines are built and never activated, and they never answer.**
/// `activate()` is where a module reaches the machine — Layout installs a
/// `CGEvent` tap — and a measurement has no business doing that. Beyond that,
/// every page is drawn against `SilentTransport`, so what is measured is the
/// page before any engine has replied: the screen every module shows at first
/// launch. That is less than a module shows in use, and it is the only state
/// that is the same on every Mac. With the real transport, Homebrew's page grew
/// from 12 layers to 681 — this machine's package list — and the numbers in the
/// ratchets would then have been a fact about this Mac's software, which is the
/// measurement that is a report and not a gate.
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
        /// Held so the objects behind the measurement outlive it.
        private let keepAlive: [AnyObject]

        init(id: String, layers: [Drawn], controls: [Control], keepAlive: [AnyObject]) {
            self.id = id
            self.layers = layers
            self.controls = controls
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
                      seededBy seed: Seed = { _, _ in }) -> [Page] {
        ModuleRegistry.all.map { page(for: $0, in: appearance, width: width, seededBy: seed) }
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
                     width: CGFloat, seededBy seed: Seed = { _, _ in }) -> Page {
        let id = type(of: descriptor).id.rawValue
        let store = NamespacedStore(namespace: id, backing: InMemoryKeyValueStore())
        // Before the engine and before the page: both read the store as they are
        // built, which is what a page opened on somebody's existing settings does.
        seed(id, store)
        // Built for its type and its lifetime, never asked anything: the page is
        // drawn against `SilentTransport`. The store is in memory, so nothing
        // here reaches `UserDefaults.standard`.
        let engine = descriptor.makeEngine(store: store)
        let viewModel = ModuleViewModel(transport: SilentTransport())
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
                    keepAlive: [engine, viewModel, view, window])
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
    func assertItDrewSomething(file: StaticString = #filePath, line: UInt = #line) {
        let floor = Self.floors[id] ?? 9
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
    /// list *does* come through the transport (`DiskCommand.volumes`), so under
    /// `SilentTransport` it is empty and the same on every Mac. What is not is
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
    /// **VPN's is 45 because its page got shorter on purpose, and the number
    /// that fell says something this render cannot otherwise see.** It drew 160+
    /// layers here only because a Mac with no VPN configured was shown 800 pt of
    /// settings for events that cannot happen — a rules card, a notice card and a
    /// spin card under an empty state. Those are behind `connections.isEmpty`
    /// now, and `SilentTransport` never sends connections, so what this render
    /// reads is the empty state: 55 layers in light and 58 in dark, identical in
    /// all eight languages, measured 2026-08-12.
    ///
    /// The rest of that page is therefore measured by nothing here, and the
    /// connections grid never was: connections arrive as an **event**, and the
    /// `Seed` above only reaches the store. A fixture for the wire — one state
    /// payload, then the same silence — is what would give this page back to all
    /// three ratchets built on this render.
    static let floors: [String: Int] = [
        "keep-awake": 250, "vpn": 45, "uninstaller": 45, "homebrew": 10,
        "leftovers": 25, "disk": 40, "duplicates": 12, "autopilot": 12, "layout": 230,
    ]
}

extension ModulePageRender {

    /// The rows a person has, for the modules whose pages hide their widest
    /// controls until something is configured.
    ///
    /// Keep Awake is the one written so far, because it is the one that was
    /// measured: three shapes of control were in none of the 72 renders — the
    /// per-app rule rows, the condition pop-up each of them carries, and the
    /// battery floor's slider under its own figure. What the page drew instead was
    /// the empty state's single prominent button.
    ///
    /// **Bundle ids that resolve to nothing, on purpose.** `AppInfo.resolve` falls
    /// back to the id itself for an app this Mac does not have, so the row's name
    /// is the fixture's own string rather than a fact about what is installed —
    /// and the icon is the system's generic bundle icon rather than somebody's
    /// software. A real id would make these numbers a measurement of this machine,
    /// which is the thing `SilentTransport` exists to avoid one line up.
    ///
    /// Two rules, not one: a list is what the page draws differently from an empty
    /// state, and the second row is where the «Add app…» line at the foot of the
    /// list appears.
    static let configured: Seed = { id, store in
        guard id == KeepAwakeEngine.moduleID else { return }
        let settings = KeepAwakeSettings(store: store)
        settings.setAppTriggers([
            AppTrigger(bundleID: "com.example.render", needsPower: true),
            AppTrigger(bundleID: "com.example.conference", needsExternalDisplay: true),
        ])
        // The two rule rows switched on, so their notes and marks are drawn as
        // well as their switches, and the mark column exists at all.
        settings.setAutoExternalDisplay(true)
        settings.setAutoPower(true)
        // The floor's own row carries the figure beside the slider, and the note
        // under it is only drawn with the guard armed.
        settings.setBatteryGuardEnabled(true)
        settings.setBatteryGuardPercent(45)
        // The interval pop-up beside «Move the pointer» is disabled until this is
        // on — a disabled control is still measured, but a page with it off is not
        // a page anybody has once they have asked for the feature.
        settings.setJiggleEnabled(true)
        settings.setJiggleIntervalMinutes(30)
        settings.setDefaultDurationMinutes(120)
    }
}

/// A transport that never answers.
///
/// Not a convenience: a fake that answers *instantly* is the shape that makes a
/// test of a wait vacuous, and one that answers out of the machine makes a
/// measurement a fact about the machine. This one refuses — the state every
/// module is in between its page opening and its first reply — and its event
/// stream never finishes, which is what the real one does too.
final class SilentTransport: EngineTransport, @unchecked Sendable {
    func send(_ command: EngineCommand) async throws -> Data { throw CancellationError() }
    let events: AsyncStream<EngineEvent> = AsyncStream { _ in }
}
