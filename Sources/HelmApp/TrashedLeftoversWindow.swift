// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import AppKit
import HelmRuntime
import HelmUI
import Module_Uninstaller_UI

/// The window that offers to clean up after an app the person dragged to the
/// Trash themselves.
///
/// It owns no window mechanics of its own — `HostWindow` has those — and asks
/// the module one question. What is in the Trash, what those apps left behind,
/// whether any of it is worth offering and what a press removes are all the
/// module's: the host calls `TrashedAppOffer.sweep` and either gets a view or
/// gets nothing, and nothing means no window at all.
///
/// One window, never one per app: several apps in the Trash are several groups in
/// this one.
@MainActor final class TrashedLeftoversWindow: HostWindow {

    /// Sweeps, and shows the window only if the module found something to offer.
    /// Returns whether a window went up, so the caller can drop its reference
    /// when none did.
    func showIfAnything(vm: ModuleViewModel) async -> Bool {
        guard let view = await TrashedAppOffer.sweep(vm: vm, onClose: { [weak self] in
            self?.close()
        }) else { return false }

        // The title is the module's to spell even though the window is the
        // host's — the host cannot name what is inside it.
        present(view, title: TrashedAppOffer.windowTitle)
        return true
    }
}
