// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Module_VPN_Engine

/// The face of a notice mode, in one place.
///
/// The card and the popover draw the same three faces beside its two pop-ups. A
/// glyph spelled twice is a glyph one side can change alone — the same reason
/// `VPNCardGlyph` exists next door.
enum VPNNoticeGlyph {
    static func of(_ mode: VPNNotice) -> String {
        switch mode {
        case .silent: return "bell.slash"
        case .menuBar: return "menubar.arrow.up.rectangle"
        case .system: return "bell.badge"
        }
    }
}
