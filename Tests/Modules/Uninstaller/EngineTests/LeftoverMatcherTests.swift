import XCTest
@testable import Module_Uninstaller_Engine

final class LeftoverMatcherTests: XCTestCase {
    let lib = URL(fileURLWithPath: "/Users/x/Library")

    func testBundleIdCandidatesCoverKnownDirs() {
        let c = LeftoverMatcher.candidates(bundleID: "com.acme.tool", appName: "Tool", library: lib)
        let paths = Set(c.map { $0.url.path })
        XCTAssertTrue(paths.contains("/Users/x/Library/Caches/com.acme.tool"))
        XCTAssertTrue(paths.contains("/Users/x/Library/Preferences/com.acme.tool.plist"))
        XCTAssertTrue(paths.contains("/Users/x/Library/Containers/com.acme.tool"))
        XCTAssertTrue(paths.contains("/Users/x/Library/Saved Application State/com.acme.tool.savedState"))
    }

    func testNameCandidatesFlaggedAndScopedToSupportAndLogs() {
        let c = LeftoverMatcher.candidates(bundleID: "com.acme.tool", appName: "Tool", library: lib)
        let named = c.filter { $0.matchedByName }
        XCTAssertFalse(named.isEmpty)
        XCTAssertTrue(named.allSatisfy { $0.kind == .appSupport || $0.kind == .logs })
        XCTAssertTrue(named.contains { $0.url.path == "/Users/x/Library/Application Support/Tool" })
    }

    func testGroupContainersIsSuffixGlob() {
        let c = LeftoverMatcher.candidates(bundleID: "com.acme.tool", appName: "Tool", library: lib)
        let gc = c.first { $0.kind == .groupContainers }
        XCTAssertNotNil(gc)
        XCTAssertTrue(gc!.isGlob)
    }

    // MARK: - Extension containers (found the hard way: a VPN app left
    // `<id>.packet-extension-mac` behind because only exact ids were matched)

    func testContainersMatchExtensionSuffixes() {
        let c = LeftoverMatcher.candidates(bundleID: "com.acme.tool", appName: "Tool",
                                           library: URL(fileURLWithPath: "/L"))
        let containerGlobs = c.filter { $0.kind == .containers && $0.isGlob }.map(\.url.path)
        XCTAssertTrue(containerGlobs.contains("/L/Containers/com.acme.tool*"), "\(containerGlobs)")
    }

    func testGroupContainersMatchBothTeamAndGroupPrefixes() {
        let c = LeftoverMatcher.candidates(bundleID: "com.acme.tool", appName: "Tool",
                                           library: URL(fileURLWithPath: "/L"))
        let globs = c.filter { $0.kind == .groupContainers }.map(\.url.path)
        // 2XZUN9L63Z.com.acme.tool  and  group.com.acme.tool
        XCTAssertTrue(globs.contains("/L/Group Containers/*.com.acme.tool"), "\(globs)")
        // …and any suffixed variant of the id itself
        XCTAssertTrue(globs.contains("/L/Group Containers/*com.acme.tool*"), "\(globs)")
    }

    func testCachesAndScriptsMatchHelperSuffixes() {
        let c = LeftoverMatcher.candidates(bundleID: "com.acme.tool", appName: "Tool",
                                           library: URL(fileURLWithPath: "/L"))
        let caches = c.filter { $0.kind == .caches }.map(\.url.path)
        XCTAssertTrue(caches.contains("/L/Caches/com.acme.tool*"), "\(caches)")
        let scripts = c.filter { $0.kind == .appScripts }.map(\.url.path)
        XCTAssertTrue(scripts.contains("/L/Application Scripts/com.acme.tool*"), "\(scripts)")
    }

    /// A glob must not swallow a different app that merely shares a prefix.
    func testPrefixGlobsStayScopedToTheId() {
        let c = LeftoverMatcher.candidates(bundleID: "com.acme.tool", appName: "Tool",
                                           library: URL(fileURLWithPath: "/L"))
        XCTAssertFalse(c.contains { $0.url.lastPathComponent == "*" })
    }
}
