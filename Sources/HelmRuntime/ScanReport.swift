import Foundation

/// What a module answers `backgroundScan` with.
///
/// The numbers the journal stores and the list the comparison needs, and nothing
/// else. A module's own richer result — duplicate groups, a directory tree, an
/// app's leftovers — stays in the module: this is the shape three unlike
/// scanners can all speak.
///
/// **Nil is not an empty report.** A scan whose root was refused, or that was
/// cancelled, or that could not read a directory in scope, must not come back as
/// "we looked and it was clean". The coordinator records nothing for nil and
/// «проверено» for an empty one, and those are different sentences to a person
/// deciding whether to trust the app with their disk.
public struct ScanReport: Codable, Equatable, Sendable {
    /// What acting on everything found would return.
    public let bytes: Int
    /// How many items that is.
    public let count: Int
    /// The items themselves, for the journal's list and the comparison.
    public let items: [ScanItem]

    public init(bytes: Int, count: Int, items: [ScanItem]) {
        self.bytes = bytes
        self.count = count
        self.items = items
    }

    public var isEmpty: Bool { count == 0 && bytes == 0 }
}
