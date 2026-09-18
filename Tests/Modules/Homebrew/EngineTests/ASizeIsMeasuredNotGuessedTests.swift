import Foundation
import XCTest
import HelmTestSupport
@testable import Module_Homebrew_Engine

/// **A package's size is a walk of its own directory, or it is nothing.**
///
/// `brew info --json=v2` carries no size in either direction — measured on this
/// Mac against Homebrew 7.0.1, 2026-09-15: `bottle.files.*.size` is null and the
/// `installed[]` entry has no size field at all. So the figure the tile draws
/// comes from `<prefix>/Cellar/<name>`, and every way that walk can fail has to
/// answer the same thing: **nil, never 0**. A zero is not a gap on the page, it
/// is a measurement, and it says a package occupies nothing.
///
/// Four questions, in the order they can go wrong:
///
/// 1. a real directory of a size computed independently of the walk;
/// 2. a directory that is missing, or that will not open;
/// 3. a cask, which has no Cellar at all — and is answered **without the
///    prefix ever being asked for**, which is the only way to say "nothing was
///    walked" rather than "the answer happened to be nil";
/// 4. the same name and version asked twice costs one walk, and a version that
///    moved costs another.
///
/// The sizes are asserted against `stat`'s own `st_blocks`, summed by this file
/// — not against `FileWeight`, which is the thing under test, and not against a
/// figure written into the test by hand: a keg's allocated size is block-rounded
/// and depends on the filesystem the scratch directory lands on.
final class ASizeIsMeasuredNotGuessedTests: XCTestCase {

    // MARK: - The fakes

    /// A brew at a prefix this test owns, which **counts how often it is
    /// asked**.
    ///
    /// The count is the subject of the cask case. `CellarWeight` cannot reach a
    /// directory without a prefix, so a call that never asks for one is a call
    /// that walked nothing — an assertion about the act rather than about the
    /// answer, which is what «nothing was walked» has to mean to be worth
    /// writing.
    private final class CountingLocator: BrewLocator, @unchecked Sendable {
        private let lock = NSLock()
        private var _asks = 0
        private let path: String?
        var asks: Int { lock.lock(); defer { lock.unlock() }; return _asks }

        /// `prefix` is the Homebrew prefix — the locator answers `<prefix>/bin/brew`,
        /// the shape `FSBrewLocator` answers with on a real Mac.
        init(prefix: URL?) { path = prefix?.appendingPathComponent("bin/brew").path }

        func brewPath() -> String? {
            lock.lock(); _asks += 1; lock.unlock()
            return path
        }
    }

    /// A weight that answers a fixed figure and counts the asks, for the
    /// questions that are about the engine's memory rather than about the walk.
    private final class CountingWeight: PackageWeight, @unchecked Sendable {
        private let lock = NSLock()
        private var _asks: [String] = []
        private var _answer: Int?
        var asks: [String] { lock.lock(); defer { lock.unlock() }; return _asks }

        init(answering answer: Int?) { _answer = answer }

        func answer(_ next: Int?) { lock.lock(); _answer = next; lock.unlock() }

        func bytes(ofPackage name: String, isCask: Bool) -> Int? {
            lock.lock(); defer { lock.unlock() }
            _asks.append(name)
            return _answer
        }
    }

    private struct FixedLocator: BrewLocator {
        func brewPath() -> String? { "/opt/homebrew/bin/brew" }
    }
    private struct NoPrivileges: PrivilegedRunner {
        func runAdmin(_ script: String) -> Bool { false }
    }
    /// Nothing here runs a `brew`: every question in this file is about a
    /// directory. A runner that launches anything at all would be an
    /// integration test against the owner's own Homebrew.
    private struct SilentRunner: ProcessRunner {
        func run(_ launchPath: String, _ args: [String],
                 env: [String: String]) -> (status: Int32, stdout: String) { (0, "") }
        func runCapturingDiagnostics(_ launchPath: String, _ args: [String],
                                     env: [String: String]) -> (status: Int32, output: String) {
            (0, "")
        }
        func stream(_ launchPath: String, _ args: [String], env: [String: String],
                    onLine: @escaping @Sendable (String) -> Void,
                    onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
            onExit(0)
            return NoProcess()
        }
    }

