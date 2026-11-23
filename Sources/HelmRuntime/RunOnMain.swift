import Foundation

/// Runs `work` now when already on the main thread, else queues it there.
func runOnMain(_ work: @escaping @Sendable () -> Void) {
    if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
}
