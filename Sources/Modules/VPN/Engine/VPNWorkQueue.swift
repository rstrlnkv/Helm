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
///
/// **`.inline` is serial too, and it was not.** It ran the block on whichever
/// thread offered it, which is one thread for everything a test drives directly
/// and a *different* one for the two pieces of work that leave the module and
/// come back through `run` — `checkExit`'s completion and `startMeasuring`'s.
/// Under `.background` those arrive behind the refresh that started them; under
/// the old `.inline` they arrived inside it, from another thread, which is the
/// one thing the real queue rules out. Two callers then met in `emitState`,
/// which compares and stamps `_lastEmitted` under the lock and emits outside
/// it, so one payload was swallowed as a duplicate of the other and the
/// survivor was emitted from a thread the test had already run past — a fake
/// freer than the port it stands for (CLAUDE.md), and every test in this module
/// written against it.
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
    /// What a recursive lock still refuses is the case that was wrong: a
    /// *second* thread entering while the first is inside.
    private static func inlineSerially(_ block: @escaping @Sendable () -> Void) {
        inlineLock.lock()
        defer { inlineLock.unlock() }
        block()
    }

    private static let inlineLock = NSRecursiveLock()

    /// Serial: the engine's state is guarded by a lock, but the commands it
    /// sends to `scutil` still have to arrive in the order they were asked for.
    private static let queue = DispatchQueue(label: "helm.vpn", qos: .userInitiated)
}
