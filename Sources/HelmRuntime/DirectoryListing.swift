import Foundation

/// What a directory holds, as paths.
///
/// Written twice, byte for byte, in the two engines that hunt for what an
/// application left behind — `FileSystemLeftovers.children` and
/// `FMFileSystem.children`. It sits beside `FileWeight` because the two are
/// always used together: list a `~/Library` folder, then weigh what came back.
public enum DirectoryListing {

    /// What one reading of a directory found — or that there was no reading.
    ///
    /// **Two answers for three facts.** `children(of:)` folds «nothing is in it»,
    /// «nothing is there» and «this process may not read it» into one empty array,
    /// and only the first two of those lead to the same finding. The third is a
    /// permission being reported as a fact about somebody's Mac: a scan says a
    /// folder holds nothing when it never opened it, and every screen built on that
    /// scan repeats the claim. It is the fold `exists(atPath:)` was taken
    /// apart for one file over — `false` there meant `ENOENT` *and* `EACCES` — and
    /// the repair is the same shape, a third answer nobody can mistake for the
    /// other two.
    ///
    /// «Not there» stays folded into `.listed([])` on purpose, and that is not the
    /// same compromise: both scanners ask about folders that need not exist — a
    /// machine that has never run a sandboxed app has no `Group Containers` — and a
    /// caller that wants to tell an absent folder from an empty one is asking about
    /// a file, which is `exists`'s question and not this one.
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
    /// A missing directory is empty rather than an error: both scanners ask
    /// about folders that need not exist — a machine that has never run a
    /// sandboxed app has no `Group Containers` — and "not there" and "nothing
    /// in it" lead to the same finding. A directory that would not *open* is
    /// empty here too, which is the fold `contents(of:)` exists to undo: a caller
    /// that concludes anything from an empty answer asks that one instead.
    public static func children(of url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(atPath: url.path))?
            .map { url.appendingPathComponent($0) } ?? []
    }
}
