import Foundation
import HelmRuntime
import UniformTypeIdentifiers

/// The one place that turns files into `FileFacts`.
///
/// Everything above it is arithmetic on those facts; keeping the reading in one
/// small type is what makes that true. It also means the answer to "what does a
/// rule know about a file" is a single file to read.
struct FolderReader: Sendable {

    /// The files a folder's rules will be offered, at the folder's depth.
    ///
    /// Depth 1 is the folder's own contents. Deeper is the folder's own
    /// setting, and the enumerator is told to skip package contents at every
    /// depth: an `.app` or an `.rtfd` is one thing to a person, and descending
    /// into it would offer a rule several hundred files that are not files as
    /// far as anybody is concerned.
    func facts(in folder: String, depth: Int, now: Date = Date()) -> [FileFacts] {
        reading(in: folder, depth: depth, now: now).files
    }

    /// The same read, with the answer to "was there anything to read".
    ///
    /// **Three states, because the caller cannot tell them apart from a count.**
    /// An enumerator built with no `errorHandler` folds a directory that is not
    /// there and one this process may not open into the same empty list as a
    /// folder with nothing in it — and `[]` is what the sweep, the banner and the
    /// page then all say. A missing folder is a rename or a moved disk; a refused
    /// one is the permission the module's own note is about.
    func reading(in folder: String, depth: Int, now: Date = Date()) -> FolderReading {
        let root = URL(fileURLWithPath: folder)
        switch state(of: folder) {
        case .missing: return .missing
        case .refused: return .refused
        case .read: break
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .fileSizeKey,
                                      .addedToDirectoryDateKey, .contentModificationDateKey,
                                      .creationDateKey, .tagNamesKey, .contentTypeKey]
        // No `errorHandler:`. It was written here first, catching a refusal on
        // the root — and `state(of:)` above answers that question before the walk
        // starts, so removing the handler failed no test and could fail none: the
        // only case left to it is the folder becoming unreadable between the
        // `opendir` and this line, which the next sweep catches anyway. A branch
        // no test can reach is not a guard. A subdirectory the walk cannot enter
        // is deliberately not a refusal either: half a folder read is more than
        // none, and the folder itself was readable.
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return .refused }

