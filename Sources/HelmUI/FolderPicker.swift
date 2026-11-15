import AppKit

/// The system's folder chooser, run modally — one folder, directories only.
///
/// Beside `AppPicker`, because six pages had each built this panel by hand. It
/// stores and seals nothing: the caller takes the URL to its own gate and setter,
/// which is where the authority of "a person just chose this" is spent.
public enum FolderPicker {
    /// The chosen folder, nil when cancelled.
    ///
    /// `canCreate` is set on the panel only when true, and `activate` brings Helm
    /// forward only when true, so a caller that never did either keeps the panel's
    /// own default and sees no New Folder button appear.
    @MainActor public static func choose(prompt: String?, startingAt: URL?,
                                         canCreate: Bool, activate: Bool) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if let prompt { panel.prompt = prompt }
        if let startingAt { panel.directoryURL = startingAt }
        if canCreate { panel.canCreateDirectories = true }
        if activate { NSApp.activate(ignoringOtherApps: true) }
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
