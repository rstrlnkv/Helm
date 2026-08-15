import Foundation
import HelmRuntime
@testable import Module_Autopilot_Engine

/// The disk, as a return sees it.
///
/// **Every state the real one can be in when somebody presses "Put back".**
/// The file gone, a different file standing in its place, the folder it came
/// from deleted, the Trash emptied, the name at the origin taken again, an
/// ancestor swapped between the check and the move, the move refused outright,
/// and the mark failing to stick on a volume that will not keep one. A fake
/// that could not be in one of those is a state no test of it could describe,
/// and deciding between them is the undo's whole job.
///
/// Where a path leads is answered from its **parent**, like the real reading:
/// keyed by the full path it would say a folder changed the moment a collision
/// made the return pick a different name in the same folder, which is a refusal
/// the filesystem never produces.
final class FakeUndoFiles: UndoFiles, @unchecked Sendable {
    private let lock = NSLock()

    /// Who is at each path. Absent means nothing is there — the Trash emptied,
    /// the file taken out by hand, or a name that was never used.
    private var who: [String: PathCanonical.FileIdentity] = [:]
    /// The directories that exist, and what each one's identity is.
    private var directories: [String: PathCanonical.AncestryIdentity] = [:]
    private var nextDirectory: UInt64 = 900
    private var tagged: [String: [String]] = [:]
    /// Answer truthfully `after` times, then answer with somewhere else — the
    /// ancestor swapped between the gate and the act, forced rather than raced.
    private struct Swap {
        let path: String
        let after: Int
        let to: PathCanonical.AncestryIdentity?
    }
    private var swap: Swap?
    private var ancestryReads: [String: Int] = [:]
    private var movesMade: [(from: String, to: String)] = []
    private var stampsWritten: [(path: String, rule: String)] = []

    /// What the move does instead of working, when a test wants it to fail.
    var moveFails: (any Error)?
    /// Whether a mark sticks. False is a volume that will not keep an extended
    /// attribute — which the module tolerates everywhere else, and which a
    /// return has to *report*, because an unmarked file is one the rule takes
    /// again within the hour.
    var stampSticks = true

    // MARK: - Planting

    func put(_ path: String, device: UInt64 = 1, inode: UInt64) {
        lock.withLock { who[path] = PathCanonical.FileIdentity(device: device, inode: inode) }
    }

    func remove(_ path: String) { lock.withLock { who[path] = nil } }

    func makeDirectory(_ path: String) {
        lock.withLock {
            nextDirectory += 1
            directories[path] = PathCanonical.AncestryIdentity(device: 1, inode: nextDirectory)
        }
    }

    /// The swap: `path` answers truthfully `after` times and then answers with
    /// somewhere else, which is a directory replaced by a link in the window
    /// between the check and the move.
    func swapAncestry(of path: String, after: Int, to inode: UInt64?) {
        lock.withLock {
            swap = Swap(path: path, after: after,
                        to: inode.map { PathCanonical.AncestryIdentity(device: 1, inode: $0) })
        }
    }

    func tag(_ path: String, _ tags: [String]) { lock.withLock { tagged[path] = tags } }

    // MARK: - Reading back

    var moves: [(from: String, to: String)] { lock.withLock { movesMade } }
    var stamps: [(path: String, rule: String)] { lock.withLock { stampsWritten } }
    func tags(at path: String) -> [String] { lock.withLock { tagged[path] ?? [] } }

    // MARK: - The port

    func identity(of path: String) -> PathCanonical.FileIdentity? { lock.withLock { who[path] } }

    func ancestry(of path: String) -> PathCanonical.AncestryIdentity? {
        lock.lock()
        defer { lock.unlock() }
        let seen = ancestryReads[path, default: 0]
        ancestryReads[path] = seen + 1
        if let swap, swap.path == path, seen >= swap.after { return swap.to }
        return directories[(path as NSString).deletingLastPathComponent]
    }

    func directoryExists(_ path: String) -> Bool { lock.withLock { directories[path] != nil } }

    func move(_ from: String, to: String) throws {
        if let moveFails { throw moveFails }
        lock.withLock {
            movesMade.append((from, to))
            who[to] = who[from]
            who[from] = nil
            tagged[to] = tagged[from]
            tagged[from] = nil
        }
    }

    func tags(of path: String) throws -> [String] { lock.withLock { tagged[path] ?? [] } }

    func setTags(_ tags: [String], on path: String) throws {
        lock.withLock { tagged[path] = tags }
    }

    func stamp(_ path: String, rule: String, key: Data) -> Bool {
        lock.withLock {
            stampsWritten.append((path, rule))
            return stampSticks
        }
    }
}
