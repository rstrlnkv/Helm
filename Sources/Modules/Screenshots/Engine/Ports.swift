import CoreGraphics
import Foundation
import HelmRuntime

// The things the engine asks the machine, each a protocol with a fake that
// holds every state the real one has. A simpler fake makes a failure
// unrepresentable rather than untested: a capture port that can only succeed
// proves nothing about what a denied grant does.

/// Whether this process may read the screen.
enum CaptureAccess: Sendable, Equatable {
    case granted, denied
}

/// What taking the frozen frame came back with.
enum FreezeOutcome: @unchecked Sendable {
    case frozen(Freeze)
    /// The grant was withdrawn between the preflight and the capture. macOS can
    /// do that, and the answer is a refusal and not an empty file: the pictures
    /// it would otherwise have returned are all-black or all-wallpaper.
    case denied
    case failed
}

/// What asking for one window came back with.
enum WindowShot: @unchecked Sendable {
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
protocol ScreenCapturing: Sendable {
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

/// What a file was at one moment: who it is and what `stat` said of it.
///
/// **A reading, never the file.** It is taken when the shot is written and compared with a fresh one before the file
/// is opened for an edit and again before it is moved to the Trash (`ShotReplacement.verdict`). The identity alone
/// would not do: a program that writes into the file in place keeps the inode, so the size and the modification time
/// are compared too. The time is carried as the two integers `stat` gives, never added up.
public struct ShotReading: Sendable, Equatable {
    let identity: PathCanonical.FileIdentity
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    /// False for a link, a folder and everything else that is not a plain file.
    let isRegularFile: Bool
}

extension ShotReading {
    /// What `fstat` or `lstat` answered.
    init(_ info: stat) {
        self.init(identity: PathCanonical.FileIdentity(status: info),
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

enum ShotWrite: Sendable, Equatable {
    case written(WrittenShot)
    case refused(WriteRefusal)
}

/// Writing one picture into a folder without ever replacing a file.
///
/// `base` is the name without an extension and `pathExtension` the one the bytes
/// are in ("png", "jpg"); the port finds the first free one with `ShotNames.candidate`, and **a name taken is not an error**. The
/// answer is the file actually written, because the name asked for may not be it, with the reading of it taken
/// from the descriptor it was written through, before it was given its name.
protocol ShotWriting: Sendable {
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
protocol ShotTrashing: Sendable {
    func trash(_ url: URL) throws
}

enum PasteOutcome: Sendable, Equatable {
    case accepted, refused
}

/// The clipboard. **Every entry marks what it puts there as not for a clipboard history** (see
/// `SystemShotPasteboard`): a picture of a screen and the words read off one are the same kind of thing, and
/// both are often what a person did not mean to keep.
protocol ShotPasteboard: Sendable {
    func copy(png: Data) -> PasteOutcome
    /// Several pictures in **one write**, each an item of its own, in the order given. A group copied picture by
    /// picture would be as many writes, each taking the board from the one before, and only the last would be
    /// there to paste. A refusal leaves none of them promised: the board says yes or no to the write, not to an item.
    func copy(pngs: [Data]) -> PasteOutcome
    /// Text read off a picture. Never recorded anywhere by the engine: it is somebody's words.
    func copy(text: String) -> PasteOutcome
}

/// What a match found in a line of text is. This list is what the blur that finds personal text blurs, and the
/// hint of its menu item names exactly it: a postal address is not here, because it was not measured to be found
/// in every language, and a kind the reader finds that is not here is dropped by the reader.
enum PrivateKind: Sendable, Equatable {
    case emailAddress, phoneNumber, cardNumber, link
}

/// One match inside a line, and where it is: `box` is in Vision's normalised coordinates of the picture that
/// was read, the origin at its **lower** left, each side a fraction of the picture's.
/// The engine acts alike on every kind (each is one blur), so `kind` is the reading's account of what was found,
/// read by no branch in `Sources`.
/// **A find that wraps over two lines is one match on its first line only** (see `VisionTextReader`).
struct PrivateMatch: Sendable, Equatable {
    let kind: PrivateKind
    let box: CGRect
}

/// One line of text as the system read it, with the matches found in it. `box` is normalised like a match's.
/// Never in a log line and never stored: `string` is somebody's words.
public struct RecognizedLine: Sendable, Equatable {
    let string: String
    let box: CGRect
    let matches: [PrivateMatch]

    init(string: String, box: CGRect, matches: [PrivateMatch] = []) {
        self.string = string
        self.box = box
        self.matches = matches
    }
}

/// What reading a picture's text came back with.
enum TextReading: Sendable, Equatable {
    /// The lines, **in reading order**. An empty list is a reading that found nothing.
    case read([RecognizedLine])
    /// The system could not be asked, or did not answer.
    case failed
}

/// The system's text recognition, as far as the engine is concerned.
///
/// **`.read([])` has several causes and the engine cannot tell them apart:** a picture with no text in it, text
/// too small or too faint for the recogniser, a script or language it does not read, text that is a photograph
/// of text. All of them are "nothing was found", and none is "there is nothing there" — a caller never says the
/// second. `.failed` is the request throwing, being cancelled, or the system's models not being there. The
/// call may take long the first time on a Mac, and it is awaited off the cooperative pool.
protocol ScreenTextReading: Sendable {
    func read(_ image: CGImage) async -> TextReading
}

/// A preference value that could be anything at all, carried across a queue.
/// `@unchecked` because a property-list value is immutable and the only things
/// in one are value types and their immutable Foundation bridges.
public struct RawSetting: @unchecked Sendable {
    let value: Any?
    init(_ value: Any?) { self.value = value }
}

/// What macOS says about itself in three preference reads Helm only **reads**.
///
/// None is ever written: `com.apple.screencapture` is where macOS keeps the
/// save folder, `com.apple.symbolichotkeys` is where it keeps which of its
/// own shortcuts are ticked, and the global domain holds the interface-sound switch.
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
protocol ShutterPlaying: Sendable {
    func play()
}
