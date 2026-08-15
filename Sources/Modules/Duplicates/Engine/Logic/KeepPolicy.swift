import Foundation
import HelmRuntime

/// What the person believes an extra copy *is*.
///
/// The module used to hold one belief and never say so: the oldest copy is the
/// original. Measured on a live engine — a file downloaded into `~/Downloads`
/// and then filed into `~/Pictures` came back with the download as the copy
/// that stays, so Helm offered to delete the one somebody had deliberately put
/// away. The rule was not the tiebreak's fault: on APFS two copies never share
/// a date added (0,29 ms apart on parallel `cp`), so the rungs below the date
/// were never reached and «the original» meant «whoever got to a folder first».
///
/// Two beliefs, and no third «as it was»: an order nobody chose is not a policy,
/// it is the state this repair exists to end.
///
/// **The raw values are stored data.** They reach `com.helm.app.plist` and are
/// sealed there, so renaming one silently reverts somebody's setting to the
/// default — `KeepPolicyTests` records the two that shipped. Public because the
/// spelling crosses the transport in `DuplicateSearchRequest`, and a wire value
/// spelled a second time in the UI is a name only one side can change.
public enum KeepPolicy: String, CaseIterable, Sendable {

    /// Where the copy sits decides. Downloads, the Desktop and the drop box are
    /// where files land; everywhere else is where somebody put them. Within one
    /// tier the older copy stays.
    case byPlace = "place"

    /// When the copy arrived decides, wherever it sits — the belief the module
    /// held silently, now one of two and said out loud.
    case byDate = "date"

    /// What a Mac that has never been asked gets.
    ///
    /// Places before dates because the place is the fact a person can see and
    /// act on: a copy in Downloads is a copy they have not filed yet.
    public static let standard = KeepPolicy.byPlace

    /// The rungs this policy asks, strongest first.
    ///
    /// **One ladder, read by both the ordering and the reason it reports.**
    /// Which copy stays and why it stays are the same question asked twice, and
    /// a second spelling of the order is how a screen comes to explain one rule
    /// while the app follows another — this module has already paid for that
    /// once, when `SurvivingCopy` replaced the alphabetical rule in one of the
    /// two pipelines.
    var ladder: [KeepReason] {
        switch self {
        case .byPlace: return [.place, .date, .depth, .name]
        case .byDate: return [.date, .place, .depth, .name]
        }
    }
}

/// Why one copy is the one that stays: the rung that separated it from the next
/// best copy in its group.
///
/// It is a rung of the ladder and the answer a person reads, deliberately one
/// type: a reason enum of its own would be a second spelling of the same list,
/// free to drift from the order it claims to describe.
///
/// `.name` is a coin toss and has to be visible as one — two copies alike in
/// every way the rule can see are separated by the alphabet, which is a fact
/// about their spelling and about nothing else.
enum KeepReason: String, Sendable {
    /// The tier said so: one is filed, the other is in transit.
    case place
    /// One arrived earlier. Only ever true of two dates that are both known and
    /// different.
    case date
    /// One sits closer to the top of the tree, so somebody carried the other
    /// further in.
    case depth
    /// Nothing above could tell them apart, and the alphabet is what is left.
    case name
}

/// The folders a file passes through rather than lives in.
///
/// **Asked of macOS, never spelled.** `~/Downloads` is an English name for a
/// place this Mac may have moved: `FileManager.url(for:)` answers where it
/// really is, and `SystemFolderNames` is what turns it back into a word for the
/// person. `~/Public/Drop Box` has no search-path constant and is a real
/// on-disk name, so it is built from the home directory.
struct TransitFolders: Sendable {

    /// Lower-cased directory paths, each ending in a separator, so a prefix test
    /// cannot mistake `~/DownloadsArchive` for something inside `~/Downloads`.
    /// A set, because the only question asked of them is whether one of them
    /// begins a path.
    private let roots: Set<String>

    /// **Both spellings of every root, and that is the point.** A moved
    /// Downloads is a link to somewhere else with a link left behind:
    /// `FileManager` answers with the link, and the walk — which never follows
    /// one — answers with the real path. `ScanRoot.resolve` records what judging
    /// only one of the two cost.
    ///
    /// Resolved once here rather than per candidate: a file's own path comes out
    /// of the walk already real, and asking the filesystem again for each of a
    /// hundred thousand of them is a question that belongs to the group.
    init(roots: [String]) {
        self.roots = Set(roots.flatMap { raw -> [String] in
            let named = (raw as NSString).standardizingPath
            return [named, PathCanonical.resolvingWholePath(named)].map {
                // One trailing separator however the caller spelled it, and
                // folded — the boot volume is case-insensitive while a path
                // comparison is not, which is the same fold `ScanRoot` makes.
                PathCanonical.withoutTrailingSeparators($0).lowercased() + "/"
            }
        })
    }

    /// Where this Mac lands what arrives.
    ///
    /// **It does not ask `TestProcess.isRunning`, and that is the answer rather
    /// than the omission.** Every other site that resolves one of the person's
    /// own folders redirects under the suite, because it is about to *write*
    /// there — the log and the scan journal both land in `$TMPDIR` instead.
    /// Nothing here is a destination: `create: false`, no read of any content,
    /// and what comes back is compared against a path as a string. Substituting
    /// it under test would cost the one thing worth having, which is that
    /// `testTheSystemTierIsTheFoldersMacOSNames` asks this Mac where Downloads
    /// really is rather than asking a fixture what it was told.
    static let system = TransitFolders(roots: systemRoots())

    private static func systemRoots() -> [String] {
        let manager = FileManager.default
        var roots = [FileManager.SearchPathDirectory.downloadsDirectory, .desktopDirectory]
            .compactMap { try? manager.url(for: $0, in: .userDomainMask,
                                           appropriateFor: nil, create: false).path }
        // What somebody else dropped on this Mac over the network: arrived, and
        // never put anywhere by the person who owns the account.
        roots.append(manager.homeDirectoryForCurrentUser
            .appendingPathComponent("Public/Drop Box").path)
        return roots
    }

    /// Whether this file is sitting in one of them.
    func holds(_ path: String) -> Bool {
        let lowered = path.lowercased()
        return roots.contains { lowered.hasPrefix($0) }
    }
}

/// A policy and the folders it needs in order to answer.
///
/// One value because the two are never useful apart, and because the alternative
/// is threading a second parameter through every function of the pipeline — the
/// shape in which one call site keeps the old behaviour and nothing says so.
struct KeepRule: Sendable {
    let policy: KeepPolicy
    let transit: TransitFolders

    init(_ policy: KeepPolicy, transit: TransitFolders = .system) {
        self.policy = policy
        self.transit = transit
    }
}

/// What the ordering needs of a copy, whichever side of the transport it is on.
///
/// `FileFacts` is what the walk collects and `DuplicateGroup.Copy` is what the
/// screen holds — and the screen re-decides which copy stays whenever the policy
/// changes, without hashing anything again. Two types, one question, so the rule
/// is written once and both answer it.
protocol KeepCandidate {
    var path: String { get }
    /// The Finder's "Date Added". `nil` on a volume that does not record it, and
    /// that is a fact the ladder treats as silence rather than as a loss.
    var added: Date? { get }
}

extension FileFacts: KeepCandidate {}
extension DuplicateGroup.Copy: KeepCandidate {}
