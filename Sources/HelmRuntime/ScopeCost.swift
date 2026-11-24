import Foundation

/// What one bounded piece of work cost the process, as a line for the log.
///
/// `FootprintTracker.Report.line` answers at a different scale: a **total** in
/// whole megabytes, silent below its threshold, where building a module would
/// print `0 MB` or nothing. This takes a delta measured *around* a scope, keeps
/// a decimal in megabytes, drops to kilobytes below one, and has no threshold:
/// the figure being small is the answer, not a reason to withhold it.
enum ScopeCost {

    /// Below this, the difference is scheduling rather than the work — a redraw
    /// that happened to land between the two readings. Named so a test can state
    /// it, and small enough that a real allocation never hides under it.
    static let noise = 1024

    static func line(grewBy bytes: Int) -> String {
        guard abs(bytes) >= noise else { return "unchanged" }
        let sign = bytes >= 0 ? "+" : "-"
        let size = abs(bytes)
        if size >= 1024 * 1024 {
            return sign + String(format: "%.1f MB", Double(size) / (1024 * 1024))
        }
        return sign + "\(size / 1024) KB"
    }
}
