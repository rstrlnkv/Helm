import Foundation

/// Every scan in flight, each under a token only its owner holds.
///
/// One slot was not enough. Drilling into a folder the scan never reached
/// issues a second "scan" command while the first is still walking, so a single
/// last-writer-wins box ended up holding the folder measurement — and when that
/// finished it cleared the box, taking the volume walk's only handle with it.
/// From then on Stop, New scan and switching the module off all reached
/// nothing, while the walk carried on holding the engine through its progress
/// closure.
///
/// A token is spent once and clears the slot it was given, never somebody
/// else's; cancelling asks for everything in flight rather than for whatever
/// was stored last.
final class ScanRegistry<Scan: AnyObject>: @unchecked Sendable {
    /// A serial queue rather than a lock: the callers are async, and an NSLock
    /// cannot be taken across a suspension point.
    private let queue = DispatchQueue(label: "helm.disk.scans")
    private var scans: [Int: Scan] = [:]
    private var lastToken = 0

    func add(_ scan: Scan) -> Int {
        queue.sync {
            lastToken += 1
            scans[lastToken] = scan
            return lastToken
        }
    }

    func remove(_ token: Int) {
        queue.sync { scans[token] = nil }
    }

    var inFlight: [Scan] {
        queue.sync { Array(scans.values) }
    }
}
