import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// `ReleaseDigest.sha256(ofFileAt:)` streams a release asset in 1 MB slices,
/// and `FileHandle.read` hands back an autoreleased `Data`, so a serial loop
/// without a pool inside it grows by the size of the file
/// (Architecture/ModulePattern.md § Bulk reads).
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

    func testHashingARealeaseAssetCostsItsSliceNotItsVolume() throws {
        let before = try XCTUnwrap(MemoryFootprint.current())
        let digest = try ReleaseDigest.sha256(ofFileAt: file)
        let after = try XCTUnwrap(MemoryFootprint.current())

        XCTAssertTrue(ReleaseDigest.isHexDigest(digest))

        let grewMB = (after - before) / (1024 * 1024)
        print("ReleaseDigest.sha256 over ~1200 MB: footprint grew \(grewMB) MB")

        // A gate, not a report: the bound is far above what the pool costs
        // and far below what its absence costs (about the file's size), since
        // the number is too noisy to pin tightly.
        XCTAssertLessThan(grewMB, 64,
                          "hashing a release asset cost \(grewMB) MB — the footprint is tracking "
                          + "the volume read rather than one slice, so the autoreleasepool inside "
                          + "the read loop is gone or no longer drains")
    }
}
