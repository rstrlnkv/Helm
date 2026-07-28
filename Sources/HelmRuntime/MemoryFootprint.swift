import Foundation

/// What the app is costing, and what made it cost that.
///
/// A total on its own answers nothing: the app was 15 MB at launch and half a
/// gigabyte after a while, and knowing both did not say which operation stood
/// between them. So the log carries a **delta against the last reading for the
/// same label** — "leftovers.scan +38 MB" is a lead, "504 MB" is a number.
///
/// `phys_footprint` is the figure Activity Monitor calls Memory and the one the
/// system kills a process over; `resident_size` counts pages shared with other
/// processes and reads high for no reason anyone can act on.
public enum MemoryFootprint {

    /// Bytes, or nil if the kernel declines — a diagnostic must never be the
    /// reason a feature fails, so every caller treats nil as "say nothing".
    public static func current() -> Int? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Int(info.phys_footprint)
    }
}

/// Keeps the last footprint per label and decides whether the change is worth a
/// line. Pure, so the accounting is a unit test rather than a guess against a
/// running app.
public struct FootprintTracker: Sendable {

    /// Below this, a change is noise: SwiftUI redraws, a formatter cache, an
    /// icon. Named rather than inlined so a test can state it.
    public static let defaultThreshold = 8 * 1024 * 1024

    private var last: [String: Int] = [:]
    private let threshold: Int

    public init(threshold: Int = FootprintTracker.defaultThreshold) {
        self.threshold = threshold
    }

    /// A reading worth logging, or nil.
    ///
    /// The first reading for a label is always worth it — that is the baseline
    /// every later delta is measured from, and without it the first line in the
    /// log would be a delta against nothing.
    public mutating func report(_ label: String, bytes: Int) -> Report? {
        defer { last[label] = bytes }
        guard let previous = last[label] else {
            return Report(label: label, bytes: bytes, delta: nil)
        }
        let delta = bytes - previous
        guard abs(delta) >= threshold else { return nil }
        return Report(label: label, bytes: bytes, delta: delta)
    }

    public struct Report: Equatable, Sendable {
        public let label: String
        public let bytes: Int
        /// nil on the first reading for a label.
        public let delta: Int?

        /// "84 MB" / "84 MB (+38 MB)" / "46 MB (-12 MB)". Whole megabytes: a
        /// tenth of one is below what any of this can act on.
        public var line: String {
            let mb = { (b: Int) in "\(b / (1024 * 1024)) MB" }
            guard let delta else { return mb(bytes) }
            let sign = delta >= 0 ? "+" : "-"
            return "\(mb(bytes)) (\(sign)\(mb(abs(delta))))"
        }
    }
}
