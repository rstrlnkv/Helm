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

/// **Two tiers, like the real port.**
///
/// `KeychainCredentials` answers from Helm's own login-keychain cache without
/// troubling anybody, and reaches `/usr/bin/security` against the System keychain
/// — which macOS gates behind a dialog — only on a miss. With one dictionary here,
/// «the secret exists but only behind a prompt» was a state no test could write
/// down, so «a rule summoned an authorization dialog» could not be written down
/// either, whatever anybody wrote.
final class FakeCreds: VPNCredentialsPort {
    /// Readable with no prompt: Helm's own cache.
    var map: [String: VPNCredentials] = [:]
    /// Readable only where a prompt is allowed: the System keychain.
    var behindAPrompt: [String: VPNCredentials] = [:]
    /// Every ask, so a test can see that nothing was asked at all — which is a
    /// different fact from any of the three answers.
    private(set) var asks: [(name: String, promptingAllowed: Bool)] = []

    func credentials(for name: String, promptingAllowed: Bool) -> VPNCredentialRead {
        asks.append((name, promptingAllowed))
        if let cached = map[name] { return answer(cached) }
        guard let stored = behindAPrompt[name] else {
            // Neither tier has anything: the configuration keeps no secret Helm
            // supplies, which is what an IKEv2 or WireGuard service looks like
            // here. The real port answers this from the absence of an
            // `AuthPassword` field.
            return .notNeeded
        }
        guard promptingAllowed else { return .behindAPrompt }
        // **The read a person's gesture allows also fills the cache**, which is
        // what makes one press of Connect enough for every automatic connect
        // afterwards. A fake that read the System tier and left the cache empty
        // could not represent that, and «the press repaired it» is the state the
        // notice on screen tells people to produce.
        map[name] = stored
        return answer(stored)
    }

    /// `.ready` only ever carries a usable secret, exactly as `KeychainCredentials`
    /// builds it — a fake free to answer `.ready` with nothing in it would be
    /// freer than the port it stands for (CLAUDE.md § A fake can also be freer
    /// than the port).
    private func answer(_ creds: VPNCredentials) -> VPNCredentialRead {
        creds.secret?.isEmpty == false ? .ready(creds) : .notNeeded
    }
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

/// The signature the fake rules in this target are bound to.
///
/// A rule is not fired on a bundle identifier alone any more — `VPNRuleTrust`
/// refuses one whose running instance is not signed as the app the person picked,
/// and one with no identity on record refuses outright. Five test files spelled
/// the same `com.a` rule out by hand as JSON, and all five stopped firing when
/// that landed, which is the change working and five places to arrange one thing.
/// The JSON stays JSON rather than becoming `VPNRules.encode`, so these tests go
/// on holding what is actually on disk.
let testAppIdentity = CodeIdentity(signingID: "com.a", teamID: "ABCDE12345")

/// The rule for `com.a`, bound to `testAppIdentity`, connecting on launch and
/// disconnecting on quit. Interpolated from the identity above rather than spelled
/// beside it: two copies that drift make every rule in the target stop firing for
/// a reason no failure message names.
let ruleJSONForA = """
    {"com.a":{"vpnName":"A","connectOnLaunch":true,"disconnectOnQuit":true,\
    "identity":{"signingID":"\(testAppIdentity.signingID ?? "")",\
    "teamID":"\(testAppIdentity.teamID ?? "")"}}}
    """

final class FakeApps: AppObserverPort {
    var bundleIDs: Set<String> = []
    /// What each running identifier is **signed** as, which is the question a
    /// bundle id cannot answer. An identifier with no entry here stands for an
    /// instance whose signature could not be read at all — a real state, and the
    /// one a forged bundle in a place the reader cannot follow would produce.
    var identities: [String: CodeIdentity] = [:]
    private(set) var onChange: (@Sendable () -> Void)?

    func runningBundleIDs() -> Set<String> { bundleIDs }
    func identity(of bundleID: String) -> CodeIdentity? { identities[bundleID] }
    func startObserving(_ onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
    }
    func fire() { onChange?() }

    /// An observer whose `com.a` is signed as `ruleJSONForA` expects — the
    /// ordinary case, so a test about something else does not have to arrange a
    /// signature to get a rule to fire.
    static func trustingA() -> FakeApps {
        let apps = FakeApps()
        apps.identities["com.a"] = testAppIdentity
        return apps
    }
}
