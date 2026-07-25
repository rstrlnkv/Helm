import Foundation

/// Finder calls `/Applications` "Программы" in Russian and "プログラム" in
/// Japanese. Those names come from macOS's own SystemFolderLocalizations
/// table, keyed by the English folder name — but only for the folders macOS
/// actually localizes, which is why eligibility is decided by path, not by
/// name: a project folder called "Documents" stays "Documents".
///
/// The lookup deliberately ignores the process's own localization: Helm picks
/// its language itself (see `AppLanguage`), so the caller passes the code.
public enum SystemFolderNames {
    private static let localizationsRoot =
        "/System/Library/CoreServices/SystemFolderLocalizations"

    /// Folders macOS localizes at the root of a volume.
    private static let topLevel: Set<String> = [
        "Applications", "Library", "System", "Users", "Network",
    ]

    /// Folders macOS localizes inside a home directory.
    private static let inHome: Set<String> = [
        "Applications", "Desktop", "Documents", "Downloads", "Library",
        "Movies", "Music", "Pictures", "Public", "Sites",
    ]

    /// The English key macOS would translate for this path, or nil when the
    /// path is not one of its localized folders.
    public static func key(forPath path: String, home: String) -> String? {
        let trimmed = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        let name = (trimmed as NSString).lastPathComponent
        let parent = (trimmed as NSString).deletingLastPathComponent
        if parent == "/" { return topLevel.contains(name) ? name : nil }
        if parent == home { return inHome.contains(name) ? name : nil }
        return nil
    }

    /// The localized name, or nil when there is nothing to translate.
    public static func display(path: String, home: String, language: String) -> String? {
        guard language != "en", let key = key(forPath: path, home: home),
              let translated = table(for: language)[key], translated != key
        else { return nil }
        return translated
    }

    // MARK: - Table

    private static let cache = TableCache()

    private static func table(for language: String) -> [String: String] {
        if let hit = cache.get(language) { return hit }
        let path = localizationsRoot + "/" + language + ".lproj/SystemFolderLocalizations.strings"
        let loaded = (NSDictionary(contentsOfFile: path) as? [String: String]) ?? [:]
        cache.set(language, loaded)
        return loaded
    }

    /// The table is a few dozen strings read once per language; the box keeps
    /// that off the filesystem for every row the ring draws.
    private final class TableCache: @unchecked Sendable {
        private let lock = NSLock()
        private var tables: [String: [String: String]] = [:]

        func get(_ language: String) -> [String: String]? {
            lock.lock(); defer { lock.unlock() }
            return tables[language]
        }

        func set(_ language: String, _ table: [String: String]) {
            lock.lock(); tables[language] = table; lock.unlock()
        }
    }
}
