import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Resolve a bundle ID to a display name + icon (shared by every module that
/// lists apps).
///
/// Both memos below are `nonisolated(unsafe)` and neither takes a lock, because
/// `NSCache` does its own — it is documented as safe to use from several threads
/// without one. Every caller draws on the main thread, which is what makes
/// handing the same `NSImage` back to all of them safe.
public enum AppInfo {
    /// The pair, so one id is one cache entry rather than two that can disagree.
    private final class Resolved {
        let name: String
        let icon: NSImage
        init(name: String, icon: NSImage) { self.name = name; self.icon = icon }
    }

    /// LaunchServices for the path, `FileManager` for the display name and
    /// `NSWorkspace` for the icon — three trips to the system, about 0.14 ms
    /// together, and `HelmAppRuleRow` asks for them in its **initialiser**.
    /// Three modules draw lists of those rows, so every filter keystroke and
    /// every scroll paid for the whole visible list again.
    ///
    /// Nothing invalidates it: an app renamed or moved while Helm is running
    /// keeps the name and icon it had until the next launch. That is the answer
    /// this app has always given — the Uninstaller's own icon memo has never
    /// invalidated either — and the price of the alternative is watching
    /// LaunchServices for a change nobody has reported noticing.
    nonisolated(unsafe) private static let resolved = NSCache<NSString, Resolved>()

    public static func resolve(_ bundleID: String) -> (name: String, icon: NSImage) {
        if let hit = resolved.object(forKey: bundleID as NSString) { return (hit.name, hit.icon) }
        let answer: Resolved
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
            answer = Resolved(name: name, icon: icon(forFile: url.path))
        } else {
            answer = Resolved(name: bundleID,
                              icon: NSWorkspace.shared.icon(for: .applicationBundle))
        }
        resolved.setObject(answer, forKey: bundleID as NSString)
        return (answer.name, answer.icon)
    }

    /// Bundle ids in the order the names they draw would be read.
    ///
    /// **A list stored by key and read by name.** Two settings pages held their
    /// app rules in a `[String: Rule]` and drew `keys.sorted()`, which is
    /// `com.apple.Safari` before `com.tinyapp.Zed` before `org.mozilla.firefox`
    /// — Safari, Zed, Firefox on screen, an order with no rule in it. Here
    /// rather than in either page for the reason every other shared drawing
    /// decision is: the second copy is where they drift.
    ///
    /// `localizedStandardCompare` is the Finder's own comparison — case
    /// insensitive, and a run of digits read as a number, so «Ableton 9» comes
    /// before «Ableton 10». The id breaks a tie, because two apps can carry one
    /// name and a list that reshuffles under the pointer is not sorted.
    ///
    /// Each id is resolved **once** rather than at every comparison a sort
    /// makes, which is the same question asked per pair instead of per item.
    ///
    /// - Parameter name: how an id becomes the word the row shows. Defaulted to
    ///   `resolve`, and an argument so the order can be tested without asking
    ///   this Mac what it has installed.
    public static func sortedByName(_ bundleIDs: some Sequence<String>,
                                    name: (String) -> String = { resolve($0).name }) -> [String] {
        bundleIDs.map { (id: $0, name: name($0)) }
            .sorted { left, right in
                switch left.name.localizedStandardCompare(right.name) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: return left.id < right.id
                }
            }
            .map(\.id)
    }

    /// The icon of a bundle whose **path** is what the caller has.
    ///
    /// A separate question from `resolve`, not a shortcut into it: the callers
    /// that need this are drawing bundles sitting in `~/.Trash`, and
    /// `urlForApplication(withBundleIdentifier:)` answers for what is installed
    /// — so the id would resolve to the copy still in `/Applications`, or to
    /// nothing. `icon(forFile:)` hits the disk, and a List re-renders its rows
    /// far more often than the disk changes.
    nonisolated(unsafe) private static let icons = NSCache<NSString, NSImage>()

    public static func icon(forFile path: String) -> NSImage {
        if let hit = icons.object(forKey: path as NSString) { return hit }
        let made = NSWorkspace.shared.icon(forFile: path)
        icons.setObject(made, forKey: path as NSString)
        return made
    }
}

/// Present an open-panel to pick one or more apps; returns their bundle IDs.
public enum AppPicker {
    @MainActor public static func choose() -> [String] {
        chooseApps().map(\.bundleID)
    }

    /// The same panel, with **where each chosen app is** as well as what it calls
    /// itself.
    ///
    /// A bundle identifier is a string in a plist anybody can write, so a caller
    /// that wants to bind a rule to the app a person actually pointed at needs the
    /// path: `CodeIdentity.of(bundleAt:)` reads the signature there, and the choice
    /// in front of a file dialog is the only moment that path is somebody's
    /// deliberate answer. VPN's rules record it; the two callers that watch apps
    /// without acting on their behalf still take `choose()`.
    @MainActor public static func chooseApps() -> [(bundleID: String, url: URL)] {
        let panel = NSOpenPanel()
        panel.title = L("Choose apps")
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap { url in
            Bundle(url: url)?.bundleIdentifier.map { (bundleID: $0, url: url) }
        }
    }
}
