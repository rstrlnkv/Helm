import XCTest
import HelmContract
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **The package view fills in; it never waits, and it never draws a figure
/// nobody measured.**
///
/// The first tier — name, version, description, action — is a function of the
/// lists the page already holds, so it is on screen the instant a row is
/// clicked. `brew info --json=v2` is a separate `brew` run behind the same
/// 90 s query deadline as every other one in this module
/// (`defaultQueryTimeout`, `Sources/Modules/Homebrew/Engine/SystemPorts.swift`),
/// and it answers `nil` three ways that the page cannot tell apart: brew
/// refused, brew is gone, or the document is a shape this build cannot read.
/// So the second tier is drawn from an answer or not drawn at all — a spinner
/// in place of the package, an empty tile or a zero standing in for a size
/// would each be the page claiming something about the machine that nothing
/// measured.
///
/// The query is superseded the way `search` and `askToUninstall` already are:
/// `LatestRequest`, a token per ask. What has to be dropped is the older
/// *answer* — a person clicking down a list of fifty rows leaves fifty asks
/// out, and the one that resolves last would otherwise describe a package that
/// is not on screen.
///
/// **The fake parks its answer on a real semaphore.** A fake that answered
/// synchronously would make every case here vacuous: the ask would be over
/// before the gesture under test happened, and a cooperative yield buys a turn
/// on the pool and no wall-clock time (CLAUDE.md, and the two sibling files
/// `AStaleSearchDoesNotLandOnANewerOneTests` and
/// `MovingOffThePackageRetiresAnUninstallAskTests` say the same).
@MainActor
final class TheInspectorDoesNotWaitForInfoTests: XCTestCase {

    private static let openssl = BrewPackage(name: "openssl@3", version: "3.6.4", isCask: false)
    private static let wget = BrewPackage(name: "wget", version: "1.25.0", isCask: false)

