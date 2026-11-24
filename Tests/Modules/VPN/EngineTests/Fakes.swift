// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmRuntime
import XCTest
@testable import Module_VPN_Engine

/// One scripted answer of `FakeRunner.handler`: a result, or a tool that never answers.
enum RunnerStep { case answer(HelmProcess.Result), hang }

final class FakeRunner: VPNRunnerPort, @unchecked Sendable {
    private let issuedLock = NSLock()
    private var _issued: [[String]] = []
    /// Every command, in order. Behind a lock: the engine asks from its own queue,
    /// the test reads from its own thread.
    var issued: [[String]] { issuedLock.withLock { _issued } }
    func count(of args: [String]) -> Int { issued.filter { $0 == args }.count }

    /// A tool scripted per command, **and one that can be made to never answer**
    /// (`.hang`), which the port really can be: a command parks its caller until
    /// `releaseAll()`, a query comes back at once with `HelmProcess.timedOutStatus`
    /// and no output, as the real runner does once its deadline has passed, so a
    /// test never waits out a clock. `nth` is how many times this exact command
    /// was issued before. Takes precedence over every other answer here.
    var handler: (@Sendable (_ args: [String], _ nth: Int) -> RunnerStep)?
    private let release = DispatchSemaphore(value: 0)
    /// Lets every parked call go, so no thread outlives its test.
    func releaseAll() { for _ in 0..<16 { release.signal() } }

    var listOutput: String = ""

    init(list: String = "") { listOutput = list }

    /// **Consecutive answers to `--nc list`, which is what the real tool gives.**
    ///
    /// `--nc start` is followed by a list that still says `Disconnected`, then
    /// `Connecting`, then `Connected`, and `pollUntilSettled` re-reads waiting for
    /// that. A fixed answer could not write «the tunnel came up on the third read»,
    /// and `maxPollAttempts` would have no test.
    ///
    /// Reads past the end repeat the last entry, because a settled tunnel keeps
    /// answering the same thing. Empty means «use `listOutput`».
    var listScript: [String] = []
    /// How many of the first `--nc list` reads exit non-zero, as a tool that was
    /// not ready does; the later ones answer from `listOutput`/`listScript`.
    var failingListReads = 0
    private var listReads = 0

    /// What `--nc status <name>` answers, per configuration name.
    ///
    /// Keyed by name because that is what the tool takes: the interface cannot
    /// be looked up by the id in `--nc list`, which is a *configuration*'s id
    /// (`VPNStatusParser`). A name with no entry here is a connection the tool
    /// can name no interface for — down, or coming up — which is a state the
    /// real tool is in for most of every session.
    var statusOutput: [String: String] = [:]

    /// What `start` and `stop` answer, **per configuration name**.
    ///
    /// The real tool answers per name, so one stop refused among several is
    /// written here rather than by mutating the fake between calls.
    var replies: [String: String] = [:]

    /// What `start` and `stop` answer when no name-specific answer is set.
    ///
    /// `""` is what the real tool prints when it **succeeded**; it reports
    /// failure by printing a line and exiting 0 (`No service`).
    var reply: String = ""

    /// **A tool that did not run**: `scutil` missing, or refused by the sandbox,
    /// is empty output — the same value it prints when it succeeded — told apart
    /// only by the exit status the port carries. `-1` is what `HelmProcess`
    /// answers when the launch itself threw.
    var exitStatus: Int32 = 0

    /// How many times the tool was asked for the list. The engine polls, so
    /// «did it re-read» is a count rather than a fact.
    var listReadCount: Int { issued.count { $0 == ["--nc", "list"] } }

    /// Called with each command as it is issued, on the thread that issued it.
    ///
    /// The engine runs the tool on its own serial queue, so «the tool was
    /// reached» arrives on another thread, and reading `issued` from the test's
    /// thread would be a race and a poll. Under its own lock because two threads
    /// touch it.
    var onRun: (@Sendable ([String]) -> Void)? {
        get { hook.lock(); defer { hook.unlock() }; return _onRun }
        set { hook.lock(); _onRun = newValue; hook.unlock() }
    }
    private let hook = NSLock()
    private var _onRun: (@Sendable ([String]) -> Void)?

