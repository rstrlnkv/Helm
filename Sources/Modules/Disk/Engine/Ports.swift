import Foundation
import HelmRuntime

/// What the system says about one mounted volume, before anyone has chosen which
/// free-space figure to believe.
///
/// **Two free-space readings, and they are different numbers.** On APFS
/// `volumeAvailableCapacity` leaves out purgeable space (local snapshots, caches
/// macOS will drop on demand), so it reads far lower than what Finder and System
/// Settings print, which is `volumeAvailableCapacityForImportantUsage`. Both are
/// carried here so that `freeSpace` is the one place that decides, and a caller
/// cannot pick the smaller by reaching for the wrong key.
///
/// The capacity fields and the name are `nil` when the system did not answer for
/// them; a volume that answers for neither capacity has no `freeSpace` rather
/// than a free space of zero. `path` and `isBrowsable` are not optional: an
/// unanswered `volumeIsBrowsable` reads as `false`, and `DiskEngine.volumes()`
/// drops a volume that is not browsable.
public struct VolumeReadout: Equatable, Sendable {
    public var name: String?
    public var path: String
    public var isBrowsable: Bool
    public var total: Int?
    /// `volumeAvailableCapacityForImportantUsage` — what Finder shows.
    public var importantFree: Int?
    /// `volumeAvailableCapacity` — purgeable space is not in it.
    public var plainFree: Int?

    public init(name: String?, path: String, isBrowsable: Bool, total: Int?,
                importantFree: Int?, plainFree: Int?) {
        self.name = name; self.path = path; self.isBrowsable = isBrowsable
        self.total = total; self.importantFree = importantFree; self.plainFree = plainFree
    }

    /// Free space, and which reading it is. The important-usage figure wins when
    /// it is anything but a bare zero; the plain one answers otherwise, and says so.
    ///
    /// Reasons that collapse into `.fallback`: the important-usage key is
    /// unreadable (`nil`), or it reads 0 while the plain key reads above zero.
    /// Measured on macOS 27.2: exFAT, FAT and any volume mounted `-nobrowse`
    /// answer the important key with 0, not nil, while the plain key holds the
    /// real figure; on HFS+ and APFS the two keys came within kilobytes of each
    /// other, and no direction is claimed. So a zero important reading is
    /// believed only when the plain one is zero, negative or unreadable too
    /// (`(plainFree ?? 0) <= 0`), which is a disk that is really full. Bounded
    /// to `0...total` when the total is known, because the values come from the
    /// system and a figure past the capacity would draw a negative used share.
    public var freeSpace: FreeSpace? {
        let bound: (Int) -> Int = { value in
            guard let total = self.total else { return max(value, 0) }
            return value.clamped(to: 0...max(total, 0))
        }
        if let value = importantFree, value != 0 || (plainFree ?? 0) <= 0 {
            return .important(bound(value))
        }
        if let value = plainFree { return .fallback(bound(value)) }
        return nil
    }
}

/// Which reading a free-space figure is. A `.fallback` is the plain
/// `volumeAvailableCapacity` figure, taken when the important-usage key gave
/// nothing to believe; on APFS the plain key leaves purgeable space out, so a
/// caller that has to tell the two apart can.
public enum FreeSpace: Equatable, Sendable {
    case important(Int)
    case fallback(Int)

    public var bytes: Int {
        switch self {
        case .important(let bytes), .fallback(let bytes): return bytes
        }
    }
}

/// The mounted volumes and their capacity. `readout(at:)` is `nil` only when the
/// system raised for the path (it does not exist, or cannot be read); a path
/// that answers for none of the capacity keys, `/dev` for one, gives a readout
/// whose capacity fields are `nil`, and it is `freeSpace` that is `nil` there.
public protocol VolumeCapacityPort: Sendable {
    func mounted() -> [VolumeReadout]
    func readout(at path: String) -> VolumeReadout?
}

public struct SystemVolumeCapacity: VolumeCapacityPort {
    public init() {}

    private static let keys: [URLResourceKey] = [
        .volumeNameKey, .volumeTotalCapacityKey, .volumeIsBrowsableKey,
        .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
    ]

    public func mounted() -> [VolumeReadout] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Self.keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap(Self.read)
    }

    public func readout(at path: String) -> VolumeReadout? {
        Self.read(URL(fileURLWithPath: path))
    }

    private static func read(_ url: URL) -> VolumeReadout? {
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
        return VolumeReadout(name: values.volumeName, path: url.path,
                             isBrowsable: values.volumeIsBrowsable == true,
                             total: values.volumeTotalCapacity,
                             importantFree: values.volumeAvailableCapacityForImportantUsage.map { Int(clamping: $0) },
                             plainFree: values.volumeAvailableCapacity)
    }
}
