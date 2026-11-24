import XCTest
import HelmRuntime
@testable import HelmApp

@MainActor
final class PanelLayoutStoreTests: XCTestCase {

    /// **The key is not `panelLayout`.** That one is in
    /// `ObsoleteDefaults.retired`, so a layout stored under it would be deleted
    /// at the next launch and the panel would forget its arrangement every
    /// morning, which looks like no bug while you are looking at it.
    func testTheKeyIsNotOneThatGetsPurgedAtLaunch() {
        let namespaced = "module.app." + PanelLayoutStore.key
        XCTAssertFalse(ObsoleteDefaults.retired.contains(namespaced),
                       "\(namespaced) is purged at every launch")
    }
}
