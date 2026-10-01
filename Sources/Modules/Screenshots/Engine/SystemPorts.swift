import AppKit
import CoreGraphics
import Darwin
import Foundation
import HelmRuntime
import ScreenCaptureKit

// MARK: - The screen

private struct Unshared<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// ScreenCaptureKit, and the window list from CoreGraphics.
///
/// The display images and a single window's pixels come from ScreenCaptureKit;
/// the window *list* comes from `CGWindowListCopyWindowInfo` because it is
/// documented to answer front to back, which `SCShareableContent.windows` is
/// not, and the order is what "the window under the pointer" means.
///
/// Helm's own windows are left out of both, by process id: the overlay and the
/// thumbnail are Helm's, and a screenshot of the screenshot's own frame is the
/// defect this excludes.
public final class SCKCapture: ScreenCapturing, @unchecked Sendable {
    private let store: NamespacedStore

    public init(store: NamespacedStore = NamespacedStore(namespace: ScreenshotsEngine.moduleID,
                                                         backing: UserDefaults.standard)) {
        self.store = store
    }

    public func access() -> CaptureAccess {
        CGPreflightScreenCaptureAccess() ? .granted : .denied
    }

    /// Once per installation, and recorded before the call: `CGWindow.h` says a
    /// previously denied process is not re-prompted, so asking on every refused
    /// press would be a call that does nothing. The request is also how a process
    /// that macOS has never heard of is put in front of the person, which is the
    /// reason to make it at all — that part is the header's intent and was not
    /// observed here. It returns at once and its dialog is the system's, so the
    /// answer is read on the next press.
    public func requestAccess() {
        guard !store.bool("screenRecordingAsked", default: false) else { return }
        store.set(true, for: "screenRecordingAsked")
        _ = CGRequestScreenCaptureAccess()
    }

    public func freeze(cursor: Bool) async -> FreezeOutcome {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            return Self.isDeclined(error) ? .denied : .failed
        }
        let me = ProcessInfo.processInfo.processIdentifier
        let own = content.applications.filter { $0.processID == me }
        // Main first: the full-screen shortcut's clipboard takes the first picture.
        let main = CGMainDisplayID()
        let displays = content.displays.sorted { $0.displayID == main && $1.displayID != main }

