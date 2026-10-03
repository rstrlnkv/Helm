import CoreGraphics
import Foundation
import HelmRuntime

// The things the engine asks the machine, each a protocol with a fake that
// holds every state the real one has. A simpler fake makes a failure
// unrepresentable rather than untested: a capture port that can only succeed
// proves nothing about what a denied grant does.

/// Whether this process may read the screen.
public enum CaptureAccess: Sendable, Equatable {
    case granted, denied
}

/// What taking the frozen frame came back with.
public enum FreezeOutcome: @unchecked Sendable {
    case frozen(Freeze)
    /// The grant was withdrawn between the preflight and the capture. macOS can
    /// do that, and the answer is a refusal and not an empty file: the pictures
    /// it would otherwise have returned are all-black or all-wallpaper.
    case denied
    case failed
}

/// What asking for one window came back with.
public enum WindowShot: @unchecked Sendable {
    /// The window's own pixels — its shadow, a transparent background, and
    /// whatever covers it left out. **A protected window comes back black, and
    /// that is this case:** macOS hands the same black to every program, and the
    /// engine saves what it is given.
    case image(CGImage)
    /// There is no such window any more.
    case gone
    case denied
    case failed
}

/// ScreenCaptureKit, as far as the engine is concerned.
///
/// "Empty" here is never one thing: `freeze` and `window` each name their
/// reasons, because a window that closed and a grant that was withdrawn are
/// acted on differently — the first is cut from the freeze, the second ends the
/// capture.
public protocol ScreenCapturing: Sendable {
    /// A reading that never prompts.
    func access() -> CaptureAccess
    /// Asks macOS for the grant, once per installation. A process that has been
    /// refused is not asked about again by the system, so without this call Helm
    /// never appears in the Screen Recording list at all.
    func requestAccess()
    /// Every display at native scale, and the window list in front-to-back
    /// order, in one go. Helm's own windows are not in either. With `cursor`
    /// the display the pointer is on also comes back a second time with the
    /// pointer drawn in (`FrozenDisplay.withCursor`); without it that costs nothing.
    func freeze(cursor: Bool) async -> FreezeOutcome
    /// One window with its shadow, over a transparent ground, so larger than
    /// the window's frame.
    func window(_ id: UInt32, cursor: Bool) async -> WindowShot
}

/// Why a picture was not written.
public enum WriteRefusal: Sendable, Equatable {
    case noFolder
    case notAFolder
    /// EPERM, EACCES or EROFS: macOS, the folder's mode or a read-only volume says no.
    case noPermission
    /// ENOSPC, or the quota.
    case diskFull
    /// Every name from the plain one to "(999)" was taken.
    case namesExhausted
    /// Anything else, as the errno that came back.
    case failed(Int32)
}

/// What a file was at one moment: who it is and what `stat` said of it.
///
/// **A reading, never the file.** It is taken when the shot is written and compared with a fresh one before the file
/// is opened for an edit and again before it is moved to the Trash (`ShotReplacement.verdict`). The identity alone
/// would not do: a program that writes into the file in place keeps the inode, so the size and the modification time
/// are compared too. The time is carried as the two integers `stat` gives, never added up.
public struct ShotReading: Sendable, Equatable {
    public let identity: PathCanonical.FileIdentity
    public let size: Int64
    public let modifiedSeconds: Int64
    public let modifiedNanoseconds: Int64
    /// False for a link, a folder and everything else that is not a plain file.
    public let isRegularFile: Bool

    public init(identity: PathCanonical.FileIdentity, size: Int64, modifiedSeconds: Int64,
                modifiedNanoseconds: Int64, isRegularFile: Bool) {
        self.identity = identity
        self.size = size
        self.modifiedSeconds = modifiedSeconds
        self.modifiedNanoseconds = modifiedNanoseconds
        self.isRegularFile = isRegularFile
    }

    /// What `fstat` or `lstat` answered.
    public init(_ info: stat) {
        self.init(identity: PathCanonical.FileIdentity(device: UInt64(bitPattern: Int64(info.st_dev)), inode: info.st_ino),
                  size: Int64(info.st_size), modifiedSeconds: Int64(info.st_mtimespec.tv_sec),
                  modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec),
                  isRegularFile: info.st_mode & S_IFMT == S_IFREG)
    }
}

/// A file the writer made, and what it was when it was made.
public struct WrittenShot: Sendable, Equatable {
    public let url: URL
    public let reading: ShotReading

    public init(url: URL, reading: ShotReading) {
        self.url = url
        self.reading = reading
    }
}

