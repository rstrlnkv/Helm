// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
@testable import Module_VPN_Engine

final class FakeInterfaces: VPNInterfacePort, @unchecked Sendable {
    /// Service id → interface. Empty is a service that is not up.
    var interfaces: [String: String] = [:]
    /// Nil is a Mac with no default route at all.
    var primary: String?
    func interface(forServiceID id: String) -> String? { interfaces[id] }
    func primaryInterface() -> String? { primary }
}

final class FakeExit: VPNExitPort, @unchecked Sendable {
    var answer: String?
    /// The service that accepted the connection and never replied. Without this
    /// the fake finishes before the caller can observe that it was waiting.
    var hangs = false
    func regionCode() async -> String? {
        if hangs { try? await Task.sleep(nanoseconds: .max) }
        return answer
    }
}

final class FakeSpeed: VPNSpeedPort, @unchecked Sendable {
    var answer: VPNSpeedReading?
    /// Every interface it was bound to, in order.
    private(set) var askedFor: [String?] = []
    func measure(onInterface: String?) -> VPNSpeedReading? {
        askedFor.append(onInterface)
        return answer
    }
}
