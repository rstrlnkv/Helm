// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import AppKit
import SwiftUI
import HelmRuntime
import HelmUI
import Module_Uninstaller_UI

/// The window that offers to clean up after an app the person dragged to the
/// Trash themselves.
///
/// It owns the `NSWindow` and nothing else. What is in the Trash, what those apps
/// left behind, whether any of it is worth offering and what a press removes are
/// all the module's — the host asks `TrashedAppOffer.sweep` and either gets a view
/// or gets nothing, and nothing means no window at all.
///
/// One window, never one per app: several apps in the Trash are several groups in
/// this one.
@MainActor final class TrashedLeftoversWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let onClose: () -> Void
    /// The view closes the window itself, which then calls `windowWillClose` —
    /// the same double-call `WelcomeWindow` guards against.
    private var closed = false

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    /// Sweeps, and shows the window only if the module found something to offer.
    /// Returns whether a window went up, so the caller can drop its reference
    /// when none did.
    func showIfAnything(vm: ModuleViewModel) async -> Bool {
        guard let view = await TrashedAppOffer.sweep(vm: vm, onClose: { [weak self] in
            self?.close()
        }) else { return false }

        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.styleMask = [.titled, .closable]
        window.title = TrashedAppOffer.windowTitle
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        self.window = window

        // Accessory apps have no Dock icon and no menu bar of their own; without
        // this the window comes up behind whatever is in front — which for a
        // window nobody asked for means it is never seen at all.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        return true
    }

    private func close() {
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
