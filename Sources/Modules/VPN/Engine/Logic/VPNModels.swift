// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

public enum VPNStatus: String, Equatable, Sendable, Codable {
    case connected, connecting, disconnected, disconnecting, unknown

    /// Up, or on its way up. Nine places asked this, six of them by spelling
    /// out the two cases and four of those inside SwiftUI — which statuses
    /// count as up is the engine's vocabulary, and a view that answers it for
    /// itself is a view that can answer it differently.
    public var isUp: Bool { self == .connected || self == .connecting }

    /// Mid-change, so the screen shows a spinner and the engine keeps polling.
    public var isTransitioning: Bool { self == .connecting || self == .disconnecting }
}

public struct VPNConnection: Identifiable, Equatable, Sendable, Codable {
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