        // All displays at once — the freeze is on the critical path of the
        // overlay appearing, and two displays taken in turn cost twice as long.
        // With the pointer asked for, the second frame is taken in the same task,
        // beside the first and not after it — and only of the display the pointer
        // is on: the others show no pointer, so theirs would be the same picture
        // again at a cost per display (measured: about 65 ms more over three
        // displays when every one took it).
        let pointer = cursor ? CGEvent(source: nil)?.location : nil
        let outcomes: [(Int, DisplayShot?)] = await withTaskGroup(of: (Int, DisplayShot?).self) { group in
            // The two ScreenCaptureKit objects are immutable descriptions the
            // framework hands out for exactly this use, and are not declared
            // `Sendable`; the box says so once.
            let shared = Unshared(own)
            for (index, display) in displays.enumerated() {
                let target = Unshared(display)
                group.addTask {
                    (index, await Self.capture(target.value, excluding: shared.value, pointer: pointer))
                }
            }
            var collected: [(Int, DisplayShot?)] = []
            for await outcome in group { collected.append(outcome) }
            return collected.sorted { $0.0 < $1.0 }
        }
        // `nil` is a display the system declined to capture for lack of the grant.
        if outcomes.contains(where: { $0.1 == nil }) { return .denied }
        return .frozen(Freeze(displays: outcomes.compactMap(\.1), windows: Self.windowList(excluding: me)))
    }

    private static func capture(_ display: SCDisplay, excluding own: [SCRunningApplication],
                                pointer: CGPoint?) async -> DisplayShot? {
        let cursor = pointer.map { display.frame.contains($0) } ?? false
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        let scale = CGFloat(SCShareableContent.info(for: filter).pointPixelScale)
        let width = Int((CGFloat(display.width) * scale).rounded())
        let height = Int((CGFloat(display.height) * scale).rounded())
        let target = Unshared(filter)
        // The overlay's picture never has the pointer in it, and the cut's does
        // when asked: `FrozenDisplay` says why there are two.
        async let plain = frame(target, width: width, height: height, pointer: false)
        async let pointed: Unshared<CGImage>? = cursor
            ? try? await frame(target, width: width, height: height, pointer: true) : nil
        do {
            let image = try await plain.value
            let withCursor = await pointed?.value
            if cursor, withCursor == nil {
                HelmLog.shared.warn(ScreenshotsEngine.moduleID, "the frame with the pointer could not be captured; the picture has none")
            }
            return .image(FrozenDisplay(id: DisplayID(display.displayID), frame: display.frame,
                                        scale: scale, image: image, withCursor: withCursor,
                                        uuid: uuid(of: display.displayID)))
        } catch {
            return isDeclined(error) ? nil : .gone(DisplayID(display.displayID))
        }
    }

    private static func frame(_ filter: Unshared<SCContentFilter>, width: Int, height: Int,
                              pointer: Bool) async throws -> Unshared<CGImage> {
        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.showsCursor = pointer
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        return Unshared(try await SCScreenshotManager.captureImage(contentFilter: filter.value,
                                                                   configuration: configuration))
    }

    private static func uuid(of display: CGDirectDisplayID) -> String? {
        guard let reference = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, reference) as String?
    }

    public func window(_ id: UInt32, cursor: Bool) async -> WindowShot {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            return Self.isDeclined(error) ? .denied : .failed
        }
        guard let window = content.windows.first(where: { $0.windowID == id }) else { return .gone }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        // **No size is given, and it is `SCScreenshotConfiguration` and not the
        // stream's.** Measured on a 993×747 pt window at 2×: a stream
        // configuration with no size answers a fixed 1920×1080 with the window
        // scaled to fit; one sized to `contentRect` keeps the shadow inside that
        // size by shrinking the window to 1870×1407 px; this one answers
        // 2078×1586 with the window at exactly 1986×1494, the shadow around it
        // untouched — the picture macOS's own tool makes of the same window.
        let configuration = SCScreenshotConfiguration()
        configuration.ignoreShadows = false
        configuration.showsCursor = cursor
        do {
            let output = try await SCScreenshotManager.captureScreenshot(contentFilter: filter,
                                                                         configuration: configuration)
            guard let image = output.sdrImage else { return .failed }
            return .image(image)
        } catch {
            return Self.isDeclined(error) ? .denied : .failed
        }
    }

    /// `SCStreamError.userDeclined` (-3801): the grant is not there, or was
    /// withdrawn while the call was in flight.
    private static func isDeclined(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == SCStreamErrorDomain && ns.code == SCStreamError.Code.userDeclined.rawValue
    }

    /// Front to back, in CG-global points. Only what a person could mean by "a
    /// window": on screen, not Helm's, not transparent.
    private static func windowList(excluding pid: pid_t) -> [FrozenWindow] {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                   kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        return raw.compactMap { entry in
            guard let number = entry[kCGWindowNumber as String] as? UInt32,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  let owner = entry[kCGWindowOwnerPID as String] as? Int, pid_t(owner) != pid,
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let x = bounds["X"], let y = bounds["Y"],
                  let width = bounds["Width"], let height = bounds["Height"]
            else { return nil }
            return FrozenWindow(id: number, frame: CGRect(x: x, y: y, width: width, height: height),
                                layer: layer,
                                ownerName: entry[kCGWindowOwnerName as String] as? String ?? "")
        }
    }
}

// MARK: - The file

/// Writes a picture into a folder and never over anything.
///
/// The bytes go to a temporary name in the same folder and are then **moved**
/// to the real one with `RENAME_EXCL`, which fails with `EEXIST` rather than
/// replace — so a name taken is one more number to try, and a half-written file
/// is never under the real name. `Data.write(options: .atomic)` is the
/// same shape with the opposite ending: it renames over whatever is there, which
/// is how a screenshot replaces one taken in the same second.
///
/// A volume that does not do RENAME_EXCL may answer `ENOTSUP` (`renamex_np(2)`:
/// «flags has a value that is not supported by the file system»), and a hard
/// link — which fails on an existing name just as atomically — takes its place.
/// No such volume was tried here, so that branch is written from the manual and
/// not exercised.
///
/// Files get the process's ordinary umask, as macOS's own screenshots do; they
/// are not `PrivateFile`, because the person is about to drag them into a chat.
public struct FileShotWriter: ShotWriting {
    public init() {}

    public func write(_ data: Data, into folder: URL, base: String, pathExtension: String) -> ShotWrite {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory)
        else { return .refused(.noFolder) }
        guard isDirectory.boolValue else { return .refused(.notAFolder) }

        let temporary = folder.appendingPathComponent(".helm-shot-\(UUID().uuidString).tmp").path
        let descriptor = open(temporary, O_WRONLY | O_CREAT | O_EXCL, 0o666)
        guard descriptor >= 0 else { return .refused(Self.refusal(errno)) }

