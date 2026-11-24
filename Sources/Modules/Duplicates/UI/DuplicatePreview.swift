// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import AppKit
import Quartz
import SwiftUI

/// The preview itself, as a view rather than the shared panel.
///
/// Not `QLPreviewPanel`: the panel is a singleton driven through the responder
/// chain — something in the chain must answer `acceptsPreviewPanelControl` —
/// and in this accessory app it never takes control, so Space and the context
/// menu would both call it and nothing would appear. `QLPreviewView` is an
/// ordinary `NSView` with none of that machinery, and a sheet needs no
/// key-window politics.
struct QuickLookSheet: NSViewRepresentable {
    let url: URL

    /// The smallest the preview sheet's picture is drawn at.
    static let minimumSize = CGSize(width: 640, height: 420)

    func makeNSView(context: Context) -> QLPreviewView {
        // .normal, not .compact: the sheet is the whole experience here,
        // not a thumbnail beside something else.
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        view.previewItem = url as NSURL
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        // Documented requirement: a QLPreviewView must be closed or it leaks
        // its preview machinery.
        view.close()
    }
}