    // MARK: - The fixture

    /// A Cellar under `prefix` holding one keg of `files`, and what those files
    /// really occupy.
    ///
    /// The expectation is summed from `stat`'s `st_blocks`, which is the
    /// filesystem's own answer and is reached by neither `FileWeight` nor
    /// `BulkWalk` — so a walk that agreed with it by construction rather than by
    /// measuring could not. Directories are not in the sum, because the walk
    /// charges files only.
    @discardableResult
    private func keg(_ name: String, version: String, in prefix: URL,
                     files: [(String, Int)]) throws -> Int {
        var occupied = 0
        for (relative, bytes) in files {
            let url = try write("Cellar/\(name)/\(version)/\(relative)", in: prefix, bytes: bytes)
            var status = stat()
            XCTAssertEqual(stat(url.path, &status), 0, "the fixture file was not written")
            occupied += Int(status.st_blocks) * 512
        }
        XCTAssertGreaterThan(occupied, 0, "a fixture that occupies nothing measures nothing")
        return occupied
    }

    private func engine(weight: PackageWeight) -> HomebrewEngine {
        HomebrewEngine(locator: FixedLocator(), runner: SilentRunner(),
                       privileged: NoPrivileges(), user: "tester",
                       marker: InMemoryOpMarker(), popularity: NoPopularity(),
                       weight: weight)
    }

    // MARK: - 1. A real directory

    /// The figure is the keg's own, to the byte the filesystem says.
    func testAKegIsMeasuredRatherThanGuessed() throws {
        let prefix = scratchDirectory("brew-size")
        let occupied = try keg("openssl@3", version: "3.6.4", in: prefix,
                               files: [("bin/openssl", 120_000), ("lib/libssl.dylib", 900_000),
                                       ("share/doc/readme", 40)])
        let weight = CellarWeight(locator: CountingLocator(prefix: prefix))

        let answered = weight.bytes(ofPackage: "openssl@3", isCask: false)
        XCTAssertEqual(answered, occupied, """
            the walk answers \(String(describing: answered)) where the filesystem charges \
            \(occupied) bytes for the same keg
            """)
    }

    /// Every version line in the keg counts, because every one of them is on
    /// the disk: `brew` leaves an old keg behind until it is cleaned up, and a
    /// figure that named only the current one would under-report what removing
    /// the package gives back.
    func testASecondVersionLineInTheKegIsPartOfTheFigure() throws {
        let prefix = scratchDirectory("brew-size-two-lines")
        var occupied = try keg("node", version: "26.8.2", in: prefix,
                               files: [("bin/node", 400_000)])
        occupied += try keg("node", version: "26.9.0", in: prefix,
                            files: [("bin/node", 410_000)])
        let weight = CellarWeight(locator: CountingLocator(prefix: prefix))

        XCTAssertEqual(weight.bytes(ofPackage: "node", isCask: false), occupied,
                       "the walk stopped at one version line and left the rest of the keg out")
    }

    // MARK: - 2. Nothing to measure is nil, never zero

    /// A name with no keg — uninstalled in a terminal between the list and the
    /// press, or keg-only and linked elsewhere.
    func testAMissingKegIsNotAPackageOfNoSize() throws {
        let prefix = scratchDirectory("brew-size-missing")
        try keg("openssl@3", version: "3.6.4", in: prefix, files: [("bin/openssl", 10_000)])
        let weight = CellarWeight(locator: CountingLocator(prefix: prefix))

        let answered = weight.bytes(ofPackage: "wget", isCask: false)
        XCTAssertNil(answered, """
            a package with no directory at all measured \(String(describing: answered)) — a \
            figure of 0 draws as «0 bytes», which is a measurement and not a gap
            """)
        XCTAssertNotNil(weight.bytes(ofPackage: "openssl@3", isCask: false),
                        "nothing in this fixture can be measured, so the nil above says nothing")
    }