        var found: [FileFacts] = []
        for case let url as URL in enumerator {
            if enumerator.level > depth { enumerator.skipDescendants(); continue }
            if let facts = facts(of: url, keys: keys, now: now) { found.append(facts) }
        }
        return .read(found)
    }

    /// Whether the folder is there and Helm may look inside it, without reading
    /// it.
    ///
    /// **One question about the folder, not one per file in it.** The page asks
    /// this for every watched folder every time it opens, and answering it by
    /// walking the tree would put a full read of Downloads behind a screen that
    /// only wants to know whether the path still exists.
    ///
    /// `opendir` rather than `access(R_OK | X_OK)`: the permission that stops
    /// this module is Full Disk Access, which is not a POSIX mode — TCC answers
    /// `access` with the mode bits, which say yes, and then refuses the open. The
    /// case the module's own note is about is precisely the one `access` cannot
    /// see.
    func state(of folder: String) -> FolderState {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory),
              isDirectory.boolValue else { return .missing }
        guard let handle = opendir(folder) else { return .refused }
        closedir(handle)
        return .read
    }

    /// Whether a rule may be offered this file at all.
    ///
    /// **The sweep and the watcher used to answer this differently, and a rule
    /// meant two things depending on which one ran.** `facts(in:)` builds its
    /// enumerator with `.skipsHiddenFiles` and `.skipsPackageDescendants`, so an
    /// `.app` is one thing and a dotfile is not there; the FSEvents leg asked for
    /// the facts of whatever path it was handed, and an FSEvents stream is
    /// recursive whether or not anybody asked. With «Include subfolders» on — the
    /// ⋯ menu writes depth 8 — a resource inside an application bundle somebody
    /// unarchived into Downloads was a live target, and the dry run could not
    /// warn them: the dry run reads through the enumerator that skips packages.
    ///
    /// The three questions are the enumerator's three, in the same order, and
    /// `TheWatcherAndTheSweepAskOneQuestionTests` pins the two answers to each
    /// other over a real tree at three depths — the reader keeps its options
    /// because pruning at the enumerator is what stops it descending a project
    /// tree at all, and an agreement proven by a test is what makes them one
    /// question rather than a sentence saying they are.
    func admits(_ url: URL, under folder: WatchedFolder) -> Bool {
        let root = URL(fileURLWithPath: folder.path).standardizedFileURL
        let components = url.standardizedFileURL.pathComponents
        let below = components.count - root.pathComponents.count
        guard components.starts(with: root.pathComponents), below >= 1,
              below <= folder.depth else { return false }
        // Every step from the folder down, the file itself included: a file
        // inside a hidden folder is one the enumerator never reaches either, and
        // a package's descendants are refused at whichever level the package sits.
        var step = root
        for name in components.suffix(below) {
            step.appendPathComponent(name)
            guard let values = try? step.resourceValues(forKeys: [.isHiddenKey, .isPackageKey])
            else { return false }
            if values.isHidden == true { return false }
            if values.isPackage == true { return step == url.standardizedFileURL }
        }
        return true
    }

    /// One file. Used by the watcher, which is told about a path rather than a
    /// folder.
    func facts(of url: URL, now: Date = Date()) -> FileFacts? {
        facts(of: url, keys: [.isDirectoryKey, .isPackageKey, .fileSizeKey,
                              .addedToDirectoryDateKey, .contentModificationDateKey,
                              .creationDateKey, .tagNamesKey, .contentTypeKey], now: now)
    }

    private func facts(of url: URL, keys: [URLResourceKey], now: Date) -> FileFacts? {
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
        let isDirectory = (values.isDirectory ?? false) && !(values.isPackage ?? false)
        return FileFacts(
            name: url.lastPathComponent,
            path: url.path,
            kind: isDirectory ? .folder : kind(of: values.contentType),
            // Not `fileSize`: a package has none — `URLResourceValues` calls a
            // `.app` a package rather than a directory, so it slipped past the
            // size rule's directory guard and answered zero. "Smaller than 1 MB
            // → Trash" then matched every application in the folder, hourly,
            // unattended.
            bytes: FileWeight.allocated(of: url),
            // `addedToDirectoryDate` is what "date added" means in the Finder
            // and it is what a Downloads rule is asking about; a file copied in
            // from elsewhere keeps its old creation date, which would make
            // "added in the last week" wrong for exactly the files people sort.
            added: values.addedToDirectoryDate ?? values.creationDate ?? Date.distantPast,
            modified: values.contentModificationDate ?? Date.distantPast,
            downloadedFrom: source(of: url),
            tags: values.tagNames ?? [],
            isDirectory: isDirectory,
            now: now)
    }

    /// The system already knows a `.heic` is an image and an `.xip` is an
    /// archive. A table of extensions here would be a second, worse answer that
    /// drifts as formats appear.
    private func kind(of type: UTType?) -> FileKind {
        guard let type else { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .archive) { return .archive }
        if type.conforms(to: .content) || type.conforms(to: .text) { return .document }
        return .other
    }

    /// `kMDItemWhereFroms` — the condition this module is worth having for.
    /// Read through the extended attribute rather than Spotlight so it works on
    /// volumes that are not indexed.
    private func source(of url: URL) -> String? {
        let attribute = "com.apple.metadata:kMDItemWhereFroms"
        let path = url.path
        let length = getxattr(path, attribute, nil, 0, 0, 0)
        guard length > 0 else { return nil }
        var data = Data(count: length)
        let read = data.withUnsafeMutableBytes { getxattr(path, attribute, $0.baseAddress, length, 0, 0) }
        guard read == length,
              let list = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let urls = list as? [String]
        else { return nil }
        return urls.first { !$0.isEmpty }
    }
}
