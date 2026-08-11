import AppKit
import HelmContract
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
    static func pages(width: CGFloat = pageWidth) -> [Page] {
        ModuleRegistry.all.map { page(for: $0, width: width) }
    }

    static func page(for descriptor: any ModuleDescriptor, width: CGFloat) -> Page {
        let id = type(of: descriptor).id.rawValue
        let store = NamespacedStore(namespace: id, backing: InMemoryKeyValueStore())
        // Built for its type and its lifetime, never asked anything: the page is
        // drawn against `SilentTransport`. The store is in memory, so nothing
        // here reaches `UserDefaults.standard`.
        let engine = descriptor.makeEngine(store: store)
        let viewModel = ModuleViewModel(transport: SilentTransport())
        let view = NSHostingView(rootView: descriptor.settingsPage(viewModel).frame(width: width))
        view.frame = NSRect(x: 0, y: 0, width: width, height: pageHeight)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled],
                              backing: .buffered, defer: false)
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
    /// **Disk's is low on purpose, and it is the exception worth naming.** Its
    /// page enumerates this Mac's mounted volumes from a `.task`, so what it
    /// draws is a fact about the machine and about when the answer arrives: 49,
    /// 129 and 170 layers were all measured on this Mac in one afternoon. The
    /// floor there asks only whether the page drew at all, which is the question
    /// this guard exists for; the volume list is out of every ratchet's reach by
    /// construction, since a Mac with an external drive would draw more of it.
    static let floors: [String: Int] = [
        "keep-awake": 250, "vpn": 160, "uninstaller": 45, "homebrew": 10,
        "leftovers": 25, "disk": 40, "duplicates": 12, "autopilot": 12, "layout": 230,
    ]
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
