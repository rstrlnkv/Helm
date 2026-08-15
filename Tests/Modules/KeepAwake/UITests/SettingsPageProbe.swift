import AppKit
import HelmContract
import HelmRuntime
import HelmUI
import SwiftUI
@testable import Module_KeepAwake_Engine
@testable import Module_KeepAwake_UI

/// The Keep Awake settings page, mounted in a window and read as pixels.
///
/// Three of this module's checks ask the same question — the engine says
/// something and does the page draw it — and each needs the same four things: a
/// transport to emit the engine's own payload on, a store of its own, a window
/// with turns of the run loop in it (a notice is *grown*, so it takes 300 ms to
/// arrive), and a way to count ink. Written out per file that was three copies of
/// a harness born in one change, which is the shape this house pays for twice.
///
/// **Not alpha, and that is a fact about pages rather than a preference.** The
/// other render checks in this module measure the alpha channel, because what
/// they mount is a view with nothing behind it. A grouped `Form` in a window
/// paints an opaque pane, so alpha is 255 at every pixel of it: the first version
/// of the battery check read `151776000` for the page with the notice, for the
/// page without it, and for a floor of 45 % against one of 5 % — one number,
/// three times, which is a check that cannot fail dressed as a measurement. Ink
/// on an opaque pane is a difference in **colour**.
@MainActor
final class SettingsPageProbe {

    /// What one still says, in the three terms these checks are written in.
    struct Ink {
        /// Colour mass — every channel of every pixel. Any difference at all.
        let mass: Int
        /// Pixels in the warning signal, which is what a `HelmBanner` is made of:
        /// a field at 13 % of it and a mark drawn in it. A page with no notice is
        /// neutral, so this counts the thing that arrives rather than «something
        /// changed», which any redraw would satisfy.
        let warning: Int
        /// Pixels in the success signal — a green tick in the mark column.
        let success: Int
    }

    let transport = LocalTransport()
    let store: NamespacedStore
    private var host: NSHostingView<AnyView>?
    private var window: NSWindow?

    init(store: NamespacedStore = NamespacedStore(namespace: KeepAwakeEngine.moduleID,
                                                 backing: InMemoryKeyValueStore())) {
        self.store = store
    }

    /// Mounts the real page and answers its view model.
    ///
    /// 810 pt wide, which is the settings pane's own width; the height is the
    /// caller's, since what has to be inside the frame differs per check.
    func mount(height: CGFloat = 900) -> KeepAwakeViewModel {
        let vm = ModuleViewModel(transport: transport)
        // This window never orders in, and a page that idles off screen
        // (`helmIdlesOffScreen`) would hand every reading an empty pane.
        let view = NSHostingView(rootView: AnyView(KeepAwakeSettingsPage(vm: vm, store: store)
            .helmMeasuringBench()))
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 810, height: height),
                             styleMask: [.titled], backing: .buffered, defer: false)
        panel.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: 810, height: height)
        panel.layoutIfNeeded()
        host = view
        window = panel
        settle()
        return KeepAwakeViewModel.shared(vm: vm)
    }

    /// Every test that mounts one calls this in its teardown: the window holds
    /// the page, and the page holds a view model with a task in it.
    func unmount() {
        window?.contentView = nil
        window = nil
        host = nil
    }

    /// Exactly what the engine emits — its own payload, encoded, under its own
    /// event name. A dictionary built in a test would be a second declaration of
    /// the wire and would go on passing after the real one changed.
    func deliver(_ payload: KeepAwakeEngine.StatePayload) -> Bool {
        guard let data = try? JSONEncoder().encode(payload) else { return false }
        transport.emit(EngineEvent(name: KeepAwakeEvent.state.rawValue, payload: data))
        settle()
        return true
    }

    /// Turns of the run loop, because a height that animates is a height that
    /// takes 300 ms to arrive.
    func settle(_ turns: Int = 60) {
        for _ in 0..<turns {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    /// One settled still, down to `depth` points of the page — `nil` when nothing
    /// drew at all, which is a machine with no window server rather than a
    /// failure.
    func read(depth: Int? = nil) -> Ink? {
        guard let host, let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            return nil
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.bitmapData, rep.samplesPerPixel == 4 else { return nil }
        let scale = max(1, rep.pixelsHigh / max(1, Int(host.bounds.height)))
        let rows = depth.map { min(rep.pixelsHigh, $0 * scale) } ?? rep.pixelsHigh
        var mass = 0, warning = 0, success = 0
        for y in 0..<rows {
            for x in 0..<rep.pixelsWide {
                let at = y * rep.bytesPerRow + x * 4
                let r = Int(data[at]), g = Int(data[at + 1]), b = Int(data[at + 2])
                mass += r + g + b
                // Orange in either appearance: red well ahead of blue, green in
                // between. A grey is r == g == b, and antialiased text on a grey
                // pane stays grey.
                if r - b > 8, r > g, g > b { warning += 1 }
                if g - r > 20, g > b { success += 1 }
            }
        }
        guard mass > 0 else { return nil }
        return Ink(mass: mass, warning: warning, success: success)
    }
}
