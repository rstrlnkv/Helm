import Foundation
import HelmContract
import HelmRuntime
import XCTest
import HelmTestSupport
@testable import Module_Uninstaller_Engine

/// **The Trash-offer switch said on with no channel from either thing that can
/// make that false.**
///
/// `FolderWatcher.start` discarded `FSEventStreamStart`'s return and returned
/// silently when `FSEventStreamCreate` answered nil, so «trash offer switched on»
/// reached the log whether or not a stream existed. And the feature needs Full
/// Disk Access to see anything at all — which every local install takes away
/// again — a question the engine never asked: only `trashedApps()` found out, only
/// when a sweep ran, and it folded the refusal into «the Trash holds no apps».
///
/// So the port answers `[TrashedApp]?` now, nil for a read it was not allowed to
/// make, and the engine keeps the two live facts behind one value the page can
/// draw. What the switch's own row *says* in the two blind states is a sentence
/// this file does not invent: the state is wired and the wording is the
/// localizer's.
final class TheOfferSwitchSaysWhatItIsDoingTests: XCTestCase {

    /// A Trash that can refuse to be read, and change its mind — the grant is
    /// taken away by an install and given back in System Settings, both while the
    /// app is running. A fake with a fixed answer could not say either.
    private final class TrashOfMine: AppLister, @unchecked Sendable {
        private let lock = NSLock()
        private var readable: Bool
        private var count = 0

        init(readable: Bool) { self.readable = readable }

        func allow(_ next: Bool) { lock.withLock { readable = next } }
        var reads: Int { lock.withLock { count } }

        func trashedApps() -> [TrashedApp]? {
            lock.withLock {
                count += 1
                return readable ? [] : nil
            }
        }

        func installedApps() -> [InstalledApp] { [] }
        func appSizes(_ apps: [InstalledApp]) -> [String: Int] { [:] }
        func installedBundleIDs() -> Set<String> { [] }
        func isKnownToSystem(bundleID: String) -> Bool { false }
    }

    private struct NoFiles: FileSystemPort {
        func exists(_ url: URL) -> Bool { false }
        func size(_ url: URL) -> Int { 0 }
        func glob(_ pattern: URL) -> [URL] { [] }
        func children(of url: URL) -> [URL] { [] }
    }

    private var home: URL!

    override func setUpWithError() throws {
        home = scratchDirectory("trash-watch")
        HelmLog.shared.setEnabled(true)
        HelmLog.shared.clearTail()
    }

    override func tearDown() {
        HelmLog.shared.clearTail()
        HelmLog.shared.setEnabled(false)
        super.tearDown()
    }

    private var logged: [String] {
        HelmLog.shared.recentEntries()
            .filter { $0.category == UninstallerEngine.moduleID }
            .map(\.message)
    }

    private func engine(_ apps: AppLister) -> UninstallerEngine {
        UninstallerEngine(home: home, apps: apps, fs: NoFiles(),
                          trash: NoTrash(), running: NoRunning())
    }

    // MARK: - The reading itself

    /// Off wins; a stream that never started is the stronger fact; and an unknown
    /// is not a failure — a person who has just pressed the switch must not be
    /// shown a permission note because an answer has not come back yet.
    func test_the_state_is_read_from_the_three_things_that_decide_it() {
        XCTAssertEqual(TrashWatch.state(on: false, watching: true, trashReadable: true), .off)
        XCTAssertEqual(TrashWatch.state(on: false, watching: false, trashReadable: false), .off,
                       "a switch that is off has nothing to be wrong about")
        XCTAssertEqual(TrashWatch.state(on: true, watching: true, trashReadable: true), .on)
        XCTAssertEqual(TrashWatch.state(on: true, watching: nil, trashReadable: nil), .on,
                       "an answer that has not arrived yet was drawn as a failure")
        XCTAssertEqual(TrashWatch.state(on: true, watching: true, trashReadable: false),
                       .cannotReadTrash)
        XCTAssertEqual(TrashWatch.state(on: true, watching: false, trashReadable: true),
                       .notWatching)
        XCTAssertEqual(TrashWatch.state(on: true, watching: false, trashReadable: false),
                       .notWatching, "with nothing watching, the Trash read decides nothing")
        XCTAssertFalse(TrashWatch.off.isOn)
        for state in TrashWatch.allCases where state != .off {
            XCTAssertTrue(state.isOn, "\(state) is a switch that is on")
        }
    }

    // MARK: - The engine

    /// Turning it on asks the one question the whole feature depends on, and the
    /// answer reaches the state the row draws.
    func test_switching_it_on_finds_out_whether_helm_can_see_the_trash() async {
        let apps = TrashOfMine(readable: false)
        let engine = engine(apps)

        await MainActor.run { engine.setWatchingTrash(true) }

        XCTAssertGreaterThan(apps.reads, 0,
                             "the switch went on without anybody asking whether the Trash reads")
        XCTAssertEqual(engine.trashWatch, .cannotReadTrash, """
            the switch says it is on and Helm cannot see the Trash at all, which is the state \
            every local install leaves behind
            """)
        XCTAssertTrue(logged.contains { $0.contains("cannot read the Trash") },
                      "and nothing in the log says why the offer will never appear: \(logged)")
    }

