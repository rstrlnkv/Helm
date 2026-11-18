import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine

/// Inputs nobody fed the real catalog: a symlinked `.app` asked for its identifier, and a watch over a folder that is not there.
/// What a planted file can hand the walk is `ACatalogUnderOddBundlesTests`'.
final class ACatalogUnderOddLocalizationTests: XCTestCase {
    private func app(_ name: String, in root: URL, id: String = "x.app") throws -> URL {
        let bundle = root.appendingPathComponent(name)
        let contents = bundle.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id, "CFBundleName": "FromPlist",
                                                              "CFBundleDevelopmentRegion": "en"] as [String: Any],
                                           format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        return bundle
    }

    func testTheIdentifierOfASymlinkedAppResolves() throws {
        let root = scratchDirectory("odd-link")
        let elsewhere = scratchDirectory("odd-link-target")
        let real = try app("Real.app", in: elsewhere, id: "x.real")
        let link = root.appendingPathComponent("Link.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        XCTAssertEqual(FileSystemAppCatalog(roots: [root]).bundleID(atPath: link.path), "x.real")
        XCTAssertNil(FileSystemAppCatalog(roots: [root]).bundleID(atPath: root.appendingPathComponent("Nothing.app").path))
    }

    /// The system's own symlinked app (Safari → Cryptexes), where this macOS has one.
    func testTheIdentifierOfSafariResolvesThroughItsSystemLink() throws {
        let path = "/Applications/Safari.app"
        try XCTSkipUnless((try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil, "Safari is not a symlink here")
        XCTAssertEqual(FileSystemAppCatalog().bundleID(atPath: path), "com.apple.Safari")
    }

    func testAWatchOverAMissingRootNeitherCrashesNorCalls() async throws {
        let missing = scratchDirectory("odd-missing").appendingPathComponent("nothing")
        let heard = LockedCount()
        var token: AnyObject? = FileSystemAppCatalog(roots: [missing]).observeChanges { heard.bump() }
        await grace(1.5)
        XCTAssertEqual(heard.value, 0)
        token = nil
        await grace(0.5)
        _ = token
    }

    func testAMissingRootDoesNotStopTheOtherRootBeingWatched() async throws {
        let missing = scratchDirectory("odd-missing2").appendingPathComponent("nothing")
        let root = scratchDirectory("odd-present")
        let heard = LockedCount()
        let token = FileSystemAppCatalog(roots: [missing, root]).observeChanges { heard.bump() }
        try await Task.sleep(for: .milliseconds(500))
        let made = try runChild("/bin/mkdir", ["-p", root.appendingPathComponent("New.app/Contents").path])
        XCTAssertEqual(made.status, 0, made.errors)
        await waitUntilWithin("a change under the present root", .seconds(8)) { heard.value > 0 }
        withExtendedLifetime(token) {}
    }
}
