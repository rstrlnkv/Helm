import Foundation
import HelmRuntime

/// Where the ledger lives between launches.
///
/// A serial queue and one small file. The ledger is written after a word is
/// put right — which happens on the tap's own thread — so the write goes off
/// it, and the reads that answer the page go through the same queue so a page
/// opened mid-write sees one state or the other and never half of both.
///
/// **`PrivateFile`, not `write(options: .atomic)`.** The mode belongs to the
/// write rather than to the file: `.atomic` renames a new inode into place, so
/// a fresh write takes the umask and a rewrite takes the replaced file's mode.
/// This file holds no words, but it does say how much somebody types and when —
/// which is nobody else's business on a shared Mac.
public final class LedgerStore: @unchecked Sendable {

    private let url: URL
    private let queue = DispatchQueue(label: "helm.layout.ledger")
    private var cached: ConversionLedger

    /// The directory is passed rather than found, so a test writes into its own
    /// scratch and never into the owner's Application Support — the module has
    /// form here: eleven engine tests once took a real keychain by default.
    /// A directory named is a directory written to. Nothing named, outside the
    /// app, means nothing on disk at all — see `persists`.
    public init(directory: URL? = nil) {
        let home = directory
            ?? HelmSupport.directory.appendingPathComponent("Layout", isDirectory: true)
        url = home.appendingPathComponent("conversions.json")
        persists = directory != nil || AppBuild.isBundledApp
        cached = persists ? (Self.read(url) ?? ConversionLedger()) : ConversionLedger()
    }

    /// **Whether this ledger touches the disk at all.**
    ///
    /// The app persists; anything else counts in memory and leaves nothing
    /// behind. Writing to a scratch folder instead was the obvious answer and
    /// the wrong one twice over: keyed to the process, the whole suite shared
    /// one file and a test asserting «one word counted» read five; keyed per
    /// instance, one run left 91 directories in `$TMPDIR` — which is how this
    /// repository once accumulated 7621 of them.
    ///
    /// A test that wants the disk names its own directory and clears it up,
    /// which is the only arrangement where «the count survived a relaunch» is
    /// something a test can actually claim.
    private let persists: Bool

    /// What the page draws, as of now.
    func totals(now: Date, calendar: Calendar = .current) -> ConversionTotals {
        queue.sync { cached.totals(now: now, calendar: calendar) }
    }

    /// One word put right. Returns nothing: the caller is a key tap, and there
    /// is nothing it could usefully do about a failed write mid-keystroke.
    func record(words: Int = 1, characters: Int, on now: Date, calendar: Calendar = .current) {
        queue.async { [self] in
            cached.add(words: words, characters: characters, on: now, calendar: calendar)
            guard persists else { return }
            guard !PrivateFile.writeMakingTheFolder(cached, at: url) else { return }
            // Said once per launch rather than per word: a disk that refuses
            // this file will refuse it every time somebody types, and a log
            // full of it would bury whatever else went wrong. No count and no
            // date — the line is «the figure on the page is not being kept».
            guard !warned else { return }
            warned = true
            HelmLog.shared.warn(LayoutEngine.moduleID,
                                "the conversion ledger could not be written — the figures on "
                                + "the page will not outlive this launch")
        }
    }

    private var warned = false

    private static func read(_ url: URL) -> ConversionLedger? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        // A ledger that will not decode is a ledger that starts again, and that
        // is the right failure: the alternative is refusing to count anything
        // for the rest of the installation because one file went bad.
        return try? JSONDecoder().decode(ConversionLedger.self, from: data)
    }
}
