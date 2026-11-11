import Foundation

/// An engine that can measure with nobody watching.
///
/// **The list and the capability are tied by the type system, not by a comment.**
/// `ScanRunner.scannableModules` is three strings; before this protocol existed
/// nothing connected them to engines that answer, and the failure mode was
/// silent in the worst way — a module named in that list whose descriptor does not
/// override the scan falls to the default, which answers `nil`, which the caller reads as what
/// this codebase spells "the module could not answer". So the coordinator would
/// call it again each time the retry gap lapsed, up to the day's runs, and log
/// «no answer» about a module that has never scanned anything.
///
/// Conformance costs an engine nothing it was not already doing, and it lets a
/// test say both halves: every id in the list has an engine that can scan, and
/// every engine that can is in the list. That its descriptor passes the call on
/// is held by `testTheDescriptorPassesTheScanOn` in each scanner's stopped-model
/// class; `testEveryScannableModuleHasAPassOnTest` holds that the test is there.
public protocol BackgroundScanning {
    func backgroundScan() async -> ScanReport?
}

/// What a module answers `backgroundScan` with.
///
/// The numbers the journal stores and the list the comparison needs, and nothing
/// else. A module's own richer result — duplicate groups, a directory tree, an
/// app's leftovers — stays in the module: this is the shape three unlike
/// scanners can all speak.
///
/// **Nil is not an empty report.** A scan whose root was refused, or that was
/// cancelled, or that could not read a directory in scope, must not come back as
/// "we looked and it was clean". For nil the coordinator records no completion
/// and no journal entry, though the attempt still spends one of the day's runs;
/// for an empty one it records «проверено». Those are different sentences to a
/// person deciding whether to trust the app with their disk.
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

}
