import Foundation

/// How many `brew desc` runs one batch of descriptions may spend, and the count
/// of what is left of it.
///
/// `HomebrewEngine.describe` asks for a whole batch and, on a non-zero exit,
/// halves it and asks again — right for the case it was written for, which is
/// *one* name in fifty that brew can no longer resolve. Nothing bounded the
/// other end: when brew refuses **every** call the bisection runs to a leaf per
/// name and pays for every interior node on the way, `2n-1` launches, each a
/// real subprocess taking one of the app's eight `HelmProcess` slots. A Cellar
/// of 54 packages turned one page load into 107 `brew` runs the moment brew
/// answered non-zero for a reason that was not about any one name — a tap that
/// is gone, a Ruby error, a CLT that no longer matches, all of which refuse the
/// whole batch with the same status as one bad name in it.
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
    /// small batch that is *more* than `n + 1` — three names with one bad is
    /// five calls — so a budget of `n + 1` alone would cut the descent off
    /// half-way and drop descriptions brew was perfectly willing to give. That
    /// is the case the split exists for; it has to fit at every size.
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

    /// What a batch of this many names was allowed, kept so the caller can say
    /// it in the log without deriving the same number a second time.
    let allowance: Int

    init(forBatchOf names: Int) {
        allowance = Self.calls(for: names)
        remaining = allowance
    }

    /// Whether the split gave up with names still unasked — the caller says so
    /// in the log, once, rather than every node of the recursion saying it.
    var exhausted: Bool { lock.lock(); defer { lock.unlock() }; return remaining <= 0 }

    /// Whether one more `brew desc` may be spent.
    func spend() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard remaining > 0 else { return false }
        remaining -= 1
        return true
    }
}
