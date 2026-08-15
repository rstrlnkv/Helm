import Foundation

/// A name nothing is using yet — `a.pdf`, then `a 2.pdf`, then `a 3.pdf`, the
/// way the Finder numbers a copy.
///
/// Overwriting is the one failure this module could commit that nobody could
/// undo, so both directions number: a rule moving a file into a folder that
/// already holds the name, and a return putting a file back under a name
/// something else has taken since. It was written once for the first and would
/// have been written twice for the second.
///
/// `taken` rather than a `FileManager` call, because the two callers ask
/// different things: the runner asks the filesystem, the return asks it through
/// the port every one of its readings goes through.
enum FreeName {

    /// Nine hundred and ninety-seven tries, then the name itself — a folder
    /// holding `a 2` through `a 999` is not a collision, it is somebody's
    /// scripted output, and the caller's own guards are what stop the write.
    static func beside(_ url: URL, taken: (String) -> Bool) -> URL {
        guard taken(url.path) else { return url }
        let folder = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        for index in 2...999 {
            let name = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            let candidate = folder.appendingPathComponent(name)
            if !taken(candidate.path) { return candidate }
        }
        return url
    }
}
