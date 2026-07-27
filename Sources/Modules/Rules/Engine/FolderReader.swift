import Foundation
import HelmRuntime
import UniformTypeIdentifiers

/// The one place that turns files into `FileFacts`.
///
/// Everything above it is arithmetic on those facts; keeping the reading in one
/// small type is what makes that true. It also means the answer to "what does a
/// rule know about a file" is a single file to read.
public struct FolderReader: Sendable {

    public init() {}

    /// The files a folder's rules will be offered, at the folder's depth.
    ///
    /// Depth 1 is the folder's own contents. Deeper is the folder's own
    /// setting, and the enumerator is told to skip package contents at every
    /// depth: an `.app` or an `.rtfd` is one thing to a person, and descending
    /// into it would offer a rule several hundred files that are not files as
    /// far as anybody is concerned.
    public func facts(in folder: String, depth: Int, now: Date = Date()) -> [FileFacts] {
        let root = URL(fileURLWithPath: folder)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .fileSizeKey,
                                      .addedToDirectoryDateKey, .contentModificationDateKey,
                                      .creationDateKey, .tagNamesKey, .contentTypeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }

        var found: [FileFacts] = []
        for case let url as URL in enumerator {
            if enumerator.level > depth { enumerator.skipDescendants(); continue }
            if let facts = facts(of: url, keys: keys, now: now) { found.append(facts) }
        }
        return found
    }

    /// One file. Used by the watcher, which is told about a path rather than a
    /// folder.
    public func facts(of url: URL, now: Date = Date()) -> FileFacts? {
        facts(of: url, keys: [.isDirectoryKey, .isPackageKey, .fileSizeKey,
                              .addedToDirectoryDateKey, .contentModificationDateKey,
                              .creationDateKey, .tagNamesKey, .contentTypeKey], now: now)
    }

    private func facts(of url: URL, keys: [URLResourceKey], now: Date) -> FileFacts? {
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
        let isDirectory = (values.isDirectory ?? false) && !(values.isPackage ?? false)
        return FileFacts(
            name: url.lastPathComponent,
            kind: isDirectory ? .folder : kind(of: values.contentType),
            bytes: values.fileSize ?? 0,
            // `addedToDirectoryDate` is what "date added" means in the Finder
            // and it is what a Downloads rule is asking about; a file copied in
            // from elsewhere keeps its old creation date, which would make
            // "added in the last week" wrong for exactly the files people sort.
            added: values.addedToDirectoryDate ?? values.creationDate ?? Date.distantPast,
            modified: values.contentModificationDate ?? Date.distantPast,
            downloadedFrom: source(of: url),
            tags: values.tagNames ?? [],
            isDirectory: isDirectory,
            now: now)
    }

    /// The system already knows a `.heic` is an image and an `.xip` is an
    /// archive. A table of extensions here would be a second, worse answer that
    /// drifts as formats appear.
    private func kind(of type: UTType?) -> FileKind {
        guard let type else { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .archive) { return .archive }
        if type.conforms(to: .content) || type.conforms(to: .text) { return .document }
        return .other
    }

    /// `kMDItemWhereFroms` — the condition this module is worth having for.
    /// Read through the extended attribute rather than Spotlight so it works on
    /// volumes that are not indexed.
    private func source(of url: URL) -> String? {
        let attribute = "com.apple.metadata:kMDItemWhereFroms"
        let path = url.path
        let length = getxattr(path, attribute, nil, 0, 0, 0)
        guard length > 0 else { return nil }
        var data = Data(count: length)
        let read = data.withUnsafeMutableBytes { getxattr(path, attribute, $0.baseAddress, length, 0, 0) }
        guard read == length,
              let list = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let urls = list as? [String]
        else { return nil }
        return urls.first { !$0.isEmpty }
    }
}
