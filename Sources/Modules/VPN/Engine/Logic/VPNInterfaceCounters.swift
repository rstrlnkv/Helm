// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// What an interface has carried, from the kernel's own counters.
///
/// **These are the interface's counters, not the connection's, and for a `utun`
/// that is the same thing**: macOS makes a new `utunN` for every tunnel it
/// raises, so the counter starts at zero when the tunnel comes up and dies with
/// it. The same code pointed at `en0` would be reporting since boot, which is
/// why this takes an interface name and never a default.
public enum VPNInterfaceCounters {

    public static func bytes(on interface: String) -> (in: UInt64, out: UInt64)? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard String(cString: entry.pointee.ifa_name) == interface,
                  let address = entry.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_LINK),
                  let raw = entry.pointee.ifa_data
            else { continue }
            let data = raw.assumingMemoryBound(to: if_data.self)
            return (UInt64(data.pointee.ifi_ibytes), UInt64(data.pointee.ifi_obytes))
        }
        return nil
    }

    /// The same count as the wire carries it: whole kilobytes.
    ///
    /// **The counters are the one part of the payload that moves on its own**,
    /// and the engine withholds only a payload equal in every field to the last
    /// one it sent (`VPNEngine.emitState`). A raw byte count therefore makes
    /// every re-read news: the poll behind one connect re-reads 26 times, and a
    /// live tunnel has carried another packet by each of them, so 26 payloads go
    /// out where one used to and every mounted page re-renders for a figure
    /// nobody can see change (`AnUnchangedStateIsSaidOnceTests`, and
    /// `HiddenPageEventChurnBenchmark` for the price of each).
    ///
    /// A kilobyte is the granularity the strip is drawn at: `HelmBytes` writes
    /// bytes exactly below one kilobyte and whole kilobytes above it, so nothing
    /// smaller than this could reach the screen anyway. Rounded rather than
    /// truncated, so the kilobyte drawn is the one the kernel counted.
    ///
    /// What survives is bounded by the callers rather than by the traffic:
    /// nothing re-reads on a timer, so a payload goes out when the network
    /// changes, when a page asks, or on one of the poll's re-reads — and an idle
    /// tunnel does not move a kilobyte between two of those.
    public static func onTheWire(_ bytes: UInt64) -> UInt64 {
        // A counter near the top of its type is arithmetic nobody performs on
        // purpose; a trap in the engine is a crash in the app.
        guard bytes <= UInt64.max - 500 else { return bytes }
        return ((bytes + 500) / 1000) * 1000
    }
}
