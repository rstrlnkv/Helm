import Foundation
import HelmContract
import HelmRuntime
import Module_Autopilot_Engine

/// The wire the page in this target is drawn against: the four things the engine
/// answers, and the three things a transport can do with a request.
///
/// **Four states, because the rule store has four.** A page over a store that is
/// valid, empty, absent and *refused* has four different things to say, and the
/// difference between the last two is the whole of the finding this target was
/// opened for: `folders` answers `[]` for a rule set something else wrote exactly
/// as it does for a Mac that has never had a rule, and only the status tells
/// them apart. A fake that could not be in the refused state would make that a
/// question no test here could ask.
///
/// A throw and an empty reply are kept apart for the reason `LeftoversWire` gives
/// one target over: `TransportClient.request` folds both to `nil`, and this
/// module's engine reaches the empty one through `guard let self` and through a
/// command name it cannot parse.
final class AutopilotWire: EngineTransport, @unchecked Sendable {

    /// What the engine behind this wire does with a request.
    enum Answer: Equatable {
        case reply
        /// `send` throws, which `TransportClient.request` turns into the same nil
        /// as a reply that will not decode.
        case refuse
        /// Empty `Data` — an engine that is gone, or a command it does not know.
        case nothing
    }

    private let lock = NSLock()
    private var folders: [WatchedFolder]
    private var status: AutopilotStatus
    private var history: [ActionRecord]
    private var preview: [PreviewRow]
    private var report: SweepReport?
    /// What a return comes back with. A whole report rather than a flag,
    /// because a pass is not atomic: the state this has to be able to be in is
    /// "three went back and two did not", which is exactly what the page has to
    /// say out loud and what a Bool could not describe.
    private var undoReport = UndoReport(lines: [])
    private var answer: Answer
    private var seen: [AutopilotCommand] = []
    /// The folder list the page last sent, so a test can ask what a gesture
    /// tried to save — and, for the refusal, that it tried nothing at all.
    private(set) var saved: [[WatchedFolder]] = []
    /// The ids the page asked to put back, so a test can assert the gesture was
    /// made before asserting what was said about it.
    private(set) var returns: [String] = []
    /// The folder the last dry run was asked about. The rules in it are the
    /// finding: the editor used to send a folder of one rule, so what the page
    /// *asks* is as much the subject of a test as what it draws with the answer.
    private(set) var previewed: WatchedFolder?

    /// The engine speaking without being asked. A wire whose stream could
    /// never yield made every test of "the page heard" unwritable — the fake
    /// being simpler than the thing it stands for. The channel is a real
    /// `LocalTransport`, not a hand-rolled subscriber map: the mechanics under
    /// test — replay of the last event per name included — are the production
    /// ones.
    private let eventChannel = LocalTransport()

    var events: AsyncStream<EngineEvent> { eventChannel.events }

    /// Whether anybody is listening yet, so a test can announce *after* the
    /// subscription exists instead of racing it.
    var eventReaderCount: Int { eventChannel.subscriberCount }

    /// What the engine would announce.
    func announce<E: RawRepresentable>(_ event: E) where E.RawValue == String {
        eventChannel.emit(EngineEvent(name: event.rawValue, payload: Data()))
    }

    init(folders: [WatchedFolder] = [],
         status: AutopilotStatus = AutopilotStatus(refusal: nil),
         history: [ActionRecord] = [],
         preview: [PreviewRow] = [],
         report: SweepReport? = nil,
         answering answer: Answer = .reply) {
        self.folders = folders
        self.status = status
        self.history = history
        self.preview = preview
        self.report = report
        self.answer = answer
    }

    /// The engine changing its mind while the page is up — a rule set that was
    /// refused and has just been discarded, a folder that has just gone away. A
    /// port that can change under the app hands that state back rather than
    /// being fixed at init.
    func answers(_ next: AutopilotStatus) { lock.withLock { status = next } }
    func holds(_ next: [WatchedFolder]) { lock.withLock { folders = next } }
    func holds(_ next: [ActionRecord]) { lock.withLock { history = next } }
    func offers(_ next: [PreviewRow]) { lock.withLock { preview = next } }
    func answers(_ next: Answer) { lock.withLock { answer = next } }
    func answers(_ next: UndoReport) { lock.withLock { undoReport = next } }

    /// Which commands reached the wire, in order, so a test can assert that the
    /// act it is about really was attempted before asserting what was said about
    /// it.
    var commands: [AutopilotCommand] { lock.withLock { seen } }

    func send(_ command: EngineCommand) async throws -> Data {
        let reply: Reply = lock.withLock {
            let name = AutopilotCommand(rawValue: command.name)
            record(name, command.payload)
            return answering(name)
        }
        switch reply {
        case .refuse: throw CancellationError()
        case .empty: return Data()
        case .data(let data): return data
        }
    }

    /// What the page sent, kept so a test can ask what a gesture tried to do
    /// before asking what was said about it. Under the caller's lock.
    private func record(_ name: AutopilotCommand?, _ payload: Data) {
        guard let name else { return }
        seen.append(name)
        switch name {
        case .setFolders:
            if let list = try? JSONDecoder().decode([WatchedFolder].self, from: payload) {
                saved.append(list)
            }
        case .previewDraft:
            previewed = try? JSONDecoder().decode(WatchedFolder.self, from: payload)
        case .undo, .undoRun:
            if let ask = try? JSONDecoder().decode(UndoRequest.self, from: payload) {
                returns.append(ask.id)
            }
        case .folders, .status, .discardRefusedRules, .history, .clearHistory, .runNow:
            break
        }
    }

    private func answering(_ name: AutopilotCommand?) -> Reply {
        switch (answer, name) {
        case (.refuse, _): return .refuse
        case (.nothing, _), (_, .none), (_, .setFolders), (_, .clearHistory),
             (_, .discardRefusedRules):
            return .empty
        case (.reply, .folders): return .json(folders)
        case (.reply, .status): return .json(status)
        case (.reply, .history): return .json(history)
        case (.reply, .previewDraft): return .json(preview)
        case (.reply, .runNow): return report.map { .json($0) } ?? .empty
        case (.reply, .undo), (.reply, .undoRun): return .json(undoReport)
        }
    }

    /// Decided under the lock and delivered outside it: a `throw` cannot happen
    /// inside `withLock` without carrying the lock into the error path.
    private enum Reply {
        case refuse, empty
        case data(Data)

        static func json<T: Encodable>(_ value: T) -> Reply {
            .data((try? JSONEncoder().encode(value)) ?? Data())
        }
    }
}
