import XCTest
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **The walk is asked for after the inspector has drawn, and only for a
/// package that is on this Mac.**
///
/// A size is a directory walk — `brew info --json=v2` carries none, in either
/// direction — so it is the last thing the package view learns and the only one
/// that can arrive after the person has already moved on. Four things follow,
/// and each is a case here:
///
/// 1. the ask goes out **after** `info` has answered, carrying the version that
///    answer named, so the engine files the figure under the keg it measured;
/// 2. a package that is not installed is never walked at all — a search hit has
///    no keg, and asking would spend a walk to find that out;
/// 3. a figure belongs to the package it was walked for: moving off takes it
///    down, and one that lands for a package nobody is looking at is dropped;
/// 4. and while it *is* out, the page says so — `SizeReading.measuring` is the
///    one state here that exists only during the wait, so every reading of it
///    below is taken with the fake blocked on a real semaphore rather than
///    between two synchronous lines.
///
/// The fake answers `info` at once and holds `size`, which is the real shape:
/// the walk is the long half. A fake that answered both synchronously would
/// make every case below vacuous — the ask would be over before the gesture
/// under test happened.
/// The two packages the fixture is installed with. File-level rather than
/// static members of the case below, which is `@MainActor`: the fake answers
/// the list from the transport's own thread, and a main-actor constant read
/// there is an `await` in a synchronous encode.
private let openssl = BrewPackage(name: "openssl@3", version: "3.6.4", isCask: false)
private let wget = BrewPackage(name: "wget", version: "1.25.0", isCask: false)

@MainActor
final class TheSizeIsAskedForAfterTheRestTests: XCTestCase {

