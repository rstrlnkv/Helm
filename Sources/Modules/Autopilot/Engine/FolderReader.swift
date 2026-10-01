import Foundation
import HelmRuntime
import UniformTypeIdentifiers

/// The one place that turns files into `FileFacts`.
///
/// Everything above it is arithmetic on those facts; keeping the reading in one
/// small type is what makes that true. It also means the answer to "what does a
/// rule know about a file" is a single file to read.
struct FolderReader: Sendable {

    /// How an entry's on-disk weight is read. A seam, because what a test has
    /// to be able to assert is that the question is *never put* for a plain
    /// folder — `FileWeight` walks one in full, and the only reader of the
    /// answer refuses directories — which no timing or output can show.
    var weigh: @Sendable (URL) -> Int = { FileWeight.allocated(of: $0) }

    /// Which home `WatchScope` measures against, for the gate this reader asks
    /// of every directory it opens. Injected for the reason the engine's is.
    /// `nil` is a reader that asks no gate — the plain reading of a folder, which
    /// is what a test of *what is offered* wants; the engine always names its home.
    var home: String?

    /// Whether the walk may descend past an entry at `level` of a read bounded
    /// by `depth`.
    ///
    /// Pure, so the decision that keeps a depth-1 read of Downloads from
    /// enumerating every file in every project tree inside it is one a test
    /// can hold still. A directory *at* the limit is offered as a thing and
    /// its contents can never be: descending into it pays for every entry
    /// below the limit only to filter them out again one at a time.
    static func prunes(atLevel level: Int, depth: Int, isDirectory: Bool) -> Bool {
        isDirectory && level >= depth
    }

    /// The files a folder's rules will be offered, at the folder's depth.
    ///
    /// Depth 1 is the folder's own contents. Deeper is the folder's own
    /// setting, and the walk does not descend into a package at any
    /// depth: an `.app` or an `.rtfd` is one thing to a person, and descending
    /// into it would offer a rule several hundred files that are not files as
    /// far as anybody is concerned.
    func facts(in folder: String, depth: Int, now: Date = Date()) -> [FileFacts] {
        reading(in: folder, depth: depth, now: now).files
    }

    /// The deepest a read goes whatever depth a folder asks for. The walk holds
    /// one descriptor per level it is inside, and a depth is an `Int` read out of
    /// a property list — a ceiling here is what keeps `Int.max` from being a
    /// request to exhaust the descriptor table of a process that holds the
    /// person's Full Disk Access.
    static let deepest = 64

    /// The same read, with the answer to "was there anything to read".
    ///
    /// **Three states, because the caller cannot tell them apart from a count.**
    /// A walk that swallowed its open errors would fold a directory that is not
    /// there and one this process may not open into the same empty list as a
    /// folder with nothing in it — and `[]` is what the sweep, the banner and the
    /// page then all say. A missing folder is a rename or a moved disk; a refused
    /// one is the permission the module's own note is about.
    ///
    /// **Read through descriptors, not through paths.** The walk this replaced
    /// was `FileManager`'s enumerator, which opens each subfolder by the path it
    /// listed it under; a subfolder swapped for a link into `~/Library` after it
    /// was listed and before it was entered was read as the protected folder, and
    /// put back, left the names of what it held in the history and the log as
    /// `.missing` refusals. Here the root is opened once and every level is
    /// opened *relative to its parent's descriptor* with `O_NOFOLLOW`, so what is
    /// listed is the directory that was opened and nothing a path leads to later;
    /// a link in its place is refused by the open (`ELOOP`) and the level is
    /// skipped. The gate is asked about the path the descriptor itself reports
    /// (`F_GETPATH`) — for the root as much as for any level — and, before a level
    /// is opened at all, about its name: reading a directory to decide whether to
    /// read it is the consent prompt the gate exists to keep away.
    ///
    /// The root *is* followed when it is itself a link: a folder saved as `~/DL`
    /// for `~/Downloads` is where its link leads, as every other question the
    /// module asks about a folder reads it, and the gate is asked about where.
    ///
    /// What is not closed: the facts of each entry are read by path, after the
    /// directory they were listed in was verified. A swap there changes the size
    /// or the tags a name is offered with, not which names are offered, and the
    /// runner asks the gate again at the act.
    func reading(in folder: String, depth: Int, now: Date = Date()) -> FolderReading {
        switch state(of: folder) {
        case .missing: return .missing
        case .refused: return .refused
        case .read: break
        }
        let root = open(folder, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard root >= 0 else { return .refused }
        defer { close(root) }
        guard let rootPath = Self.path(of: root), allows(rootPath) else { return .refused }

        var found: [FileFacts] = []
        walk(root, at: rootPath, level: 1, depth: depth, now: now, into: &found)
        return .read(found)
    }

    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isHiddenKey, .fileSizeKey,
        .addedToDirectoryDateKey, .contentModificationDateKey,
        .creationDateKey, .tagNamesKey, .contentTypeKey]

