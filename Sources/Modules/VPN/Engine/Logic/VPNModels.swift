// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

public enum VPNStatus: String, Equatable, Sendable, Codable {
    case connected, connecting, disconnected, disconnecting, unknown
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
