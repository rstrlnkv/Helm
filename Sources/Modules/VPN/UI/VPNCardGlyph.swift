// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Module_VPN_Engine

/// The mark on a connection's button, for each of the three verbs the card can
/// offer.
///
/// **A power key, and one exception.** Connecting and disconnecting are two
/// directions of one act, so both wear `power`; the row's dot and status word
/// say which. Abandoning a handshake takes `xmark`: there is no connection to
/// switch off yet (`VPNCardAction` gives it its own word for the same reason).
///
/// The word is the button's tooltip and the name VoiceOver reads
/// (`VPNStr.cardWord`).
enum VPNCardGlyph {
    /// A symbol name is a string, and a string can be wrong: a misspelling
    /// draws nothing at all and looks like a button that lost its face.
    static func of(_ action: VPNCardAction) -> String {
        switch action.word {
        case .cancel: return "xmark"
        case .connect, .disconnect: return "power"
        }
    }
}