    private final class HeldSize: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }

        private let lock = NSLock()
        private var gates: [String: DispatchSemaphore] = [:]
        private var arrivals: [String: XCTestExpectation] = [:]
        /// Every `size` ask, in order, as the engine would have received it.
        private var _walked: [PackageSizeRequest] = []
        private let infos: [String: PackageInfo]
        private let figures: [String: Int]

        var walked: [PackageSizeRequest] { lock.lock(); defer { lock.unlock() }; return _walked }

        init(infos: [String: PackageInfo], figures: [String: Int]) {
            self.infos = infos
            self.figures = figures
        }

        func release(_ name: String) { gate(for: name)?.signal() }

        /// Registers a gate for `name` **and** the expectation that says its
        /// walk has reached the transport. Only a name registered this way is
        /// held; anything else answers at once.
        ///
        /// That asymmetry is deliberate. A fake that parked every ask would
        /// turn «this package was never walked» into a test that *hangs* rather
        /// than one that fails — the ask would park on a gate nobody releases,
        /// and the case would sit there rather than say what went wrong. So a
        /// package the test never registered is answered immediately, which
        /// leaves an ask that should not have happened visible in `walked`.
        func arrival(_ name: String) -> XCTestExpectation {
            lock.lock(); defer { lock.unlock() }
            if gates[name] == nil { gates[name] = DispatchSemaphore(value: 0) }
            if let existing = arrivals[name] { return existing }
            let made = XCTestExpectation(description: "size(\(name)) reached the transport")
            arrivals[name] = made
            return made
        }

        private func gate(for name: String) -> DispatchSemaphore? {
            lock.lock(); defer { lock.unlock() }
            return gates[name]
        }

        /// Synchronous, for the reason the sibling fakes give: a lock held
        /// across an await is a lock taken on one side of a field.
        private func entered(_ request: PackageSizeRequest) -> (Int?, XCTestExpectation?) {
            lock.lock(); defer { lock.unlock() }
            _walked.append(request)
            return (figures[request.name], arrivals[request.name])
        }

        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled:
                return try JSONEncoder().encode([openssl, wget])
            case .outdated:
                return try JSONEncoder().encode([OutdatedPackage]())
            case .descriptions:
                return try JSONEncoder().encode([String: String]())
            case .search:
                return try JSONEncoder().encode([SearchHit(name: "helm", isCask: false)])
            case .info:
                guard let ref = try? JSONDecoder().decode(PackageRef.self, from: command.payload),
                      let answer = infos[ref.name] else { return Data() }
                return try JSONEncoder().encode(answer)
            case .size:
                guard let request = try? JSONDecoder().decode(PackageSizeRequest.self,
                                                              from: command.payload)
                else { return Data() }
                let (figure, arrival) = entered(request)
                arrival?.fulfill()
                if let gate = self.gate(for: request.name) {
                    // Off the cooperative pool, the way the real wait is.
                    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                        DispatchQueue.global().async { gate.wait(); c.resume() }
                    }
                }
                guard let figure else { return Data() }
                return try JSONEncoder().encode(figure)
            default:
                return Data()
            }
        }
    }

    private static func info(_ name: String, installed: String?) -> PackageInfo {
        PackageInfo(name: name, isCask: false, desc: "d", homepage: nil, license: "MIT",
                    tap: "homebrew/core", latestVersion: installed ?? "9.9.9",
                    installedVersion: installed, installedAt: nil, installedOnRequest: true,
                    deprecationReason: nil, replacement: nil, siblings: [],
                    dependencies: [], caveats: nil)
    }

    private func fake() -> HeldSize {
        HeldSize(infos: ["openssl@3": Self.info("openssl@3", installed: "3.6.4"),
                         "wget": Self.info("wget", installed: "1.25.0"),
                         "helm": Self.info("helm", installed: nil)],
                 figures: ["openssl@3": 41_353_216, "wget": 2_097_152])
    }

    private func loaded(_ transport: HeldSize) async -> HomebrewViewModel {
        let model = HomebrewViewModel(vm: ModuleViewModel(transport: transport))
        await model.loadIfNeeded()
        XCTAssertEqual(model.installed.count, 2, "the fixture list never arrived")
        XCTAssertTrue(transport.walked.isEmpty, "a package nobody selected was walked")
        return model
    }

    // MARK: - 1. It lands, and it lands late

    /// The figure arrives after `info` and carries the version that answer
    /// named — and until it does, the page holds nothing rather than a nought.
    func testTheFigureLandsAfterTheAnswerItBelongsBeside() async {
        let transport = fake()
        let model = await loaded(transport)
        let asked = transport.arrival("openssl@3")

        model.select(openssl.id)
        await fulfillment(of: [asked], timeout: 5)

        XCTAssertNotNil(model.info, "the walk went out before the answer it is asked after")
        // **The state the tile draws while the walk is parked.** The fake has
        // reached `send` and is blocked on a semaphore off the cooperative pool,
        // so this reading is taken with a real walk genuinely in flight rather
        // than between two synchronous lines.
        XCTAssertEqual(model.size, .measuring, """
            the page is holding \(String(describing: model.size)) while a walk for this package \
            is out — it is neither the figure (nobody has one) nor nothing (one is being counted)
            """)
        XCTAssertEqual(transport.walked.map(\.version), ["3.6.4"],
                       "the ask carried a version brew never named for this package")

        transport.release("openssl@3")
        await model.infoAsk?.value
        XCTAssertEqual(model.size, .measured(41_353_216), "the figure never reached the page")
    }

    /// A refused walk stays refused: the tile is absent, not a zero.
    func testARefusedWalkLeavesTheFigureAbsent() async {
        let transport = HeldSize(infos: ["openssl@3": Self.info("openssl@3", installed: "3.6.4")],
                                 figures: [:])
        let model = HomebrewViewModel(vm: ModuleViewModel(transport: transport))
        await model.loadIfNeeded()
        let asked = transport.arrival("openssl@3")

        model.select(openssl.id)
        await fulfillment(of: [asked], timeout: 5)
        transport.release("openssl@3")
        await model.infoAsk?.value

        XCTAssertEqual(model.size, .notMeasured, """
            a refused walk was recorded as \(String(describing: model.size)) — the engine answers \
            nil for a keg it could not read, and nothing on this side may turn that into a figure \
            or leave the tile counting a walk that is over
            """)
        XCTAssertNotNil(model.info, "the refused walk took the rest of the tier down with it")
    }

    // MARK: - 2. Nothing is walked for a package that is not here

    /// A search hit has no keg, so no walk is spent learning that.
    func testAPackageThatIsNotInstalledIsNeverWalked() async {
        let transport = fake()
        let model = await loaded(transport)

        model.segment = .search
        await model.search("helm")
        model.select(SearchHit(name: "helm", isCask: false).id)
        await model.infoAsk?.value

        XCTAssertEqual(model.info?.name, "helm", "the fixture's answer never arrived")
        XCTAssertEqual(model.size, .notMeasured, """
            a package that is not installed is holding \(String(describing: model.size)) — nothing \
            is being walked for it and nothing ever will be
            """)
        XCTAssertTrue(transport.walked.isEmpty, """
            a package that is not on this Mac was walked \(transport.walked.count) time(s) — \
            there is no Cellar directory for it to have measured
            """)
    }

    // MARK: - 3. A figure belongs to the package it was walked for

    /// Moving to another package takes the figure down with it, before the new
    /// one is out — 41 MB left standing under the heading wget is a real
    /// measurement of the wrong thing.
    func testMovingToAnotherPackageClearsTheFigure() async {
        let transport = fake()
        let model = await loaded(transport)

        let first = transport.arrival("openssl@3")
        model.select(openssl.id)
        await fulfillment(of: [first], timeout: 5)
        transport.release("openssl@3")
        await model.infoAsk?.value
        XCTAssertEqual(model.size, .measured(41_353_216), "the first figure never landed")

        let second = transport.arrival("wget")
        model.select(wget.id)
        await fulfillment(of: [second], timeout: 5)

        XCTAssertEqual(model.size, .measuring, """
            the page is describing wget and the tile under it reads \
            \(String(describing: model.size)) — openssl@3's figure had to go the moment the \
            subject moved, and what stands in its place is wget's own walk, which is out
            """)

        transport.release("wget")
        await model.infoAsk?.value
        XCTAssertEqual(model.size, .measured(2_097_152))
    }

    // MARK: - 4. What the tile says while the walk is out

    /// **The waiting state reaches the tile, and it is a tile rather than a
    /// gap.**
    ///
    /// The three cases above read the view model's own field; this one spends it
    /// the way the page does — through `PackageFacts`, which is what decides
    /// whether there is a tile at all — and it reads it while the walk is
    /// genuinely parked in the transport, which is the only moment this state
    /// exists. In all eight languages, because the word in it is one a person
    /// reads.
    ///
    /// Three readings of one walk, in order: none before the ask, the word while
    /// it is out, the figure after. The first is what keeps «Counting…» from
    /// being something the page says merely because a package is selected.
    func testTheTileSaysTheFigureIsBeingCountedWhileTheWalkIsOut() async {
        let transport = fake()
        let model = await loaded(transport)
        let asked = transport.arrival("openssl@3")

        let before = PackageFacts.of(Self.info("openssl@3", installed: "3.6.4"),
                                     size: model.size)
        XCTAssertFalse(before.contains { $0.label == HbStr.tileOnDisk },
                       "a size tile drew before any walk had been asked for")

        model.select(openssl.id)
        await fulfillment(of: [asked], timeout: 5)

        AppLanguage.each { language in
            guard let info = model.info else {
                return XCTFail("\(language.rawValue): the fixture's own answer never arrived")
            }
            let facts = PackageFacts.of(info, size: model.size)
            XCTAssertEqual(facts.last?.label, HbStr.tileOnDisk, """
                \(language.rawValue): the walk for openssl@3 is in the transport and the tier \
                drew \(facts.map(\.label)) — the tile the figure lands in is not there to \
                land in
                """)
            XCTAssertEqual(facts.last?.value, HbStr.countingTheSize, """
                \(language.rawValue): the size tile reads «\(facts.last?.value ?? "")» while the \
                walk is out, where it should say the figure is being counted
                """)
            XCTAssertNotEqual(facts.last?.value, Bytes(0), """
                \(language.rawValue): a walk that has not answered was drawn as a measurement
                """)
        }

        transport.release("openssl@3")
        await model.infoAsk?.value
        AppLanguage.each { language in
            guard let info = model.info else { return XCTFail("\(language.rawValue): no answer") }
            let facts = PackageFacts.of(info, size: model.size)
            XCTAssertEqual(facts.filter { $0.label == HbStr.tileOnDisk }.count, 1, """
                \(language.rawValue): the figure arrived beside the waiting tile rather than \
                into it — \(facts.map(\.label))
                """)
            XCTAssertEqual(facts.last?.value, Bytes(41_353_216), """
                \(language.rawValue): the tile still reads «\(facts.last?.value ?? "")» after \
                the walk answered
                """)
        }
    }

    /// **A walk that answered nothing takes the tile away rather than leaving it
    /// counting for ever.**
    ///
    /// Read as three states in order — absent, counting, absent — because the
    /// middle one is what makes the last one a statement: a tile that was never
    /// there cannot be said to have gone.
    func testARefusedWalkTakesTheWaitingTileAwayAgain() async {
        let transport = HeldSize(infos: ["openssl@3": Self.info("openssl@3", installed: "3.6.4")],
                                 figures: [:])
        let model = HomebrewViewModel(vm: ModuleViewModel(transport: transport))
        await model.loadIfNeeded()
        let asked = transport.arrival("openssl@3")

        model.select(openssl.id)
        await fulfillment(of: [asked], timeout: 5)
        guard let info = model.info else { return XCTFail("the fixture's own answer never arrived") }
        XCTAssertTrue(PackageFacts.of(info, size: model.size).contains { $0.label == HbStr.tileOnDisk },
                      "precondition: no waiting tile drew, so its going away says nothing")

        transport.release("openssl@3")
        await model.infoAsk?.value
        XCTAssertFalse(PackageFacts.of(info, size: model.size).contains { $0.label == HbStr.tileOnDisk },
                       """
                       the walk came back with nothing and the tile is still on the page — it \
                       either sits there counting a walk that is over or shows a figure nobody \
                       measured
                       """)
    }

    /// And one that answers for a package nobody is looking at any more is
    /// dropped rather than drawn.
    func testAFigureForAPackageNoLongerSelectedIsDropped() async {
        let transport = fake()
        let model = await loaded(transport)

        let first = transport.arrival("openssl@3")
        model.select(openssl.id)
        await fulfillment(of: [first], timeout: 5)
        let older = model.infoAsk

        let second = transport.arrival("wget")
        model.select(wget.id)
        await fulfillment(of: [second], timeout: 5)
        let newer = model.infoAsk
        XCTAssertNotEqual(older, newer, "both selections share one ask, so nothing was superseded")

        // The newer one answers and is drawn; **then** the older one arrives.
        transport.release("wget")
        await newer?.value
        XCTAssertEqual(model.size, .measured(2_097_152),
                       "the selected package's own figure was dropped")

        transport.release("openssl@3")
        await older?.value
        XCTAssertEqual(model.size, .measured(2_097_152), """
            the page is describing wget and the size tile says \
            \(String(describing: model.size)) — the figure walked for a package the person \
            clicked away from was drawn over the one they are looking at
            """)
    }
}
