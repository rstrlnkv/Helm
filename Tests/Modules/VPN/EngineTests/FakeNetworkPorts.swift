// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
@testable import Module_VPN_Engine

/// The three ports the module asks the network about, as fakes.
///
/// **`FakeInterfaces` can no longer be planted with a service id → interface
/// pair**, because the port cannot answer that question any more: the id the
/// module has is a configuration's and the store is keyed by network service, so
/// every such pair this fake accepted was one the system could not produce, and
/// the suite stayed green while the strip was absent on every Mac (CLAUDE.md
/// § A fake can also be freer than the port). The interface is `scutil`'s answer
/// now, so it is `FakeRunner.statusOutput` — keyed by the name the tool takes.
///
/// **Every one of them is reached from a thread that is not the test's** — the
/// module's serial queue reads the interfaces on every emission, and the speed
/// run happens off both that queue and the cooperative pool. They were
/// `@unchecked Sendable` with plain mutable properties, which is the compiler
/// being told to trust the author for exactly the race that was there: the
/// engine appending to `askedFor` while the test read it. Each keeps its state
/// under a lock now.
final class FakeInterfaces: VPNInterfacePort, @unchecked Sendable {
    private let lock = NSLock()
    private var _primary: String?
    private var _counters: [String: (in: UInt64, out: UInt64)] = [:]
    private var _carriesPerRead: UInt64 = 0

    /// Nil is a Mac with no default route at all.
    var primary: String? {
        get { lock.lock(); defer { lock.unlock() }; return _primary }
        set { lock.lock(); _primary = newValue; lock.unlock() }
    }
    /// What each interface has carried. An interface with no entry is one the
    /// kernel has no counters for — a tunnel that has just gone.
    var counters: [String: (in: UInt64, out: UInt64)] {
        get { lock.lock(); defer { lock.unlock() }; return _counters }
        set { lock.lock(); _counters = newValue; lock.unlock() }
    }
    /// What every reading adds to those counters.
    ///
    /// A link that answers the same pair however often it is asked is a link
    /// with nothing on it, and the engine re-reads up to 26 times behind one
    /// connect — so «the tunnel carried a packet between two readings», which is
    /// what every live tunnel does, would be a state no test could write down.
    var carriesPerRead: UInt64 {
        get { lock.lock(); defer { lock.unlock() }; return _carriesPerRead }
        set { lock.lock(); _carriesPerRead = newValue; lock.unlock() }
    }

    func primaryInterface() -> String? {
        lock.lock(); defer { lock.unlock() }; return _primary
    }
    func bytes(on interface: String) -> (in: UInt64, out: UInt64)? {
        lock.lock(); defer { lock.unlock() }
        guard let carried = _counters[interface] else { return nil }
        _counters[interface] = (in: carried.in + _carriesPerRead,
                                out: carried.out + _carriesPerRead)
        return carried
    }
}

final class FakeExit: VPNExitPort, @unchecked Sendable {
    private let lock = NSLock()
    private var _answer: String?
    private var _hangs = false
    private var _asks = 0

    var answer: String? {
        get { lock.lock(); defer { lock.unlock() }; return _answer }
        set { lock.lock(); _answer = newValue; lock.unlock() }
    }
    /// The service that accepted the connection and never replied. Without this
    /// the fake finishes before the caller can observe that it was waiting.
    var hangs: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _hangs }
        set { lock.lock(); _hangs = newValue; lock.unlock() }
    }
    /// How many runs have **entered** the call. A test asserting that a call has
    /// not returned needs this first: an absence also holds when the caller was
    /// never scheduled, and then it is measuring nothing.
    var asks: Int {
        lock.lock(); defer { lock.unlock() }; return _asks
    }

    func regionCode() async -> String? {
        // A synchronous property that takes the lock and returns the value, never
        // an `await` with the lock held: Swift 6 makes `NSLock.lock()`
        // unavailable inside an `async` function outright (CLAUDE.md § A lock
        // taken on one side of a field guards nothing).
        let asked = enter()
        if asked.hangs { try? await Task.sleep(nanoseconds: .max) }
        return asked.answer
    }

    private func enter() -> (hangs: Bool, answer: String?) {
        lock.lock(); defer { lock.unlock() }
        _asks += 1
        return (_hangs, _answer)
    }
}

/// **The slowest thing in the module, and the fake could not be slow.**
///
/// `networkQuality` runs for about fifteen seconds by design and blocks the
/// thread it is on for as long as it does — which is why `VPNSpeedPort.measure`
/// says so at the protocol and why the engine keeps it off its serial queue. A
/// fake that answers the instant it is called makes every test of that
/// arrangement vacuous: «a Connect pressed while a measurement is in flight» and
/// «the tile says Measuring…» are both states the subject is already past
/// (CLAUDE.md § A fake that finishes instantly makes a test of a wait vacuous).
final class FakeSpeed: VPNSpeedPort, @unchecked Sendable {
    private let lock = NSLock()
    private var _answer: VPNSpeedReading?
    private var _askedFor: [String?] = []
    private var _blocks = false
    private var _onStart: (@Sendable () -> Void)?
    /// The gate the test opens. A semaphore rather than a sleep: the run stops
    /// until somebody says so, so a test never races the clock.
    private let gate = DispatchSemaphore(value: 0)

    var answer: VPNSpeedReading? {
        get { lock.lock(); defer { lock.unlock() }; return _answer }
        set { lock.lock(); _answer = newValue; lock.unlock() }
    }
    /// Every interface it was bound to, in order.
    var askedFor: [String?] {
        lock.lock(); defer { lock.unlock() }; return _askedFor
    }
    /// Hold the run open until `release()`, the way the real tool holds its
    /// thread for fifteen seconds.
    var blocksUntilReleased: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _blocks }
        set { lock.lock(); _blocks = newValue; lock.unlock() }
    }
    /// Called on the measuring thread as the run **starts**, before it blocks,
    /// so a test can wait for the state to exist instead of guessing at it.
    var onStart: (@Sendable () -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _onStart }
        set { lock.lock(); _onStart = newValue; lock.unlock() }
    }

    func release() { gate.signal() }

    func measure(onInterface: String?) -> VPNSpeedReading? {
        lock.lock()
        _askedFor.append(onInterface)
        let blocks = _blocks
        let onStart = _onStart
        let answer = _answer
        lock.unlock()
        onStart?()
        if blocks { gate.wait() }
        return answer
    }
}
