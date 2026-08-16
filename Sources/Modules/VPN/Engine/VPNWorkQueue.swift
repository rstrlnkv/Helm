// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// Where the engine does work that blocks.
///
/// `scutil` is a subprocess: on this machine a single `--nc list` measured
/// 16 ms, and a connect polls it up to 25 times. All of that used to run on the
/// main thread — through `DispatchQueue.main.asyncAfter` for the poll, and
/// through AppKit's own running-applications notification for auto-connect,
/// which also reaches a synchronous keychain read that can put a modal panel on
/// screen. Tests drive the engine synchronously and assert on the commands it
/// issued, so they run it `.inline`; the app runs it `.background`.
public enum VPNWorkQueue: Sendable {
    case background
    case inline

    func run(_ block: @escaping @Sendable () -> Void) {
        switch self {
        case .inline: block()
        case .background: Self.queue.async(execute: block)
        }
    }

    func run(after seconds: Double, _ block: @escaping @Sendable () -> Void) {
        switch self {
        case .inline: block()
        case .background: Self.queue.asyncAfter(deadline: .now() + seconds, execute: block)
        }
    }

    /// Serial: the engine's state is guarded by a lock, but the commands it
    /// sends to `scutil` still have to arrive in the order they were asked for.
    private static let queue = DispatchQueue(label: "helm.vpn", qos: .userInitiated)
}
