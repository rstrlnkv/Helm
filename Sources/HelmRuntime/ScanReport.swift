import Foundation

/// An engine that can measure with nobody watching.
///
/// **The list and the capability are tied by the type system.** A module in
/// `ScanRunner.scannableModules` whose descriptor does not override the scan
/// answers the default `nil`, "could not answer", and the coordinator would
/// retry it all day and log «no answer» about a module that never scanned.
///
/// Conformance lets a test say both halves: every id in the list has an engine
/// that can scan, and every engine that can is in the list. That its descriptor
/// passes the call on is held by `testTheDescriptorPassesTheScanOn` in each
/// scanner's stopped-model class; `testEveryScannableModuleHasAPassOnTest`
/// holds that the test is there.
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
/// for an empty one it records a clean check.
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
