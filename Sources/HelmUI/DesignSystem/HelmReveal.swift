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
///   enclosing folder is revealed instead, which is the honest answer to
///   "show me" — *opened* when it is a plain folder, *selected* when it is a
///   bundle, because `NSWorkspace.open` on a `.app` launches it and on a
///   `.photoslibrary` mounts it. A disk scan lists the top-level children of a
///   bundle, so a stale row inside one is reachable and this is not theoretical.
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
        /// Highlight this in its parent window. Never launches or mounts it —
        /// `activateFileViewerSelecting` selects a bundle without opening it.
        case select(URL)
        /// Open this folder to its contents. **Only ever a plain directory:**
        /// `NSWorkspace.open` on a `.app` launches it and on a `.photoslibrary`
        /// mounts it, so a package is selected instead (below).
        case open(URL)
    }

    /// `nil` reveals nothing. Two call sites guarded a `String?` by hand and the
    /// rest did not, and an empty path is worse than harmless:
    /// `URL(fileURLWithPath: "")` is the process's current directory, so the
    /// fallback would open a folder nobody asked about.
    ///
    /// `traits` answers whether the enclosing folder is a directory and whether
    /// it is a package, so the bundle decision is testable without a real `.app`.
    /// It returns `nil` for a folder that is not there — an unmounted volume,
    /// most often — and then there is nothing to reveal.
    ///
    /// **This is also the answer to "will the button do anything".** `nil` here
    /// is the whole of "nothing can be shown", it is pure, and it can be asked
    /// *before* the button is drawn — which is worth more than a report after
    /// somebody has pressed one. `inFinder` used to return a `Bool` for that
    /// purpose and no caller ever read it.
    public static func target(
        for path: String,
        exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        traits: (String) -> (isDirectory: Bool, isPackage: Bool)? = {
            guard let v = try? URL(fileURLWithPath: $0)
                .resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]) else { return nil }
            return (v.isDirectory ?? false, v.isPackage ?? false)
        }
    ) -> Target? {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        // What is there is selected — a file, a folder, a bundle alike. Selecting
        // never launches, so even a `.app` that exists is shown, not run.
        if exists(path) { return .select(url) }

        // Gone: fall back to where it was. The enclosing folder is *opened* only
        // when it is a plain directory; a package is selected in its own parent,
        // because opening it would launch or mount it. A folder that is itself
        // gone (an ejected volume) leaves nothing to show.
        let folder = url.deletingLastPathComponent()
        guard let t = traits(folder.path) else { return nil }
        return t.isDirectory && !t.isPackage ? .open(folder) : .select(folder)
    }

    /// Reveal `path`, and bring Finder forward whichever way it went.
    ///
    /// It answers nothing, because it has nothing to answer with. This returned
    /// a `Bool` documented as "whether anything could be shown, so a caller can
    /// say so" — and all ten call sites dropped it, with `@discardableResult`
    /// there to make sure no build ever mentioned that. The half of it that
    /// could be true is `target(for:)`'s, and that one is pure, tested, and
    /// available before the button is drawn; the half that was measured here
    /// could not be, because `activateFileViewerSelecting` reports nothing at
    /// all, so the selecting arm answered `true` by writing `true`.
    ///
    /// Finder is activated by name rather than by `NSWorkspace.shared.open`ing
    /// it: activating the running instance raises the window that was just
    /// opened, and asking to open Finder again does not.
    @MainActor public static func inFinder(_ path: String) {
        switch target(for: path) {
        case .select(let url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .open(let folder):
            // `open` launches nothing here — `target` only ever hands `.open` a
            // plain directory.
            NSWorkspace.shared.open(folder)
        case nil:
            return
        }
        NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.finder").first?.activate()
    }
}
