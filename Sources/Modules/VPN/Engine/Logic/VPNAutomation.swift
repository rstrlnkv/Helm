// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmRuntime

/// One firing of a VPN rule: Helm raised or dropped a tunnel by itself.
///
/// A tunnel the person started from Helm's panel, from the macOS menu bar or
/// from System Settings is deliberately not one of these. An indicator that
/// fires for everything indicates nothing.
public struct VPNAutomation: Codable, Equatable, Sendable {
    /// What happened. **Three, not two** — a tunnel Helm took down when an app
    /// quit and a tunnel that fell over are the same movement and not the same
    /// news, and they shared a case for as long as the module existed.
    ///
    /// `.disconnected` is a rule doing what it was asked to. `.dropped` is the
    /// network, the server or somebody in System Settings taking the tunnel
    /// away while the person believed they were behind it — the one event here
    /// worth interrupting somebody for, and it was announced in the same words,
    /// at the same volume, as the one they had arranged themselves.
    public enum Kind: String, Codable, Sendable { case connected, disconnected, dropped

        /// Which way the tunnel went. The ring turns in one of two colours and
        /// this is the question it asks: down is down, however it got there.
        public var goingUp: Bool { self == .connected }
    }
    public let at: Date
    public let name: String
    public let kind: Kind

    public init(at: Date, name: String, kind: Kind) {
        self.at = at
        self.name = name
        self.kind = kind
    }

    /// How long the ring turns. Two revolutions at 0.6 s each — long enough to
    /// register as movement, short enough that it cannot be mistaken for a
    /// progress indicator. The host measures the same window from
    /// `StatusPlan.spinDuration`, so this reads it rather than repeating it.
    public static let spinDuration: TimeInterval = StatusPlan.spinDuration
    /// How long the name stays. It outlives the ring on purpose: the movement
    /// catches the eye, the word answers what caught it.
    public static let nameDuration: TimeInterval = 3.0

    /// 0…1 through the spin, or nil when there is nothing to draw.
    public static func spinPhase(_ automation: VPNAutomation, now: Date) -> Double? {
        let elapsed = now.timeIntervalSince(automation.at)
        guard elapsed >= 0, elapsed < spinDuration else { return nil }
        return elapsed / spinDuration
    }

    public static func showsName(_ automation: VPNAutomation, now: Date) -> Bool {
        let elapsed = now.timeIntervalSince(automation.at)
        return elapsed >= 0 && elapsed < nameDuration
    }

    /// The moment the ring stops — what the host is told to spin until.
    public static func spinEnd(_ automation: VPNAutomation) -> Date {
        automation.at.addingTimeInterval(spinDuration)
    }
}
