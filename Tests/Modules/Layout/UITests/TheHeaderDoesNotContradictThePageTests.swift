import HelmContract
import XCTest
@testable import Module_Layout_UI
import Module_Layout_Engine

/// The window header and the page are the same screen, 56 pt apart.
///
/// With a password field in front the module suspends itself deliberately, and
/// the page says so: an orange «Paused» pill and a line explaining that Helm
/// never reads one. The header read `enabled` alone — which is whether the tap
/// is live, and it stays live through a pause — so it drew a green «Active»
/// pill directly above the orange one. Two marks about one module, in two
/// signal colours, disagreeing.
///
/// The header is allowed to be coarser than the page. It is not allowed to say
/// the opposite. `ModuleActivity` has two cases by design and a module may not
/// invent a third, so the pause reports as idle here and the page keeps the
/// word for it — «Paused» is a state to be waited out, not a fault to act on,
/// which is why it belongs in the page's own words rather than in a badge every
/// module would have to grow a case for.
///
/// The rule is a pure function so this test can reach it: `activity(_:)` needs
/// a `ModuleViewModel`, which needs a transport and an engine, and none of that
/// is the subject.
@MainActor
final class TheHeaderDoesNotContradictThePageTests: XCTestCase {

    func testARunningModuleIsActive() {
        XCTAssertEqual(LayoutDescriptor.activity(enabled: true, suspended: false), .active)
    }

    /// The defect.
    func testAPausedModuleIsNotDrawnAsActive() {
        XCTAssertNotEqual(LayoutDescriptor.activity(enabled: true, suspended: true), .active,
                          "the header said Active over a page that said Paused")
    }

    func testASwitchedOffTapIsIdleWhetherOrNotItIsAlsoPaused() {
        XCTAssertEqual(LayoutDescriptor.activity(enabled: false, suspended: false), .idle)
        XCTAssertEqual(LayoutDescriptor.activity(enabled: false, suspended: true), .idle)
    }
}
