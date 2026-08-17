// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

/// The order the connection cards are drawn in: whatever is up, then the rest
/// as macOS handed them over.
///
/// It exists because the page now draws six cards and puts the rest behind a
/// button. `scutil --nc list` answers in the order the configurations were
/// made, so without this the connected tunnel can be the ninth — hidden behind
/// «Show all», which is the one card the page is for. A cap without an order is
/// a way of hiding the answer.
///
/// The tail is **not** re-sorted. The system's order is the person's own, and
/// sorting it by name would move every card whenever a tunnel came up or went
/// down — motion on a list nobody touched.
public enum VPNConnectionOrder {
    /// `isUp`, not `isConnected`: a handshake in flight is something happening
    /// on this Mac, and the card that can cancel it belongs on screen while it
    /// runs.
    public static func upFirst(_ connections: [VPNConnection]) -> [VPNConnection] {
        connections.filter { $0.status.isUp } + connections.filter { !$0.status.isUp }
    }
}
