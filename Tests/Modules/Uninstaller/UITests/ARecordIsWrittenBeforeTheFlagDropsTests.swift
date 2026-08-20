import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// **The flag came down one line after the reply, and the round was not over.**
///
/// `TrashedLeftoversModel.busy` is read by two different things and they want
/// different halves of it. The footer wants "is a batch in flight", which is
/// what `TheTrashOfferSendsOneBatchTests` drives. `refresh()` wants something
/// wider — `guard !busy, outcome == nil` — because a Trash arrival landing
/// mid-removal would rebuild `groups` out from under the record about to be
/// written from them, and `removeSelection` fixes the list it answers for
/// *before* the work starts precisely so that answering on somebody's behalf
/// cannot happen.
///
/// `busy = false` sat between the reply and `answered()`, so that door stood
/// open for exactly the stretch where it matters: the permanent record —
/// `trashOfferDismissed`, final for as long as the app sits in the Trash — is
/// written after it, over files that are on no other screen Helm has.
///
/// The record is what the flag is measured against here, rather than the reply:
/// a transport that answers the batch and then hangs on the dismissal puts the
/// model in the middle of the write, which is the moment the old ordering had
/// already declared itself idle.
@MainActor
final class ARecordIsWrittenBeforeTheFlagDropsTests: XCTestCase {

    /// Answers the sweep and the batch at once, and holds the **record** open
    /// until released.
    private final class HoldsTheRecord: EngineTransport, @unchecked Sendable {
        var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }
        private let lock = NSLock()
        private var written = 0
        /// How many apps have been filed so far.
        var records: Int { lock.withLock { written } }
        private let released = AsyncStream<Void>.makeStream()
        private let offers: [TrashedAppLeftovers]

        init(offers: [TrashedAppLeftovers]) { self.offers = offers }

        func release() { released.continuation.finish() }

        /// The enum rather than a name of its own: a fake answering strings goes
        /// on answering after the module renames a command, and what it answers
        /// then is `Data()` — which this codebase spells «the module could not
        /// answer».
        func send(_ command: EngineCommand) async throws -> Data {
            switch UninstallerCommand(rawValue: command.name) {
            case .trashedAppLeftovers:
                return (try? JSONEncoder().encode(offers)) ?? Data()
            case .trashPaths:
                return (try? JSONEncoder().encode(
                    UninstallResult(trashed: ["\(NSHomeDirectory())/Library/Caches/com.vendor.tool"],
                                    freedBytes: 2_048))) ?? Data()
            case .dismissTrashedApp:
                lock.withLock { written += 1 }
                // Hangs until `release()`. A `return` here would put the model
                // past the write before anything could look at it, and the
                // ordering this file is about would be untestable.
                for await _ in released.stream {}
                return Data()
            default:
                return Data()
            }
        }
    }

    private func offer(_ id: String) -> TrashedAppLeftovers {
        TrashedAppLeftovers(
            bundleID: id, name: "Vendor Tool", appPath: "/Users/x/.Trash/\(id).app",
            leftovers: [Leftover(path: "\(NSHomeDirectory())/Library/Caches/\(id)",
                                 kind: .caches, sizeBytes: 2_048, matchedByName: false)])
    }

    // MARK: -

    func testTheModelIsStillBusyWhileThePermanentRecordIsWritten() async throws {
        let transport = HoldsTheRecord(offers: [offer("com.vendor.tool")])
        let model = TrashedLeftoversModel(vm: ModuleViewModel(transport: transport))
        await model.load()
        XCTAssertFalse(model.selected.isEmpty, "precondition: something is ticked")

        let running = Task { await model.removeSelection() }
        for _ in 0..<50 where transport.records == 0 { await Task.yield() }
        XCTAssertEqual(transport.records, 1, """
            precondition: the model is inside the write. Without that this test asserts \
            something about a moment that never happened, which is a test of an absence \
            passing because its subject was never reached.
            """)

        XCTAssertTrue(model.busy, """
            the removal declared itself idle before the record was written. `refresh()` \
            reads that flag to decide whether a Trash arrival may rebuild `groups`, and the \
            record being written names the apps this round answered for — so the door stands \
            open for exactly the stretch where a rebuild changes what is being answered for.
            """)

        transport.release()
        _ = await running.value
        XCTAssertFalse(model.busy, "the flag outlived the work it describes")
    }
}
