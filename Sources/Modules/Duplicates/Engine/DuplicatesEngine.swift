import Foundation
import HelmContract
import HelmRuntime

/// The duplicate finder, as a module of its own.
///
/// It began inside Disk, sharing that module's scan and its basket, because
/// the folder it searched was whatever the ring was showing. That coupling was
/// the feature's whole shape: you could not look for duplicates anywhere you
/// had not first drawn a ring. Standing on its own, it takes a folder
/// directly — which is what someone looking for duplicates actually wants —
/// and Disk goes back to answering one question.
public final class DuplicatesEngine: ModuleEngine, @unchecked Sendable {
    private let localTransport: LocalTransport
    public let transport: EngineTransport
    private let finderBox = FinderBox()

    public init(transport: LocalTransport = LocalTransport()) {
        self.localTransport = transport
        self.transport = transport
        wireTransport()
    }

    public func activate() {}
    public func deactivate() { finderBox.current?.cancel() }

    /// Synchronous work on the module's own queue; nil when cancelled, because
    /// a partial answer to "what is duplicated" is a wrong answer rather than
    /// a smaller right one.
    public func find(under path: String) async -> [DuplicateGroup]? {
        // A new search supersedes any still running.
        finderBox.current?.cancel()
        let finder = DuplicateScanner()
        let slot = finderBox.start(finder)
        defer { slot.finish() }
        let groups: [DuplicateGroup]? = await offTheCooperativePool {
            finder.find(under: path, onProgress: { progress in
                if let data = try? JSONEncoder().encode(progress) {
                    self.localTransport.emit(EngineEvent(name: "progress", payload: data))
                }
            })
        }
        return groups
    }

    /// The engine has the last word on deletion, as everywhere else in Helm:
    /// the view model builds the list, and this decides what may go.
    /// Refusals come back in `failed`, never dropped.
    public func trash(_ paths: [String]) async -> DuplicateRemoval {
        await offTheCooperativePool {
            let unique = Array(Set(paths))
            let (allowed, refused) = UserFileScope.partition(unique)
            return HelmTrash.remove(allowed: allowed, outOfScope: refused, module: "duplicates")
        }
    }


    // MARK: - Transport

    private struct PathPayload: Codable { let path: String }

    private func wireTransport() {
        localTransport.setHandler { [weak self] command in
            guard let self else { return Data() }
            switch command.name {
            case "find":
                guard let payload = try? JSONDecoder().decode(PathPayload.self,
                                                              from: command.payload)
                else { return Data() }
                return (try? JSONEncoder().encode(await self.find(under: payload.path))) ?? Data()
            case "cancel":
                self.finderBox.current?.cancel()
                return Data()
            case "trash":
                guard let paths = try? JSONDecoder().decode([String].self, from: command.payload)
                else { return Data() }
                return (try? JSONEncoder().encode(await self.trash(paths))) ?? Data()
            default:
                return Data()
            }
        }
    }
}

/// What the trash command answers with — the same value `DiskRemoval` names,
/// and for the same reason. Its doc comment used to point at `DiskRemoval` for
/// the explanation of a field, which is a type citing its own duplicate.
public typealias DuplicateRemoval = HelmTrash.Result

/// Serial box around the in-flight search, so cancel can reach it.
///
/// A search leaving clears the slot it was given and no other. It used to clear
/// the box outright: a superseded search returning — cancelled, and after its
/// replacement had already started — emptied the box behind the search that had
/// taken its place, and from then on Stop reached nothing and `deactivate()`
/// left the hashing running.
final class FinderBox: @unchecked Sendable {
    /// A serial queue rather than a lock: the callers are async, and an NSLock
    /// cannot be taken across a suspension point.
    private let queue = DispatchQueue(label: "helm.duplicates.finder")
    private var finder: DuplicateScanner?
    private var token = 0

    /// The right to clear one slot, spent once.
    struct Slot {
        fileprivate let token: Int
        fileprivate let box: FinderBox
        func finish() { box.finish(token) }
    }

    var current: DuplicateScanner? { queue.sync { finder } }

    func start(_ value: DuplicateScanner) -> Slot {
        let mine = queue.sync { () -> Int in
            token += 1
            finder = value
            return token
        }
        return Slot(token: mine, box: self)
    }

    private func finish(_ owner: Int) {
        queue.sync { if owner == token { finder = nil } }
    }
}
