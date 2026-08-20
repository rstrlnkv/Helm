import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// **The record `TrashOfferPlan.answered` refuses to write is written anyway,
/// one click later, by the close.**
///
/// Two promises stand behind the unprompted Trash window, both of them about the
/// same permanent record — `trashOfferDismissed`, final for as long as the app
/// sits in the Trash, over files that are on no other screen Helm has:
///
/// - `TrashOfferPlan.answered`: «Not the ones whose files macOS refused. A
///   refusal is not a decision — the person can grant Full Disk Access, unlock
///   the file, quit whatever was holding it.»
/// - `TrashedLeftoversModel.removeSelection`, on a reply that never came:
///   «Nothing is recorded, the window stays, and it says what is true: nobody
///   knows what moved.»
///
/// Both are undone by the way out. `TrashedLeftoversView.onDisappear` runs
/// `Task { await model.answered() }` with no argument, which declines **every
/// group on screen** — and after a refusal or a lost reply the only thing left
/// in the footer is «Done», so the person's next click writes exactly the record
/// the two rules above spent their care refusing. The window standing open is
/// the whole of what they buy.
///
/// The subject here is the close, so the tests drive what the close drives:
/// `removeSelection()`, then `answered()`. `testTheCloseIsWhatRecordsTheAnswer`
/// keeps that pairing honest — it is the line in the view, read from the source,
/// so a `.onDisappear` that stops calling `answered()` fails here rather than
/// quietly making the rest of this file a test of nothing.
@MainActor
final class ARefusalIsNotADeclineAtTheCloseTests: XCTestCase {

    private func offer(_ id: String, matchedByName: Bool = false) -> TrashedAppLeftovers {
        TrashedAppLeftovers(
            bundleID: id, name: "Vendor Tool", appPath: "/Users/x/.Trash/\(id).app",
            leftovers: [Leftover(path: "\(NSHomeDirectory())/Library/Caches/\(id)",
                                 kind: .caches, sizeBytes: 2_048, matchedByName: matchedByName)])
    }

    private func opened(_ wire: UninstallerWire) async -> TrashedLeftoversModel {
        let model = TrashedLeftoversModel(vm: ModuleViewModel(transport: wire))
        await model.load()
        return model
    }

    /// The bundle ids written to the permanent record, in the order they were
    /// written.
    private func declined(_ wire: UninstallerWire) -> [String] {
        wire.payloads(of: .dismissTrashedApp).compactMap { String(bytes: $0, encoding: .utf8) }
    }

    // MARK: -

    /// **The finding.** One app's files moved, the other's were refused by macOS.
    /// The window keeps itself up to say so — and then the click that takes it
    /// down files the refused app as the person's own "no".
    func testAnAppMacOSRefusedIsNotDeclinedByClosingTheReport() async throws {
        let moved = offer("com.vendor.moved")
        let refused = offer("com.vendor.refused")
        let wire = UninstallerWire(
            removal: UninstallResult(
                trashed: moved.leftovers.map(\.path), freedBytes: 2_048,
                failures: refused.leftovers.map {
                    TrashFailureInfo(path: $0.path, reason: .needsFullDiskAccess,
                                     message: "Operation not permitted")
                }),
            offers: [moved, refused])
        let model = await opened(wire)
        XCTAssertEqual(model.groups.count, 2, "precondition: both apps are on screen")

        let mayClose = await model.removeSelection()

        XCTAssertFalse(mayClose, "precondition: a refusal keeps the window up to report it")
        XCTAssertEqual(declined(wire), ["com.vendor.moved"], """
            precondition: the removal filed the app it answered for and only that one — \
            the subject of the assertion below has to have happened for its absence to \
            mean anything
            """)

        // The close. `TrashedLeftoversView.onDisappear` runs exactly this, and it
        // is reached by Done, by Escape and by the red button alike.
        await model.answered()

        XCTAssertFalse(declined(wire).contains("com.vendor.refused"), """
            closing the report filed the app macOS refused as the person's own "no". That \
            record is final for as long as the app sits in the Trash, and this window is the \
            only place a Group Container or a name-matched folder is ever offered — so \
            granting Full Disk Access afterwards does not bring the offer back.
            """)
    }

    /// The same for the silence, which is the state
    /// `ADismissalIsWrittenFromAnAnswerTests` proves `removeSelection` handles —
    /// and which the close undoes. Nobody knows what moved, and the window files
    /// every app in it anyway.
    func testALostReplyIsNotADeclineWhenTheWindowIsClosed() async throws {
        for silence in UninstallerWire.Answer.silences {
            let group = offer("com.vendor.tool")
            let wire = UninstallerWire(offers: [group])
            let model = await opened(wire)
            XCTAssertFalse(model.selected.isEmpty, "precondition: something is ticked (\(silence))")

            wire.answers(silence, to: .trashPaths)
            let mayClose = await model.removeSelection()

            XCTAssertTrue(wire.commands.contains(.trashPaths),
                          "precondition: the batch really was sent (\(silence))")
            XCTAssertFalse(mayClose, "precondition: the window stays up (\(silence))")
            XCTAssertTrue(model.replyLost, "precondition: it knows the reply was lost (\(silence))")

            await model.answered()

            XCTAssertEqual(declined(wire), [], """
                the window was closed over a batch nobody answered — the engine may have \
                moved every file or none of them — and filed the app as declined anyway \
                (\(silence)). Nothing is left that would ever offer those files again.
                """)
        }
    }

    /// **The half that must keep working**, and the reason the assertions above
    /// cannot simply be "record nothing at the close": a window closed without an
    /// answer *is* a "no", and one that is not recorded comes back at the next
    /// launch. Cancel, Escape and the red button all reach this with no removal
    /// before them.
    func testClosingWithoutARemovalStillDeclinesEveryAppOnScreen() async throws {
        let first = offer("com.vendor.one")
        let second = offer("com.vendor.two")
        let wire = UninstallerWire(offers: [first, second])
        let model = await opened(wire)

        await model.answered()

        XCTAssertEqual(Set(declined(wire)), ["com.vendor.one", "com.vendor.two"],
                       "a window shut without an answer will open again at the next launch")
        XCTAssertFalse(wire.commands.contains(.trashPaths),
                       "precondition: nothing was removed, so this is the plain no")
    }

    /// The pairing this file rests on, read off the view that ships.
    ///
    /// Without it every assertion above is about a method the window might no
    /// longer call — a test of an absence, passing because the subject never
    /// happens. `RepoSource.root` rather than a count of parent directories,
    /// which is a fact about where this file sits (CLAUDE.md § Test plumbing).
    func testTheCloseIsWhatRecordsTheAnswer() throws {
        let view = RepoSource.root
            .appendingPathComponent("Sources/Modules/Uninstaller/UI/TrashedLeftoversView.swift")
        let source = try String(contentsOf: view, encoding: .utf8)

        let disappear = try XCTUnwrap(source.range(of: ".onDisappear"),
                                      "the window no longer records an answer when it goes away")
        XCTAssertTrue(source[disappear.lowerBound...].prefix(200).contains("model.answered()"), """
            `.onDisappear` no longer calls `answered()`, so the tests in this file drive a \
            path the window does not take. Either the record moved, and they should move \
            with it, or every way out of this window has stopped being an answer.
            """)
    }
}
