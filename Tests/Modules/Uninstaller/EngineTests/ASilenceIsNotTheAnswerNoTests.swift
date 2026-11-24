import HelmRuntime
import XCTest
@testable import Module_Uninstaller_Engine

/// The record of a "no" is written from an answer, never from its absence: it
/// is final while the app sits in the Trash (`TrashOfferPlan.answered`). A
/// batch the engine held, or one macOS refused, answers for nobody it touched.
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

    /// A batch held for a running application moved nothing and answers for
    /// nobody. This window never sends a bundle, but the rule's failure would be
    /// permanent and silent, so it holds regardless.
    func testABatchHeldForARunningAppAnswersForNobody() {
        let result = UninstallResult(trashed: [], freedBytes: 0,
                                     stillRunning: ["/Applications/Vendor Player.app"])

        XCTAssertEqual(TrashOfferPlan.answered(groups, to: result).map(\.bundleID), [],
                       "a batch that moved nothing was filed as the person's no")
    }

    /// And a refusal from macOS is still not a decision.
    func testAnAppMacOSRefusedIsStillNotAnswered() {
        let result = UninstallResult(
            trashed: ["/b1"], freedBytes: 10,
            failures: [TrashFailureInfo(path: "/a1", reason: .needsFullDiskAccess)])

        XCTAssertEqual(TrashOfferPlan.answered(groups, to: result).map(\.bundleID), ["com.b"],
                       "an app macOS refused was filed as the person's no")
    }
}
