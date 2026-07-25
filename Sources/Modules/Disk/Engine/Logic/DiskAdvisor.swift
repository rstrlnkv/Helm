import Foundation

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

    public init(name: String, path: String, bytes: Int, kind: Kind) {
        self.name = name; self.path = path; self.bytes = bytes; self.kind = kind
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

    public static func advise(root: DiskNode, home: String, now: Date = Date()) -> [DiskAdvice] {
        var advice: [DiskAdvice] = []

        for relative in cacheFolders {
            let path = home + "/" + relative
            if let node = find(path: path, under: root), node.bytes >= cacheFloor,
               DiskSafety.isRemovable(node.path) {
                advice.append(DiskAdvice(name: node.name, path: node.path,
                                         bytes: node.bytes, kind: .cache))
            }
        }
        // Anything inside an advised cache is already covered by it.
        let cachePrefixes = advice.map { $0.path + "/" }

        let downloads = home + "/Downloads/"
        var stack = [root]
        while let node = stack.popLast() {
            stack.append(contentsOf: node.children)
            guard !node.isDirectory, node.name != "…", node.modified > 0,
                  DiskSafety.isRemovable(node.path),
                  !cachePrefixes.contains(where: { node.path.hasPrefix($0) })
            else { continue }
            let age = now.timeIntervalSince1970 - node.modified
            if node.path.hasPrefix(downloads), node.bytes >= downloadFloor, age > downloadAge {
                advice.append(DiskAdvice(name: node.name, path: node.path,
                                         bytes: node.bytes, kind: .oldDownload))
            } else if node.bytes >= largeFloor, age > largeAge {
                advice.append(DiskAdvice(name: node.name, path: node.path,
                                         bytes: node.bytes, kind: .largeOld))
            }
        }

        return Array(advice.sorted { $0.bytes > $1.bytes }.prefix(cap))
    }

    private static func find(path: String, under root: DiskNode) -> DiskNode? {
        guard path.hasPrefix(root.path) else { return nil }
        var node = root
        while node.path != path {
            guard let next = node.children.first(where: {
                $0.path == path || path.hasPrefix($0.path + "/")
            }) else { return nil }
            node = next
        }
        return node
    }
}