        var failure: Int32 = 0
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    failure = errno
                    return
                }
                offset += written
            }
        }
        if Darwin.close(descriptor) != 0, failure == 0 { failure = errno }
        guard failure == 0 else {
            unlink(temporary)
            return .refused(Self.refusal(failure))
        }

        for attempt in 0..<ShotNames.limit {
            let destination = folder.appendingPathComponent(
                ShotNames.candidate(base: base, pathExtension: pathExtension, attempt: attempt))
            var answer = renamex_np(temporary, destination.path, UInt32(RENAME_EXCL))
            var code = errno
            if answer != 0, code == ENOTSUP || code == EINVAL {
                answer = link(temporary, destination.path)
                code = errno
                if answer == 0 { unlink(temporary) }
            }
            if answer == 0 { return .written(destination) }
            if code == EEXIST { continue }
            unlink(temporary)
            return .refused(Self.refusal(code))
        }
        unlink(temporary)
        return .refused(.namesExhausted)
    }

    private static func refusal(_ code: Int32) -> WriteRefusal {
        switch code {
        case EPERM, EACCES, EROFS: .noPermission
        case ENOSPC, EDQUOT: .diskFull
        case ENOENT: .noFolder
        case ENOTDIR: .notAFolder
        default: .failed(code)
        }
    }
}

// MARK: - The clipboard

/// **Every copy a capture makes is marked, so a clipboard manager skips it.**
/// A screenshot is often of something that was not meant to outlive the moment
/// — a password manager's window, a bank page — and a manager that records every
/// copy would keep it in a history, on disk, for weeks. The convention is
/// nspasteboard.org's: a type the pasteboard carries beside the data, whose
/// content is ignored. `ConcealedType` is the one that says "do not record";
/// `TransientType` says the item is short-lived and is added because a manager
/// may honour one of the two and not the other. Neither stops anything from
/// pasting the picture. Whether a given manager honours them was not measured.
///
/// The board is injectable by name so a test reads the types off a pasteboard of its own
/// and never the person's.
public struct SystemShotPasteboard: ShotPasteboard {
    public static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    public static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    private let name: NSPasteboard.Name

    public init(named name: NSPasteboard.Name = .general) { self.name = name }

    public func copy(png: Data) -> PasteOutcome {
        let board = NSPasteboard(name: name)
        board.declareTypes([.png, Self.concealedType, Self.transientType], owner: nil)
        // The picture first: a refused picture is a refusal whatever the markers did.
        guard board.setData(png, forType: .png) else { return .refused }
        _ = board.setData(Data(), forType: Self.concealedType)
        _ = board.setData(Data(), forType: Self.transientType)
        return .accepted
    }
}

// MARK: - macOS's own preferences

/// Read-only, through `CFPreferences` so another domain's file is read the way
/// the system reads it. **Nothing here writes**, and nothing should.
///
/// `CFPreferencesCopyAppValue` answers `nil` for a key that is absent and for a
/// domain it could not read, and cannot say which. The hotkey reading therefore
/// calls `nil` absent — macOS's defaults, all on — which is the side that never
/// tells a person a combination is free; a value of the wrong type is
/// `unreadable`.
public struct SystemCapturePreferences: CapturePreferences {
    public init() {}

    public func location() -> RawSetting {
        RawSetting(CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString))
    }

    public func uiSounds() -> RawSetting {
        RawSetting(CFPreferencesCopyAppValue("com.apple.sound.uiaudio.enabled" as CFString,
                                             kCFPreferencesAnyApplication))
    }

    public func symbolicHotkeys() -> SymbolicHotkeysReading {
        guard let value = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString,
                                                    "com.apple.symbolichotkeys" as CFString)
        else { return .absent }
        guard let table = value as? [String: Any] else { return .unreadable }
        return .read(table)
    }
}

// MARK: - The shutter

/// macOS's own capture sound, read from its bundle at run time and not copied.
///
/// `Screen Capture.aif` under CoreAudio's system sounds is the file; `Grab.aif`
/// and `Shutter.aif` beside it are the same inode on the Mac this was written on.
/// Which of the three macOS's own capture plays was not verified. A file that is
/// not there is an absence and not a refusal — a future macOS may move it — so
/// the shutter is silent and nothing is logged.
///
/// `NSSound` is touched on the main thread only: `play()` hops there and returns
/// at once, so the freeze's caller is never held by the sound.
public final class SystemShutter: ShutterPlaying, @unchecked Sendable {
    static let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"

    /// Read and written on the main thread only.
    private var sound: NSSound?
    private var loaded = false

    public init() {}

    public func play() {
        DispatchQueue.main.async { [self] in
            if !loaded {
                loaded = true
                sound = NSSound(contentsOfFile: Self.path, byReference: true)
            }
            // A second shot inside the first's tail restarts it: `play` answers
            // false on a sound that is still sounding.
            sound?.stop()
            sound?.play()
        }
    }
}
