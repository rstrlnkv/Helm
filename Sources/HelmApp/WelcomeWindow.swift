// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import AppKit
import HelmRuntime
import HelmUI

/// The tour's window. Shown once per installation, deciding nothing itself:
/// `WelcomeGate` says whether, `WelcomeSteps` says what, `HostWindow` owns the
/// `NSWindow`, and this is the one write that records it was seen.
///
/// `onClose` runs however the window goes away, which is what the permission
/// audit is deferred into: both want the first launch, and two things arriving
/// together is not an introduction.
@MainActor final class WelcomeWindow: HostWindow {

    static func shouldShow(store: NamespacedStore) -> Bool {
        WelcomeGate.shouldShow(seenRevision: store.int(WelcomeGate.storeKey, default: 0))
    }

    func show(steps: [WelcomeStep], store: NamespacedStore, actions: WelcomeActions) {
        // Written when the window opens, not when it closes: a person who
        // force-quits mid-tour has still been shown it, and showing it again
        // at every launch until they press Done is worse than not showing it.
        store.set(WelcomeGate.revision, for: WelcomeGate.storeKey)

        let view = WelcomeView(steps: steps,
                               actions: actions) { [weak self] in self?.close() }
        present(view, title: WelcomeStr.windowTitle,
                styleMask: [.titled, .closable, .fullSizeContentView],
                transparentTitlebar: true)
    }
}
