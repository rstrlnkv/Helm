import Foundation
import HelmRuntime

/// One thing the user could delete to reclaim space, and why.
public struct DiskAdvice: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        /// A known cache location that grew past the threshold.
        case cache
        /// A big Downloads item nobody has touched in a month.
        case oldDownload
        /// A huge file untouched for half a year.
        case largeOld
    }

    /// One path this advice will really hand to the Trash, and what it weighs.
    ///
    /// The weight travels with the path because a partial removal has to leave
    /// an honest row behind: half the targets gone and the row still claiming
    /// the whole folder is the same lie in a quieter place.
    public struct Target: Codable, Equatable, Sendable {
        public let path: String
        public let bytes: Int

        public init(path: String, bytes: Int) {
            self.path = path
            self.bytes = bytes
        }
    }

    public var id: String { path }
    public let name: String
    public let path: String
    public let bytes: Int
    public let kind: Kind
    /// What pressing + really removes. Usually `path` itself; for a cache it is
    /// the folder's contents, because the folder is not the app's to take away —
    /// see `DiskAdvisor.cacheFolders`. Never empty, and `bytes` is its total.
    public let targets: [Target]
    /// When the file was last **written**, as epoch seconds — the only date the
    /// scanner has (`ATTR_CMN_MODTIME`), and the one the age thresholds above
    /// are measured against. nil where there is none to give: a cache advice is
    /// a folder, whose own mtime says when something was last added to it and
    /// nothing about what is inside.
    ///
    /// It travels with the advice because the row that asks somebody to bin a
    /// gigabyte otherwise offers a category word as its whole reason — and the
    /// category word claimed *use*, which no attribute here measures.
    public let modified: TimeInterval?

    /// The thing itself: one path, weighing what the row says.
    public init(name: String, path: String, bytes: Int, kind: Kind,
                modified: TimeInterval? = nil) {
        self.init(name: name, path: path, kind: kind, modified: modified,
                  targets: [Target(path: path, bytes: bytes)])
    }

    /// The contents of a container. The row still names `path` — one row, one
    /// size, one button — and the size is the sum of what will be attempted.
    public init(name: String, path: String, kind: Kind,
                modified: TimeInterval? = nil, targets: [Target]) {
        self.name = name; self.path = path; self.kind = kind
        self.modified = modified
        self.targets = targets
        self.bytes = targets.reduce(0) { $0 + $1.bytes }
    }

    /// A scan cached by a build that named only the container decodes as one
    /// target: itself. Dropping the whole tree over a missing key would cost
    /// somebody a minute of scanning on the first launch after an update, and
    /// `modified` already earned that lesson.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let path = try c.decode(String.self, forKey: .path)
        let bytes = try c.decode(Int.self, forKey: .bytes)
        // Through the initializer above rather than assigning the fields here,
        // so `bytes` is derived from `targets` in exactly one place and a file
        // whose two figures disagree cannot decode into a row that lies.
        self.init(name: try c.decode(String.self, forKey: .name),
                  path: path,
                  kind: try c.decode(Kind.self, forKey: .kind),
                  modified: try c.decodeIfPresent(TimeInterval.self, forKey: .modified),
                  targets: try c.decodeIfPresent([Target].self, forKey: .targets)
                      ?? [Target(path: path, bytes: bytes)])
    }
}

/// Walks a finished scan tree and points at likely reclaimable space.
/// Heuristics only — everything still goes through the basket and the user's
/// confirmation; nothing here deletes.
public enum DiskAdvisor {
    private static let cacheFloor = 100_000_000          // 100 MB
    private static let downloadFloor = 50_000_000        // 50 MB
    private static let downloadAge: TimeInterval = 30 * 86_400
    private static let largeFloor = 1_000_000_000        // 1 GB
    private static let largeAge: TimeInterval = 180 * 86_400
    private static let cap = 12

    /// Cache folders whose whole **contents** are regenerable. Relative to home.
    ///
    /// The contents, and never the folder. `~/Library/Caches` carries an ACL
    /// its children do not — `group:everyone deny delete`, which `ls -lde`
    /// prints and which makes `trashItem` answer NSCocoaErrorDomain 513 — so a
    /// row offering the folder recommended the one action macOS refuses.
    ///
    /// The other two carry no such ACL today and their containers really are
    /// trashable, and they are still treated the same way. Two reasons, in
    /// order: emptying is what the row already claims ("Cache — apps rebuild
    /// it") whatever the folder's own permissions happen to be, and applications
    /// expect their cache folder to exist; and which of the three wears the ACL
    /// is a fact about this release of macOS, so a per-folder rule would pin
    /// today's `ls` output into the advisor and go quietly wrong when it moves.
    /// Uniform costs one empty folder left behind — the one Xcode would create
    /// again on its next build.
    ///
    /// There is no runtime "would macOS take this" probe here because there is
    /// none to call: measured against the real folder,
    /// `FileManager.isDeletableFile` and `faccessat(_DELETE_OK)` both answer yes
    /// for `~/Library/Caches`. Reading the ACL with `acl_get_file` would, and
    /// nothing needs it while the rule is "a cache means its contents".
    ///
    /// `Library/Logs` was here and drew "Cache — safe to clear" over a folder
    /// named Logs. Two different claims: a cache is rebuilt on demand, a log
    /// is the record somebody may still need to read.
    private static let cacheFolders = [
        "Library/Caches",
        "Library/Developer/Xcode/DerivedData",
        "Library/Developer/CoreSimulator/Caches",
    ]