    /// Every `start(_:supplying:)` the engine made, in order: the credentials
    /// travel here and never through `issued`, which is the point.
    var supplied: [(name: String, credentials: VPNCredentials)] = []
    /// What the in-process start answers; the port's four states and no more.
    var startAnswer: VPNStartAnswer = .started

    func start(_ name: String, supplying credentials: VPNCredentials) -> VPNStartAnswer {
        supplied.append((name, credentials))
        return startAnswer
    }

    /// A query answers as a command does: this fake never runs out of time.
    /// A read that does is scripted with `handler`.
    func read(_ args: [String], timeout: TimeInterval) -> HelmProcess.Result {
        perform(args, bounded: true)
    }

    func run(_ args: [String]) -> HelmProcess.Result { perform(args, bounded: false) }

    private func perform(_ args: [String], bounded: Bool) -> HelmProcess.Result {
        onRun?(args)
        let nth = issuedLock.withLock {
            let n = _issued.filter { $0 == args }.count
            _issued.append(args)
            return n
        }
        if let step = handler?(args, nth) {
            switch step {
            case .answer(let result): return result
            case .hang:
                if bounded { return .init(status: HelmProcess.timedOutStatus, output: "") }
                _ = release.wait(timeout: .now() + 120)
                return .init(status: -1, output: "")
            }
        }
        if args == ["--nc", "list"] {
            defer { listReads += 1 }
            if listReads < failingListReads { return HelmProcess.Result(status: 1, output: "") }
            guard !listScript.isEmpty else { return answer(listOutput) }
            return answer(listScript[min(listReads, listScript.count - 1)])
        }
        // Before the `replies` lookup below, which is keyed by the same last
        // argument: a test scripting a refused `--nc start` must not have that
        // refusal answered to a status read as well.
        if args.count == 3, args[0] == "--nc", args[1] == "status" {
            return answer(statusOutput[args[2]] ?? "No service")
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
/// — which macOS gates behind a dialog — only on a miss, so «the secret exists
/// but only behind a prompt» is a state a test can write down.
final class FakeCreds: VPNCredentialsPort {
    /// Readable with no prompt: Helm's own cache.
    var map: [String: VPNCredentials] = [:]
    /// Readable only where a prompt is allowed: the System keychain.
    var behindAPrompt: [String: VPNCredentials] = [:]
    /// Names whose credential read failed: the tool answered nothing usable, so
    /// nobody knows whether a secret is kept (`VPNCredentialRead.unreadable`).
    var unreadable: Set<String> = []
    /// Every ask, so a test can see that nothing was asked at all — which is a
    /// different fact from any of the three answers.
    private(set) var asks: [(name: String, promptingAllowed: Bool)] = []

    func credentials(for name: String, promptingAllowed: Bool) -> VPNCredentialRead {
        asks.append((name, promptingAllowed))
        if unreadable.contains(name) { return .unreadable }
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
        // afterwards — the state the notice on screen tells people to produce.
        map[name] = stored
        return answer(stored)
    }

    /// `.ready` only ever carries a usable secret, exactly as `KeychainCredentials`
    /// builds it: a fake free to answer `.ready` with nothing in it would be freer
    /// than the port it stands for (Architecture/TestsAndMeasurement.md § Fakes).
    private func answer(_ creds: VPNCredentials) -> VPNCredentialRead {
        creds.secret?.isEmpty == false ? .ready(creds) : .notNeeded
    }
}

/// A clock the test moves, for anything this module measures an interval by.
///
/// The engine takes its own `now` so a firing's moment is a fact of the caller
/// rather than of the machine, and the settle is a clock rather than a timer
/// for the reason `VPNDropSettle` gives — `VPNWorkQueue.inline` runs a delayed
/// block at once, so a test of the wait would be over before it began.
///
/// One clock for the target, so tests do not each write their own
/// (Architecture/TestsAndMeasurement.md § Tests and measurement).
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date

    /// The epoch does not matter to a test that measures from its own start,
    /// which is all of them; it is a parameter for the one that pins a date.
    init(_ start: Date = Date(timeIntervalSince1970: 1_700_000_000)) { _now = start }

    var now: Date {
        get { lock.lock(); defer { lock.unlock() }; return _now }
        set { lock.lock(); _now = newValue; lock.unlock() }
    }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
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
/// `VPNRuleTrust` refuses a rule whose running instance is not signed as the
/// app the person picked, and one with no identity on record outright, so every
/// rule in this target is bound to one signature. The JSON stays JSON rather
/// than becoming `VPNRules.encode`, so these tests hold what is actually on disk.
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
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var onChange: (@Sendable () -> Void)?

    func runningBundleIDs() -> Set<String> { bundleIDs }
    func identity(of bundleID: String) -> CodeIdentity? { identities[bundleID] }
    func startObserving(_ onChange: @escaping @Sendable () -> Void) {
        starts += 1
        self.onChange = onChange
    }
    func stopObserving() {
        stops += 1
        onChange = nil
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

/// The fixture two blip files share: a tunnel Helm itself raised, because that is
/// what a drop is about. `_autoConnected` is written by an *automatic* connect — a
/// rule firing for an app that launched — not by a command somebody sent.
private let blipBundleID = "com.example.app"
private let blipIdentity = CodeIdentity(signingID: "com.example.app", teamID: "ABCDE12345")

func blipList(_ status: String) -> String {
    ["Available network connection services:",
     "* (\(status)) 11111111-1111-1111-1111-111111111111 VPN (com.x.work) \"work\" [VPN:com.x.work]"]
        .joined(separator: "\n")
}

func blipEngineHoldingTheTunnel(_ runner: FakeRunner, _ clock: TestClock) -> VPNEngine {
    let apps = FakeApps()
    apps.identities[blipBundleID] = blipIdentity
    apps.bundleIDs = [blipBundleID]
    let settings = VPNSettings.inMemory()
    settings.setRulesJSON(VPNRules.encode(
        [blipBundleID: VPNAppRule(vpnName: "work", identity: blipIdentity)]))
    runner.listOutput = blipList("Disconnected")
    // Every port named, none defaulted: three of the defaults reach the
    // network or run a tool for many seconds (`NoTestTakesAProductionPortTests`).
    let engine = VPNEngine(settings: settings, runner: runner, apps: apps,
                           interfaces: FakeInterfaces(), exit: FakeExit(),
                           speed: FakeSpeed(), now: { clock.now }, work: .inline)
    engine.activate()
    runner.listOutput = blipList("Connected")
    engine.refresh()
    XCTAssertTrue(engine.autoConnected.contains("work"),
                  "precondition: Helm is not holding the tunnel, so nothing here is a drop")
    engine.clearLastAutomationForTesting()
    return engine
}

/// `scutil --nc status "<name>"` for a tunnel that is up, as the real tool writes
/// it: the tunnel's own `InterfaceName` inside the `IPv4` dictionary, the routing
/// flag one level out (absent when `primary` is nil), then any `extra` lines.
/// `TheInterfaceComesFromTheToolTests` carries the whole captured output, decoys and all.
func scutilStatus(_ interface: String = "utun4", primary: Bool? = nil, extra: [String] = []) -> String {
    (["Connected", "Extended Status <dictionary> {", "  IPv4 : <dictionary> {",
      "    InterfaceName : \(interface)", "  }"]
        + (primary.map { ["  IsPrimaryInterface : \($0 ? 1 : 0)"] } ?? [])
        + extra.map { "  " + $0 } + ["}"]).joined(separator: "\n")
}

extension VPNSettings {
    /// Settings over a store that lives and dies with the test, in the module's own namespace.
    static func inMemory() -> VPNSettings {
        VPNSettings(store: NamespacedStore(namespace: "vpn", backing: InMemoryKeyValueStore()))
    }
}

/// One `scutil --nc list` row in the plain IPSec shape, without the leading `*`.
func scutilListRow(_ status: String, _ name: String = "A",
                   id: String = "11111111-1111-1111-1111-111111111111") -> String {
    "(\(status)) \(id) IPSec \"\(name)\""
}