    /// One directory's entries at `level`, then each subdirectory the depth
    /// allows. Hidden entries are not there, a package is one thing, a directory
    /// at the limit is offered and not entered — the three `FileManager`'s
    /// enumerator options and `prunes` used to answer.
    private func walk(_ fd: Int32, at path: String, level: Int, depth: Int, now: Date,
                      into found: inout [FileFacts]) {
        // A depth below one reads nothing, and the ceiling is the descriptors'.
        guard level <= depth, level <= Self.deepest else { return }
        for name in Self.names(in: fd) {
            // Cheap and first: a dotfile needs no facts read.
            guard !name.hasPrefix(".") else { continue }
            let url = URL(fileURLWithPath: path + "/" + name)
            guard let values = try? url.resourceValues(forKeys: Set(Self.keys)),
                  values.isHidden != true else { continue }
            let facts = facts(from: values, of: url, now: now)
            found.append(facts)
            guard !Self.prunes(atLevel: level, depth: depth, isDirectory: facts.isDirectory),
                  facts.isDirectory, level < Self.deepest else { continue }
            // By name, then by descriptor: the name is judged without opening
            // anything, and the open that follows is of what that name is *now*
            // and refuses a link.
            guard allows(url.path) else { continue }
            let child = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard child >= 0 else { continue }
            defer { close(child) }
            guard let childPath = Self.path(of: child),
                  allows(childPath) else { continue }
            walk(child, at: childPath, level: level + 1, depth: depth, now: now, into: &found)
        }
    }

    private func allows(_ path: String) -> Bool {
        home.map { WatchScope.allows(path, home: $0) } ?? true
    }

    /// The names in a directory the descriptor holds open. A duplicate is listed
    /// and closed, so the descriptor itself stays open for the `openat`s beneath
    /// it and nothing is left half-read.
    private static func names(in fd: Int32) -> [String] {
        let copy = dup(fd)
        guard copy >= 0, let stream = fdopendir(copy) else {
            if copy >= 0 { close(copy) }
            return []
        }
        defer { closedir(stream) }
        var names: [String] = []
        while var entry = readdir(stream) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            if name != "." && name != ".." { names.append(name) }
        }
        return names
    }

    /// Where an open descriptor is, as the kernel says — which is the directory
    /// that was opened, whatever the path it was opened by now leads to.
    private static func path(of fd: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(fd, F_GETPATH, &buffer) != -1 else { return nil }
        return String(cString: buffer)
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
    /// meant two things depending on which one ran.** `facts(in:)` reads through
    /// `walk`, which leaves hidden entries out and treats a package as one thing,
    /// so an `.app` is one thing and a dotfile is not there; the FSEvents leg
    /// asked for the facts of whatever path it was handed, and an FSEvents stream
    /// is recursive whether or not anybody asked. With «Include subfolders» on —
    /// the ⋯ menu writes depth 8 — a resource inside an application bundle
    /// somebody unarchived into Downloads was a live target, and the dry run
    /// could not warn them: the dry run reads through the walk that skips
    /// packages.
    ///
    /// The three questions are the walk's three — depth, hidden, package — in the
    /// same order, and `TheWatcherAndTheSweepAskOneQuestionTests` pins the two
    /// answers to each other over a real tree at three depths; an agreement
    /// proven by a test is what makes them one question rather than a sentence
    /// saying they are. **Known gap F-Y2:** the walk stops at `deepest` and this
    /// question does not know it, so for a depth past 64 — which the UI never
    /// writes and the sealed property list does not take by hand — the watcher
    /// admits files the sweep never reads
    /// (`TheDescriptorWalkHoldsItsGroundTests.testPastTheCeilingTheWatcherAndTheSweepAgree`,
    /// skipped until it is decided).
    func admits(_ url: URL, under folder: WatchedFolder) -> Bool {
        let file = url.standardizedFileURL
        var root = URL(fileURLWithPath: folder.path).standardizedFileURL
        var components = file.pathComponents
        if !components.starts(with: root.pathComponents) {
            // Spelled two ways: an event carries the real path and the folder may
            // have been saved as a link to it, or through `/var` for `/private/var`.
            // Both read as where they lead — the file by its folder, so a file that
            // is itself a link is judged as the link it is.
            root = root.resolvingSymlinksInPath()
            components = file.deletingLastPathComponent().resolvingSymlinksInPath()
                .appendingPathComponent(file.lastPathComponent).pathComponents
        }
        let below = components.count - root.pathComponents.count
        guard components.starts(with: root.pathComponents), below >= 1,
              below <= folder.depth else { return false }
        // Every step from the folder down, the file itself included: a file
        // inside a hidden folder is one the walk never reaches either, and
        // a package's descendants are refused at whichever level the package sits.
        var step = root
        for name in components.suffix(below) {
            step.appendPathComponent(name)
            guard let values = try? step.resourceValues(forKeys: [.isHiddenKey, .isPackageKey])
            else { return false }
            if values.isHidden == true { return false }
            if values.isPackage == true { return step.pathComponents == components }
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
        return facts(from: values, of: url, now: now)
    }

    private func facts(from values: URLResourceValues, of url: URL, now: Date) -> FileFacts {
        let isDirectory = (values.isDirectory ?? false) && !(values.isPackage ?? false)
        return FileFacts(
            name: url.lastPathComponent,
            path: url.path,
            kind: isDirectory ? .folder : kind(of: values.contentType),
            // Not `fileSize`: a package has none — `URLResourceValues` calls a
            // `.app` a package rather than a directory, so it slipped past the
            // size rule's directory guard and answered zero. "Smaller than 1 MB
            // → Trash" then matched every application in the folder, hourly,
            // unattended. A *plain* folder is the opposite trade: the walk
            // `FileWeight` makes of one is the module's whole time budget, and
            // the only reader of `bytes` refuses a directory outright — so the
            // number is never computed rather than computed and thrown away.
            bytes: isDirectory ? 0 : weigh(url),
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
