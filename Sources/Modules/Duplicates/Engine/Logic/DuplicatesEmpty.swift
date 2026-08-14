import Foundation

/// Why the result screen has no groups on it — or nothing, when it has some.
///
/// **The page asserted rather than reported.** «No duplicates here. Every large
/// file under this folder is one of a kind» is a claim about somebody's Mac, and
/// it was drawn identically whether the walk read the whole tree or was refused
/// every directory in it. The scanner knew better and told the log:
/// `unreadablePaths` from the enumerator's error handler, and one count per file
/// whose digest could not be taken. `find` answered a bare array, and there was
/// nowhere in that type to put either.
///
/// Here rather than in the view, and over counts rather than over the groups,
/// because it is the module's rule about what its screen means. Leftovers keeps
/// `LeftoversEmpty` for the same reason and it is the same repair.
public enum DuplicatesEmpty {

    /// Three, and two of them are holes.
    ///
    /// A **refusal** is a fault with something to do about it — the grant, the
    /// permissions on a folder, a disk that is failing. An application
    /// **library** stepped over is policy: what is inside a photo library is not
    /// a file anybody should be offered, and the walk declines on purpose. Both
    /// leave the answer partial, and only one of them is anybody's to fix, so
    /// they are not one case with one sentence.
    ///
    /// Exhaustive on purpose, like `LeftoversEmpty.Reason`: a `default` at a
    /// caller is how a fourth state would come to be drawn as the all-clear,
    /// which is the defect this type exists for.
    public enum Reason: Equatable, Sendable {
        /// The walk read what it was pointed at, and there was nothing.
        case nothingFound
        /// Some of it could not be read: a directory the walk was refused, or a
        /// file whose digest could not be taken. Both leave files out of the
        /// comparison, and a file left out cannot be reported as unique.
        case notEverythingRead(Int)
        /// Everything readable was read, and this many application libraries
        /// were passed by rather than opened.
        case librariesNotOpened(Int)
    }

    /// - Parameters:
    ///   - groups: how many the search answered with. Any at all and this screen
    ///     is a list, not a statement.
    ///   - unreadable: directories the walk was refused plus files whose digest
    ///     failed — the two ways a file this scan should have compared was not
    ///     compared.
    ///   - librariesSkipped: application libraries the walk declined to enter.
    ///     Undercounts by construction: a library macOS knows as a package is
    ///     stepped over by `.skipsPackageDescendants` before the walk is asked,
    ///     and nothing counts those. Under-reporting a hole is the safe
    ///     direction — every one it does report is real.
    public static func reason(groups: Int, unreadable: Int,
                              librariesSkipped: Int) -> Reason? {
        guard groups == 0 else { return nil }
        // The refusal first: it is the one with a next step, and a screen can
        // only say one thing.
        if unreadable > 0 { return .notEverythingRead(unreadable) }
        return librariesSkipped > 0 ? .librariesNotOpened(librariesSkipped) : .nothingFound
    }
}
