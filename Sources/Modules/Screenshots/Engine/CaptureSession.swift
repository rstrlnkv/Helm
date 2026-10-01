import CoreGraphics
import Foundation
import HelmRuntime
import ImageIO

/// Why a capture did not become a picture, or not all of one.
public enum CaptureRefusal: Sendable, Equatable {
    /// Screen Recording is not granted, or was withdrawn mid-capture.
    case noPermission
    /// The screen could not be captured for a reason the system did not give.
    case captureFailed
    /// A display was listed and gone by the time it was captured.
    case displayGone
    /// A window that neither the system nor the freeze has any more.
    case windowGone
    case write(WriteRefusal)
    case pasteboard
    case encoding
}

/// What a capture ended as: the files that exist, whether the clipboard took
/// it, and every reason something did not happen. Two fields rather than one
/// verdict, because the full-screen shortcut over two displays can save one and lose the other, and
/// "saved 2" over a display that was gone is the sentence a person believes.
public struct Delivery: @unchecked Sendable {
    public var files: [URL] = []
    public var copied = false
    public var refusals: [CaptureRefusal] = []
    /// The first picture that was made, for the thumbnail.
    public var image: CGImage?

    public init() {}
}

/// The result of asking for one window.
public enum WindowResult: @unchecked Sendable {
    case image(CGImage)
    case refused(CaptureRefusal)
}

public enum BeginResult: @unchecked Sendable {
    case ready(Freeze)
    case refused(CaptureRefusal)
}

/// One capture, start to finish, from the ports and the logic.
///
/// `@unchecked Sendable`: its closures read a `NamespacedStore`, which is a
/// reader over `UserDefaults` and is not declared `Sendable`, and they are read
/// at the act on whichever thread the call resumed on.
///
/// Not an actor and not a holder of state: every call is a function of the
/// machine as it is at that call. The freeze is the only thing carried from one
/// call to the next, and the caller carries it, because its owner is the
/// overlay and the overlay's lifetime is the capture's.
///
/// **Nothing here is a phase in the activity trail and nothing logs a capture.**
/// The log is for what was refused — no grant, a failed write, a folder that
/// was refused — and a line per press would be noise in the file a person
/// attaches to a bug report. Paths go through `Redact`.
public final class CaptureSession: @unchecked Sendable {
    private let capture: ScreenCapturing
    private let writer: ShotWriting
    private let pasteboard: ShotPasteboard
    private let preferences: CapturePreferences
    private let settings: () -> ScreenshotsSettings
    private let naming: () -> ShotNaming
    private let now: () -> Date
    private let locations: ScreenshotsLocations
    private let category = "screenshots"

    public init(capture: ScreenCapturing, writer: ShotWriting, pasteboard: ShotPasteboard,
                preferences: CapturePreferences,
                settings: @escaping () -> ScreenshotsSettings,
                naming: @escaping () -> ShotNaming = { .english },
                now: @escaping () -> Date = { Date() },
                locations: ScreenshotsLocations = .system) {
        self.capture = capture
        self.writer = writer
        self.pasteboard = pasteboard
        self.preferences = preferences
        self.settings = settings
        self.naming = naming
        self.now = now
        self.locations = locations
    }

    // MARK: - Freezing

    /// The permission is asked **before** anything is frozen: a press without
    /// the grant freezes nothing, raises no overlay and leaves one line in the
    /// log. Without it a freeze returns a desktop with no windows in it, and an
    /// overlay over that looks like the feature working.
    public func begin() async -> BeginResult {
        guard capture.access() == .granted else {
            refuseForPermission()
            return .refused(.noPermission)
        }
        switch await capture.freeze() {
        case .frozen(let freeze):
            return .ready(freeze)
        case .denied:
            // The grant went between the preflight and the capture. It is a
            // refusal: counted as a failure it would end up as a capture of
            // nothing, written as a file.
            HelmLog.shared.warn(category, "screen recording was withdrawn while the screen was being frozen")
            return .refused(.noPermission)
        case .failed:
            HelmLog.shared.warn(category, "the screen could not be frozen")
            return .refused(.captureFailed)
        }
    }

    private func refuseForPermission() {
        HelmLog.shared.warn(category, "no screen recording permission — capture refused")
        capture.requestAccess()
    }

    // MARK: - Cutting

    /// A selection made on one display, cut from that display's frozen frame.
    /// Nil when nothing of the selection is on the frame.
    public func crop(_ freeze: Freeze, display: DisplayID, local rect: CGRect) -> CGImage? {
        guard let frame = freeze.frames.first(where: { $0.id == display }),
              let pixels = ScreenSpace.pixels(ofLocal: rect, scale: frame.scale,
                                              imageWidth: frame.image.width,
                                              imageHeight: frame.image.height)
        else { return nil }
        return frame.image.cropping(to: pixels)
    }

