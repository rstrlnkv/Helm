import HelmTestSupport
import XCTest
@testable import HelmRuntime

/// The directory a store of the person's redirects itself into while XCTest is
/// loaded, and the sweep that keeps it from becoming 452 of them.
///
/// `AbandonedJournalsTests` holds the *judgement* — which of these names belong
/// to processes that have gone — and holds it under the journal's own spelling of
/// it. This holds the two halves that judgement does not reach: that two
/// processes are handed two directories, and that the sweep beside them actually
/// removes one. The 452 were never a wrong judgement; they were a judgement
/// nobody called.
///
/// Every case runs against a base directory of its own rather than `$TMPDIR`, so
/// nothing here can sweep the journal of a suite running beside it.
final class TestScratchTests: XCTestCase {

    private let scratch = TestScratch(prefix: "helm-scratch-probe-")
    private var mine: Int32 { ProcessInfo.processInfo.processIdentifier }

    // MARK: - One directory per process

    func testTheDirectoryIsThisProcessesOwn() {
        XCTAssertEqual(scratch.directory(in: scratchDirectory("scratch-base")).lastPathComponent,
                       "helm-scratch-probe-\(mine)")
    }

    /// Sharing one directory across runs is the other shape available here — the
    /// log takes it — and it is wrong for a store: two suites run side by side on
    /// a build machine, a store holds one slot, and a slot read by one process
    /// and written by another is the nondeterminism the redirection exists to
    /// end.
    func testItIsNotTheBaseItself() {
        let base = scratchDirectory("scratch-base")
        XCTAssertNotEqual(scratch.directory(in: base).path, base.path)
    }

    // MARK: - And an end to them

    func testItTakesBackWhatADeadProcessLeft() throws {
        let base = scratchDirectory("scratch-sweep")
        let abandoned = try made("helm-scratch-probe-4242", in: base)

        _ = scratch.directory(in: base, isAlive: { _ in false })

        XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.path),
                       "a directory whose process has gone was kept, which is how 452 of them "
                       + "accumulate")
    }

    /// The case that costs somebody a debugging session rather than a directory:
    /// the suite running beside this one.
    func testItLeavesALivingProcessesDirectoryAlone() throws {
        let base = scratchDirectory("scratch-sweep")
        let live = try made("helm-scratch-probe-777", in: base)

        _ = scratch.directory(in: base, isAlive: { $0 == 777 })

        XCTAssertTrue(FileManager.default.fileExists(atPath: live.path),
                      "the directory of a running process was swept")
    }

    /// `$TMPDIR` belongs to everything on the machine, and the sweep walks all of
    /// it. A name that is not this family's is not the sweep's to judge — asked
    /// here of the removal rather than of the decision, because a sweep that
    /// ignored the decision would pass every case above.
    func testItLeavesAStrangerAlone() throws {
        let base = scratchDirectory("scratch-sweep")
        let stranger = try made("com.apple.something", in: base)

        _ = scratch.directory(in: base, isAlive: { _ in false })

        XCTAssertTrue(FileManager.default.fileExists(atPath: stranger.path),
                      "something belonging to nobody here was removed")
    }

    /// A directory the sweep is meant to see, asserted into existence: a test of
    /// a removal passes for free when there was nothing there to remove.
    private func made(_ name: String, in base: URL) throws -> URL {
        let url = base.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "the fixture is not on disk, so nothing below is a test")
        return url
    }
}
