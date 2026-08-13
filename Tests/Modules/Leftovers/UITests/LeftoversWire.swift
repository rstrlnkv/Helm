import Foundation
import HelmContract
import HelmRuntime
import Module_Leftovers_Engine

/// The wire the pages in this target are drawn against: one scan reply, one
/// removal reply, and the three things the transport behind the real page can do
/// with a request.
///
/// **There were two of these, and they were one fake.**
/// `ARemovalReportDoesNotEatTheListTests.Wire` and
/// `LeftoversPageContractTests.ScanTransport` answered the same two commands from
/// the same two fields through the same lock; the only difference was that one
/// could be told what the rescan after a removal would find and the other could
/// not — so the poorer of the two silently made «the list after the removal» a
/// question no test in that file could ask. One fake with the richer behaviour,
/// the way `HelmTestSupport` holds `scratchDirectory` rather than thirty copies of
/// it. It is not in `HelmTestSupport` itself for the reason nothing module-shaped
/// can be: that target is below the modules and knows no `StaleItem`.
///
/// **Three answers, because the wire has three and the view model reads two of
/// them as success.** A reply; empty `Data`; or a throw.
///
/// Empty `Data` is the one this module reaches today, and it reaches it in three
/// ways that are all in the tree: `LeftoversEngine.wireTransport` returns it from
/// `guard let self else` (the engine deallocated under a page that is still up) and
/// from `guard let name = LeftoversCommand(rawValue:)` (a command name the engine
/// does not know — the door that enum's own doc deliberately leaves open); and
/// `LeftoversViewModel.shared(vm:)` says in as many words that a cached model
/// outliving its engine holds a transport that «answers every request with empty
/// Data from then on». `TransportClient` calls that «the module could not answer»;
/// this view model reads it as «no leftovers on this Mac» and «moved to the Trash».
///
/// A throw is what `EngineTransport.send` is declared to do and what
/// `TransportClient.request` already folds to the same nil with `try?` — today's
/// only implementation raises it just by way of a handler that throws, which is
/// what `FixtureTransport` in `HelmAppTests` does for a command it was not given.
/// It is kept apart from the empty reply rather than folded into it because the
/// two are not the same wire: JSON decodes nothing from either, but a *raw* reply
/// decodes something from empty `Data`, so a module that ever answers a plain
/// string tells them apart even though this one cannot.
///
/// A fake that could only reply could not be in either state, so what the page
/// says about an unanswered scan and an unanswered removal was a question no test
/// in this target could ask.
final class LeftoversWire: EngineTransport, @unchecked Sendable {

    /// What the engine behind this wire does with a request.
    enum Answer: Equatable {
        /// The reply the fixture holds: an engine that is there and answers.
        case reply
        /// `send` throws, which `TransportClient.request` turns into the same nil
        /// as a reply that will not decode.
        case refuse
        /// Empty `Data` — an engine that is gone, or a command it does not know.
        case nothing
    }

    private let lock = NSLock()
    private var items: [StaleItem]
    private var removal: LeftoversRemoval
    private var answer: Answer
    private var seen: [LeftoversCommand] = []

    var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }

    init(items: [StaleItem],
         removal: LeftoversRemoval = LeftoversRemoval(removed: [], refused: [], freedBytes: 0),
         answering answer: Answer = .reply) {
        self.items = items
        self.removal = removal
        self.answer = answer
    }

    /// What the rescan after a removal — or after a toggle — will see.
    func setItems(_ next: [StaleItem]) { lock.withLock { items = next } }

    /// The engine going away under the page, or coming back. A port that can
    /// change while the app is running hands that state back rather than being
    /// fixed at init (CLAUDE.md § Anything that can stop being true on its own).
    func answers(_ next: Answer) { lock.withLock { answer = next } }

    /// Which commands reached the wire, in order — so a test can assert that the
    /// act it is about really was attempted before asserting what was said about
    /// it. An assertion about an absence passes when the subject never happened.
    var commands: [LeftoversCommand] { lock.withLock { seen } }

    /// The enum, not the two literals this used to switch on. A fake that answers
    /// names of its own goes on answering after the module renames one — and what
    /// it answers then is `Data()`, which this codebase spells «the module could
    /// not answer».
    func send(_ command: EngineCommand) async throws -> Data {
        let name = LeftoversCommand(rawValue: command.name)
        // One turn of the lock for the whole answer: the record of the request and
        // the state it is answered from have to be the same moment, or a `setItems`
        // between them makes the reply describe a wire nobody was in.
        let reply: Reply = lock.withLock {
            if let name { seen.append(name) }
            switch (answer, name) {
            case (.refuse, _): return .refuse
            case (.nothing, _), (_, .none), (_, .setDisabled): return .empty
            case (.reply, .scan): return .data((try? JSONEncoder().encode(items)) ?? Data())
            case (.reply, .trash): return .data((try? JSONEncoder().encode(removal)) ?? Data())
            }
        }
        switch reply {
        case .refuse: throw CancellationError()
        case .empty: return Data()
        case .data(let data): return data
        }
    }

    /// The answer, decided under the lock and delivered outside it — a `throw`
    /// cannot happen inside `withLock` without carrying the lock into the error
    /// path, and Swift 6 will not let this function take the lock itself.
    private enum Reply {
        case refuse, empty
        case data(Data)
    }
}
