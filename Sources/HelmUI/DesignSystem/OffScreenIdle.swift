// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI
import AppKit

/// Unmounts a subtree while the window holding it is off screen.
///
/// A mounted SwiftUI tree pays for every published change whether or not
/// anybody can see it, and most of the cost is kept: each environment write
/// chains a new element into SwiftUI's attribute graph that cannot be freed
/// while the tree lives, so a page that publishes steadily grows the heap
/// steadily. Detaching the hosting view from its window does not stop it, since
/// the graph lives in the `NSHostingView`. Unmounting the subtree does: while
/// the window is off screen the content is out of the hierarchy, and it is
/// rebuilt from the view model's current state when the window returns. The
/// view model keeps its subscription, so the menu-bar surfaces that read it
/// keep hearing.
///
/// A view with no window at all counts as seen, so offscreen render harnesses
/// still draw. A harness whose window exists but never shows declares itself
/// with `helmMeasuringBench()`.
private struct OffScreenIdle: ViewModifier {
    @Environment(\.helmTreatsWindowAsSeen) private var bench
    /// Starts `true` and is corrected by the reader: a subtree mounted into a
    /// window that is already on screen (switching pages in open Settings)
    /// must not blank a frame waiting for a notification to say so.
    @State private var seen = true

    @ViewBuilder
    func body(content: Content) -> some View {
        if bench {
            // No reader either: a bench needs no window watching, and
            // `ImageRenderer` — which one geometry probe draws through —
            // renders a subtree holding any `NSViewRepresentable` as
            // transparent, which reads as ink at x = 0 to a pixel walk.
            content
        } else {
            ZStack {
                // Always mounted, so the change back to visible has a listener.
                WindowSeenReader(seen: $seen)
                if seen {
                    content
                }
            }
        }
    }
}

extension View {
    /// The subtree is unmounted while its window is off screen, and rebuilt
    /// from current state when the window returns. See `OffScreenIdle`.
    public func helmIdlesOffScreen() -> some View {
        modifier(OffScreenIdle())
    }
}

extension EnvironmentValues {
    /// A window that never orders in but must draw anyway — a render harness's
    /// declaration, never set in the app.
    @Entry var helmTreatsWindowAsSeen: Bool = false
}

extension View {
    /// The declaration every render harness makes, in one spelling: this
    /// subtree sits on a bench whose window never orders in, and it must draw
    /// anyway. It mounts no window reader, which also keeps `ImageRenderer`
    /// benches working: `ImageRenderer` renders any subtree holding an
    /// `NSViewRepresentable` as transparent. Never called in the app.
    func helmMeasuringBench() -> some View {
        environment(\.helmTreatsWindowAsSeen, true)
    }
}

/// Reports whether the window this view sits in is on screen. Zero-size,
/// draws nothing.
struct WindowSeenReader: NSViewRepresentable {
    @Binding var seen: Bool

    func makeNSView(context: Context) -> Reader {
        Reader(frame: .zero)
    }

    func updateNSView(_ view: Reader, context: Context) {
        // Rebound on every update: a stale closure would write into a binding
        // whose view has moved on.
        view.onChange = { value in
            if seen != value { seen = value }
        }
    }

    final class Reader: NSView {
        var onChange: ((Bool) -> Void)?
        /// Written only on the main thread (`viewDidMoveToWindow`), read once
        /// more in `deinit` — which Swift 6 treats as nonisolated, hence the
        /// annotation rather than a lock for a field with one writer.
        nonisolated(unsafe) private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            if let window {
                // Occlusion covers ordering: `orderOut` and `orderFront` both
                // post this notification in the app. A plain `swift test`
                // process is not the window server's client: it gets none and
                // its windows report `.visible` throughout, so do not "correct"
                // this from a test run.
                observer = NotificationCenter.default.addObserver(
                    forName: NSWindow.didChangeOcclusionStateNotification,
                    object: window, queue: .main
                    // Delivering on the main queue is what makes
                    // `assumeIsolated` true here. `report()` still hops, for
                    // its own reason below.
                ) { [weak self] _ in MainActor.assumeIsolated { self?.report() } }
            }
            report()
        }

        func report() {
            // Out of the current layout/update transaction: this fires from
            // AppKit mid-update, and a state write there is a SwiftUI error.
            // The window is read inside the hop, so a report queued while the
            // window was being built cannot overwrite a newer value. That makes
            // this a poll of the window's level, not an edge, which is all
            // `updateNSView` compares (Architecture/ModulePattern.md § A value crossing to the main thread).
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // `isVisible`, not occlusion: a window covered by another app
                // stays mounted, so a glance elsewhere does not throw away
                // scroll positions and half-edited fields. What idles is a
                // window ordered out. No window at all is a bare harness view,
                // which draws.
                self.onChange?(self.window.map(\.isVisible) ?? true)
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
