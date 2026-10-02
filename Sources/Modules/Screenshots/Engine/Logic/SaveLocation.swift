import Foundation

/// Why the folder macOS names was not the one used.
public enum SaveFolderRefusal: String, Sendable, Codable, Equatable {
    /// `location` held something that is not a path: a number, data, a list.
    case notAPath
    /// An empty string, or only whitespace.
    case empty
    /// Not absolute, so it names nothing until some working directory says
    /// where "Pictures" is — and this process has none worth trusting.
    case relative
    case missing
    /// A file is there, not a folder.
    case notAFolder
    /// A folder the person may not write into.
    case notWritable
}

/// Where a screenshot goes.
public struct SaveFolder: Equatable, Sendable {
    public let url: URL
    /// Nil when the answer is macOS's own, or the plain Desktop with nothing
    /// asked of it. Set when a `location` was there and was refused: the caller
    /// logs that, once, and the Desktop carries on.
    public let refused: SaveFolderRefusal?
}

public enum SaveLocation {

    /// The folder macOS saves into — `com.apple.screencapture`'s `location`,
    /// **read and never written** — or the Desktop.
    ///
    /// `raw` is whatever the preferences domain held, because it is a file
    /// anything running as the person can write and `defaults write location
    /// -int 5` is a legal one. Each kind of garbage is refused by name, and all
    /// of them land on the Desktop rather than on an error: a person who has
    /// pressed the shortcut wants the picture somewhere, and the folder they
    /// had in mind is a thing to tell them about, not a reason to lose it.
    ///
    /// **An absent `location` is not a refusal.** It is the commonest state of
    /// any Mac — nobody has ever changed it — and logging it would be a line
    /// per press about nothing having gone wrong.
    ///
    /// The folder is judged against the disk as it is at this call: it exists,
    /// it is a directory, and it is writable. A volume that was unplugged since
    /// the preference was set is `missing`, and the Desktop takes the picture.
    public static func resolve(raw: Any?, desktop: URL, home: URL,
                               writable: (String) -> Bool = { FileManager.default.isWritableFile(atPath: $0) }) -> SaveFolder {
        let shaped = shape(raw: raw, desktop: desktop, home: home)
        guard shaped.refused == nil, raw != nil else { return shaped }
        let url = shaped.url
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        else { return SaveFolder(url: desktop, refused: .missing) }
        guard isDirectory.boolValue else { return SaveFolder(url: desktop, refused: .notAFolder) }
        guard writable(url.path) else { return SaveFolder(url: desktop, refused: .notWritable) }
        return SaveFolder(url: url, refused: nil)
    }

    /// Everything `resolve` can say **without asking the disk**: the shape of the
    /// value and the path it spells. A view body draws from this and nothing else,
    /// because asking the disk about the Desktop or Documents is what raises a
    /// protected-folder prompt, and a body runs on every render. `url` is the
    /// path the raw value spells, or the Desktop when it spells none.
    public static func shape(raw: Any?, desktop: URL, home: URL) -> SaveFolder {
        guard let raw else { return SaveFolder(url: desktop, refused: nil) }
        guard let text = raw as? String else { return SaveFolder(url: desktop, refused: .notAPath) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return SaveFolder(url: desktop, refused: .empty) }

        let expanded: String
        if trimmed == "~" {
            expanded = home.path
        } else if trimmed.hasPrefix("~/") {
            expanded = home.path + String(trimmed.dropFirst(1))
        } else {
            expanded = trimmed
        }
        guard expanded.hasPrefix("/") else { return SaveFolder(url: desktop, refused: .relative) }
        return SaveFolder(url: URL(fileURLWithPath: expanded, isDirectory: true), refused: nil)
    }

    /// Where this capture's file goes, or nil for the clipboard, which has none.
    ///
    /// **Every folder is judged by `resolve`, the chosen one included:** the
    /// Desktop and Documents are asked by path like any other, and the folder a
    /// person chose in Helm is a string in a file anything running as them can
    /// write, so it is no more trusted than `location` is. `macOS` is
    /// `location`'s raw value, read by the caller. A target `other` with no
    /// folder stored is a refusal (`empty`) and not a quiet Desktop: somebody
    /// chose something and it is not there.
    public static func folder(for settings: ScreenshotsSettings, macOS: Any?,
                              locations: ScreenshotsLocations,
                              writable: (String) -> Bool = { FileManager.default.isWritableFile(atPath: $0) }) -> SaveFolder? {
        guard let raw = rawValue(for: settings, macOS: macOS, locations: locations) else { return nil }
        return resolve(raw: raw.value, desktop: locations.desktop, home: locations.home, writable: writable)
    }

    /// The same folder as `folder(for:)` names, without asking the disk.
    public static func shownFolder(for settings: ScreenshotsSettings, macOS: Any?,
                                   locations: ScreenshotsLocations) -> SaveFolder? {
        guard let raw = rawValue(for: settings, macOS: macOS, locations: locations) else { return nil }
        return shape(raw: raw.value, desktop: locations.desktop, home: locations.home)
    }

    private struct Raw { let value: Any? }

    private static func rawValue(for settings: ScreenshotsSettings, macOS: Any?,
                                 locations: ScreenshotsLocations) -> Raw? {
        switch settings.saveTarget {
        case .clipboard: nil
        case .macOS: Raw(value: macOS)
        case .desktop: Raw(value: locations.desktop.path)
        case .documents: Raw(value: locations.documents.path)
        case .other: Raw(value: settings.otherFolder ?? "")
        }
    }
}
