// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// Which way a request to `scutil --nc` goes — the one place this module says it.
///
/// It was written down three times over: as the card's own `Verb`, as the
/// `verb: String` the engine passed its own log line, and as the wording of the
/// sentence a refusal draws, which had no verb at all and therefore said
/// «refused to connect» about a *stop* the tool would not perform. A person who
/// asked to bring a tunnel down then read that it was down while it was up,
/// which is the one sentence this module must never produce.
///
/// `String`-backed and `Codable` because it crosses the transport inside
/// `VPNFailure`, and the log word is the same declaration rather than a literal
/// typed beside it.
public enum VPNVerb: String, Codable, Equatable, Sendable {
    case connect, disconnect

    /// The state the tool was asked to reach, which is what a poll waits for.
    ///
    /// Not `isUp`: a connect that has reached `.connecting` has not arrived, and
    /// the poll exists for exactly that stretch.
    public var settledStatus: VPNStatus {
        switch self {
        case .connect: return .connected
        case .disconnect: return .disconnected
        }
    }
}
