// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI
import AppKit

/// Unmounts a subtree while the window holding it is off screen.
///
/// A mounted SwiftUI tree pays for every published change whether or not
/// anybody can see it — and it pays twice. The render itself is the small
/// half. The large half is kept: measured with `malloc_history` on the VPN
/// settings page, each view-model publish re-ran `ChildEnvironment.updateValue`
/// inside SwiftUI's attribute graph, whose environment write is
/// `PropertyList.prependValue` — a fresh `PropertyList.Element` chained in
/// front of the ones before it, none of which can be freed while the tree
/// lives. ~3–6 KB per event, sustained over six benchmark laps with no decay,
/// hidden window and visible window alike (`HiddenPageEventChurnBenchmark`),
/// and the installed build's heap showed the same signature at rest: 3 766
/// live ObservationTracking dictionaries and a ~3 MB/hour ratchet.
///
/// Detaching the hosting view from its window was measured doing **nothing** —
/// the graph lives in the `NSHostingView`, not the window, and a detached page
/// kept the same ~2.5–6 KB per event. What stops the meter is unmounting the
/// subtree, which is what this does: while the window is not on screen the
/// content is out of the hierarchy entirely, and on the next
/// `didChangeOcclusionState` it is built afresh from the view model's current
/// state — the view model keeps its subscription throughout, so nothing is
/// missed, and the menu-bar surfaces that read it (`statusChanges`, banners)
/// keep hearing.
///
/// A view with **no window at all** counts as seen: the offscreen render
/// harnesses (`ModulePageRender`, geometry probes) drive bare hosting views
/// and windows that are never ordered in, and a measurement of a page that
/// declined to draw would be a measurement of nothing. A harness whose window
/// exists but never shows opts in through `helmTreatsWindowAsSeen` — an
/// explicit declaration that the window is a measuring bench, made where the
/// bench is built.
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

public extension View {
    /// The subtree is unmounted while its window is off screen, and rebuilt
    /// from current state when the window returns. See `OffScreenIdle`.
    func helmIdlesOffScreen() -> some View {
        modifier(OffScreenIdle())
    }
}

public extension EnvironmentValues {
    /// A window that never orders in but must draw anyway — a render harness's
    /// declaration, never set in the app.
    @Entry var helmTreatsWindowAsSeen: Bool = false
}

public extension View {
    /// The declaration every render harness makes, in one spelling: this
    /// subtree sits on a measuring bench whose window never orders in, and it
    /// must draw anyway. Also what keeps `ImageRenderer` benches working — a
    /// benched subtree mounts no window reader, and `ImageRenderer` renders
    /// any subtree holding an `NSViewRepresentable` as transparent.
    /// Never called in the app; the harnesses are its callers.
    func helmMeasuringBench() -> some View {
        environment(\.helmTreatsWindowAsSeen, true)
    }
}

/// Reports whether the window this view sits in is on screen. Zero-size,
/// draws nothing.
private struct WindowSeenReader: NSViewRepresentable {
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
                // Occlusion covers ordering: `orderOut` drops `.visible` and
                // `orderFront` restores it, and both post this notification.
                observer = NotificationCenter.default.addObserver(
                    forName: NSWindow.didChangeOcclusionStateNotification,
                    object: window, queue: .main
                ) { [weak self] _ in self?.report() }
            }
            report()
        }

        private func report() {
            // `isVisible`, not occlusion: a window fully covered by another app
            // is still "on screen" here on purpose — unmounting it would throw
            // away scroll positions and mid-edit fields every time the person
            // glances at another window. What this idles is a window that is
            // ordered out: the closed Settings window, a panel that was
            // dismissed. No window at all is a bare harness view, which draws.
            let value = window.map(\.isVisible) ?? true
            // Out of the current layout/update transaction: this fires from
            // AppKit mid-update, and a state write there is a SwiftUI error.
            DispatchQueue.main.async { [weak self] in self?.onChange?(value) }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
