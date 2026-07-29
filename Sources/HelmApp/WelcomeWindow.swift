// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import AppKit
import SwiftUI
import HelmRuntime
import HelmUI

/// The tour's window. Shown once per installation, deciding nothing itself:
/// `WelcomeGate` says whether, `WelcomeSteps` says what, and this owns the
/// `NSWindow` and the one write that records it was seen.
@MainActor final class WelcomeWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    /// Run when the window goes away, however it goes away. The permission
    /// audit is deferred into this: both want the first launch, and two things
    /// arriving together is not an introduction.
    private let onClose: () -> Void
    /// Guards against running `onClose` twice — Done calls `close()`, and
    /// closing the window then calls `windowWillClose` as well.
    private var closed = false

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    static func shouldShow(store: NamespacedStore) -> Bool {
        WelcomeGate.shouldShow(seenRevision: store.int(WelcomeGate.storeKey, default: 0))
    }

    func show(steps: [WelcomeStep], store: NamespacedStore) {
        // Written when the window opens, not when it closes: a person who
        // force-quits mid-tour has still been shown it, and showing it again
        // at every launch until they press Done is worse than not showing it.
        store.set(WelcomeGate.revision, for: WelcomeGate.storeKey)

        let view = WelcomeView(steps: steps) { [weak self] in self?.close() }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.title = WelcomeStr.windowTitle
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        self.window = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
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
