import Foundation

/// How many `brew desc` runs one batch of descriptions may spend (one batch is
/// as many names as one argv carries; `descriptions` makes a budget for each),
/// and the count of what is left of it.
///
/// `HomebrewEngine.describe` halves a batch on a non-zero exit, right for *one*
/// name brew can no longer resolve. When brew refuses **every** call (a tap
/// that is gone, a Ruby error) the bisection runs to a leaf per name, `2n-1`
/// launches, each taking one of the app's `HelmProcess` slots. This bounds it.
final class DescriptionBudget: @unchecked Sendable {

    /// **Two floors, and the larger wins, because each is a floor for a
    /// different reason.**
    ///
    /// `n + 1` — one optimistic batch, then at most one call per name — is the
    /// most a wholesale refusal can justify: past it the split has stopped
    /// beating the naive strategy it replaced.
    ///
    /// `2⌈log₂n⌉ + 1` is what isolating a single unresolvable name costs: two
    /// calls a level, the half that answers and the half that does not. For a
    /// small batch that is *more* than `n + 1` (three names with one bad is
    /// five calls), so `n + 1` alone would cut the descent off half-way, in
    /// the very case the split exists for.
    private static func calls(for names: Int) -> Int {
        max(names + 1, 2 * levels(names) + 1)
    }

    /// ⌈log₂n⌉ — how deep the halving goes before a batch is one name.
    private static func levels(_ names: Int) -> Int {
        guard names > 1 else { return 0 }
        return Int.bitWidth - (names - 1).leadingZeroBitCount
    }

    private let lock = NSLock()
    private var remaining: Int
    private var refused = false

    /// What a batch of this many names was allowed, kept so the caller can say
    /// it in the log without deriving the same number a second time.
    let allowance: Int

    init(forBatchOf names: Int) {
        allowance = Self.calls(for: names)
        remaining = allowance
    }

    /// Whether the split gave up with names still unasked — the caller says so
    /// in the log, once, rather than every node of the recursion saying it.
    /// A spend that was refused is the signal: spending the last call of the
    /// allowance on the last name asked everything.
    var exhausted: Bool { lock.lock(); defer { lock.unlock() }; return refused }

    private var sawTimeout = false

    /// Whether a call of this batch hit the deadline — a fact about brew, not
    /// about a name, so the caller stops asking further batches.
    var timedOut: Bool { lock.lock(); defer { lock.unlock() }; return sawTimeout }

    func noteTimeout() { lock.lock(); sawTimeout = true; lock.unlock() }

    /// Whether one more `brew desc` may be spent.
    func spend() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard remaining > 0 else { refused = true; return false }
        remaining -= 1
        return true
    }
}