    /// One window, **asked for again at the click**.
    ///
    /// The list in the freeze is a reading and the click is an act seconds
    /// later: the window may have closed, been replaced by another at the same
    /// place, or been covered. So the window's own pixels are requested now. If
    /// it has gone, what was on screen at the freeze is cut from the freeze,
    /// which is what the person was looking at when they clicked. A protected
    /// window is saved as it came.
    public func window(_ id: UInt32, in freeze: Freeze) async -> WindowResult {
        switch await capture.window(id) {
        case .image(let image):
            return .image(image)
        case .gone:
            return cutFromFreeze(id, in: freeze)
        case .denied:
            HelmLog.shared.warn(category, "screen recording was withdrawn before the window was captured")
            return .refused(.noPermission)
        case .failed:
            HelmLog.shared.warn(category, "a window could not be captured; cut from the frozen frame instead")
            return cutFromFreeze(id, in: freeze)
        }
    }

    private func cutFromFreeze(_ id: UInt32, in freeze: Freeze) -> WindowResult {
        guard let window = freeze.windows.first(where: { $0.id == id }) else {
            HelmLog.shared.warn(category, "a window was gone and was not in the frozen frame either")
            return .refused(.windowGone)
        }
        let displays = freeze.frames.map { (id: $0.id, frame: $0.frame) }
        guard let home = WindowPick.home(of: window.frame, among: displays),
              let frame = freeze.frames.first(where: { $0.id == home.id }),
              let image = crop(freeze, display: frame.id,
                               local: ScreenSpace.local(home.part, in: frame.frame))
        else { return .refused(.windowGone) }
        return .image(image)
    }

    // MARK: - Delivering

    /// Copies and saves one picture. The area and window captures do both until
    /// the editor takes their place: the editor's own buttons decide then.
    public func deliver(_ image: CGImage, saves: Bool, copies: Bool) async -> Delivery {
        var delivery = Delivery()
        delivery.image = image
        await deliver(image, saves: saves, copies: copies, into: &delivery)
        return delivery
    }

    private func deliver(_ image: CGImage, saves: Bool, copies: Bool,
                         into delivery: inout Delivery) async {
        guard let png = await offTheCooperativePool({ Self.encode(image) }) else {
            HelmLog.shared.warn(category, "a picture could not be encoded")
            delivery.refusals.append(.encoding)
            return
        }
        if copies {
            switch pasteboard.copy(png: png) {
            case .accepted: delivery.copied = true
            case .refused:
                HelmLog.shared.warn(category, "the clipboard refused the picture")
                delivery.refusals.append(.pasteboard)
            }
        }
        guard saves else { return }
        let folder = await resolvedFolder()
        let base = ShotNames.base(date: now(), naming: naming())
        let writer = writer
        let outcome = await offTheCooperativePool { writer.write(png, into: folder.url, base: base) }
        switch outcome {
        case .written(let url):
            delivery.files.append(url)
        case .refused(let reason):
            HelmLog.shared.warn(category, "save refused: \(reason) in \(Redact.path(folder.url.path))")
            delivery.refusals.append(.write(reason))
        }
    }

    /// The full-screen shortcut: one file per display, and the clipboard — when it is asked for —
    /// gets the first display's picture, which is the main one.
    ///
    /// The count of files is the count of files written. A display that was
    /// listed and gone is a refusal and **not** a file: counting it as saved
    /// tells a person they have a picture of a screen they do not.
    public func captureScreens() async -> Delivery {
        var delivery = Delivery()
        let freeze: Freeze
        switch await begin() {
        case .ready(let frozen): freeze = frozen
        case .refused(let reason):
            delivery.refusals.append(reason)
            return delivery
        }
        // Asked after the freeze and before anything is written, copied or
        // presented: the caller cancels a press whose module was switched off
        // during the freeze, and a check after this returns is too late.
        guard !Task.isCancelled else { return delivery }
        let destination = settings().afterFullScreen
        var copiedOne = false
        for shot in freeze.displays {
            switch shot {
            case .gone:
                HelmLog.shared.warn(category, "a display was gone before it could be captured")
                delivery.refusals.append(.displayGone)
            case .image(let frame):
                if delivery.image == nil { delivery.image = frame.image }
                await deliver(frame.image, saves: destination.saves,
                              copies: destination.copies && !copiedOne, into: &delivery)
                copiedOne = copiedOne || destination.copies
            }
        }
        return delivery
    }

    // MARK: - The folder

    /// Read at each save, not once: the folder is a preference the person
    /// changes in another program, and a volume can leave between two presses.
    /// A refusal is logged here, where it is acted on, and the Desktop carries on.
    func resolvedFolder() async -> SaveFolder {
        let raw = await offTheCooperativePool { [preferences] in preferences.location() }
        let folder = SaveLocation.resolve(raw: raw.value, desktop: locations.desktop,
                                          home: locations.home)
        if let reason = folder.refused {
            HelmLog.shared.warn(category, "the save folder macOS names was refused (\(reason.rawValue)); using the Desktop")
        }
        return folder
    }

    // MARK: - PNG

    /// A PNG of the picture, or nil when ImageIO would not make one. The pool is
    /// inside the call: encoding a 5K frame leaves autoreleased buffers, and the
    /// work is one iteration of whoever called.
    static func encode(_ image: CGImage) -> Data? {
        autoreleasepool {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                data, "public.png" as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination), data.length > 0 else { return nil }
            return data as Data
        }
    }
}
