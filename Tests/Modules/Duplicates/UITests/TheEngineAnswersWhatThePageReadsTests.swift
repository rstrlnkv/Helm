import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// A real engine, a real transport, a real view model — the only arrangement in
/// which the two spellings of the search reply can be seen to disagree.
///
/// **Every fake in this target encodes the reply itself.** So the engine's answer
/// and the page's reading of it are two independent spellings of one wire type,
/// and nothing in the suite ever puts them end to end: the day `find` began
/// answering `DuplicateFindings` where the view model still asked for
/// `[DuplicateGroup]`, the whole module stopped returning a result — a search
/// that landed on «Pick a folder» — and the package built clean and the suite
/// stayed green. That is the family CLAUDE.md names, «a name spelled twice
/// across a target boundary»: one side changes it and nothing is an error
/// anywhere.
///
/// So these drive the engine itself. They are slow — a real walk over a real
/// fixture — and they are the only tests here that can fail for that reason.
@MainActor
final class TheEngineAnswersWhatThePageReadsTests: XCTestCase {

    /// Held for the length of a test: `LocalTransport`'s handler captures the
    /// engine weakly, so an engine nobody keeps answers empty `Data` and every
    /// assertion below would be about a lost reply instead.
    private var engine: DuplicatesEngine?

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    /// Both ends are handed a key of the suite's own. The engine's `settings:`
    /// and the view model's default to `DuplicatesSettings.guardOfScanSettings`,
    /// which is `com.helm.app / settings-seal` in the *person's* login keychain —
    /// and `DuplicatesViewModel.init` reads the keep policy through it, which
    /// spends `establishKey()` and creates the item where it is absent.
    /// `ATestNamesTheKeychainPortsItBuildsOverTests` is the rule; the machine is
    /// a boundary of its own.
    private func model(searching root: URL) async -> DuplicatesViewModel {
        let transport = LocalTransport()
        engine = DuplicatesEngine(transport: transport, store: nil,
                                  settings: SettingGuard(keys: PlantedSealKey()))
        let dvm = DuplicatesViewModel(vm: ModuleViewModel(transport: transport),
                                      store: duplicatesStore(folder: root.path),
                                      settings: SettingGuard(keys: PlantedSealKey()))
        dvm.search()
        for _ in 0..<20_000 where dvm.phase == .searching { await Task.yield() }
        return dvm
    }

    /// The list the engine found reaches the screen. It did not: the reply
    /// decoded as nothing, `search()` read that as the cancellation it also
    /// means, and the page went back to its first screen with a folder chosen.
    func testAListTheEngineFoundReachesTheScreen() async throws {
        let root = scratchDirectory("dup-wire-list")
        try write("a.bin", in: root, bytes: 1_200_000, filler: 4)
        try write("b.bin", in: root, bytes: 1_200_000, filler: 4)

        let dvm = await model(searching: root)

        XCTAssertEqual(dvm.phase, .result, """
            the engine answered and the page read nothing: the search reply is spelled twice, \
            and the two spellings have parted company
            """)
        XCTAssertEqual(dvm.groups.count, 1, "the pair the engine found: \(dvm.groups)")
        XCTAssertNil(dvm.nothingToShow, "a list is its own answer")
    }

    /// And what the walk could not look at reaches it too, which is the half a
    /// bare array had nowhere to put.
    func testAWalkRefusedAtADoorSaysSoOnTheScreen() async throws {
        let root = scratchDirectory("dup-wire-refused")
        try write("a.bin", in: root, bytes: 1_200_000, filler: 3)
        let wall = root.appendingPathComponent("wall")
        try FileManager.default.createDirectory(at: wall, withIntermediateDirectories: true)
        // Put back first, or the scratch teardown cannot drain a folder it is
        // not allowed to read.
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                   ofItemAtPath: wall.path)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o000],
                                              ofItemAtPath: wall.path)

        let dvm = await model(searching: root)

        XCTAssertEqual(dvm.phase, .result, "precondition: the search came back at all")
        XCTAssertTrue(dvm.groups.isEmpty, "precondition: this fixture has no duplicates")
        XCTAssertEqual(dvm.nothingToShow, .notEverythingRead(1), """
            «No duplicates here. Every large file under this folder is one of a kind» was drawn \
            over a tree the walk was refused at
            """)
    }

    /// A clean walk claims nothing of the sort — the half that keeps the note
    /// from standing over every honest empty folder for ever.
    func testACleanWalkStillSaysThereIsNothingHere() async throws {
        let root = scratchDirectory("dup-wire-clean")
        try write("a.bin", in: root, bytes: 1_200_000, filler: 3)

        let dvm = await model(searching: root)

        XCTAssertEqual(dvm.phase, .result, "precondition: the search came back")
        XCTAssertEqual(dvm.nothingToShow, .nothingFound)
    }

    /// The next search takes the last one's excuses down with its list.
    func testAFreshSearchDropsTheLastWalksExcuses() async throws {
        let root = scratchDirectory("dup-wire-again")
        try write("a.bin", in: root, bytes: 1_200_000, filler: 3)
        let wall = root.appendingPathComponent("wall")
        try FileManager.default.createDirectory(at: wall, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                   ofItemAtPath: wall.path)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o000],
                                              ofItemAtPath: wall.path)

        let dvm = await model(searching: root)
        XCTAssertEqual(dvm.nothingToShow, .notEverythingRead(1),
                       "precondition: the first walk was refused")

        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: wall.path)
        dvm.search()
        for _ in 0..<20_000 where dvm.phase == .searching { await Task.yield() }

        XCTAssertEqual(dvm.phase, .result, "precondition: the second search came back")
        XCTAssertEqual(dvm.nothingToShow, .nothingFound,
                       "the excuse outlived the walk it was about")
    }
}
