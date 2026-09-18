import Foundation

/// How often each package was installed over Homebrew's published window.
///
/// One shape for both documents, because they *are* one shape: the cask file
/// keys its packages under `"formulae"` exactly as the formula file does, and
/// the only difference is the name of a field inside each entry that this
/// parser never reads. The dictionary key is the package name.
public struct InstallCounts: Sendable, Equatable {
    let counts: [String: Int]
    init(counts: [String: Int]) { self.counts = counts }
    /// No reading yet, or one that was refused. Distinct from a reading that
    /// came back with nothing in it only in what the caller does about it —
    /// which is, in both cases, leave the order alone.
    static let none = InstallCounts(counts: [:])

    /// nil when the bytes are not a document this parser recognises: not JSON,
    /// not an object, cut off mid-write, or an object with no `formulae` field
    /// at all. An endpoint that has moved must not read as a world where nobody
    /// installs anything.
    ///
    /// **`{"formulae":{}}` is not one of those**, and neither is a document
    /// whose every entry this parser skips: the field is there, so the endpoint
    /// answered — with nothing in it. That is a reading, and the caller
    /// (`PopularityRefresh.answer`) adopts it. The distinction this nil carries
    /// is "nobody answered" against "the answer was empty", and only the first
    /// of the two may leave the stored reading standing.
    static func parse(_ data: Data) -> InstallCounts? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let packages = root["formulae"] as? [String: Any] else { return nil }
        var counts: [String: Int] = [:]
        counts.reserveCapacity(packages.count)
        for (name, entries) in packages {
            guard let first = (entries as? [[String: Any]])?.first,
                  let raw = first["count"] as? String,
                  // Published as "1,162". `Int(_:)` answers nil on that, which
                  // would have cost a rank to precisely the packages people
                  // install most.
                  let value = Int(raw.replacingOccurrences(of: ",", with: ""))
            else { continue }
            counts[name] = value
        }
        return InstallCounts(counts: counts)
    }
}
