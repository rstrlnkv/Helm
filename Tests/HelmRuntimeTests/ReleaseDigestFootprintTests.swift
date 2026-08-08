import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// `ReleaseDigest.sha256(ofFileAt:)` streams a release asset in 1 MB slices —
/// the same shape `DuplicateScanner.hash` used before its autoreleasepool fix
/// (ARCHITECTURE.md § Memory), and the same defect: `FileHandle.read` hands
/// back an autoreleased `Data`, this loop has no pool, and nothing else on
/// this call path forces a drain. Unlike the duplicate hasher this call is
/// serial — no `concurrentPerform` involved — so it is a clean check of
/// whether a single-threaded streaming loop needs the same fix. It does:
/// measured on the file this test writes, the loop **without** the pool grew
/// 1204 MB against a 1200 MB file, and 0 MB with it.
///
/// Gated: this test writes and hashes over a gigabyte to make the defect
/// unmissable — `HELM_BENCH=1 swift test --filter ReleaseDigestFootprintTests`.
final class ReleaseDigestFootprintTests: XCTestCase {

    private var file: URL!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        file = scratchDirectory("digest-footprint").appendingPathComponent("asset.bin")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        let chunk = Data(count: 1024 * 1024)
        for _ in 0..<1200 { handle.write(chunk) }   // 1200 MB
    }

    override func tearDownWithError() throws {
        if let file { try? FileManager.default.removeItem(at: file) }
    }

    func testHashingARealeaseAssetCostsItsSliceNotItsVolume() throws {
        let before = try XCTUnwrap(MemoryFootprint.current())
        let digest = try ReleaseDigest.sha256(ofFileAt: file)
        let after = try XCTUnwrap(MemoryFootprint.current())

        XCTAssertTrue(ReleaseDigest.isHexDigest(digest))

        let grewMB = (after - before) / (1024 * 1024)
        print("ReleaseDigest.sha256 over ~1200 MB: footprint grew \(grewMB) MB")

        // A gate, not a report. The bound is deliberately far above what the
        // fix actually costs (0 MB measured) and far below what its absence
        // costs (1204 MB): anything in between means the pool stopped
        // draining per slice, and the number itself is too noisy to pin
        // tightly. A test that only prints cannot fail, and this defect
        // reached a release once already.
        XCTAssertLessThan(grewMB, 64,
                          "hashing a release asset cost \(grewMB) MB — the footprint is tracking "
                          + "the volume read rather than one slice, so the autoreleasepool inside "
                          + "the read loop is gone or no longer drains")
    }
}
