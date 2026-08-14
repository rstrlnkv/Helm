import Foundation

/// What reading a watched folder came to.
///
/// **The three used to be one value.** An empty folder, a folder Helm may not
/// read and a folder that no longer exists all reached the page as `examined 0,
/// acted 0` — the same sentence for a folder with nothing to do, a folder behind
/// a permission and a folder somebody renamed. The commonest way this module
/// dies is the middle two, and neither said a word.
///
/// No error code: what the page has to say is which of the three it was, and a
/// number in a sentence would be a code shown to somebody who cannot act on it.
/// The log carries the reason.
public enum FolderState: String, Codable, Equatable, Sendable {
    /// Helm read the folder. It may well have been empty — that is a folder with
    /// nothing to do, and it is the only one of these three that is fine.
    case read
    /// There is nothing at that path any more.
    case missing
    /// It is there and Helm was not allowed to look inside it.
    case refused
}

/// A folder as the reader found it: what was in it, and whether it could be
/// looked into at all.
///
/// The files and the state travel together because every caller needs both and a
/// caller that took only the files is exactly the defect this closes.
struct FolderReading: Equatable {
    let state: FolderState
    let files: [FileFacts]

    static func read(_ files: [FileFacts]) -> FolderReading {
        FolderReading(state: .read, files: files)
    }

    static let missing = FolderReading(state: .missing, files: [])
    static let refused = FolderReading(state: .refused, files: [])
}
