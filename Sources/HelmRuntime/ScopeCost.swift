import Foundation

/// What one bounded piece of work cost the process, as a line for the log.
///
/// `FootprintTracker.Report.line` answers a different question at a different
/// scale: a **total** with a delta against the last reading for the same label, in
/// whole megabytes, silent below 8 MB. That was right for the hunt it was built
/// for, where the figures were hundreds of megabytes. Building a module is single
/// digits — rendered by that formatter every one of the nine would print `0 MB`,
/// and thresholded by it none of them would print at all.
///
/// So this one takes a delta measured *around* a scope rather than against a
/// previous sighting of the same label, keeps a decimal in megabytes, drops to
/// kilobytes below one, and has no threshold: nine modules switching on twice each
/// is not a stream, and the figure being small is the answer, not a reason to
/// withhold it.
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
