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
///
/// **The interface MIB, because the other two readings count in 32 bits.** This
/// read `ifa_data` off `getifaddrs` as `struct if_data`, whose `ifi_ibytes` is a
/// `u_int32_t` — so the count wraps at 4 GiB, which a tunnel carrying real
/// traffic passes within a session. Measured on the owner's Mac, 2026-08-18:
/// the app read 188 673 024 where `netstat -ib` had 4 483 640 977, one wrap
/// apart, and the page drew «188 МБ» for a tunnel that had carried 4,48 GB.
///
/// The obvious repair is not one. `sysctl(NET_RT_IFLIST2)` hands back
/// `if_msghdr2`, whose `ifm_data` is an `if_data64` and *declares* 64-bit byte
/// counts — but the kernel fills those two fields from the 32-bit originals:
/// measured the same day, that route gave lo0 3 402 308 608 against
/// `netstat`'s 67 826 818 352, again exactly one wrap apart, while
/// `ifi_ipackets` in the same message matched to the packet. The counts that
/// are whole come from `net.link.generic.ifdata.<index>.general`, whose
/// `ifmibdata` carries an `if_data64` the kernel fills at full width: lo0,
/// en0 and utun8 all agreed with `netstat` to the byte at the same instant.
enum VPNInterfaceCounters {

    static func bytes(on interface: String) -> (in: UInt64, out: UInt64)? {
        // The MIB row is the interface index, and the name is read back rather
        // than trusted: an index reused by the next interface up would
        // otherwise report somebody else's traffic as this tunnel's.
        let index = if_nametoindex(interface)
        guard index != 0 else { return nil }
        var mib: [Int32] = [CTL_NET, PF_LINK, NETLINK_GENERIC,
                            IFMIB_IFDATA, Int32(index), IFDATA_GENERAL]
        var row = ifmibdata()
        var size = MemoryLayout<ifmibdata>.size
        // A short write is refused rather than read: the rest of the struct is
        // still the zeros it was made with, and «this tunnel has carried
        // nothing» is a worse answer than «the kernel had no counters».
        guard sysctl(&mib, u_int(mib.count), &row, &size, nil, 0) == 0,
              size == MemoryLayout<ifmibdata>.size,
              isNamed(interface, row)
        else { return nil }
        let counters: if_data64 = row.ifmd_data
        return (counters.ifi_ibytes, counters.ifi_obytes)
    }

    /// Whether the row is the interface asked for, by the bytes of its own
    /// fixed-width `ifmd_name` field — a name the kernel wrote is not a string
    /// anybody needs, only one to agree or disagree with.
    private static func isNamed(_ interface: String, _ row: ifmibdata) -> Bool {
        withUnsafeBytes(of: row.ifmd_name) { field in
            field.prefix { $0 != 0 }.elementsEqual(interface.utf8)
        }
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
    static func onTheWire(_ bytes: UInt64) -> UInt64 {
        // A counter near the top of its type is arithmetic nobody performs on
        // purpose; a trap in the engine is a crash in the app.
        guard bytes <= UInt64.max - 500 else { return bytes }
        return ((bytes + 500) / 1000) * 1000
    }
}
