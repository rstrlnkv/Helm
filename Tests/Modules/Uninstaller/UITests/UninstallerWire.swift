import Foundation
import HelmContract
import HelmRuntime
import Module_Uninstaller_Engine

/// An engine on the other end of the transport that can be told what to answer —
/// including **not to**.
///
/// The UI tests here drive a real `UninstallerEngine` over a real
/// `LocalTransport`, which is the right shape for what an engine really does and
/// cannot produce the state this file exists for: a request that comes back with
/// nothing. `UninstallerEngine.wireTransport` answers empty `Data` when the
/// engine has gone under a page that is still up and again for a command name it
/// cannot parse; `EngineTransport.send` is declared to throw;
/// `UninstallerViewModel.shared(vm:)`'s own comment says a cached model
/// outliving its engine «answers every request with empty Data for as long as the
/// app runs». `TransportClient.request` folds all of that to one nil, and the
/// view model reads that nil as an answer.
final class UninstallerWire: EngineTransport, @unchecked Sendable {

    /// What the engine behind this wire does with a request.
    enum Answer: Equatable {
        /// The fixture's reply: an engine that is there and answers.
        case reply
        /// `send` throws, which `TransportClient.request` turns into the same nil
        /// as a reply that will not decode.
        case refuse
        /// Empty `Data` — an engine that is gone, or a command it does not know.
        case nothing

        /// The two the caller cannot tell apart: `TransportClient.request` folds
        /// both to one nil. A test about "nobody answered" runs over this rather
        /// than picking one, and it lives here because it is a fact about the
        /// wire — two test files had written the pair out.
        static let silences: [Answer] = [.refuse, .nothing]
    }

    private let lock = NSLock()
    private var apps: [InstalledApp]
    private var scans: [String: ScanResult]
    private var removal: UninstallResult
    private var offers: [TrashedAppLeftovers]
    /// What the engine says the Trash-offer switch is *doing*, which is not the
    /// same as what it says: a `Bool` here is how the switch came to be the only
    /// thing the page could know (`TrashWatch`).
    private var watch: TrashWatch
    private var answer: Answer
    /// A reply that will not decode is a fact about one command, not about the
    /// engine: the removal can be lost while the scan behind it still answers.
    private var perCommand: [UninstallerCommand: Answer] = [:]
    private var seen: [UninstallerCommand] = []
    private var sentPayloads: [(UninstallerCommand, Data)] = []

    var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }

    init(apps: [InstalledApp] = [],
         scans: [String: ScanResult] = [:],
         removal: UninstallResult = UninstallResult(trashed: [], freedBytes: 0),
         offers: [TrashedAppLeftovers] = [],
         watching watch: TrashWatch = .off,
         answering answer: Answer = .reply) {
        self.apps = apps
        self.scans = scans
        self.removal = removal
        self.offers = offers
        self.watch = watch
        self.answer = answer
    }

    /// The engine going away under the page, or coming back. A port that can
    /// change while the app is running hands that state back rather than being
    /// fixed at init (CLAUDE.md § Anything that can stop being true on its own).
    func answers(_ next: Answer) { lock.withLock { answer = next } }

    /// The same, for one command only.
    func answers(_ next: Answer, to command: UninstallerCommand) {
        lock.withLock { perCommand[command] = next }
    }

    /// The state the engine reports for the switch. Its own setter, because the
    /// grant it depends on is taken away and given back while the app runs.
    func setWatch(_ next: TrashWatch) { lock.withLock { watch = next } }

    /// What the next removal comes back with.
    func setRemoval(_ next: UninstallResult) { lock.withLock { removal = next } }

    /// What the next scan finds — the Trash is a place files move to, so a scan
    /// after a removal is not a scan before it.
    func setScans(_ next: [String: ScanResult]) { lock.withLock { scans = next } }

    /// Which commands reached the wire, in order — so a test can assert that the
    /// act it is about really was attempted before asserting what was said about
    /// it. An assertion about an absence passes when the subject never happened.
    var commands: [UninstallerCommand] { lock.withLock { seen } }

    /// What a command was sent with, for the tests that are about the request
    /// rather than the reply.
    func payload(of command: UninstallerCommand) -> Data? {
        lock.withLock { sentPayloads.last { $0.0 == command }?.1 }
    }

    /// Every payload a command was sent with, in order.
    ///
    /// The last one is the wrong question for a command sent once per app:
    /// `dismissTrashedApp` writes the record that is final for as long as an app
    /// sits in the Trash, and *which* apps it named is the whole of what a test
    /// of that record can ask. Reading only the last would pass over a decline
    /// written for an app whose files are still there.
    func payloads(of command: UninstallerCommand) -> [Data] {
        lock.withLock { sentPayloads.filter { $0.0 == command }.map(\.1) }
    }

    /// The enum, not a literal: a fake that answers names of its own goes on
    /// answering after the module renames one, and what it answers then is
    /// `Data()` — which this codebase spells «the module could not answer».
    func send(_ command: EngineCommand) async throws -> Data {
        let name = UninstallerCommand(rawValue: command.name)
        // One turn of the lock for the whole answer: the record of the request
        // and the state it is answered from have to be the same moment.
        let reply: Reply = lock.withLock {
            if let name {
                seen.append(name)
                sentPayloads.append((name, command.payload))
            }
            switch name.flatMap({ perCommand[$0] }) ?? answer {
            case .refuse: return .refuse
            case .nothing: return .empty
            case .reply: return name.map { fixture(for: $0, payload: command.payload) } ?? .empty
            }
        }
        switch reply {
        case .refuse: throw CancellationError()
        case .empty: return Data()
        case .data(let data): return data
        }
    }

    /// What an engine that is there and answering says. Called under the lock.
    private func fixture(for command: UninstallerCommand, payload: Data) -> Reply {
        switch command {
        case .listApps: return .json(apps)
        case .appSizes:
            return .json(Dictionary(uniqueKeysWithValues: apps.map { ($0.path, $0.sizeBytes) }))
        case .scan:
            let request = try? JSONDecoder().decode(UninstallScanRequest.self, from: payload)
            let found = request.flatMap { scans[$0.bundleID] }
            return .json(found ?? ScanResult(bundleID: request?.bundleID ?? "",
                                             appPath: request?.appPath ?? "",
                                             appSizeBytes: 0, leftovers: [],
                                             runningNow: false))
        case .trashPaths: return .json(removal)
        case .trashedAppLeftovers: return .json(offers)
        case .watchingTrash: return .json(watch)
        case .scanOrphans: return .json([OrphanGroup]())
        // No reply at all is what the engine itself answers to these.
        case .backgroundScan, .quit, .setWatchingTrash, .dismissTrashedApp: return .empty
        }
    }

    /// Decided under the lock and delivered outside it — a `throw` cannot happen
    /// inside `withLock` without carrying the lock into the error path.
    private enum Reply {
        case refuse, empty
        case data(Data)

        static func json<T: Encodable>(_ value: T) -> Reply {
            .data((try? JSONEncoder().encode(value)) ?? Data())
        }
    }
}
