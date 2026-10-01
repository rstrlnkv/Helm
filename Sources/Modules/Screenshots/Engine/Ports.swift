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
    /// order, in one go. Helm's own windows are not in either.
    func freeze() async -> FreezeOutcome
    func window(_ id: UInt32) async -> WindowShot
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
/// `base` is the name without an extension; the port finds the first free one
/// with `ShotNames.candidate`, and **a name taken is not an error**. The
/// answer is the file actually written, because the name asked for may not be it.
public protocol ShotWriting: Sendable {
    func write(_ png: Data, into folder: URL, base: String) -> ShotWrite
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

/// What macOS says about itself in two preference domains Helm only **reads**.
///
/// Neither is ever written: `com.apple.screencapture` is where macOS keeps the
/// save folder, and `com.apple.symbolichotkeys` is where it keeps which of its
/// own shortcuts are ticked. Changing a system shortcut is the person's act in
/// System Settings; Helm opens the pane and says what to untick.
public protocol CapturePreferences: Sendable {
    /// `location`, raw. **Every reason it may be empty is `nil`:** the key is
    /// absent, which is the ordinary state, and nothing distinguishes that from
    /// a domain that could not be read. `SaveLocation` treats both as "use the
    /// Desktop", and neither is worth a log line.
    func location() -> RawSetting
    func symbolicHotkeys() -> SymbolicHotkeysReading
}
