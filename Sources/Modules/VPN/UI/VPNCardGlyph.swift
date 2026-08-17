// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Module_VPN_Engine

/// The mark on a connection's button, for each of the three verbs the card can
/// offer.
///
/// **A power key, and one exception.** Connecting and disconnecting are the two
/// directions of one act — the Mac's own power key is the same key both ways —
/// so both wear `power`, and which direction it is comes from the row it sits
/// in: the dot, the ring and the status word all say it already. Abandoning a
/// handshake is not that act, and it takes `xmark`: there is no connection to
/// switch off yet, which is the same reasoning `VPNCardAction` uses to give it
/// its own word.
///
/// The word has not gone anywhere. It is the button's tooltip and the name
/// VoiceOver reads (`VPNStr.cardWord`), so the control is named in the two
/// places a glyph-faced control has to be named — `NamedControlsTests` scans
/// the source for exactly this shape.
enum VPNCardGlyph {
    /// A symbol name is a string, and a string can be wrong: a misspelling
    /// draws nothing at all and looks like a button that lost its face.
    /// `TheCardWearsAGlyphThatExistsTests` resolves every one of these against
    /// SF Symbols.
    static func of(_ action: VPNCardAction) -> String {
        switch action.word {
        case .cancel: return "xmark"
        case .connect, .disconnect: return "power"
        }
    }
}
