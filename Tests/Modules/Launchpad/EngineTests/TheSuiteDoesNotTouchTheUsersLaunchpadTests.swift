import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine

/// `<Application Support>/Helm/Launchpad/layout.json` is the person's own arrangement; `LayoutStore()` is the
/// initializer the app uses, and in a test process it must resolve under the scratch folder `HelmSupport` makes.
/// The expected home is spelled out here rather than read off the store, which is the thing on trial.
final class TheSuiteDoesNotTouchTheUsersLaunchpadTests: XCTestCase {
    private var personsLibrary: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    func testTheDefaultStoreIsNotThePersonsOwnFile() {
        XCTAssertTrue(TestProcess.isRunning)
        XCTAssertFalse(LayoutStore().fileURL.path.hasPrefix(personsLibrary.path), "\(LayoutStore().fileURL.path) is the person's own file")
    }

    func testTheDefaultStoreSitsUnderHelmSupport() {
        XCTAssertEqual(LayoutStore().fileURL.standardizedFileURL.path,
                       HelmSupport.directory.appendingPathComponent("Launchpad/layout.json").standardizedFileURL.path)
    }
}
