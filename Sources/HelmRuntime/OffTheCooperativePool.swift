import Foundation

/// Run blocking work somewhere it cannot starve the cooperative pool.
///
/// Every scanning module wrote this bridge itself — five identical copies of
/// the same eight lines. What they are all avoiding is the same hazard: Swift
/// concurrency's pool has one thread per core, and a directory walk or a
/// `brew` invocation holds one of them for seconds. Enough of those at once and
/// nothing else in the app gets to run, including the UI's own actor hops.
///
/// A module with its own serial queue should use that instead, so the work is
/// also serialised — Autopilot does. This is for the ones that only need to be
/// off the pool.
public func offTheCooperativePool<T: Sendable>(
    qos: DispatchQoS.QoSClass = .userInitiated,
    _ work: @escaping @Sendable () -> T
) async -> T {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: qos).async { continuation.resume(returning: work()) }
    }
}
