import Foundation
import HelmRuntime

/// What the counts file said, as `LayoutRead` says it of the layout.
typealias CountsRead = LaunchpadFileRead<LaunchCounts>

extension LaunchpadFileRead where Value == LaunchCounts {
    /// What the order may use: nothing when the file is absent or would not read.
    var counts: [AppID: Int] {
        if case .loaded(let loaded) = self { loaded.counts } else { [:] }
    }
}

/// **The counts file beside the layout, private (0600 in a 0700 folder)**, written by `record` and `reset` only; a read never writes.
///
/// An unreadable file reads as no counts (one warning per distinct bad file, no ids), and the first `record` or `reset` moves it
/// aside once to its `.unreadable` name before writing fresh; if the move fails nothing is written. One lock covers read, bump and
/// save together, so two launches in flight do not lose one. It is its own lock, taken after the engine's and never before it.
final class LaunchCountStore: @unchecked Sendable {
    private let file: LaunchpadFile
    private let lock = NSLock()

    init(directory: URL) { file = LaunchpadFile(directory: directory, name: "launch-counts.json") }

    var fileURL: URL { file.url }

    func load() -> CountsRead { lock.withLock { read() } }

    /// One more launch of `id`. False when it was not kept (logged here).
    func record(_ id: AppID) -> Bool {
        change { $0.record(id) }
    }

    /// The counts emptied. Nothing is written when there is no file.
    func reset() -> Bool {
        lock.withLock {
            if case .absent = read() { return true }
            // A bad file is moved aside by the write; the aside holds bundle ids and counts, and a reset is the person's word that they go.
            guard write(.empty) else { return false }
            file.removeAside()
            return true
        }
    }

    private func change(_ edit: (inout LaunchCounts) -> Void) -> Bool {
        lock.withLock {
            var counts = LaunchCounts.empty
            if case .loaded(let loaded) = read() { counts = loaded }
            edit(&counts)
            return write(counts)
        }
    }

    /// Under `lock`.
    private func read() -> CountsRead {
        file.read(warning: "the launch counts could not be read — the order falls back to alphabetical until the next launch",
                  decode: LaunchCounts.decode)
    }

    /// Under `lock`: a bad file is moved aside first; the write is not made when that fails.
    private func write(_ counts: LaunchCounts) -> Bool {
        if case .unreadable = read(),
           !file.moveAside(warning: "the unreadable launch counts could not be moved aside — they are kept and nothing is written") { return false }
        return file.save(warning: "the launch counts could not be saved") {
            return PrivateFile.writeMakingTheFolder(counts.encoded(), at: $0)
        }
    }
}
