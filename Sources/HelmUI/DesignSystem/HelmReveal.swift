import AppKit
import Foundation

/// Show a path in Finder.
///
/// The button sits beside paths that are often already gone: files that failed
/// to move, files Autopilot moved elsewhere, leftovers deleted a moment ago.
///
/// - **Selecting a file Finder cannot see does nothing**: no window, no error.
///   The enclosing folder is revealed instead, *opened* when it is a plain
///   folder and *selected* when it is a bundle, because `NSWorkspace.open`
///   launches a `.app` and mounts a `.photoslibrary`. A disk scan lists the
///   children of a bundle, so a stale row inside one is reachable.
/// - **Finder does not always come forward**: `activateFileViewerSelecting`
///   may select in a window behind the settings window.
///
/// The decision is separate from the doing and takes the existence check as a
/// parameter, so which of the two things happens can be tested.
public enum HelmReveal {

    /// What Finder is asked to do.
    enum Target: Equatable {
        /// Highlight this in its parent window. Never launches or mounts it —
        /// `activateFileViewerSelecting` selects a bundle without opening it.
        case select(URL)
        /// Open this folder to its contents. **Only ever a plain directory:**
        /// `NSWorkspace.open` on a `.app` launches it and on a `.photoslibrary`
        /// mounts it, so a package is selected instead (below).
        case open(URL)
    }

    /// `nil` reveals nothing. An empty path is not harmless:
    /// `URL(fileURLWithPath: "")` is the process's current directory, so the
    /// fallback would open a folder nobody asked about.
    ///
    /// `traits` answers whether the enclosing folder is a directory and whether
    /// it is a package, so the bundle decision is testable without a real `.app`.
    /// It returns `nil` for a folder that is not there (most often an unmounted
    /// volume), and then there is nothing to reveal.
    ///
    /// This is also the answer to «will the button do anything», pure and
    /// available before the button is drawn.
    static func target(
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
    /// It returns nothing: `activateFileViewerSelecting` reports nothing, so
    /// «could anything be shown» is `target(for:)`'s answer, asked before the
    /// button is drawn. Finder is activated by its running instance rather than
    /// opened again, which raises the window that was just opened.
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
