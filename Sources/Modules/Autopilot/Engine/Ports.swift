import Foundation
import HelmRuntime

/// Where this Mac keeps the two folders the presets are about.
///
/// A port, because it is the one part of a preset that is not a constant:
/// `~/Downloads` can be moved, and a Mac in another language keeps it under the
/// same path with a different display name. Reading the path out of
/// `FileManager` is the only way to be right about both — and a seam is what
/// lets a test stand a moved Downloads, or one that leads out of the home
/// directory, in front of the gate.
public protocol PresetFolderPort: Sendable {
    /// The folder's path, or nothing when the system will not say — which is
    /// not «the default place»: guessing `~/Downloads` for a Mac that keeps it
    /// elsewhere is how a rule comes to watch a folder nobody meant.
    func path(of folder: PresetFolder) -> String?
}

/// Where the mark is kept, as a port: the production answer is a keychain item
/// whose access list names only Helm, and a test must not write to the user's.
public protocol RuleSequencePort: Sendable {
    func highWater() -> RuleSequence
    /// Records a new mark. False when it could not be written — which costs a
    /// save nothing and leaves the rollback window one save wide.
    @discardableResult
    func raise(to seq: UInt64) -> Bool
}

/// Everything a return asks of the disk.
///
/// A port for the reason `RuleRunner`'s `ancestry` is a seam and for one more:
/// the states this has to tell apart are states a test cannot conjure on the
/// machine running the suite. A volume that will not keep an extended
/// attribute, a directory swapped for a symlink between two syscalls, a Trash
/// emptied mid-decision — each is a branch that decides whether somebody's file
/// moves, and each is unreachable from a temporary folder.
protocol UndoFiles: Sendable {
    /// Who is at `path`, by `lstat`, or nothing when there is nothing.
    func identity(of path: String) -> PathCanonical.FileIdentity?
    /// Where `path`'s resolved parent chain leads *now*.
    func ancestry(of path: String) -> PathCanonical.AncestryIdentity?
    func directoryExists(_ path: String) -> Bool
    func move(_ from: String, to: String) throws
    func tags(of path: String) throws -> [String]
    func setTags(_ tags: [String], on path: String) throws
    /// Whether the mark stuck.
    func stamp(_ path: String, rule: String, key: Data) -> Bool
}
