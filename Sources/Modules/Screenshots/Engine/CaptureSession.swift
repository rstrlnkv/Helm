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
    private let shutterPort: ShutterPlaying
    private let settings: () -> ScreenshotsSettings
    private let naming: () -> ShotNaming
    private let now: () -> Date
    private let locations: ScreenshotsLocations
    private let category = ScreenshotsEngine.moduleID

    public init(capture: ScreenCapturing, writer: ShotWriting, pasteboard: ShotPasteboard,
                preferences: CapturePreferences, shutter: ShutterPlaying,
                settings: @escaping () -> ScreenshotsSettings,
                naming: @escaping () -> ShotNaming = { .english },
                now: @escaping () -> Date = { Date() },
                locations: ScreenshotsLocations = .system) {
        self.capture = capture
        self.writer = writer
        self.pasteboard = pasteboard
        self.preferences = preferences
        self.shutterPort = shutter
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
        switch await capture.freeze(cursor: settings().showCursor) {
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

    /// A selection made on one display, cut from that display's frozen frame —
    /// the one with the pointer in it when the freeze took one. Nil when nothing
    /// of the selection is on the frame.
    public func crop(_ freeze: Freeze, display: DisplayID, local rect: CGRect) -> CGImage? {
        guard let frame = freeze.frames.first(where: { $0.id == display }),
              let pixels = ScreenSpace.pixels(ofLocal: rect, scale: frame.scale,
                                              imageWidth: frame.image.width,
                                              imageHeight: frame.image.height)
        else { return nil }
        return frame.shot.cropping(to: pixels)
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
        // The menu bar and the Dock are cut from the freeze at their own rects: the
        // Dock's window is a display-sized sheet and the system's picture of it
        // is not the strip. A Dock placed by its own Accessibility bounds is the
        // exception: the system's picture of that window is the Dock alone.
        if let surface = freeze.windows.first(where: { $0.id == id }), WindowPick.isSystemSurface(surface),
           !surface.drawnAlone {
            return cutFromFreeze(id, in: freeze)
        }
        switch await capture.window(id, cursor: settings().showCursor) {
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

    /// `saves` asks for a file and is answered by the setting: under the
    /// clipboard target no file is made, and `copies` is what puts the picture
    /// on the board. The file is in the setting's format and the clipboard's copy
    /// is always PNG; a PNG is encoded once when both want one.
    private func deliver(_ image: CGImage, saves: Bool, copies: Bool,
                         into delivery: inout Delivery) async {
        let current = settings()
        let toFile = saves && current.saveTarget.savesAFile
        let format = current.format
        let png: Data?
        if copies || (toFile && format == .png) {
            png = await offTheCooperativePool({ Self.encode(image, as: .png) })
            if png == nil {
                HelmLog.shared.warn(category, "a picture could not be encoded")
                delivery.refusals.append(.encoding)
                return
            }
        } else {
            png = nil
        }
        if copies, let png {
            switch pasteboard.copy(png: png) {
            case .accepted: delivery.copied = true
            case .refused:
                HelmLog.shared.warn(category, "the clipboard refused the picture")
                delivery.refusals.append(.pasteboard)
            }
        }
        guard toFile else { return }
        let bytes: Data
        if format == .png, let png {
            bytes = png
        } else if let jpeg = await offTheCooperativePool({ Self.encode(image, as: format) }) {
            bytes = jpeg
        } else {
            HelmLog.shared.warn(category, "a picture could not be encoded")
            delivery.refusals.append(.encoding)
            return
        }
        guard let folder = await resolvedFolder(for: current) else { return }
        let base = ShotNames.base(date: now(), naming: naming())
        let writer = writer
        let outcome = await offTheCooperativePool {
            writer.write(bytes, into: folder.url, base: base, pathExtension: format.pathExtension)
        }
        switch outcome {
        case .written(let url):
            delivery.files.append(url)
        case .refused(let reason):
            HelmLog.shared.warn(category, "save refused: \(reason) in \(Redact.path(folder.url.path))")
            delivery.refusals.append(.write(reason))
        }
    }

    /// The full-screen shortcut: one file per display, or — under the clipboard
    /// target — the first display's picture on the board, which is the main one.
    ///
    /// The shutter sounds at the freeze, before anything is written: it is the
    /// moment the picture was taken, and a disk that is slow does not delay it.
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
        shutter()
        return await deliverScreens(freeze)
    }

    /// The part of `captureScreens` after the freeze: every display of it, to
    /// the file or the clipboard the setting names.
    public func deliverScreens(_ freeze: Freeze) async -> Delivery {
        var delivery = Delivery()
        let toBoard = settings().saveTarget == .clipboard
        var copiedOne = false
        for shot in freeze.displays {
            switch shot {
            case .gone:
                HelmLog.shared.warn(category, "a display was gone before it could be captured")
                delivery.refusals.append(.displayGone)
            case .image(let frame):
                if delivery.image == nil { delivery.image = frame.shot }
                await deliver(frame.shot, saves: true, copies: toBoard && !copiedOne, into: &delivery)
                copiedOne = copiedOne || toBoard
            }
        }
        return delivery
    }

    // MARK: - The shutter

    /// Plays the shutter when the module's setting and the system's both say so.
    /// The engine decides whether; the caller decides when.
    public func shutter() {
        let sounds = preferences.uiSounds().value
        guard ShutterRule.plays(setting: settings().shutterSound, uiAudio: sounds) else { return }
        shutterPort.play()
    }

    // MARK: - The folder

    /// Read at each save, not once: the folder is a preference the person
    /// changes in another program, and a volume can leave between two presses.
    /// A refusal is logged here, where it is acted on, and the Desktop carries on.
    /// Nil when the target is the clipboard.
    func resolvedFolder(for current: ScreenshotsSettings) async -> SaveFolder? {
        let raw = await offTheCooperativePool { [preferences] in preferences.location() }
        let locations = locations
        guard let folder = SaveLocation.folder(for: current, macOS: raw.value, locations: locations)
        else { return nil }
        if let reason = folder.refused {
            let which: String
            switch current.saveTarget {
            case .other: which = "the folder chosen in Helm"
            case .documents: which = "the Documents folder"
            case .desktop: which = "the Desktop"
            case .macOS, .clipboard: which = "the save folder macOS names"
            }
            HelmLog.shared.warn(category, "\(which) was refused (\(reason.rawValue)); using the Desktop")
        }
        return folder
    }

    // MARK: - Encoding

    /// What a JPEG is flattened onto: white. It is what macOS's own tool puts
    /// under a window's shadow — the corner of `screencapture -l<id> -t jpg` was
    /// read back as 255, 255, 255 — and a JPEG has no alpha to leave it in.
    static let jpegGround = CGColor(red: 1, green: 1, blue: 1, alpha: 1)

    /// The picture as a PNG or a JPEG, or nil when ImageIO would not make one. The
    /// pool is inside the call: encoding a 5K frame leaves autoreleased buffers,
    /// and the work is one iteration of whoever called.
    ///
    /// **A JPEG is drawn onto an opaque ground first,** so the ground is Helm's
    /// choice and not whatever ImageIO makes of an alpha channel it is about to
    /// drop. (On the macOS this was written on, ImageIO alone also lands on
    /// white — a clear picture and a half-transparent one both came out right
    /// with the flattening taken out — so this pins the ground rather than
    /// repairing a defect that was seen.)
    static func encode(_ image: CGImage, as format: ShotFormat) -> Data? {
        autoreleasepool {
            let source: CGImage
            switch format {
            case .png: source = image
            case .jpeg:
                guard let flat = flattened(image) else { return nil }
                source = flat
            }
            let data = NSMutableData()
            let type = format == .png ? "public.png" : "public.jpeg"
            guard let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil)
            else { return nil }
            let options: CFDictionary? = format == .jpeg
                ? [kCGImageDestinationLossyCompressionQuality: ShotFormat.jpegQuality] as CFDictionary
                : nil
            CGImageDestinationAddImage(destination, source, options)
            guard CGImageDestinationFinalize(destination), data.length > 0 else { return nil }
            return data as Data
        }
    }

    /// The picture over `jpegGround`, in its own colour space when that is an RGB
    /// one an 8-bit bitmap can be made in, sRGB otherwise — an extended-range
    /// space (a display's HDR or wide-gamut reading) cannot hold one, and a PNG
    /// of the same picture is fine, so the JPEG falls back rather than refuses.
    static func flattened(_ image: CGImage) -> CGImage? {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        var spaces = [srgb]
        if let own = image.colorSpace, own.model == .rgb, own.supportsOutput { spaces.insert(own, at: 0) }
        for space in spaces {
            guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { continue }
            let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            context.setFillColor(jpegGround)
            context.fill(rect)
            context.draw(image, in: rect)
            return context.makeImage()
        }
        return nil
    }
}