public enum ShotWrite: Sendable, Equatable {
    case written(WrittenShot)
    case refused(WriteRefusal)

    /// The file that was written, nil for a refusal.
    public var url: URL? {
        if case .written(let shot) = self { shot.url } else { nil }
    }
}

/// Writing one picture into a folder without ever replacing a file.
///
/// `base` is the name without an extension and `pathExtension` the one the bytes
/// are in ("png", "jpg"); the port finds the first free one with `ShotNames.candidate`, and **a name taken is not an error**. The
/// answer is the file actually written, because the name asked for may not be it, with the reading of it taken
/// from the descriptor it was written through, before it was given its name.
public protocol ShotWriting: Sendable {
    func write(_ data: Data, into folder: URL, base: String, pathExtension: String) -> ShotWrite
    /// What is at `url` now, by `lstat`: a link answers for itself, not for what it points at. **Every reason there
    /// is nothing to read is `nil`:** no such name, a folder above it gone, a folder above it that may not be
    /// searched. `ShotReplacement.verdict` reads all of them as `.missing`, and every one of them refuses.
    func reading(of url: URL) -> ShotReading?
    /// Gives `written` the name `name`, **only when that name is free**. False for every reason it did not: the name
    /// is taken, `written` is gone, the volume refused. The caller does one thing with all of them, which is to
    /// leave `written` under the name it has.
    func claim(_ written: URL, as name: URL) -> Bool
}

/// The move to the Trash, as a port: `CaptureSession` hands it to `HelmTrash.remove` as its `trashing`, which keeps
/// the batch's rules there and lets a fake say what was moved and when. It throws what `FileManager.trashItem`
/// throws, because `HelmTrash` reads the error's code.
public protocol ShotTrashing: Sendable {
    func trash(_ url: URL) throws
}

public enum PasteOutcome: Sendable, Equatable {
    case accepted, refused
}

public protocol ShotPasteboard: Sendable {
    func copy(png: Data) -> PasteOutcome
    /// Several pictures in **one write**, each an item of its own, in the order given. A group copied picture by
    /// picture would be as many writes, each taking the board from the one before, and only the last would be
    /// there to paste. A refusal leaves none of them promised: the board says yes or no to the write, not to an item.
    func copy(pngs: [Data]) -> PasteOutcome
}

/// A preference value that could be anything at all, carried across a queue.
/// `@unchecked` because a property-list value is immutable and the only things
/// in one are value types and their immutable Foundation bridges.
public struct RawSetting: @unchecked Sendable {
    public let value: Any?
    public init(_ value: Any?) { self.value = value }
}

/// What macOS says about itself in three preference reads Helm only **reads**.
///
/// None is ever written: `com.apple.screencapture` is where macOS keeps the
/// save folder, `com.apple.symbolichotkeys` is where it keeps which of its
/// own shortcuts are ticked, and the global domain holds the interface-sound switch. Changing a system shortcut is the person's act in
/// System Settings; Helm opens the pane and says what to untick.
public protocol CapturePreferences: Sendable {
    /// `location`, raw. **Every reason it may be empty is `nil`:** the key is
    /// absent, which is the ordinary state, and nothing distinguishes that from
    /// a domain that could not be read. `SaveLocation` treats both as "use the
    /// Desktop", and neither is worth a log line.
    func location() -> RawSetting
    func symbolicHotkeys() -> SymbolicHotkeysReading
    /// `com.apple.sound.uiaudio.enabled` in the global domain, raw. **Every
    /// reason it may be empty is `nil`:** the key is absent, which is the
    /// ordinary state and means on, and nothing tells that from a domain that
    /// could not be read — `ShutterRule` reads both as on.
    func uiSounds() -> RawSetting
}

/// The shutter. Fire and forget: it returns at once and says nothing, because a
/// sound that could not be played is not worth a refusal toast. Whether to play
/// is the session's decision (`CaptureSession.shutter`) and when is the caller's.
public protocol ShutterPlaying: Sendable {
    func play()
}

/// Where the Dock is, as the Dock itself says through Accessibility.
///
/// **Optional by design:** the module declares no Accessibility permission and never
/// asks for it; a Mac that has granted it to Helm for another module gets the Dock's
/// exact bounds, any other gets `.notTrusted` and the strip. Main thread only, because
/// it is an AppKit-side system call. `pid` is the Dock's process, from the window list.
public protocol DockBounds: Sendable {
    func read(dockPID pid: pid_t) -> DockBoundsReading
}
