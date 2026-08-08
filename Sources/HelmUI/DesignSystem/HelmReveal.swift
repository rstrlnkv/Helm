import AppKit
import Foundation

/// Show a path in Finder.
///
/// Nine places offer this — beside a removal failure, in Autopilot's history, on
/// a leftover, on a row of a disk scan, on the log file — and eight of them were
/// one bare `NSWorkspace.shared.activateFileViewerSelecting([url])`, which has
/// two problems the ninth had already found and fixed for itself:
///
/// - **Selecting a file Finder cannot see does nothing.** No window, no error,
///   no Finder in front. That is not an edge case here: the button sits next to
///   files that failed to move, files Autopilot moved somewhere else, and
///   leftovers deleted a moment ago in another window — so the most likely
///   moment for someone to press it is the moment the path is already gone. The
///   enclosing folder opens instead, which is the honest answer to "show me".
/// - **Finder does not always come forward.** `activateFileViewerSelecting`
///   selects in a window that may be behind the settings window it was pressed
///   in, so the reveal happens where nobody can see it.
///
/// The decision is separate from the doing, and takes the existence check as a
/// parameter, because "which of the two things happens" is the part worth a test
/// and the part that was missing in eight places.
public enum HelmReveal {

    /// What Finder is asked to do.
    public enum Target: Equatable {
        /// Open a window with this path highlighted.
        case select(URL)
        /// Open the folder the path was in. What is left when the path is gone.
        case openEnclosing(URL)
    }

    /// `nil` reveals nothing. Two call sites guarded a `String?` by hand and the
    /// rest did not, and an empty path is worse than harmless:
    /// `URL(fileURLWithPath: "")` is the process's current directory, so the
    /// fallback would open a folder nobody asked about.
    public static func target(for path: String,
                              exists: (String) -> Bool = {
                                  FileManager.default.fileExists(atPath: $0)
                              }) -> Target? {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        // A folder is selected too, not opened: Finder shows it highlighted in
        // its parent, which is what "show in Finder" means everywhere else.
        return exists(path) ? .select(url) : .openEnclosing(url.deletingLastPathComponent())
    }

    /// Reveal `path`, and bring Finder forward whichever way it went.
    ///
    /// Finder is activated by name rather than by `NSWorkspace.shared.open`ing
    /// it: activating the running instance raises the window that was just
    /// opened, and asking to open Finder again does not.
    @MainActor public static func inFinder(_ path: String) {
        switch target(for: path) {
        case .select(let url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .openEnclosing(let folder):
            NSWorkspace.shared.open(folder)
        case nil:
            return
        }
        NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.finder").first?.activate()
    }
}
