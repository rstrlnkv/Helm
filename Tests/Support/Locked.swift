import Foundation

/// One value behind one lock, for a `@Sendable` closure that has to hand it to
/// the test: a callback's last report, a flag, a count.
///
/// A plain captured `var` is not legal from a `@Sendable` block, and `Mutex`
/// is noncopyable, so it cannot be captured by an escaping one. Hand-written
/// in dozens of test files before it moved here (`ProgressBox` was its first
/// shared form, for a progress callback's last count). A change that reads then
/// writes goes through `withLock`, never `value += 1`: a get and a set are two
/// lock takings, not one.
public final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    public init(_ initial: Value) { stored = initial }

    public var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    public func withLock<R>(_ body: (inout Value) -> R) -> R { lock.withLock { body(&stored) } }
}

/// A counter a `@Sendable` block may add to; `next()` answers the new count.
public typealias LockedCount = Locked<Int>

public extension Locked where Value == Int {
    convenience init() { self.init(0) }

    func bump() { withLock { $0 += 1 } }

    func next() -> Int { withLock { $0 += 1; return $0 } }
}
