import Foundation

/// **How many times each app was opened from Launchpad**, the order of the category view. Pure: the file is `LaunchCountStore`'s.
///
/// The document is `{"version":1,"counts":{"<bundle id>":N}}`. Everything read from it is bounded by `LaunchpadLimits`: an id
/// that is empty or too long is dropped (cutting it would merge two ids); more than `maxCountedApps` entries keep the highest
/// counts, ties by the smaller id. **What a number that is not a number means:** a count that is not a finite number counts as
/// no count (the app is dropped), never as the ceiling and never a trap; any other is clamped to `0...maxLaunchCount` and rounded
/// down, and a count of 0 is not kept.
struct LaunchCounts: Equatable, Sendable {
    static let currentVersion = 1
    static let empty = LaunchCounts(counts: [:])

    private(set) var counts: [AppID: Int]

    /// One value of the file, read whatever it is: a string or a list is no number, not a failure of the whole file.
    private struct Lenient: Decodable {
        let number: Double?
        init(from decoder: Decoder) throws { number = try? decoder.singleValueContainer().decode(Double.self) }
    }

    private struct Document: Decodable {
        let version: Int
        let counts: [String: Lenient]
    }

    private struct Written: Encodable {
        let version: Int
        let counts: [String: Int]
    }

    /// nil for a shape that is not this document or a `version` that is not this build's (`currentVersion`: an older number is no document of this shape either).
    static func decode(_ data: Data) -> LaunchCounts? {
        guard let document = try? JSONDecoder().decode(Document.self, from: data), document.version == currentVersion else { return nil }
        var kept: [AppID: Int] = [:]
        for (id, value) in document.counts where !id.isEmpty && id.count <= LaunchpadLimits.maxStringLength {
            guard let number = value.number, number.isFinite else { continue }
            let count = Int(number.clamped(to: 0...Double(LaunchpadLimits.maxLaunchCount)).rounded(.down))
            if count > 0 { kept[id] = count }
        }
        return LaunchCounts(counts: kept).pruned()
    }

    func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(Written(version: Self.currentVersion, counts: counts))) ?? Data()
    }

    /// One more launch of `id`, held at the ceiling.
    mutating func record(_ id: AppID) {
        counts[id] = min((counts[id] ?? 0) + 1, LaunchpadLimits.maxLaunchCount)
        self = pruned()
    }

    private func pruned() -> LaunchCounts {
        guard counts.count > LaunchpadLimits.maxCountedApps else { return self }
        let best = counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(LaunchpadLimits.maxCountedApps)
        return LaunchCounts(counts: Dictionary(uniqueKeysWithValues: best.map { ($0.key, $0.value) }))
    }
}
