import HelmRuntime
import XCTest
@testable import Module_Uninstaller_Engine

/// **The record of a "no" is written from an answer, never from its absence.**
///
/// The unprompted Trash window remembers which apps the person declined to clean
/// up after, and the record is final for as long as the app sits in the Trash
/// (`TrashOfferMemory.stillDismissed`) — after that the bundle that identified
/// those files is gone for good. `TrashOfferPlan.answered`'s own doc says why
/// that matters more here than anywhere: this window is the only place some of
/// these files are ever offered.
///
/// The rule takes the answer itself, not a count of failed paths taken out of
/// it: a batch the engine held, or one macOS refused, answers for nobody it
/// touched, and neither can be folded into "no path failed" at the call site.
final class ASilenceIsNotTheAnswerNoTests: XCTestCase {

    private static func group(_ id: String, _ paths: [String]) -> TrashedAppLeftovers {
        TrashedAppLeftovers(
            bundleID: id, name: id, appPath: "/Users/x/.Trash/\(id).app",
            leftovers: paths.map { Leftover(path: $0, kind: .caches, sizeBytes: 10,
                                            matchedByName: false) })
    }

    private let groups = [group("com.a", ["/a1"]), group("com.b", ["/b1"])]

    /// The half that keeps the rule from being "answer for nobody, ever": a
    /// removal that came back still answers for the apps whose paths moved.
    func testAnAnsweredRemovalStillAnswersForTheAppsThatMoved() {
        let result = UninstallResult(trashed: ["/a1", "/b1"], freedBytes: 20)

        XCTAssertEqual(TrashOfferPlan.answered(groups, to: result).map(\.bundleID),
                       ["com.a", "com.b"],
                       "a removal that worked left the window asking the same question again")
    }

    /// A batch the engine held because an application was still running moved
    /// nothing, so it answered for nobody either. This window can never send an
    /// app bundle, so the state does not arise here today — and "cannot arise" is
    /// exactly the kind of claim that stops being true one call site later, in a
    /// rule whose failure is permanent and silent.
    func testABatchHeldForARunningAppAnswersForNobody() {
        let result = UninstallResult(trashed: [], freedBytes: 0,
                                     stillRunning: ["/Applications/Vendor Player.app"])

        XCTAssertEqual(TrashOfferPlan.answered(groups, to: result).map(\.bundleID), [],
                       "a batch that moved nothing was filed as the person's no")
    }

    /// And a refusal is still not a decision — the existing rule, restated
    /// through the new door so that the repair cannot have quietly dropped it.
    func testAnAppMacOSRefusedIsStillNotAnswered() {
        let result = UninstallResult(
            trashed: ["/b1"], freedBytes: 10,
            failures: [TrashFailureInfo(path: "/a1", reason: .needsFullDiskAccess)])

        XCTAssertEqual(TrashOfferPlan.answered(groups, to: result).map(\.bundleID), ["com.b"],
                       "an app macOS refused was filed as the person's no")
    }
}
