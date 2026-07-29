import Foundation

/// What a directory holds, as paths.
///
/// Written twice, byte for byte, in the two engines that hunt for what an
/// application left behind — `FileSystemLeftovers.children` and
/// `FMFileSystem.children`. It sits beside `FileWeight` because the two are
/// always used together: list a `~/Library` folder, then weigh what came back.
public enum DirectoryListing {

    /// The directory's entries as full URLs, hidden ones included.
    ///
    /// A missing directory is empty rather than an error: both scanners ask
    /// about folders that need not exist — a machine that has never run a
    /// sandboxed app has no `Group Containers` — and "not there" and "nothing
    /// in it" lead to the same finding.
    public static func children(of url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(atPath: url.path))?
            .map { url.appendingPathComponent($0) } ?? []
    }
}
