import XCTest
import HelmContract
@testable import Module_Hosts_UI

@MainActor
final class HostsDescriptorTests: XCTestCase {

    /// The descriptor reads the engine's constant rather than repeating it.
    /// Two spellings of one id do not fail — they read a different store, and
    /// the person's settings are simply gone.
    func testTheDescriptorTakesItsIDFromTheEngine() {
        XCTAssertEqual(HostsDescriptor.id.rawValue, "hosts")
    }

    /// The sidebar column is fixed and truncates mid-word, so a compound name
    /// carries a short form. This fails if someone drops it later.
    func testTheSidebarNameIsShorterThanTheFullName() {
        let m = HostsDescriptor.metadata
        XCTAssertLessThan(m.shortName.count, m.name.count)
    }
}
