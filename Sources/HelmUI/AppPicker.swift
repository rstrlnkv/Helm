import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Resolve a bundle ID to a display name + icon (shared by every module that
/// lists apps).
public enum AppInfo {
    public static func resolve(_ bundleID: String) -> (name: String, icon: NSImage) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
            return (name, NSWorkspace.shared.icon(forFile: url.path))
        }
        return (bundleID, NSWorkspace.shared.icon(for: .applicationBundle))
    }
}

/// Present an open-panel to pick one or more apps; returns their bundle IDs.
public enum AppPicker {
    @MainActor public static func choose() -> [String] {
        let panel = NSOpenPanel()
        panel.title = L("Choose apps", [.ru: "Выбор приложений", .es: "Elegir apps", .fr: "Choisir des apps",
                                        .de: "Apps auswählen", .ja: "アプリを選択", .zh: "选择应用", .pt: "Escolher apps"])
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
    }
}
