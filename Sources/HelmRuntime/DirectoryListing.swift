import Foundation

/// What a directory holds, as paths.
///
/// Shared by the two engines that hunt for what an application left behind
/// (`FileSystemLeftovers.children`, `FMFileSystem.children`). Beside
/// `FileWeight`, because the two are used together: list a `~/Library` folder,
/// then weigh what came back.
public enum DirectoryListing {

    /// What one reading of a directory found — or that there was no reading.
    ///
    /// **Two answers for three facts.** `children(of:)` folds «nothing is in it»,
    /// «nothing is there» and «this process may not read it» into one empty array,
    /// and only the first two lead to the same finding. The third reports a
    /// permission as a fact about somebody's Mac: a folder said to hold nothing
    /// that was never opened. `exists(atPath:)` makes the same split for a file.
    ///
    /// «Not there» stays folded into `.listed([])` on purpose: both scanners ask
    /// about folders that need not exist (no `Group Containers` on a Mac that has
    /// never run a sandboxed app), and telling an absent folder from an empty one
    /// is `exists`'s question.
    public enum Contents: Equatable, Sendable {
        /// The directory opened, and these are its entries — hidden ones included,
        /// and empty for a directory that holds nothing or is not there at all.
        case listed([URL])
        /// The directory would not open: a mode, an ACL, a folder belonging to
        /// somebody else, or a TCC grant this process does not have. Nothing is
        /// known about what is inside, and «empty» is the one answer that must not
        /// be given for it.
        case refused

        /// What was in it, and nothing for a reading that did not happen. For a
        /// caller that only walks what it finds; a caller that draws a conclusion
        /// from emptiness has to read the case.
        public var entries: [URL] {
            switch self {
            case .listed(let entries): entries
            case .refused: []
            }
        }
    }

    /// The directory's entries, and whether they were readable at all.
    ///
    /// `opendir` decides, because the errno is the answer and `contentsOfDirectory`
    /// throws the same kind of error for every reason — the same reading
    /// `exists(atPath:)` takes for a file. `ENOENT` and `ENOTDIR` are
    /// «there is nothing there», `ENAMETOOLONG` a path no directory can have;
    /// everything else, `EACCES` above all, is «this process may not look».
    public static func contents(of url: URL) -> Contents {
        guard let handle = opendir(url.path) else {
            return isAbsence(errno) ? .listed([]) : .refused
        }
        closedir(handle)
        return .listed(children(of: url))
    }

    /// `stat`, not `FileManager.fileExists`, because the errno is the answer.
    ///
    /// `ENOENT` and `ENOTDIR` are «there is nothing there»; `ENAMETOOLONG` is a
    /// path no file can have. Everything else — `EACCES` above all, and the one
    /// this Mac gives for a file under a mode-000 parent — is «this process may
    /// not look», which is not a fact about the file, and comes back as `nil`.
    public static func exists(atPath path: String) -> Bool? {
        var info = stat()
        guard stat(path, &info) != 0 else { return true }
        return isAbsence(errno) ? false : nil
    }

    private static func isAbsence(_ code: Int32) -> Bool {
        code == ENOENT || code == ENOTDIR || code == ENAMETOOLONG
    }

    /// The directory's entries as full URLs, hidden ones included.
    ///
    /// Empty for a missing directory, and also for one that would not *open*:
    /// a caller that concludes anything from an empty answer asks
    /// `contents(of:)` instead.
    public static func children(of url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(atPath: url.path))?
            .map { url.appendingPathComponent($0) } ?? []
    }
}
