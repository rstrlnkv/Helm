import HelmContract
import HelmUI
import XCTest
@testable import HelmApp

/// **A tour that only describes hands nothing over.** Nine steps, nine
/// summaries, a switch on each, and at the end of it every module is exactly as
/// unconfigured as it was — which is the right answer for eight of them, and the
/// wrong one for the module that does nothing at all until somebody writes a
/// rule.
///
/// The offer is the descriptor's, so this is the check that the one module with
/// something to hand over says so, and that no other module quietly grew a
/// button on its step.
@MainActor
final class TheTourOffersWhatAModuleHasTests: XCTestCase {

    private var metadata: [ModuleMetadata] { ModuleRegistry.all.map(\.moduleMetadata) }

    func testExactlyOneModuleOffersSomethingAndItIsAutopilot() {
        let offering = metadata.filter { $0.welcomeOffer != nil }
        XCTAssertEqual(offering.map(\.id.rawValue), ["autopilot"])
    }

    /// The offer reaches the step, which is the half a person sees. Built from
    /// the real registry rather than from a fixture: the two halves are a
    /// descriptor and a builder in different targets, and only this sees both.
    func testTheOfferReachesTheStepForThatModule() throws {
        let steps = WelcomeSteps.build(from: metadata)
        let autopilot = try XCTUnwrap(steps.first { $0.moduleID == "autopilot" })

        XCTAssertEqual(autopilot.offer,
                       try XCTUnwrap(metadata.first { $0.id.rawValue == "autopilot" })
                           .welcomeOffer)
        XCTAssertFalse(autopilot.offer?.isEmpty ?? true, "the button carries no word")
    }

    /// And every other step carries none, so the button is where it was meant
    /// to be rather than everywhere.
    func testNoOtherStepCarriesAnOffer() {
        let steps = WelcomeSteps.build(from: metadata)
        XCTAssertEqual(steps.filter { $0.offer != nil }.map(\.moduleID), ["autopilot"])
    }
}
