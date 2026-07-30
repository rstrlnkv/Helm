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

    public var id: String { path }
    public let name: String
    public let path: String
    public let bytes: Int
    public let kind: Kind
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

    public init(name: String, path: String, bytes: Int, kind: Kind,
                modified: TimeInterval? = nil) {
        self.name = name; self.path = path; self.bytes = bytes; self.kind = kind
        self.modified = modified
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

    /// Cache folders whose whole contents are regenerable. Relative to home.
    private static let cacheFolders = [
        "Library/Caches",
        "Library/Developer/Xcode/DerivedData",
        "Library/Developer/CoreSimulator/Caches",
        "Library/Logs",
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
            if let node = find(path: path, under: root, rootPath: rootPath),
               node.bytes >= cacheFloor, UserFileScope.isRemovable(path) {
                advice.append(DiskAdvice(name: node.name, path: path,
                                         bytes: node.bytes, kind: .cache))
            }
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
