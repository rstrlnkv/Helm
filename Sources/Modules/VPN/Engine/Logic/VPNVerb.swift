// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// Which way a request to `scutil --nc` goes — the one place this module says it.
///
/// The card, the log line and a refusal's sentence all read it, so a refused
/// *stop* can never be worded as a refused connect. `String`-backed because the
/// log word is the same declaration rather than a literal typed beside it.
public enum VPNVerb: String, Equatable, Sendable {
    case connect, disconnect

    /// The state the tool was asked to reach, which is what a poll waits for.
    ///
    /// Not `isUp`: a connect that has reached `.connecting` has not arrived, and
    /// the poll exists for exactly that stretch.
    var settledStatus: VPNStatus {
        switch self {
        case .connect: return .connected
        case .disconnect: return .disconnected
        }
    }
}
