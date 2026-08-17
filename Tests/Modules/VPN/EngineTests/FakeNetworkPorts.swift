// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
@testable import Module_VPN_Engine

final class FakeInterfaces: VPNInterfacePort, @unchecked Sendable {
    /// Service id → interface. Empty is a service that is not up.
    var interfaces: [String: String] = [:]
    /// Nil is a Mac with no default route at all.
    var primary: String?
    /// What each interface has carried. An interface with no entry is one the
    /// kernel has no counters for — a tunnel that has just gone.
    var counters: [String: (in: UInt64, out: UInt64)] = [:]
    /// What every reading adds to those counters.
    ///
    /// A link that answers the same pair however often it is asked is a link
    /// with nothing on it, and the engine re-reads up to 26 times behind one
    /// connect — so «the tunnel carried a packet between two readings», which is
    /// what every live tunnel does, would be a state no test could write down.
    var carriesPerRead: UInt64 = 0

    func interface(forServiceID id: String) -> String? { interfaces[id] }
    func primaryInterface() -> String? { primary }

    func bytes(on interface: String) -> (in: UInt64, out: UInt64)? {
        guard let carried = counters[interface] else { return nil }
        defer {
            counters[interface] = (in: carried.in + carriesPerRead,
                                   out: carried.out + carriesPerRead)
        }
        return carried
    }
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
