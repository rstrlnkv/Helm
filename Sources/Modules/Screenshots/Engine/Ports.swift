import CoreGraphics
import Foundation

// The four things the engine asks the machine, each a protocol with a fake that
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
    /// The window's own pixels — its shadow unless the caller asked for none, a transparent background, and
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
    /// One window over a transparent ground. With `shadow` — the default of the
    /// pick — its shadow is in the picture, so it is larger than the window's
    /// frame; without it (an option-click) the system is asked to leave the
    /// shadow out.
    func window(_ id: UInt32, cursor: Bool, shadow: Bool) async -> WindowShot
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

public enum ShotWrite: Sendable, Equatable {
    case written(URL)
    case refused(WriteRefusal)
}

/// Writing one picture into a folder without ever replacing a file.
///
/// `base` is the name without an extension and `pathExtension` the one the bytes
/// are in ("png", "jpg"); the port finds the first free one with `ShotNames.candidate`, and **a name taken is not an error**. The
/// answer is the file actually written, because the name asked for may not be it.
public protocol ShotWriting: Sendable {
    func write(_ data: Data, into folder: URL, base: String, pathExtension: String) -> ShotWrite
}

public enum PasteOutcome: Sendable, Equatable {
    case accepted, refused
}

public protocol ShotPasteboard: Sendable {
    func copy(png: Data) -> PasteOutcome
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