    /// `rootPath` is where `root` was scanned from, and it is not `home`: the
    /// volume walk hands in `/` while home is somewhere inside it. The two were
    /// one parameter for as long as `DiskNode` stored its own path, and the
    /// tests never caught the conflation because they scan home itself.
    public static func advise(root: DiskNode, rootPath: String, home: String,
                              now: Date = Date()) -> [DiskAdvice] {
        var advice: [DiskAdvice] = []

        for relative in cacheFolders {
            let path = home + "/" + relative
            guard let node = find(path: path, under: root, rootPath: rootPath),
                  UserFileScope.isRemovable(path) else { continue }
            let candidate = DiskAdvice(name: node.name, path: path, kind: .cache,
                                       targets: contents(of: node, at: path))
            // The threshold reads the figure the row will show, by reading the
            // row: `node.bytes` counts the folded bucket too, and no path in it
            // will ever be attempted.
            guard candidate.bytes >= cacheFloor else { continue }
            advice.append(candidate)
        }
        // Anything inside an advised cache is already covered by it.
        let cachePrefixes = advice.map { $0.path + "/" }

        let downloads = home + "/Downloads/"
        // A depth-first descent, and deliberately not the breadth-first stack
        // this used to be. The path is composed on the way down and released on
        // the way up, so the strings alive at any moment number the depth of the
        // tree — a stack of pending siblings would hold one per node still to
        // visit, handing back as a transient spike exactly the ~345 MB that
        // dropping the stored path saved.
        func sweep(_ node: DiskNode, path: String) {
            if !node.isDirectory, !node.isFolded, node.modified > 0,
               UserFileScope.isRemovable(path),
               !cachePrefixes.contains(where: { path.hasPrefix($0) }) {
                let age = now.timeIntervalSince1970 - node.modified
                if path.hasPrefix(downloads), node.bytes >= downloadFloor, age > downloadAge {
                    advice.append(DiskAdvice(name: node.name, path: path,
                                             bytes: node.bytes, kind: .oldDownload,
                                             modified: node.modified))
                } else if node.bytes >= largeFloor, age > largeAge {
                    advice.append(DiskAdvice(name: node.name, path: path,
                                             bytes: node.bytes, kind: .largeOld,
                                             modified: node.modified))
                }
            }
            // A node is judged before its children, as it was when this popped a
            // stack: `sorted` below is not stable, so a changed visit order would
            // silently reshuffle advice of equal size.
            for child in node.children {
                sweep(child, path: ScanPath.child(of: path, name: child.name))
            }
        }
        sweep(root, path: rootPath)

        return Array(advice.sorted { $0.bytes > $1.bytes }.prefix(cap))
    }

    /// What clearing a cache folder really removes: everything directly inside
    /// it, each with its own weight.
    ///
    /// The folded bucket is left out and it is not an oversight — it is an
    /// aggregate of the small loose files, wearing the name `…`, and
    /// `UserFileScope` refuses any path ending in one. Including it would
    /// advertise bytes nothing would ever be asked to free.
    private static func contents(of node: DiskNode,
                                 at path: String) -> [DiskAdvice.Target] {
        node.children.filter { !$0.isFolded }.map {
            DiskAdvice.Target(path: ScanPath.child(of: path, name: $0.name),
                              bytes: $0.bytes)
        }
    }

    /// Descends towards `path`, composing each candidate's path from its name.
    /// The node it returns does not know where it is, so the caller keeps the
    /// path it asked for — which is the same string by construction.
    private static func find(path: String, under root: DiskNode,
                             rootPath: String) -> DiskNode? {
        // `child(of: rootPath, name: "")` is the root with exactly one trailing
        // slash, whether or not it already had one — the same arithmetic the
        // descent uses, so the cheap reject cannot disagree with it.
        guard path == rootPath
                || path.hasPrefix(ScanPath.child(of: rootPath, name: "")) else { return nil }
        var node = root
        var here = rootPath
        while here != path {
            guard let next = node.children.first(where: {
                let candidate = ScanPath.child(of: here, name: $0.name)
                return candidate == path || path.hasPrefix(candidate + "/")
            }) else { return nil }
            here = ScanPath.child(of: here, name: next.name)
            node = next
        }
        return node
    }
}
