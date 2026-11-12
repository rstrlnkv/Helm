import XCTest
@testable import HelmRuntime

/// Decision 1: Helm Dev writes under `Application Support/Helm Dev`; the
/// release, a test runner and a process with no identifier keep `Helm`.
final class HelmDevKeepsItsOwnFoldersTests: XCTestCase {
    private let home = "/Users/anna"

    func testTheReleaseNilAndTheTestRunnerKeepTheDeployedFolder() {
        for id in ["com.helm.app", nil, "com.apple.dt.xctest.tool"] as [String?] {
            XCTAssertEqual(DataFolder.of(identifier: id), .helm, "\(id ?? "nil")")
        }
        XCTAssertEqual(HelmSupport.path(home: home, folder: .helm),
                       "/Users/anna/Library/Application Support/Helm")
    }

    func testHelmDevHasAFolderOfItsOwn() {
        XCTAssertEqual(DataFolder.of(identifier: "com.helm.app.dev"), .helmDev)
        XCTAssertEqual(HelmSupport.path(home: home, folder: .helmDev),
                       "/Users/anna/Library/Application Support/Helm Dev")
    }

    func testTheDirectoryIsNamedByTheFolderOverTheLookupOrTheSpelledPath() {
        let base = URL(fileURLWithPath: "/Users/anna/Library/Application Support")
        XCTAssertEqual(HelmSupport.directory(base: base, home: home, folder: .helmDev).path,
                       "/Users/anna/Library/Application Support/Helm Dev")
        XCTAssertEqual(HelmSupport.directory(base: base, home: home, folder: .helm).path,
                       "/Users/anna/Library/Application Support/Helm")
        XCTAssertEqual(HelmSupport.directory(base: nil, home: home, folder: .helmDev).path,
                       "/Users/anna/Library/Application Support/Helm Dev")
    }

    func testUnderATestRunnerThisBuildIsTheDeployedFolder() {
        XCTAssertEqual(AppBuild.dataFolder, .helm)
        let base = URL(fileURLWithPath: "/Users/anna/Library/Application Support")
        XCTAssertEqual(HelmSupport.buildDirectory(base: base, home: home).path,
                       "/Users/anna/Library/Application Support/Helm")
        XCTAssertEqual(HelmSupport.buildDirectory(base: nil, home: home).path,
                       "/Users/anna/Library/Application Support/Helm")
    }
}
