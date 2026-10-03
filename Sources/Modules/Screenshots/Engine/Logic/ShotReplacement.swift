import Foundation

/// Whether the file at a shot's path is still the file the shot wrote.
///
/// Asked of a stored reading and a fresh one, twice in the life of an edit: before the pixels are read for the
/// editor, and at the move of the original to the Trash (`CaptureSession.replace`). The same question Autopilot's
/// return asks before it moves a file back (`UndoRunner`, `notTheSameFile`), with the size and the time on top of the
/// identity: a program that writes into a file in place leaves its inode as it was.
public enum ShotReplacement {
    public enum Verdict: Sendable, Equatable {
        /// The same plain file, the same size, last written at the same moment.
        case same
        /// Nothing is at the path: renamed, moved away or deleted, or not to be read (`ShotWriting.reading`).
        case missing
        /// Something is at the path and it is not what was written: another file, a link, a folder, or the same
        /// file written into since.
        case changed
    }

    public static func verdict(stored: ShotReading, now: ShotReading?) -> Verdict {
        guard let now else { return .missing }
        // A stored reading of something that is not a plain file is of nothing this module wrote.
        guard stored.isRegularFile, now.isRegularFile,
              now.identity == stored.identity,
              now.size == stored.size,
              now.modifiedSeconds == stored.modifiedSeconds,
              now.modifiedNanoseconds == stored.modifiedNanoseconds
        else { return .changed }
        return .same
    }
}
