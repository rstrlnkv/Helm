// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmRuntime
@testable import Module_VPN_Engine

final class FakeRunner: VPNRunnerPort {
    var issued: [[String]] = []
    var listOutput: String = ""

    /// **Consecutive answers to `--nc list`, which is what the real tool gives.**
    ///
    /// `listOutput` alone is a tool whose answer never changes as a consequence
    /// of the command it was just given — and the engine's whole poll exists
    /// because it does: `--nc start` is followed by a list that still says
    /// `Disconnected`, then `Connecting`, then `Connected`, and
    /// `pollUntilSettled` re-reads up to 25 times waiting for that. With one
    /// fixed answer, «the tunnel came up on the third read» is a state no test
    /// could write down — so `maxPollAttempts`, the only thing standing between
    /// a tunnel that never settles and `scutil` being run for ever, had no test
    /// of any kind and could be deleted without a single failure.
    ///
    /// Reads past the end repeat the last entry, because a settled tunnel keeps
    /// answering the same thing. Empty means «use `listOutput`», so every test
    /// written before this stays exactly as it was.
    var listScript: [String] = []
    private var listReads = 0

    /// What `start` and `stop` answer, **per configuration name**.
    ///
    /// `reply` alone is a tool that answers the same way about every name, so
    /// «this rule's configuration was renamed and the other one is fine» — one
    /// stop refused among several — could only be written by mutating the fake
    /// between calls, which is a different sequence from the one the app
    /// performs. The real tool answers per name; so does this now.
    var replies: [String: String] = [:]

    /// What `start` and `stop` answer when no name-specific answer is set.
    ///
    /// It was hard-coded to `""`, which is what the real tool prints when it
    /// **succeeded** — so «scutil refused» was a state no test could write
    /// down, whatever anybody wrote, and none did. The tool reports failure by
    /// printing a line and exiting 0 (`No service`), and both call sites threw
    /// that line away for as long as this fake could not produce one.
    ///
    var reply: String = ""

    /// **A tool that did not run**, which this fake could not be while
    /// `VPNRunnerPort.run` answered with a bare `String`: `scutil` missing, or
    /// refused by the sandbox, is empty output — the same value it prints when it
    /// succeeded — and the exit status `HelmProcess` had read was gone before it
    /// reached the engine. The port carries the status now, so the state exists
    /// here too. `-1` is what `HelmProcess` answers when the launch itself threw.
    var exitStatus: Int32 = 0

    /// How many times the tool was asked for the list. The engine polls, so
    /// «did it re-read» is a count rather than a fact.
    var listReadCount: Int { issued.count { $0 == ["--nc", "list"] } }

    func run(_ args: [String]) -> HelmProcess.Result {
        issued.append(args)
        if args == ["--nc", "list"] {
            defer { listReads += 1 }
            guard !listScript.isEmpty else { return answer(listOutput) }
            return answer(listScript[min(listReads, listScript.count - 1)])
        }
        if let name = args.last, let scripted = replies[name] { return answer(scripted) }
        return answer(reply)
    }

    private func answer(_ output: String) -> HelmProcess.Result {
        HelmProcess.Result(status: exitStatus, output: output)
    }
}

final class FakeCreds: VPNCredentialsPort {
    var map: [String: VPNCredentials] = [:]
    func credentials(for name: String) -> VPNCredentials? { map[name] }
}

/// Records the observer's lifetime as well as its callback: an observer a
/// module starts has to stop, and "did it stop" is the assertion that catches
/// the callback landing on a freed engine.
final class FakeNetwork: NetworkWatchPort {
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var onChange: (@Sendable () -> Void)?

    func startObserving(_ onChange: @escaping @Sendable () -> Void) {
        starts += 1
        self.onChange = onChange
    }
    func stopObserving() {
        stops += 1
        onChange = nil
    }
    /// Only fires while something is watching, like the real store.
    func fire() { onChange?() }
}

final class FakeApps: AppObserverPort {
    var bundleIDs: Set<String> = []
    private(set) var onChange: (@Sendable () -> Void)?

    func runningBundleIDs() -> Set<String> { bundleIDs }
    func startObserving(_ onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
    }
    func fire() { onChange?() }
}
