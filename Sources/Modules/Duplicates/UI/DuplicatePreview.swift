// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import AppKit
import QuickLookUI
import SwiftUI
import Module_Duplicates_Engine

public enum DuplicatePreview {
    /// The file a preview would show, or nil when there is nothing to show.
    ///
    /// The selection is checked against the groups rather than trusted: a copy
    /// that has just been trashed leaves the list while the selection still
    /// names it, and a panel opened onto a file that is gone is an empty frame
    /// with no explanation.
    public static func target(selection: String?, in groups: [DuplicateGroup]) -> URL? {
        guard let selection,
              groups.contains(where: { $0.paths.contains(selection) }) else { return nil }
        return URL(fileURLWithPath: selection)
    }
}

/// Owns the shared Quick Look panel for one file.
///
/// `QLPreviewPanel` is driven through the responder chain: something in the
/// chain has to answer `acceptsPreviewPanelControl` and then hand itself over
/// as data source and delegate. SwiftUI puts nothing there, so this is a bare
/// `NSView` inserted into the hierarchy for the sole purpose of being that
/// something.
///
/// **`@preconcurrency` is load-bearing, not decoration.** QuickLookUI declares
/// these two protocols on `NSResponder` through a category with no `@MainActor`,
/// while `NSResponder` is main-actor isolated by inference — a mismatch in the
/// SDK rather than in this code. `@MainActor` alone cannot close it: on the
/// class the conformance still "crosses into main actor-isolated code"; on the
/// conformance it becomes "cannot be used in nonisolated context" at
/// `panel.dataSource = self`; on the three overrides it collides with the
/// `nonisolated` declarations being overridden. Measured against the macOS 27
/// SDK, four ways round, before this.
@MainActor
final class PreviewPanelOwner: NSView, @preconcurrency QLPreviewPanelDataSource,
                               @preconcurrency QLPreviewPanelDelegate {
    var url: URL?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { url != nil }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        url as (any QLPreviewItem)?
    }

    /// Toggles, which is what Space does in the Finder and therefore what a
    /// person will try. The panel is a shared singleton, so asking whether it
    /// is visible is asking about the whole app, not about this list — which is
    /// correct here: only one list can be in front.
    func toggle(_ url: URL?) {
        self.url = url
        guard url != nil, let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists() && panel.isVisible {
            panel.orderOut(nil)
        } else {
            window?.makeFirstResponder(self)
            panel.makeKeyAndOrderFront(nil)
        }
        panel.reloadData()
    }
}

/// Puts a `PreviewPanelOwner` in the SwiftUI hierarchy and hands the view a
/// way to drive it.
struct PreviewPanelHost: NSViewRepresentable {
    /// Called once with the owner so the view can toggle it from a button.
    let attach: (PreviewPanelOwner) -> Void

    func makeNSView(context: Context) -> PreviewPanelOwner {
        let view = PreviewPanelOwner()
        attach(view)
        return view
    }

    func updateNSView(_ nsView: PreviewPanelOwner, context: Context) {}
}
