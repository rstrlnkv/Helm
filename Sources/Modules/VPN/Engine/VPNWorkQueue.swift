// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// Where the engine does work that blocks.
///
/// `scutil` is a subprocess, a connect polls it many times, and auto-connect
/// reaches a synchronous keychain read that can put a modal panel on screen:
/// none of it may run on the main thread. Tests drive the engine synchronously
/// and assert on the commands it issued, so they run it `.inline`; the app runs
/// it `.background`.
///
/// **`.inline` is serial too.** Two pieces of work leave the module and come
/// back through `run` from another thread — `checkExit`'s completion and
/// `startMeasuring`'s. Under `.background` they arrive behind the refresh that
/// started them; an `.inline` that ran them at once on their own thread would
/// let two callers meet in `emitState` and swallow one payload as a duplicate,
/// a fake freer than the port it stands for
/// (Architecture/TestsAndMeasurement.md § Fakes).
public enum VPNWorkQueue: Sendable {
    case background
    case inline

    func run(_ block: @escaping @Sendable () -> Void) {
        switch self {
        case .inline: Self.inlineSerially(block)
        case .background: Self.queue.async(execute: block)
        }
    }

    func run(after seconds: Double, _ block: @escaping @Sendable () -> Void) {
        switch self {
        case .inline: Self.inlineSerially(block)
        case .background: Self.queue.asyncAfter(deadline: .now() + seconds, execute: block)
        }
    }

    /// One block at a time, still on the caller's own thread.
    ///
    /// **Recursive on purpose.** The engine reaches this from inside a block it
    /// is already running — `connectNow` calls `poll`, and `pollUntilSettled`
    /// re-enters itself through `run(after:)`, which `.inline` runs at once —
    /// so a plain lock would deadlock the poll loop the whole module depends on.
    /// What a recursive lock still refuses is a *second* thread entering while
    /// the first is inside.
    private static func inlineSerially(_ block: @escaping @Sendable () -> Void) {
        inlineLock.withLock { block() }
    }

    private static let inlineLock = NSRecursiveLock()

    /// Serial: the engine's state is guarded by a lock, but the commands it
    /// sends to `scutil` still have to arrive in the order they were asked for.
    private static let queue = DispatchQueue(label: "helm.vpn", qos: .userInitiated)
}