    /// Answers the lists at once and holds every `info` until the test releases
    /// that package's gate, so two asks can genuinely be in flight together.
    ///
    /// A gate **per package name** rather than one shared semaphore, for the
    /// reason `AStaleSearchDoesNotLandOnANewerOneTests` records: which of two
    /// parked callers a `DispatchSemaphore` wakes is not the test's to choose,
    /// and arrival order is the whole subject of the third case below.
    private final class HeldInfo: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }

        private let lock = NSLock()
        private var gates: [String: DispatchSemaphore] = [:]
        private var arrivals: [String: XCTestExpectation] = [:]
        private var calls: [String: Int] = [:]
        private var infos: [String: PackageInfo] = [:]
        private var list: [BrewPackage]

        init(list: [BrewPackage], infos: [String: PackageInfo]) {
            self.list = list
            self.infos = infos
        }

        /// Pushes one engine event into the view model's own loop — the door
        /// `refreshAfterOp` is reached through in the running app.
        func emit(_ event: EngineEvent) { stream.continuation.yield(event) }

        /// What this package will answer with from now on, for the case that
        /// asks again after an upgrade.
        func reanswer(_ name: String, info: PackageInfo, listedAs version: String) {
            lock.lock()
            infos[name] = info
            list = list.map {
                $0.name == name
                    ? BrewPackage(name: $0.name, version: version, isCask: $0.isCask)
                    : $0
            }
            lock.unlock()
        }

        /// Fulfilled the moment the `nth` `info` for `name` is inside the
        /// transport, so the test knows the ask is in flight rather than hoping.
        ///
        /// Keyed by the call's ordinal rather than by a fulfilment count: a
        /// single expectation asked for twice can only be waited on once, and
        /// the last case here has to wait for the first ask, act, and then wait
        /// for the second.
        func arrival(_ name: String, nth: Int = 1) -> XCTestExpectation {
            lock.lock(); defer { lock.unlock() }
            let key = "\(name)#\(nth)"
            if let existing = arrivals[key] { return existing }
            let made = XCTestExpectation(description: "info(\(name)) #\(nth) reached the transport")
            arrivals[key] = made
            return made
        }

        /// Lets the parked `info` for `name` answer.
        func release(_ name: String) { gate(for: name).signal() }

        func infoCalls(_ name: String) -> Int {
            lock.lock(); defer { lock.unlock() }; return calls[name] ?? 0
        }

        private func gate(for name: String) -> DispatchSemaphore {
            lock.lock(); defer { lock.unlock() }
            if let existing = gates[name] { return existing }
            let made = DispatchSemaphore(value: 0)
            gates[name] = made
            return made
        }

        /// Synchronous, for the reason the sibling fake gives: Swift 6 makes
        /// `NSLock.lock()` unavailable inside an `async` function, and a lock
        /// held across an await is a lock taken on one side of a field.
        private func entered(_ name: String) -> (PackageInfo?, XCTestExpectation?) {
            lock.lock(); defer { lock.unlock() }
            let nth = (calls[name] ?? 0) + 1
            calls[name] = nth
            return (infos[name], arrivals["\(name)#\(nth)"])
        }

        private func packages() -> [BrewPackage] {
            lock.lock(); defer { lock.unlock() }; return list
        }

        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled:
                return try JSONEncoder().encode(packages())
            case .outdated:
                return try JSONEncoder().encode([OutdatedPackage]())
            case .descriptions:
                return try JSONEncoder().encode([String: String]())
            case .info:
                guard let ref = try? JSONDecoder().decode(PackageRef.self, from: command.payload)
                else { return Data() }
                let (answer, arrival) = entered(ref.name)
                arrival?.fulfill()
                let gate = self.gate(for: ref.name)
                // Off the cooperative pool, the way the real wait is: a
                // semaphore parked inside an `async` function holds one of its
                // threads.
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                    DispatchQueue.global().async { gate.wait(); c.resume() }
                }
                guard let answer else { return Data() }
                return try JSONEncoder().encode(answer)
            default:
                return Data()
            }
        }
    }

    private static func info(_ name: String, version: String,
                            onRequest: Bool? = false) -> PackageInfo {
        PackageInfo(name: name, isCask: false, desc: "Cryptography and SSL/TLS Toolkit",
                    homepage: "https://openssl-library.org", license: "Apache-2.0",
                    tap: "homebrew/core", installedVersion: version,
                    installedAt: Date(timeIntervalSince1970: 1_757_700_000),
                    installedOnRequest: onRequest, deprecationReason: nil, replacement: nil,
                    siblings: ["openssl@1.1"], dependencies: ["ca-certificates"], caveats: nil)
    }

    private func fake() -> HeldInfo {
        HeldInfo(list: [Self.openssl, Self.wget],
                 infos: ["openssl@3": Self.info("openssl@3", version: "3.6.4"),
                         "wget": Self.info("wget", version: "1.25.0", onRequest: true)])
    }

    /// A loaded page with nothing selected, and no `info` ask spent on it.
    private func loaded(_ transport: HeldInfo) async -> HomebrewViewModel {
        let model = HomebrewViewModel(vm: ModuleViewModel(transport: transport))
        await model.loadIfNeeded()
        XCTAssertEqual(model.installed.count, 2, "the fixture list never arrived")
        XCTAssertEqual(transport.infoCalls("openssl@3"), 0,
                       "a package nobody has selected was asked about")
        return model
    }

    /// The first tier, read the one way the page reads it.
    private func firstTier(_ model: HomebrewViewModel) -> InspectorSubject? {
        guard case let .package(subject) = InspectorState.of(
            segment: model.segment, selected: model.selected, installed: model.installed,
            outdated: model.outdated, loadedOutdated: model.loadedOutdated,
            hits: model.searchHits, descriptions: model.descriptions)
        else { return nil }
        return subject
    }

    // MARK: - 1. The first tier does not wait

    /// Selecting a package puts the whole first tier on screen while the query
    /// is still inside brew — and puts **nothing** in `info`.
    ///
    /// The nil is the load-bearing half. An implementation that filled the
    /// second tier with a placeholder while it waited — an empty-string
    /// homepage, a zero size, a `PackageInfo` of nils standing in for "not
    /// answered yet" — would pass a test that only asked whether the name and
    /// the button were drawn.
    func testTheFirstTierDrawsWhileTheQueryIsStillOut() async {
        let transport = fake()
        let model = await loaded(transport)
        let arrived = transport.arrival("openssl@3")

        model.select(Self.openssl.id)
        await fulfillment(of: [arrived], timeout: 5)

        XCTAssertNil(model.info, """
            the page is holding \(String(describing: model.info)) for a query that has not \
            answered — every field of it is a claim about this Mac that nothing has measured
            """)
        guard let subject = firstTier(model) else {
            return XCTFail("the package view draws nothing at all while `info` is out — "
                           + "the first tier is waiting on a query it does not read")
        }
        XCTAssertEqual(subject.name, "openssl@3")
        XCTAssertEqual(subject.version, "3.6.4", "the version is the list's, not the query's")
        XCTAssertEqual(subject.action, .uninstall)

        transport.release("openssl@3")
        await model.infoAsk?.value
    }

    // MARK: - 2. The answer lands

    /// The subject asserted before any absence: without this the two cases
    /// either side would hold against a view model that never asks at all.
    func testTheAnswerLandsOnInfoWhenItIsReleased() async {
        let transport = fake()
        let model = await loaded(transport)
        let arrived = transport.arrival("openssl@3")

        model.select(Self.openssl.id)
        await fulfillment(of: [arrived], timeout: 5)
        transport.release("openssl@3")
        await model.infoAsk?.value

        XCTAssertEqual(model.info?.name, "openssl@3", """
            the second tier never fills — `info` is \(String(describing: model.info)) after the \
            query answered, so everything the package view knows is what the list already said
            """)
        XCTAssertEqual(model.info?.installedVersion, "3.6.4")
        XCTAssertEqual(model.info?.license, "Apache-2.0")
        XCTAssertEqual(model.info?.tap, "homebrew/core")
        XCTAssertEqual(model.info?.siblings, ["openssl@1.1"])
        XCTAssertEqual(transport.infoCalls("openssl@3"), 1,
                       "one selection cost \(transport.infoCalls("openssl@3")) brew runs")
    }

    /// And a refusal stays a refusal: brew gone, brew hung and a document this
    /// build cannot read all reach the page as `nil`, and none of the three may
    /// be drawn as a fact. The fixture has no answer for this package, which is
    /// what the engine's own three nil paths look like from here.
    func testARefusedAnswerLeavesTheSecondTierAbsentRatherThanEmpty() async {
        let transport = HeldInfo(list: [Self.openssl], infos: [:])
        let model = HomebrewViewModel(vm: ModuleViewModel(transport: transport))
        await model.loadIfNeeded()
        let arrived = transport.arrival("openssl@3")

        model.select(Self.openssl.id)
        await fulfillment(of: [arrived], timeout: 5)
        transport.release("openssl@3")
        await model.infoAsk?.value

        XCTAssertNil(model.info, """
            a refused query was recorded as \(String(describing: model.info)) — an answer of \
            empty fields reads on the page as facts about the package
            """)
        XCTAssertNotNil(firstTier(model),
                        "a refused query took the first tier down with it")
    }

    // MARK: - 3. An answer for a package nobody is looking at is dropped

    /// Moving to another package takes the answer down with it, before the new
    /// one is out.
    ///
    /// The facts belong to the package they were read about: a licence, a
    /// homepage, a tap and an install date left standing under the next
    /// heading are four sentences about the wrong package, and they are the
    /// most believable kind of wrong because they are real facts about
    /// *something*. Nothing else in this file can see this — the two cases
    /// below both move off a package whose answer had not landed yet.
    func testMovingToAnotherPackageClearsTheAnswerItHad() async {
        let transport = fake()
        let model = await loaded(transport)

        let first = transport.arrival("openssl@3")
        model.select(Self.openssl.id)
        await fulfillment(of: [first], timeout: 5)
        transport.release("openssl@3")
        await model.infoAsk?.value
        XCTAssertEqual(model.info?.name, "openssl@3", "the first answer never landed")

        let second = transport.arrival("wget")
        model.select(Self.wget.id)
        await fulfillment(of: [second], timeout: 5)

        XCTAssertNil(model.info, """
            the page is describing wget and the tier under it still reads \
            \(String(describing: model.info?.name))'s licence, tap and install date
            """)

        transport.release("wget")
        await model.infoAsk?.value
        XCTAssertEqual(model.info?.name, "wget")
    }

    /// Two asks in flight, the newer one answering first: the older must not
    /// land on top of it.
    ///
    /// This is the shape that made the same defect in `search` visible — and
    /// here the cost is a package view describing openssl@3 under the heading
    /// wget, with a licence and a homepage belonging to neither.
    func testAnAnswerForAPackageNoLongerSelectedIsDropped() async {
        let transport = fake()
        let model = await loaded(transport)

        let first = transport.arrival("openssl@3")
        model.select(Self.openssl.id)
        await fulfillment(of: [first], timeout: 5)
        let older = model.infoAsk

        let second = transport.arrival("wget")
        model.select(Self.wget.id)
        await fulfillment(of: [second], timeout: 5)
        let newer = model.infoAsk

        XCTAssertNotEqual(older, newer,
                          "both selections share one ask, so nothing was superseded")
        XCTAssertEqual(transport.infoCalls("openssl@3"), 1)
        XCTAssertEqual(transport.infoCalls("wget"), 1)
        XCTAssertNil(model.info,
                     "moving to another package left the previous one's answer on screen")

        // The newer one answers and is drawn; **then** the older one arrives,
        // which is the order that puts a stale package's facts on the page.
        // Awaited in between, so the second really does land on top of the
        // first rather than racing it.
        transport.release("wget")
        await newer?.value
        XCTAssertEqual(model.info?.name, "wget", "the selected package's own answer was dropped")

        transport.release("openssl@3")
        await older?.value
        XCTAssertEqual(model.info?.name, "wget", """
            the page is describing wget and `info` says \
            \(String(describing: model.info?.name)) — the answer for a package the person \
            clicked away from was drawn over the one they are looking at
            """)
    }

    // MARK: - 4. What an operation changed is re-asked

    /// An upgrade rewrites the very fact the second tier's first tile carries.
    ///
    /// The first tier is rebuilt from `refreshAfterOp`'s new list, so after an
    /// upgrade the heading reads 3.7.0 while a kept `info` would have the tile
    /// under it still saying 3.6.4 — one screen carrying two accounts of one
    /// package. `refreshAfterOp` is the place that already knows the machine
    /// moved, so it re-asks; the answer it had is cleared rather than shown
    /// while the new one is out.
    func testAnOperationReasksWhatItMayHaveChanged() async {
        let transport = fake()
        let model = await loaded(transport)
        let first = transport.arrival("openssl@3")
        let second = transport.arrival("openssl@3", nth: 2)

        model.select(Self.openssl.id)
        await fulfillment(of: [first], timeout: 5)
        transport.release("openssl@3")
        await model.infoAsk?.value
        XCTAssertEqual(model.info?.installedVersion, "3.6.4", "the first answer never landed")

        transport.reanswer("openssl@3", info: Self.info("openssl@3", version: "3.7.0"),
                           listedAs: "3.7.0")
        transport.emit(EngineEvent(
            name: HomebrewEvent.opState.rawValue,
            payload: try! JSONEncoder().encode(
                OpState(phase: .done, label: "upgrade openssl@3", exitCode: 0))))

        // The second ask parks on the same gate, so it is waited for and then
        // let through in turn — the ordering is the test's, not the pool's.
        await fulfillment(of: [second], timeout: 5)
        transport.release("openssl@3")
        for _ in 0..<20_000 where model.info?.installedVersion != "3.7.0" { await Task.yield() }

        XCTAssertEqual(model.info?.installedVersion, "3.7.0", """
            the tile still reads \(String(describing: model.info?.installedVersion)) where the \
            heading above it now reads 3.7.0 — the second tier is describing the package as it \
            was before the operation
            """)
        XCTAssertEqual(model.installed.first(where: { $0.id == Self.openssl.id })?.version,
                       "3.7.0", "the list itself never refreshed, so nothing was contradicted")
    }
}
