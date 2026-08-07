// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import AppKit
import SwiftUI

/// A window the host owns on somebody else's behalf.
///
/// ARCHITECTURE.md § «A window a module needs and the host owns» calls
/// `TrashedLeftoversWindow` the pattern, and there were two hand-written copies
/// of it — that one and `WelcomeWindow`. Both held an `NSWindow`, a closing
/// callback and a `closed` flag; both put the window up the same way and took
/// the activation policy back down in `windowWillClose`. The pattern is written
/// once here, so «the pattern» is a type rather than a paragraph two files
/// happen to agree with.
///
/// Three things it owns, each of which the copies had to get right separately:
///
/// - **The activation policy round trip.** Helm is an accessory app: no Dock
///   icon and no menu bar, so a window ordered front without `.regular` comes up
///   *behind* whatever the person is looking at — and a window nobody asked for
///   that opens behind something else is a window never seen. Back to
///   `.accessory` when it goes, or Helm keeps a Dock icon it did not earn.
/// - **The `closed` flag.** Every way out is one answer, and there are two paths
///   to it: the view calls `close()`, which makes AppKit call `windowWillClose`.
///   Without the guard `onClose` runs twice — and for the Trash offer that is
///   the record of a refusal written twice.
/// - **`isReleasedWhenClosed = false`**, because the holder is a Swift
///   reference and AppKit releasing it underneath would be an over-release.
///
/// What it does **not** own is the content or the title: subclasses hand those
/// over, and for a module's window the title is the module's to spell
/// (`TrashedAppOffer.windowTitle`) even though the `NSWindow` is the host's.
@MainActor class HostWindow: NSObject, NSWindowDelegate {
    private(set) var window: NSWindow?
    private let onClose: () -> Void
    /// Guards `onClose` against the second call — see the note above.
    private var closed = false

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    /// Puts `view` up in a window this object owns and comes forward with it.
    func present(_ view: some View, title: String,
                 styleMask: NSWindow.StyleMask = [.titled, .closable],
                 transparentTitlebar: Bool = false) {
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.styleMask = styleMask
        window.title = title
        if transparentTitlebar {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
        }
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        self.window = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// The way out a view is handed. It closes the window, which is what calls
    /// `windowWillClose` — the answer is recorded there and nowhere else, so
    /// pressing Done and pressing the red button end the same way.
    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard !closed else { return }
        closed = true
        NSApp.setActivationPolicy(.accessory)
        window = nil
        onClose()
    }
}
