import HelmContract
import HelmRuntime
import HelmUI
import XCTest
import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// **The unprompted Trash window read a silence as «the person said no».**
///
/// `removeSelection` computed `TrashOfferPlan.answered(answering, failed:
/// Set(result?.failed ?? []))`, so a reply that never came meant *no path
/// failed*, which meant **every** group had been answered for and was written to
/// `trashOfferDismissed` — and then the window closed as if the job were done.
/// The record is final for as long as the app sits in the Trash, and after that
/// the bundle that identified those files is gone for good: a group container, a
/// name-matched support folder and a set of caches, on no screen Helm has, from
/// one dropped reply.
///
/// The window already has a state for «we are not done»: a report keeps it up
/// and turns the footer into a single «Done».
@MainActor
final class ADismissalIsWrittenFromAnAnswerTests: XCTestCase {

    private static let silences: [UninstallerWire.Answer] = [.refuse, .nothing]

    private func offer(_ id: String) -> TrashedAppLeftovers {
        TrashedAppLeftovers(
            bundleID: id, name: "Vendor Tool", appPath: "/Users/x/.Trash/Vendor Tool.app",
            leftovers: [Leftover(path: "\(NSHomeDirectory())/Library/Caches/\(id)",
                                 kind: .caches, sizeBytes: 2_048, matchedByName: false)])
    }

    private func opened(_ wire: UninstallerWire) async -> TrashedLeftoversModel {
        let model = TrashedLeftoversModel(vm: ModuleViewModel(transport: wire))
        await model.load()
        return model
    }

    // MARK: -

    /// The finding: nothing was recorded, and the window stays.
    func testALostReplyRecordsNoDismissalAndKeepsTheWindowOpen() async {
        for silence in Self.silences {
            let group = offer("com.vendor.tool")
            let wire = UninstallerWire(offers: [group])
            let model = await opened(wire)
            XCTAssertEqual(model.groups.count, 1, "precondition: the window has a group (\(silence))")
            XCTAssertFalse(model.selected.isEmpty, "precondition: something is ticked (\(silence))")

            wire.answers(silence)
            let mayClose = await model.removeSelection()

            XCTAssertTrue(wire.commands.contains(.trashPaths),
                          "precondition: the batch really was sent (\(silence))")
            XCTAssertFalse(wire.commands.contains(.dismissTrashedApp), """
                a removal the engine never answered (\(silence)) was filed as the person's \
                "no" for every app in the window — permanently, for files that are on no \
                other screen
                """)
            XCTAssertFalse(mayClose,
                           "and the window closed over files that are still there (\(silence))")
            XCTAssertTrue(model.replyLost,
                          "with nothing on it to say what happened (\(silence))")
            XCTAssertNil(model.outcome, "and nothing may claim anything moved (\(silence))")
        }
    }

    /// The half that keeps the record working: a removal that *was* answered
    /// still files the apps it answered for, and the window closes.
    func testAnAnsweredRemovalStillRecordsTheApps() async {
        let group = offer("com.vendor.tool")
        let wire = UninstallerWire(
            removal: UninstallResult(trashed: group.leftovers.map(\.path), freedBytes: 2_048),
            offers: [group])
        let model = await opened(wire)

        let mayClose = await model.removeSelection()

        XCTAssertTrue(wire.commands.contains(.dismissTrashedApp),
                      "an app whose files all moved will be offered again at the next launch")
        XCTAssertTrue(mayClose, "and the window stayed open over a job that is done")
        XCTAssertFalse(model.replyLost)
    }
}
