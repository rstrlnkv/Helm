import Foundation

/// How often each package was installed over Homebrew's published window.
///
/// One shape for both documents, because they *are* one shape: the cask file
/// keys its packages under `"formulae"` exactly as the formula file does, and
/// the only difference is the name of a field inside each entry that this
/// parser never reads. The dictionary key is the package name.
public struct InstallCounts: Sendable, Equatable {
    public let counts: [String: Int]
    public init(counts: [String: Int]) { self.counts = counts }
    /// No reading yet, or one that was refused. Distinct from a reading that
    /// came back with nothing in it only in what the caller does about it —
    /// which is, in both cases, leave the order alone.
    public static let none = InstallCounts(counts: [:])

    /// nil when the bytes are not a document this parser recognises: not JSON,
    /// cut off mid-write, or an object with no packages in it. An endpoint that
    /// has moved must not read as a world where nobody installs anything.
    public static func parse(_ data: Data) -> InstallCounts? {
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
