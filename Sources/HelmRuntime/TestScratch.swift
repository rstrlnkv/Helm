import Foundation

/// Where a store of somebody's own files goes instead, while XCTest is loaded.
///
/// `TestProcess` answers whether to ask for one of these at all and says why the
/// question is the one it is; this answers what it looks like. Several stores
/// need it (the scan journal, Disk's last-scan cache, the support directory,
/// Screenshots' home), and the naming, the sweep and the liveness question are
/// the same each time.
///
/// **A redirection with no end to it is half an improvement.** One directory
/// per process, kept for ever, piles up in `$TMPDIR`, so handing out this
/// process's directory is also when those of processes that have gone are
/// taken back.
public struct TestScratch: Sendable {

    /// What every directory of this family is called, before the process number.
    /// One value, read by the maker and by the sweeper, so the two cannot
    /// disagree about what one of these looks like.
    private let prefix: String

    public init(prefix: String) { self.prefix = prefix }

    /// This process's directory under `base`, after taking back what dead
    /// processes left there.
    ///
    /// **Per process rather than one directory reused by every run.** The log
    /// takes the other shape: it appends to one file its own rollover bounds. A
    /// store holds a slot, and two suites can run side by side; a slot one
    /// process reads and another writes is the nondeterminism this ends.
    ///
    /// The directory is named, not created: whoever writes into it makes it, with
    /// the mode that file deserves (`PrivateFile`). A run that only reads leaves
    /// nothing at all behind.
    public func directory(in base: URL = URL(fileURLWithPath: NSTemporaryDirectory(),
                                            isDirectory: true)) -> URL {
        directory(in: base, isAlive: Self.processExists)
    }

    /// The same, with the liveness question in the caller's hands: a sweep that
    /// can only be watched against the real kernel is a sweep no test can watch
    /// deciding either way.
    func directory(in base: URL, isAlive: (Int32) -> Bool) -> URL {
        sweepAbandoned(under: base, isAlive: isAlive)
        return base.appendingPathComponent("\(prefix)\(ProcessInfo.processInfo.processIdentifier)",
                                           isDirectory: true)
    }

    /// Which of these names belong to test processes that have exited.
    ///
    /// Pure, and separated from the removal, because the decision is the part
    /// worth testing: the removal is one `FileManager` call and the judgement is
    /// what must never say yes about a living process. A name that is not one of
    /// this family's, or whose tail is not a number, is not this function's
    /// business.
    ///
    /// **The sanity check on the number lives here, not in the caller**, so the
    /// decision is never looser than the code in front of it. `0` and negatives
    /// are process *groups* to `kill`, not processes.
    func abandoned(_ names: [String], isAlive: (Int32) -> Bool) -> [String] {
        names.filter { name in
            guard name.hasPrefix(prefix),
                  let pid = Int32(name.dropFirst(prefix.count)),
                  pid > 0
            else { return false }
            return !isAlive(pid)
        }
    }

    /// Takes back what earlier test processes left here.
    ///
    /// **Liveness is asked of the kernel, not of the clock.** `kill(pid, 0)`
    /// sends no signal; it only answers whether that process is there. `EPERM`
    /// means it is there and belongs to somebody else, which is still there —
    /// treating it as gone would delete the store of a suite running beside this
    /// one, which on a build machine is the ordinary case.
    private func sweepAbandoned(under base: URL, isAlive: (Int32) -> Bool) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: base.path) else { return }
        for name in abandoned(names, isAlive: isAlive) {
            try? fm.removeItem(at: base.appendingPathComponent(name))
        }
    }

    static func processExists(_ pid: Int32) -> Bool {
        guard pid > 0 else { return true }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}
