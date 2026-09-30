import XCTest
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **The pause: nothing on a keystroke, one ask once the local filter has had
/// its say — apart from the real field that drives it.**
///
/// The owner's decision, 2026-09-22: typing filters the current tab's own
/// list, and only once that filter finds nothing does a pause start toward
/// asking brew about a word that is not installed — cancelled by the very
/// next keystroke. `ATypedWordAsksBrewAfterAPauseTests` (`Tests/HelmAppTests`)
/// drives the real `NSSearchField`; this drives `HomebrewViewModel.query`
/// directly, which is the seam the field's own binding writes into, and is
/// where the trigger rule itself — `ownListShowsNothing(for:)` — can be held
/// without a window.
@MainActor
final class AWordNotHereIsAskedAfterAPauseTests: XCTestCase {

    /// Answers every query at once — the pause itself is what this file times,
    /// so nothing here needs to hold a reply back the way
    /// `AStaleSearchDoesNotLandOnANewerOneTests`'s fake does, apart from
    /// `heldInstalled`, held for exactly one scenario below.
    private final class Counter: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }
        private var installedList: [BrewPackage]
        private var outdatedList: [OutdatedPackage]
        init(installed: [BrewPackage] = [], outdated: [OutdatedPackage] = []) {
            installedList = installed
            outdatedList = outdated
        }

        private let lock = NSLock()
        private var asked: [String] = []
        var searches: [String] { lock.withLock { asked } }

        /// Held until `releaseInstalled()` — for the one scenario that needs
        /// `brew list` to answer *during* the pause rather than before it.
        private let installedGate = DispatchSemaphore(value: 0)
        private var holdInstalled = false
        func heldInstalled(_ list: [BrewPackage]) {
            lock.withLock { holdInstalled = true; installedList = list }
        }
        func releaseInstalled() { installedGate.signal() }

        /// Held and then refused rather than answered — a word typed before
        /// the list has answered must still be asked once the refusal lands,
        /// with no second keystroke.
        private var refuseInstalledOnRelease = false
        func heldInstalledThenRefused() { lock.withLock { holdInstalled = true; refuseInstalledOnRelease = true } }

        func setOutdated(_ list: [OutdatedPackage]) { lock.withLock { outdatedList = list } }

        /// Held until `releaseOutdated()` — a cold `brew outdated` measured at
        /// 7.4 s (`SystemPorts.swift`'s own probe), long enough that the 700 ms
        /// pause always elapses first: this is what stands in for that gap.
        private let outdatedGate = DispatchSemaphore(value: 0)
        private var holdOutdated = false
        func heldOutdated(_ list: [OutdatedPackage]) {
            lock.withLock { holdOutdated = true; outdatedList = list }
        }
        func releaseOutdated() { outdatedGate.signal() }

        /// `heldInstalledThenRefused`'s twin for `brew outdated`.
        private var refuseOutdatedOnRelease = false
        func heldOutdatedThenRefused() { lock.withLock { holdOutdated = true; refuseOutdatedOnRelease = true } }

        /// Held until `releaseDescriptions()` — the one thing that lands
        /// *after* `brew list`, which is exactly the gap
        /// `testAWordThatOnlyMatchesADescriptionLoadedMidPauseSendsNothing`
        /// needs open: `refreshInstalled` sets `installedReading = .answered`
        /// and only then awaits this call, so a query typed once that line has
        /// run already sees a landed, name-only-empty list and genuinely arms
        /// a pause — unlike `heldInstalled`, which delays the line that would
        /// arm one in the first place.
        private let descriptionsGate = DispatchSemaphore(value: 0)
        private var holdDescriptions = false
        private var pendingDescriptions: [String: String] = [:]
        func heldDescriptions(_ answers: [String: String]) {
            lock.withLock { holdDescriptions = true; pendingDescriptions = answers }
        }
        func releaseDescriptions() { descriptionsGate.signal() }

        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled:
                if lock.withLock({ holdInstalled }) {
                    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                        DispatchQueue.global().async { self.installedGate.wait(); c.resume() }
                    }
                }
                if lock.withLock({ refuseInstalledOnRelease }) { throw CancellationError() }
                return try JSONEncoder().encode(lock.withLock { installedList })
            case .outdated:
                if lock.withLock({ holdOutdated }) {
                    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                        DispatchQueue.global().async { self.outdatedGate.wait(); c.resume() }
                    }
                }
                if lock.withLock({ refuseOutdatedOnRelease }) { throw CancellationError() }
                return try JSONEncoder().encode(lock.withLock { outdatedList })
            case .search:
                let word = String(data: command.payload, encoding: .utf8) ?? ""
                lock.withLock { asked.append(word) }
                return try JSONEncoder().encode([SearchHit]())
            case .descriptions:
                guard let req = try? JSONDecoder().decode(DescriptionsRequest.self, from: command.payload)
                else { return try JSONEncoder().encode([String: String]()) }
                if lock.withLock({ holdDescriptions }) {
                    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                        DispatchQueue.global().async { self.descriptionsGate.wait(); c.resume() }
                    }
                }
                let answer = lock.withLock { pendingDescriptions }
                    .filter { req.names.contains($0.key) }
                return try JSONEncoder().encode(answer)
            default: return Data()
            }
        }
    }

    /// A pause well short of the owner's real 700 ms, so each case exercises
    /// the timer itself rather than waiting it out on a real clock.
    private static let pause: Duration = .milliseconds(60)

    private func model(installed: [BrewPackage] = []) -> (Counter, HomebrewViewModel) {
        let transport = Counter(installed: installed)
        let vm = HomebrewViewModel(vm: ModuleViewModel(transport: transport))
        vm.searchPause = Self.pause
        return (transport, vm)
    }

    /// A real deadline, never an exact sleep and never a bare `Task.yield` —
    /// the second buys a turn on the pool and no wall-clock time at all
    /// (CLAUDE.md).
    private func waitForASearch(_ transport: Counter,
                                deadline: Duration = .milliseconds(500)) async {
        let start = ContinuousClock.now
        while transport.searches.isEmpty, ContinuousClock.now - start < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func testAWordNotInstalledIsAskedAfterThePause() async {
        let (transport, vm) = model()
        await vm.loadIfNeeded()
        vm.query = "zzqq"
        XCTAssertEqual(transport.searches, [], "the pause has not elapsed yet")
        await waitForASearch(transport)
        XCTAssertEqual(transport.searches, ["zzqq"])
    }

    /// Retyping over an unfinished pause must restart it, not race it.
    ///
    /// **Two guards, both proven load-bearing together, and each redundant of
    /// the other for this exact case.** Measured 2026-09-24: cutting
    /// `pause?.cancel()` alone left this green, because `searchAfterPause`'s
    /// own re-read of `query` against `q` catches the same staleness; cutting
    /// only that re-read left it green too, because the cancelled task never
    /// reaches the line it would have guarded. Cutting both together turned it
    /// red — `["zzq"]` where `["zzqq"]` was expected — which is the only
    /// combination this one scenario can tell apart. The two are kept as
    /// separate defences on purpose (cancelling holds down the number of
    /// tasks in flight; the re-read is what protects a caller that reaches
    /// `searchAfterPause` some other way), and this test's own doc comment
    /// says so rather than crediting either line alone with more than this
    /// measurement showed.
    func testRetypingBeforeThePauseFiresSendsOnlyTheLastWord() async {
        let (transport, vm) = model()
        await vm.loadIfNeeded()
        vm.query = "zzq"
        try? await Task.sleep(for: .milliseconds(30))
        vm.query = "zzqq"
        await waitForASearch(transport)
        XCTAssertEqual(transport.searches, ["zzqq"], """
            \(transport.searches) — a stale prefix's own pause must not have reached brew \
            once a newer word had been typed
            """)
    }

    /// The trigger rule's own floor: an installed row already answers the
    /// question, so nothing is asked.
    func testAWordThatMatchesAnInstalledPackageAsksNothing() async {
        let (transport, vm) = model(installed: [BrewPackage(name: "wget", version: "1.25.0",
                                                             isCask: false)])
        await vm.loadIfNeeded()
        vm.query = "wget"
        await waitForASearch(transport, deadline: .milliseconds(250))
        XCTAssertEqual(transport.searches, [], "the installed row already answers \"wget\"")
    }

    /// `shortestAutomaticQuery` — measured against `brew search --formula|--cask`
    /// on this Mac 2026-09-24: `a` alone answers 3575 formula hits and 4750
    /// cask hits, a `brew desc` batch over thousands of names for one
    /// keystroke.
    func testAOneCharacterWordIsNotAskedAutomatically() async {
        let (transport, vm) = model()
        await vm.loadIfNeeded()
        vm.query = "z"
        await waitForASearch(transport, deadline: .milliseconds(250))
        XCTAssertEqual(transport.searches, [], "one character is under the floor")
    }

    /// Switching tabs re-evaluates the trigger, but a word already answered is
    /// not asked a second time just because the tab moved — and the section
    /// stays visible on the new tab.
    func testSwitchingTabWithTheSectionAlreadyThereAsksNothingAgain() async {
        let (transport, vm) = model()
        await vm.loadIfNeeded()
        vm.query = "zzqq"
        await waitForASearch(transport)
        XCTAssertEqual(transport.searches, ["zzqq"], "precondition: the first ask went out")

        vm.segment = .updates
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(transport.searches, ["zzqq"], """
            \(transport.searches) — switching tabs asked brew again for a word it had \
            already answered
            """)
        XCTAssertNotNil(vm.section, "the section must still be there on the new tab")
    }

    /// Erasing the field retires the held answer outright — the one case that
    /// really does clear rather than merely hide it (`AvailableSection`'s own
    /// doc comment on the difference).
    func testErasingTheQueryDropsTheHeldAnswer() async {
        let (transport, vm) = model()
        await vm.loadIfNeeded()
        vm.query = "zzqq"
        await waitForASearch(transport)
        XCTAssertNotNil(vm.section, "precondition: the section is there")

        vm.query = ""
        XCTAssertNil(vm.section, "an emptied field must not go on showing the old word's answer")
    }

    /// The owner's own number, pinned so a future change to it is a decision
    /// rather than a slip.
    func testThePauseIsTheOwnersNumber() {
        XCTAssertEqual(HomebrewViewModel.searchPause, .milliseconds(700))
    }

    // MARK: - A tab switch waits for the pause rather than asking at once

    /// **Switching to a tab that has not loaded yet must not ask brew before
    /// that tab's own refresh has had a chance to run.** `segment`'s own
    /// `didSet` used to call `ask(_:)` directly, so a word already matching
    /// `outdated` was asked about the moment the tab changed — before
    /// `refreshOutdated()`, which the page's own `.onChange(of: segment)`
    /// runs right after, had sent a single byte. Through the pause instead:
    /// the assertion below runs immediately after `refreshOutdated()`
    /// completes, with no sleep in between, which is exactly the window the
    /// direct `ask(_:)` call used to fill.
    func testSwitchingToATabThatHasNotLoadedYetWaitsForThePause() async {
        let (transport, vm) = model()
        transport.setOutdated([OutdatedPackage(name: "node", installed: "26.8.2",
                                               latest: "26.9.0", isCask: false)])
        await vm.loadIfNeeded()
        vm.query = "node"

        vm.segment = .updates
        await vm.refreshOutdated()

        XCTAssertEqual(vm.shownOutdated.map(\.name), ["node"], "precondition: the list loaded")
        XCTAssertEqual(transport.searches, [], """
            \(transport.searches) — brew was asked about "node" before `refreshOutdated` had \
            even run, off a list this Mac already has
            """)

        // And the pause that *was* scheduled fires into a list that has since
        // loaded, so nothing is asked afterwards either.
        await waitForASearch(transport, deadline: .milliseconds(250))
        XCTAssertEqual(transport.searches, [])
    }

    // MARK: - The fire-time re-read covers a list answered mid-pause

    /// **This is a vacuous pass and not a proof of the fire-time re-read —
    /// corrected 2026-09-25.** This file used to claim that cutting
    /// `searchAfterPause`'s own `ownListShowsNothing` guard left this case
    /// green because `refreshInstalled`'s own `scheduleAutomaticSearch` call
    /// "cooperates" with it. Measured: neither ever runs. `vm.query = "wget"`
    /// below is set while `installedReading` is still `.waiting`, and
    /// `ownListShowsNothing`'s own guard (`installedReading != .waiting`)
    /// makes `scheduleAutomaticSearch` return with no pause armed at all —
    /// `pause` stays nil. Once the list lands, `refreshInstalled`'s own
    /// `scheduleAutomaticSearch(for:)` call runs a second time, and by then
    /// `shownInstalled` already holds the exact name "wget", so that call's
    /// own guard refuses to arm a pause either. `searchAfterPause` is never
    /// reached, so removing its guard leaves this exact test exactly as
    /// green as before — this case is worth keeping for what it does prove
    /// (a list that answers mid-pause with an exact name match asks
    /// nothing), but it is not the fire-time-re-read regression test the
    /// header used to say it was. `testAWordThatOnlyMatchesADescriptionLoaded-
    /// MidPauseSendsNothing` below is that test: its query never matches a
    /// name, only a description that lands *after* the list, which is the
    /// one shape that leaves a pause armed and lets `searchAfterPause`'s own
    /// re-read be the thing that catches the newly-widened list.
    func testAnInstalledListThatAnswersDuringThePauseSendsNothing() async {
        let transport = Counter()
        let vm = HomebrewViewModel(vm: ModuleViewModel(transport: transport))
        vm.searchPause = Self.pause
        transport.heldInstalled([BrewPackage(name: "wget", version: "1.25.0", isCask: false)])

        let loading = Task { await vm.loadIfNeeded() }
        // Typed before `brew list` has answered — `installedReading` is still
        // `.waiting` and `shownInstalled` is still empty, which schedules the
        // pause the same way a genuine miss would.
        vm.query = "wget"

        try? await Task.sleep(for: Self.pause / 2)
        transport.releaseInstalled()
        await loading.value

        await waitForASearch(transport, deadline: .milliseconds(250))
        XCTAssertEqual(transport.searches, [], """
            \(transport.searches) — the installed list answered "wget" during the pause, and \
            the fire-time re-read must have found it
            """)
        XCTAssertEqual(vm.shownInstalled.map(\.name), ["wget"], "precondition: the list did land")
    }

    /// **The actual fire-time-re-read regression test.** `refreshInstalled`
    /// sets `installedReading = .answered` and only then awaits
    /// `loadDescriptions` — so a query typed once the list has landed but
    /// before its description has genuinely arms a pause off a list that
    /// `ownListShowsNothing` reads as empty (the name "curl" does not match
    /// "wget"). Releasing the description partway through must leave the
    /// fire-time read seeing the description that just arrived — the only
    /// door `PackageStanding.matching` opens besides the name. Mutation:
    /// drop `ownListShowsNothing(for: q)` from `searchAfterPause`'s own guard
    /// and this test alone (of the two in this section) goes red, «wget»
    /// asked over a description that had already made it unnecessary.
    func testAWordThatOnlyMatchesADescriptionLoadedMidPauseSendsNothing() async {
        let transport = Counter(installed: [BrewPackage(name: "curl", version: "8.9.0",
                                                         isCask: false)])
        transport.heldDescriptions(["curl": "Transfer a file, wget-style, from a server"])
        let vm = HomebrewViewModel(vm: ModuleViewModel(transport: transport))
        vm.searchPause = Self.pause

        let loading = Task { await vm.loadIfNeeded() }
        // The list is not held, so this settles the moment it lands —
        // `installedReading == .answered` — while `loadIfNeeded` itself is
        // still parked inside the held `loadDescriptions` call beneath it.
        let deadline = ContinuousClock.now + .milliseconds(500)
        while !vm.loadedInstalled, ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertTrue(vm.loadedInstalled, "precondition: the installed list never landed")

        vm.query = "wget"
        XCTAssertEqual(vm.shownInstalled, [], """
            precondition: "curl" already matches "wget" with no description landed at all, so \
            this case is not testing what it means to
            """)

        try? await Task.sleep(for: Self.pause / 2)
        transport.releaseDescriptions()
        await loading.value

        await waitForASearch(transport, deadline: .milliseconds(250))
        XCTAssertEqual(transport.searches, [], """
            \(transport.searches) — curl's description matching "wget" landed during the pause, \
            and the fire-time re-read must have found it
            """)
        XCTAssertEqual(vm.shownInstalled.map(\.name), ["curl"], """
            precondition: the description never actually landed, so the assertion above proved \
            nothing about a re-read
            """)
    }

    /// **The pause firing before `brew outdated` answers must not ask brew
    /// either.** `ownListShowsNothing` used to read `shownOutdated.isEmpty` on
    /// its own, which is exactly as true of an unread list as of a genuinely
    /// empty one — so a cold `brew outdated` (measured at 7.4 s) left the
    /// pause firing into a list that had not answered yet, every time. This
    /// is `testAnInstalledListThatAnswersDuringThePauseSendsNothing`'s own
    /// scenario one call site over: there the list answers mid-pause, here it
    /// has not answered even once the pause has *fired*.
    func testAColdOutdatedListDoesNotGetAskedAtThePause() async {
        let (transport, vm) = model()
        transport.heldOutdated([OutdatedPackage(name: "node", installed: "26.8.2",
                                                latest: "26.9.0", isCask: false)])
        await vm.loadIfNeeded()
        vm.query = "node"

        vm.segment = .updates
        let refreshing = Task { await vm.refreshOutdated() }

        // The pause is well past by now, and `brew outdated` still has not
        // answered — `outdatedReading` is `.waiting`.
        try? await Task.sleep(for: Self.pause * 3)
        XCTAssertEqual(transport.searches, [], """
            \(transport.searches) — brew was asked about "node" while `brew outdated` was \
            still out, off a reading `ownListShowsNothing` must not read as empty
            """)

        transport.releaseOutdated()
        await refreshing.value
        XCTAssertEqual(vm.shownOutdated.map(\.name), ["node"], "precondition: the list landed")

        // And the list landing re-evaluates the trigger on its own, correctly
        // finding a match this time.
        await waitForASearch(transport, deadline: .milliseconds(250))
        XCTAssertEqual(transport.searches, [], "\"node\" is on the list that just landed")
    }

    // MARK: - A refusal reschedules the pause on its own, with no second keystroke

    /// **A word typed while `brew list` is out must be asked once the
    /// refusal lands, without the person typing anything else.**
    /// `queryMoved()`'s own call to `scheduleAutomaticSearch` armed nothing
    /// while `installedReading == .waiting` (`ownListShowsNothing`'s own
    /// guard), and before this pass nothing else re-asked the question once
    /// the refusal actually landed — only a *successful* `refreshInstalled`
    /// rescheduled. Mutation: remove the rescheduling line this pass added to
    /// `refreshInstalled`'s refusal branch, and this test goes red.
    func testARefusedInstalledListStillFiresThePauseOnceTheRefusalLands() async {
        let transport = Counter()
        let vm = HomebrewViewModel(vm: ModuleViewModel(transport: transport))
        vm.searchPause = Self.pause
        transport.heldInstalledThenRefused()

        let loading = Task { await vm.loadIfNeeded() }
        // Typed before `loadIfNeeded()`'s own task has even run its first
        // line — this test's own body is `@MainActor` and never suspends
        // between the `Task { … }` above and this assignment, so the new
        // task has not started and `installedReading` still reads
        // `.notAsked` here, not `.waiting`. `ownListShowsNothing`'s guard
        // treats the two alike, so the precondition below does not need
        // `.waiting` specifically — only that the list has not yet answered.
        vm.query = "zzqq"
        transport.releaseInstalled()
        await loading.value
        XCTAssertEqual(vm.installedReading, .unanswerable, "precondition: the list refused")

        await waitForASearch(transport)
        XCTAssertEqual(transport.searches, ["zzqq"], """
            \(transport.searches) — "zzqq" was typed while the list was still loading and \
            never asked once the refusal landed
            """)
    }

    /// **The same fix's twin for `brew outdated`.**
    func testARefusedOutdatedListStillFiresThePauseOnceTheRefusalLands() async {
        let (transport, vm) = model()
        await vm.loadIfNeeded()
        transport.heldOutdatedThenRefused()

        vm.segment = .updates
        let refreshing = Task { await vm.refreshOutdated() }
        vm.query = "zzqq"
        transport.releaseOutdated()
        await refreshing.value
        XCTAssertEqual(vm.loadedOutdated, false, "precondition: the list refused")

        await waitForASearch(transport)
        XCTAssertEqual(transport.searches, ["zzqq"], """
            \(transport.searches) — "zzqq" was typed while `brew outdated` was still out and \
            never asked once the refusal landed
            """)
    }

    /// **Состояние asks nothing, and the word waits for a tab that can show
    /// the answer.** The "Available to install" section is not drawn under
    /// Состояние — a search for a package is not a question about this Mac's
    /// health — so a `brew search` asked from there would be paid for and never
    /// seen. Neither the pause nor Return asks; the word stays in the field,
    /// and the first package tab it is carried to asks for it as it always did.
    ///
    /// The `Counter` answers no `.config` and no `.doctor` case at all, which
    /// `client.request` reads as a refusal — the reading that used to be the
    /// one an unseen ask was armed by. Mutation, run 2026-09-29: answering
    /// `shownInstalled.isEmpty` from `ownListShowsNothing`'s `.health` arm
    /// instead of `false` turned this case red.
    func testAWordTypedUnderTheHealthTabIsNotAsked() async {
        let (transport, vm) = model()
        await vm.loadIfNeeded()
        vm.segment = .health
        await vm.refreshConfig()
        await vm.refreshDoctor()
        XCTAssertNotEqual(vm.doctor, .notAsked, "precondition: doctor has been asked at least once")

        vm.query = "zzqq"
        await waitForASearch(transport, deadline: .milliseconds(300))
        XCTAssertEqual(transport.searches, [], """
            \(transport.searches) — a word typed under Состояние went to `brew search`, for an \
            answer the tab has no place to draw
            """)

        vm.searchNow()
        await waitForASearch(transport, deadline: .milliseconds(300))
        XCTAssertEqual(transport.searches, [], "Return under Состояние asked brew about a package")

        vm.segment = .installed
        await waitForASearch(transport)
        XCTAssertEqual(transport.searches, ["zzqq"], """
            \(transport.searches) — the word did not survive the trip to a tab that draws the \
            section, so nothing ever asked about it
            """)
    }
}
