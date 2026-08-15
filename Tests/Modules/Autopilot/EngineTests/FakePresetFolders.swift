import Foundation
import Module_Autopilot_Engine

/// A stand-in for the two folders `FileManager` is asked about.
///
/// **It can be in every state the real read can.** `~/Downloads` is not a
/// constant: it can be moved to another disk, it can be a symbolic link to
/// somewhere outside the home directory, and `FileManager` can decline to name
/// it at all. A fake that answered `~/Downloads` for ever would make all three
/// of those states unrepresentable — and each of them is a state in which a
/// preset must *not* be offered, or must be offered against a different path
/// than the one anybody would have guessed.
///
/// What it deliberately cannot say is how deep a folder is watched. That is a
/// fact about the folder in the person's rule set, not about where the system
/// keeps it, and a resolver free to plant it would be freer than the port it
/// stands for.
struct FakePresetFolders: PresetFolderPort {
    /// Where each folder is, or nothing when the system will not say. Absent
    /// and present-but-nil are the same answer here, which is the port's own
    /// shape.
    var paths: [PresetFolder: String]

    init(_ paths: [PresetFolder: String]) { self.paths = paths }

    /// An ordinary Mac: both folders where they were installed.
    init(home: String) {
        self.init([.desktop: home + "/Desktop", .downloads: home + "/Downloads"])
    }

    func path(of folder: PresetFolder) -> String? { paths[folder] }
}