    /// The control: a Trash that reads answers `on`, and the probe really ran.
    func test_a_readable_trash_switches_on_without_a_complaint() async {
        let apps = TrashOfMine(readable: true)
        let engine = engine(apps)

        await MainActor.run { engine.setWatchingTrash(true) }

        XCTAssertGreaterThan(apps.reads, 0, "precondition: the read was attempted")
        XCTAssertEqual(engine.trashWatch, .on)
        XCTAssertFalse(logged.contains { $0.contains("cannot read the Trash") },
                       "a Trash that reads was reported as unreadable: \(logged)")
    }

    /// Off is off, and it claims nothing about a folder nobody read.
    func test_a_switch_that_is_off_says_off() async {
        let engine = engine(TrashOfMine(readable: false))

        XCTAssertEqual(engine.trashWatch, .off)
    }

    /// **The reverse channel.** The grant is taken away by the next install and
    /// given back in System Settings, both while the app is running, so the state
    /// is a reading and not a memory: the sweep is where the port says so.
    func test_a_grant_lost_after_the_switch_went_on_is_noticed_by_the_sweep() async {
        let apps = TrashOfMine(readable: true)
        let engine = engine(apps)
        await MainActor.run { engine.setWatchingTrash(true) }
        XCTAssertEqual(engine.trashWatch, .on, "precondition: it started out working")

        apps.allow(false)
        _ = await engine.trashedAppLeftovers()

        XCTAssertEqual(engine.trashWatch, .cannotReadTrash,
                       "the switch went on saying on after the grant it depends on was gone")
    }

    /// And back: nothing here is sticky, or the note would outlive the grant being
    /// restored — which is the half of this family that keeps a page green with
    /// nobody listening.
    func test_a_grant_given_back_is_noticed_too() async {
        let apps = TrashOfMine(readable: false)
        let engine = engine(apps)
        await MainActor.run { engine.setWatchingTrash(true) }
        XCTAssertEqual(engine.trashWatch, .cannotReadTrash, "precondition: it started out blind")

        apps.allow(true)
        _ = await engine.trashedAppLeftovers()

        XCTAssertEqual(engine.trashWatch, .on,
                       "the person restored the grant and the page never noticed")
    }

    /// A sweep that could not read the Trash says so instead of answering «there
    /// is nothing in it», which is the same sentence a working sweep of an empty
    /// Trash gives.
    func test_a_sweep_that_could_not_read_the_trash_says_so() async {
        let apps = TrashOfMine(readable: false)
        let engine = engine(apps)
        await MainActor.run { engine.setWatchingTrash(true) }
        HelmLog.shared.clearTail()

        let offered = await engine.trashedAppLeftovers()

        XCTAssertEqual(offered.count, 0, "precondition: nothing was offered")
        XCTAssertTrue(logged.contains { $0.contains("cannot read the Trash") }, """
            a sweep that was refused the read wrote the same line as a sweep that found an \
            empty Trash: \(logged)
            """)
    }

    // MARK: - The port that answers it

    /// The real lister's two silences, which are not one silence.
    ///
    /// A Trash that is **not there** is empty: a fresh account has none until
    /// something is deleted, and reporting that as a missing permission would put a
    /// note on the page of somebody who has every grant. A Trash that is there and
    /// **refused** is nil, which is the Full Disk Access case — every install
    /// (CLAUDE.md). Reached here with a mode-000 directory rather than by revoking
    /// anything on this machine: `contentsOfDirectory` answers
    /// `NSFileReadNoPermissionError` either way.
    func test_a_missing_trash_is_empty_and_a_refused_one_is_not_an_answer() throws {
        let lister = WorkspaceAppLister(home: home, fs: FMFileSystem())
        XCTAssertEqual(lister.trashedApps()?.count, 0,
                       "a home with no Trash in it answered «I was not allowed to look»")

        let trash = home.appendingPathComponent(".Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        // Put back before the scratch teardown, which has to be able to remove it.
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                  ofItemAtPath: trash.path)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o000],
                                              ofItemAtPath: trash.path)

        XCTAssertNil(lister.trashedApps(), """
            a Trash this process may not read answered «there are no apps in it», which is the \
            reading that made the switch on the Leftovers tab a claim nobody had checked
            """)
    }

    // MARK: - What the page is told

    /// The reply the page reads is this value, and both sides read the enum: a
    /// `Bool` here is how the switch came to be the only thing anybody knew.
    func test_the_command_answers_the_state_and_not_a_flag() async throws {
        let apps = TrashOfMine(readable: false)
        let transport = LocalTransport()
        let engine = UninstallerEngine(home: home, apps: apps, fs: NoFiles(),
                                       trash: NoTrash(), running: NoRunning(),
                                       transport: transport)
        await MainActor.run { engine.setWatchingTrash(true) }

        let reply = try await transport.send(
            EngineCommand(name: UninstallerCommand.watchingTrash.rawValue, payload: Data()))

        XCTAssertEqual(try JSONDecoder().decode(TrashWatch.self, from: reply), .cannotReadTrash,
                       "the page cannot tell a switch that works from one that does nothing")
    }
}
