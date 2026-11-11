// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

public enum VPNStatus: String, Equatable, Sendable {
    case connected, connecting, disconnected, disconnecting, unknown

    /// Up, or on its way up. Nine places asked this, six of them by spelling
    /// out the two cases and four of those inside SwiftUI — which statuses
    /// count as up is the engine's vocabulary, and a view that answers it for
    /// itself is a view that can answer it differently.
    public var isUp: Bool { self == .connected || self == .connecting }

    /// Mid-change, so the screen shows a spinner and the engine keeps polling.
    public var isTransitioning: Bool { self == .connecting || self == .disconnecting }

    /// Up, and only up. `isUp` answers "is something happening here", which is
    /// the right question for the panel tile's switch, and the wrong one for
    /// anything that lights or counts: a tunnel whose card says "Connecting…"
    /// and whose panel row shows a spinner is not connected yet.
    public var isConnected: Bool { self == .connected }
}

public struct VPNConnection: Identifiable, Equatable, Sendable {
    public let id: String       // service identifier (UUID from scutil)
    public let name: String     // user-visible service name
    public var status: VPNStatus
    public let kind: String?    // e.g. "IKEv2", "IPSec"

    public init(id: String, name: String, status: VPNStatus, kind: String?) {
        self.id = id
        self.name = name
        self.status = status
        self.kind = kind
    }
}

/// A command the tool refused, named so a screen can say which one.
///
/// The name is here unredacted and in the log it is not: `Redact.vpn` exists
/// because a diagnostic file leaves the machine, and this value never does —
/// it goes to the window of the person who configured the thing it names.
public struct VPNFailure: Equatable, Sendable {
    public enum Reason: String, Sendable {
        /// No configuration by that name — renamed or deleted in System
        /// Settings, or a rule left pointing at one that is gone.
        case noSuchService
        /// `scutil` said something else. What it said is in the log; the screen
        /// gets the fact rather than the tool's own words, which are English
        /// and are not written for a person.
        case refused
        /// The configuration could not be read (`VPNCredentialRead.unreadable`), so
        /// Helm did not connect: said of a person's press only.
        case secretUnreadable
    }
    public let name: String
    public let reason: Reason
    /// Which command was refused.
    ///
    /// **The screen said «connect» whatever had happened.** A refused `--nc stop`
    /// drew «macOS refused to connect «Office»», so the person who had just asked
    /// to bring a tunnel down read a sentence about bringing one up — and the
    /// tunnel they wanted closed was still carrying their traffic. The reason and
    /// the verb are two different facts and the sentence needs both.
    public let verb: VPNVerb

    public init(name: String, reason: Reason, verb: VPNVerb) {
        self.name = name
        self.reason = reason
        self.verb = verb
    }
}