    /// A keg that will not open. Ordinary enough to matter: a `sudo` in
    /// somebody's terminal is all it takes, and every TCC refusal arrives this
    /// way too.
    func testAKegThatWillNotOpenIsNotAPackageOfNoSize() throws {
        let prefix = scratchDirectory("brew-size-refused")
        try keg("shut", version: "1.0", in: prefix, files: [("bin/shut", 80_000)])
        let closed = prefix.appendingPathComponent("Cellar/shut")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: closed.path)
        // Put back before the scratch drain, which cannot remove what it cannot
        // enter — a teardown block, so it runs *after* this test's own
        // assertions and *before* the drain registered above it.
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                   ofItemAtPath: closed.path)
        }
        let weight = CellarWeight(locator: CountingLocator(prefix: prefix))

        let answered = weight.bytes(ofPackage: "shut", isCask: false)
        XCTAssertNil(answered, """
            a directory that would not open measured \(String(describing: answered)) — a refusal \
            drawn as a figure is the page stating a fact about a Cellar nobody read
            """)
    }

    /// And the name is not allowed to leave the Cellar. `name` reaches here
    /// from `brew`'s own stdout and from a search box somebody types into, and
    /// it is appended to a path that is then **walked**: `..` would point the
    /// walk at the prefix, and an absolute-looking name at whatever it names.
    func testANameThatWouldLeaveTheCellarIsNotAPackage() throws {
        let prefix = scratchDirectory("brew-size-escape")
        try keg("openssl@3", version: "3.6.4", in: prefix, files: [("bin/openssl", 10_000)])
        let locator = CountingLocator(prefix: prefix)
        let weight = CellarWeight(locator: locator)

        for name in ["..", ".", "", "../Cellar/openssl@3", "openssl@3/3.6.4", "/etc"] {
            XCTAssertNil(weight.bytes(ofPackage: name, isCask: false),
                         "«\(name)» was walked as though it named a package")
        }
        XCTAssertNotNil(weight.bytes(ofPackage: "openssl@3", isCask: false),
                        "nothing here is measurable, so the nils above say nothing")
    }

    // MARK: - 3. A cask is answered without looking

    /// **Nothing is walked for a cask, and the locator never hears about it.**
    ///
    /// A cask has no Cellar directory — it lands under `Caskroom` and in
    /// `/Applications` — so the answer is known rather than measured, the way
    /// `dependents` answers a cask without running `brew uses`. Asserted at the
    /// locator: a walk needs a prefix, so a call that asked for none walked
    /// nothing. The fixture has a directory of exactly that name sitting in the
    /// Cellar, so a body that did look would answer a figure rather than nil.
    func testACaskIsAnsweredWithoutAskingWhereTheCellarIs() throws {
        let prefix = scratchDirectory("brew-size-cask")
        try keg("docker", version: "4.3.0", in: prefix, files: [("bin/docker", 600_000)])
        let locator = CountingLocator(prefix: prefix)
        let weight = CellarWeight(locator: locator)

        XCTAssertNil(weight.bytes(ofPackage: "docker", isCask: true),
                     "a cask was given a figure out of a directory that is not its own")
        XCTAssertEqual(locator.asks, 0, """
            the cask answer cost \(locator.asks) reading(s) of where Homebrew is — it went \
            looking for a Cellar directory a cask does not have
            """)

        // The same name as a formula: `docker` is both, which is why the id in
        // this module is prefixed. A figure here proves the directory was
        // readable all along, so the nil above is the cask rule and not a
        // broken fixture.
        XCTAssertNotNil(weight.bytes(ofPackage: "docker", isCask: false))
        XCTAssertEqual(locator.asks, 1)
    }

    // MARK: - 4. What the engine remembers

    /// One figure per `name@version`, for the engine's life: the walk is the
    /// expensive half, and the answer cannot change while that version is the
    /// one on disk.
    func testTheSameNameAndVersionIsWalkedOnce() {
        let weight = CountingWeight(answering: 4_096)
        let engine = engine(weight: weight)

        XCTAssertEqual(engine.size(name: "openssl@3", isCask: false, version: "3.6.4"), 4_096)
        XCTAssertEqual(engine.size(name: "openssl@3", isCask: false, version: "3.6.4"), 4_096)
        XCTAssertEqual(weight.asks.count, 1, """
            the same package at the same version was walked \(weight.asks.count) times — the \
            figure is remembered against the version it was measured for
            """)
    }

    /// And a version that moved is a different keg: the upgrade that changed the
    /// number in the tile above changed the one this draws.
    func testAVersionThatMovedIsWalkedAgain() {
        let weight = CountingWeight(answering: 4_096)
        let engine = engine(weight: weight)

        XCTAssertEqual(engine.size(name: "openssl@3", isCask: false, version: "3.6.4"), 4_096)
        weight.answer(8_192)
        XCTAssertEqual(engine.size(name: "openssl@3", isCask: false, version: "3.7.0"), 8_192, """
            the figure measured for 3.6.4 was handed back for 3.7.0 — the tile then reads a size \
            for a keg that was replaced
            """)
        XCTAssertEqual(weight.asks.count, 2)
    }

    /// Two packages do not share one entry — the plainest way a cache keyed by
    /// the wrong thing shows itself.
    func testTwoPackagesDoNotShareOneFigure() {
        let weight = CountingWeight(answering: 4_096)
        let engine = engine(weight: weight)

        XCTAssertEqual(engine.size(name: "openssl@3", isCask: false, version: "1.0"), 4_096)
        weight.answer(8_192)
        XCTAssertEqual(engine.size(name: "wget", isCask: false, version: "1.0"), 8_192,
                       "wget was answered with openssl@3's figure")
    }

    /// A nil is never remembered. «Nothing was measured» is a live fact about a
    /// directory — a refusal that has since been lifted, a keg that has since
    /// been installed — and a remembered nil would keep the tile absent for the
    /// life of the app.
    func testARefusalIsNotRemembered() {
        let weight = CountingWeight(answering: nil)
        let engine = engine(weight: weight)

        XCTAssertNil(engine.size(name: "openssl@3", isCask: false, version: "3.6.4"))
        weight.answer(4_096)
        XCTAssertEqual(engine.size(name: "openssl@3", isCask: false, version: "3.6.4"), 4_096,
                       "a refusal was remembered as though it were a measurement")
    }

    /// And an operation drops what is remembered, whatever it was and whatever
    /// package it names.
    ///
    /// The version in the key catches an upgrade on its own; this catches every
    /// other shape — `brew reinstall` and a `brew doctor` fix leave the version
    /// string where it was and change the bytes under it, and `upgrade all`
    /// moves packages this figure's own key knows nothing about.
    func testAFinishedOperationForgetsEveryFigure() {
        let weight = CountingWeight(answering: 4_096)
        let engine = engine(weight: weight)
        XCTAssertEqual(engine.size(name: "openssl@3", isCask: false, version: "3.6.4"), 4_096)

        // The whole of an operation, through the one door every operation uses:
        // `SilentRunner` exits the child at once, so the conclude path has run
        // by the time this returns.
        engine.uninstall(name: "wget", isCask: false)
        weight.answer(8_192)

        XCTAssertEqual(engine.size(name: "openssl@3", isCask: false, version: "3.6.4"), 8_192, """
            the figure measured before an operation was handed back after it — a `brew \
            reinstall` or a doctor fix rewrites a keg without moving its version string
            """)
        XCTAssertEqual(weight.asks.count, 2)
    }
}
