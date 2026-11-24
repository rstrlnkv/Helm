import XCTest
import HelmRuntime
@testable import HelmApp

@MainActor
final class PanelLayoutStoreTests: XCTestCase {

    /// **The key is not `panelLayout`.** That one is in
    /// `ObsoleteDefaults.retired` — a grid the app had once and rolled back —
    /// so a layout stored under it would be deleted at the next launch and the
    /// panel would forget its arrangement every morning. Nothing about that
    /// failure looks like a bug while you are looking at it.
    func testTheKeyIsNotOneThatGetsPurgedAtLaunch() {
        let namespaced = "module.app." + PanelLayoutStore.key
        XCTAssertFalse(ObsoleteDefaults.retired.contains(namespaced),
                       "\(namespaced) is purged at every launch")
    }
}
