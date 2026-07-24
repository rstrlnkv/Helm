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
}
