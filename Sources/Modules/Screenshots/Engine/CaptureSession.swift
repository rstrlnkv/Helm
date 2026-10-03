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
    /// «Edit» was asked and nothing was opened: the shot's file is no longer the file that shot wrote, or it is, and
    /// no picture could be read from it, or the shot has neither a file nor a picture held.
    case notEditable
    /// The edit is saved and the original was not replaced. Where each reason leaves the two is told by
    /// `ReplaceRefusal`: the original is where it was and the edit beside it, except where a case says otherwise.
    case notReplaced(ReplaceRefusal)
}

/// Why an edit did not take its original's place.
public enum ReplaceRefusal: Sendable, Equatable {
    /// The second re-ask, inside the move, found nothing at the shot's path: the original was renamed, moved away or
    /// deleted between the edit's write and the move. The edit is beside where it was.
    case missing
    /// The path held what the shot did not write (`ShotReplacement.Verdict.changed`), found at the move, or no move was
    /// tried at all: the edit was written in a format this module does not write over (a foreign extension). The original
    /// renamed or deleted before the edit's write also comes out here: the edit took the original's own name, the first
    /// of the ladder, and is what the move found there. The edit is then under the original's name.
    case changed
    /// The original's folder took no write (refused, every name of the ladder taken, or the folder itself renamed or
    /// gone), so the edit lies where the settings save and the original was never asked about. Told to a person as
    /// `.missing` is: that is a sentence of the screen's, and this case is for whoever must tell the reasons apart.
    case folderRefused
    /// `HelmTrash` refused the original, or macOS did: the gate's `outOfScope` is one of these.
    case trash(TrashFailure.Reason)
}

/// What a capture ended as: the files that exist, whether the clipboard took
/// it, and every reason something did not happen. Two fields rather than one
/// verdict, because the full-screen shortcut over two displays can save one and lose the other, and
/// "saved 2" over a display that was gone is the sentence a person believes.
public struct Delivery: @unchecked Sendable {
    /// Every file this delivery wrote, each with the reading of it the next edit is checked against.
    public var written: [WrittenShot] = []
    public var files: [URL] { written.map(\.url) }
    /// The original of an edit went to the Trash and the file here has its name. Not set when the name was taken
    /// between the two: the file here is then beside it, and nothing is said of the name.
    public var replaced = false
    public var copied = false
    public var refusals: [CaptureRefusal] = []
    /// The first picture that was made, for the thumbnail.
    public var image: CGImage?

    public init() {}
}

/// Where a shot's full picture is, for a copy of several at once: in memory for a shot that was only copied, in its
/// file for a saved one.
public enum ShotSource: @unchecked Sendable {
    case picture(CGImage)
    case file(URL)
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

public enum EditOpening: @unchecked Sendable {
    case ready(PictureOnScreen)
    case refused(CaptureRefusal)
}

/// Whether one pass of `CaptureSession.copyAll` is to go on: read between two pictures, set from any thread.
private final class GroupPass: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func stop() { lock.lock(); stopped = true; lock.unlock() }
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
/// **Nothing logs a capture, and one thing here is a phase in the activity trail:** the move of an edit's
/// original to the Trash, which `HelmTrash.remove` opens as it does for every module. The log is for what was
/// refused — no grant, a failed write, a folder that was refused, an original that was not replaced — and a line
/// per press would be noise in the file a person attaches to a bug report. Paths go through `Redact`.
public final class CaptureSession: @unchecked Sendable {
    private let capture: ScreenCapturing
    private let writer: ShotWriting
    private let trash: ShotTrashing
    private let pasteboard: ShotPasteboard
    private let preferences: CapturePreferences
    private let shutterPort: ShutterPlaying
    private let settings: () -> ScreenshotsSettings
    private let naming: () -> ShotNaming
    private let now: () -> Date
    private let locations: ScreenshotsLocations
    private let category = ScreenshotsEngine.moduleID
    /// The group's copy runs on one queue, so one pass at a time; `latestPass` is the token the next press stops.
    /// The only state here besides the ports.
    private let groupQueue = DispatchQueue(label: "helm.screenshots.copy-all", qos: .userInitiated)
    private let passes = NSLock()
    private var latestPass: GroupPass?

    public init(capture: ScreenCapturing, writer: ShotWriting, trash: ShotTrashing, pasteboard: ShotPasteboard,
                preferences: CapturePreferences, shutter: ShutterPlaying,
                settings: @escaping () -> ScreenshotsSettings,
                naming: @escaping () -> ShotNaming = { .english },
                now: @escaping () -> Date = { Date() },
                locations: ScreenshotsLocations = .system) {
        self.capture = capture
        self.writer = writer
        self.trash = trash
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

    // MARK: - Editing a shot that was taken

    /// «Edit»: the shot's picture over a fresh freeze, for the overlay to open on.
    ///
    /// **The file is asked before a pixel of it is read.** `shot` carries the reading taken when it was written,
    /// and the path is a name: by now it may lead to another picture, and an editor opened on that one would
    /// offer to replace somebody's file with an edit of it. A file that is not the one written is a refusal and
    /// the editor does not open. `held` is the picture of a shot that has no file, which is asked nothing.
    public func openEdit(of shot: WrittenShot?, held: CGImage?, on display: DisplayID?) async -> EditOpening {
        let writer = writer, category = category
        let read: CGImage? = await offTheCooperativePool {
            guard let shot else { return held }
            let verdict = ShotReplacement.verdict(stored: shot.reading, now: writer.reading(of: shot.url))
            guard verdict == .same else {
                HelmLog.shared.warn(category, "edit refused: the shot's file is \(verdict) at \(Redact.path(shot.url.path))")
                return nil
            }
            guard let source = CGImageSourceCreateWithURL(shot.url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                HelmLog.shared.warn(category, "edit refused: no picture could be read from \(Redact.path(shot.url.path))")
                return nil
            }
            return image
        }
        guard let picture = read else { return .refused(.notEditable) }
        guard !Task.isCancelled else { return .refused(.captureFailed) }
        switch await begin() {
        case .refused(let reason): return .refused(reason)
        case .ready(let freeze):
            guard let shown = await offTheCooperativePool({ PictureOnScreen.place(picture, over: freeze, on: display) })
            else {
                HelmLog.shared.warn(category, "the picture could not be laid over the frozen screen")
                return .refused(.captureFailed)
            }
            return .ready(shown)
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

    /// A selection cut like `crop`, with the editor's layers drawn over it **at the
    /// pixels' own resolution**: the points of the layers are multiplied by the
    /// scale of the display they were drawn on — that display's `FrozenDisplay.scale`
    /// and no screen's — so a stroke is as thick in the file as on the screen, and
    /// the cut's pixel offset is the one `crop` uses, so the layers land on the
    /// same pixels the overlay showed them over. No layers: the crop itself, which keeps its
    /// parent's pixels alive — unless `detached`, which draws the cut into a bitmap of its own so
    /// that what holds it (a pin) holds the selection and not the whole frozen display.
    public func annotated(_ freeze: Freeze, display: DisplayID, local rect: CGRect,
                          layers: [Annotation], detached: Bool = false) async -> CGImage? {
        guard let frame = freeze.frames.first(where: { $0.id == display }),
              let pixels = ScreenSpace.pixels(ofLocal: rect, scale: frame.scale,
                                              imageWidth: frame.image.width, imageHeight: frame.image.height),
              let cut = frame.shot.cropping(to: pixels)
        else { return nil }
        guard !layers.isEmpty || detached else { return cut }
        let scale = frame.scale
        return await offTheCooperativePool { Self.draw(layers, over: cut, at: pixels.origin, scale: scale) }
    }

    /// The edit of a finished picture: the part of `picture` under the area, with the layers over it, **at the
    /// picture's own size**. The layers are in the points of the display the picture was shown on. **Each axis has
    /// the ratio of its own** (the picture's pixels over the rectangle's points on that axis): the rectangle is
    /// whole display pixels, so on a thin picture reduced to fit the two ratios differ by a good part, and one
    /// number for both put a mark off by up to the whole file. The marks are moved into the picture's own
    /// proportions by those two ratios, so a mark lands where it was drawn within a display pixel on both axes
    /// and the whole area is exactly the picture's pixel size; a stroke is then as thick as `pixelsPerPoint`
    /// says, the larger ratio, which is the display's scale while the picture fits.
    /// What of the area lies outside the picture is not in the file; nil when none of it is on the picture.
    public func annotated(_ shown: PictureOnScreen, local rect: CGRect, layers: [Annotation]) async -> CGImage? {
        let picture = shown.picture, perPoint = shown.pixelsPerPoint, stand = shown.rect
        let part = rect.intersection(stand)
        // A point of the display to the point of a picture drawn at `perPoint` on both axes.
        let kx = CGFloat(picture.width) / stand.width / perPoint, ky = CGFloat(picture.height) / stand.height / perPoint
        func inPicture(_ point: CGPoint) -> CGPoint { CGPoint(x: (point.x - stand.minX) * kx, y: (point.y - stand.minY) * ky) }
        guard !part.isNull,
              let pixels = ScreenSpace.pixels(ofLocal: CGRect(origin: inPicture(part.origin),
                                                              size: CGSize(width: part.width * kx, height: part.height * ky)),
                                              scale: perPoint, imageWidth: picture.width, imageHeight: picture.height),
              let cut = picture.cropping(to: pixels)
        else { return nil }
        guard !layers.isEmpty else { return cut }
        let moved = layers.map { $0.mapped(inPicture) }
        return await offTheCooperativePool { Self.draw(moved, over: cut, at: pixels.origin, scale: perPoint) }
    }

    /// The pool is inside the call, as in `encode`: a 5K cut is one iteration of the caller's work.
    static func draw(_ layers: [Annotation], over cut: CGImage, at origin: CGPoint, scale: CGFloat) -> CGImage? {
        autoreleasepool {
            for space in bitmapSpaces(for: cut) {
                guard let context = CGContext(data: nil, width: cut.width, height: cut.height,
                                              bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { continue }
                context.draw(cut, in: CGRect(x: 0, y: 0, width: cut.width, height: cut.height))
                context.setAllowsAntialiasing(true)
                for layer in layers {
                    context.saveGState()
                    // The pencil's grain is a clip in the bitmap's own pixels, so it goes in before the points' transform.
                    if layer.tool.isGrainy, let stroke = layer.stroke {
                        let cutPixels = CGRect(origin: origin, size: CGSize(width: cut.width, height: cut.height))
                        guard let grain = PencilGrain.mask(for: layer.points, width: stroke.width, scale: scale, pixels: cutPixels)
                        else { context.restoreGState(); continue }
                        context.clip(to: CGRect(x: grain.pixels.minX - origin.x,
                                                y: CGFloat(cut.height) - (grain.pixels.maxY - origin.y),
                                                width: grain.pixels.width, height: grain.pixels.height), mask: grain.grey)
                    }
                    // Display-local points, top-left, to this bitmap's pixels, bottom-left.
                    context.translateBy(x: 0, y: CGFloat(cut.height))
                    context.scaleBy(x: scale, y: -scale)
                    context.translateBy(x: -origin.x / scale, y: -origin.y / scale)
                    context.addPath(layer.outline)
                    if let stroke = layer.stroke {
                        context.setLineWidth(stroke.width)
                        context.setLineCap(stroke.cap)
                        context.setLineJoin(stroke.join)
                        context.setStrokeColor(stroke.color)
                        if stroke.multiplies { context.setBlendMode(.multiply) }
                        context.strokePath()
                    } else {
                        context.setFillColor(layer.fillColor)
                        context.fillPath()
                    }
                    context.restoreGState()
                }
                return context.makeImage()
            }
            return nil
        }
    }

    // MARK: - Delivering

    /// Copies and saves one picture; the editor's exits and the window and display
    /// picks say which of the two they want.
    ///
    /// `fileEvenFromClipboard` is the editor's ⌘S: a person who pressed Save wants a
    /// file whatever "after a capture" says, and under the clipboard target the
    /// folder is the one the `.macOS` choice names.
    ///
    /// `original` is the shot an edit was opened from, and makes a save a **replacement**: the file is written
    /// beside the original, in the original's format and whatever the save target says, and then takes its place
    /// (`replace`). Without a save it is ignored: ⌘C on an edit copies and replaces nothing.
    public func deliver(_ image: CGImage, saves: Bool, copies: Bool,
                        fileEvenFromClipboard: Bool = false, replacing original: WrittenShot? = nil) async -> Delivery {
        var delivery = Delivery()
        delivery.image = image
        await deliver(image, saves: saves, copies: copies, fileEvenFromClipboard: fileEvenFromClipboard,
                      replacing: saves ? original : nil, into: &delivery)
        return delivery
    }

    /// Every shot of a group on the clipboard in **one write** (`ShotPasteboard.copy(pngs:)`), in the order given.
    /// A shot with a file is read back from it, as the single shot's Copy is. **All or none:** a shot that cannot
    /// be read or encoded refuses the whole copy with `.encoding`, since a board holding fewer pictures than the
    /// control counted would say nothing of the missing one.
    ///
    /// **One pass at a time, and a displaced one stops at its next picture.** A press while an earlier pass is still
    /// reading stops that pass (`GroupPass`) and waits behind it on a queue of its own, so two never run side by
    /// side. The task's cancellation stops it the same way, which the queue's block would not see. A pass that was
    /// stopped refuses nothing and writes nothing.
    ///
    /// The pool is inside the loop: each picture decodes and encodes in its own, and a pool round the loop would
    /// keep every one of them until the last.
    public func copyAll(_ shots: [ShotSource]) async -> Delivery {
        var delivery = Delivery()
        let pass = GroupPass()
        passes.withLock {
            latestPass?.stop()
            latestPass = pass
        }
        let pngs: [Data]? = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                groupQueue.async { continuation.resume(returning: Self.encodeAll(shots, until: pass)) }
            }
        } onCancel: { pass.stop() }
        if pass.isStopped { return delivery }
        guard let pngs, !pngs.isEmpty else {
            HelmLog.shared.warn(category, "a group's picture could not be read or encoded")
            delivery.refusals.append(.encoding)
            return delivery
        }
        guard !Task.isCancelled else { return delivery }
        switch pasteboard.copy(pngs: pngs) {
        case .accepted: delivery.copied = true
        case .refused:
            HelmLog.shared.warn(category, "the clipboard refused the group's pictures")
            delivery.refusals.append(.pasteboard)
        }
        return delivery
    }

    /// Nil when a picture could not be read or encoded, and when the pass was stopped before the last.
    private static func encodeAll(_ shots: [ShotSource], until pass: GroupPass) -> [Data]? {
        var all: [Data] = []
        for shot in shots {
            if pass.isStopped { return nil }
            let png: Data? = autoreleasepool {
                switch shot {
                case .picture(let image): return encode(image, as: .png)
                case .file(let url):
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
                    return encode(image, as: .png)
                }
            }
            guard let png else { return nil }
            all.append(png)
        }
        return all
    }

    /// `saves` asks for a file and is answered by the setting: under the
    /// clipboard target no file is made, and `copies` is what puts the picture
    /// on the board. The file is in the setting's format and the clipboard's copy
    /// is always PNG; a PNG is encoded once when both want one.
    private func deliver(_ image: CGImage, saves: Bool, copies: Bool, fileEvenFromClipboard: Bool = false,
                         replacing original: WrittenShot? = nil, into delivery: inout Delivery) async {
        var current = settings()
        if fileEvenFromClipboard, current.saveTarget == .clipboard { current.saveTarget = .macOS }
        // An edit takes its original's name, so its bytes are in the format that name says, not the setting's.
        let ownFormat = original.flatMap { shot in ShotFormat.allCases.first { $0.pathExtension == shot.url.pathExtension } }
        let toFile = saves && (original != nil || current.saveTarget.savesAFile)
        let format = ownFormat ?? current.format
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
        // Asked after every wait and right before each act: a delivery cancelled
        // while it was encoding or finding the folder reaches neither the clipboard nor the disk.
        guard !Task.isCancelled else { return }
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
        let folder: URL, base: String
        if let original {
            // Step one of a replacement: beside the original, under the first free name of the ladder, which begins at its own.
            folder = original.url.deletingLastPathComponent()
            base = original.url.deletingPathExtension().lastPathComponent
        } else {
            guard let resolved = await resolvedFolder(for: current) else { return }
            folder = resolved.url
            base = ShotNames.base(date: now(), naming: naming())
        }
        guard !Task.isCancelled else { return }
        let writer = writer
        let outcome = await offTheCooperativePool {
            writer.write(bytes, into: folder, base: base, pathExtension: format.pathExtension)
        }
        switch outcome {
        case .written(let shot):
            delivery.written.append(shot)
            guard let original else { return }
            // A name in a format this module does not write is not a name its own bytes may take.
            guard ownFormat != nil else { delivery.refusals.append(.notReplaced(.changed)); return }
            await replace(original, with: shot, in: &delivery)
        case .refused(let reason):
            HelmLog.shared.warn(category, "save refused: \(reason) in \(Redact.path(folder.path))")
            guard original != nil else { delivery.refusals.append(.write(reason)); return }
            // The original's folder would not take the edit, so there is no "beside": the edit is saved where
            // the settings save, as a new shot, and the original is left as it is.
            let before = delivery.written.count
            await deliver(image, saves: true, copies: false, fileEvenFromClipboard: true, into: &delivery)
            if delivery.written.count > before { delivery.refusals.append(.notReplaced(.folderRefused)) }
        }
    }

    // MARK: - Replacing the original

    private struct NotTheFileTheShotWrote: Error {}

    /// Steps two and three of a replacement; step one, the edit written beside the original under a name of its
    /// own, is done and stays done whatever happens here. **No byte is written over a file and nothing is
    /// removed but through `HelmTrash`:** the original goes to the Trash, and the edit then takes the name that
    /// freed, by a move that fails on a name that is taken.
    ///
    /// The gate is `UserFileScope`: the question it asks, whether this belongs to the person, is the question
    /// about a screenshot in a folder of theirs. The stored reading is `original.reading`, taken by the writer
    /// from the descriptor it wrote through. **It is asked again inside the move itself,** as the first thing
    /// `HelmTrash.remove`'s `trashing` does, after that function's own weighing and its re-reading of the
    /// ancestry: a file that was renamed, replaced, written into or turned into a link since is not moved. What
    /// this narrows and does not close is what `HelmTrash.remove` says of itself: one resolution of the path lies
    /// between that `lstat` and `trashItem`'s own.
    ///
    /// Every refusal is in `delivery.refusals`, with the reason's own case: the original is left where it is, and the edit
    /// beside it, except where `ReplaceRefusal` says otherwise.
    /// A name taken between the two steps is not one: the original is in the Trash and the edit keeps its own name,
    /// and the delivery says so by not being `replaced`, which claims the name. **The reading the shot carries on
    /// is `edit.reading`, the descriptor's,** and is not taken again by `lstat` of the name after the claim (a
    /// descriptor's reading is the object's, a name's is whoever stands there): another file may stand under the name between the two, and a reading of it would be the
    /// next replacement's licence to trash a stranger. A rename changes neither inode, size nor time written.
    private func replace(_ original: WrittenShot, with edit: WrittenShot, in delivery: inout Delivery) async {
        // Asked right before the act: a delivery cancelled while the edit was written moves nothing.
        guard !Task.isCancelled else { return }
        let writer = writer, trash = trash, category = category
        let path = original.url.path
        let outcome: (refusal: ReplaceRefusal?, file: WrittenShot, named: Bool) = await offTheCooperativePool {
            let scope = UserFileScope.partition([path])
            var atTheMove = ShotReplacement.Verdict.same
            let result = HelmTrash.remove(allowed: scope.allowed, outOfScope: scope.refused, module: category, trashing: { url in
                atTheMove = ShotReplacement.verdict(stored: original.reading, now: writer.reading(of: url))
                guard atTheMove == .same else { throw NotTheFileTheShotWrote() }
                try trash.trash(url)
            })
            switch atTheMove {
            case .missing: return (.missing, edit, false)
            case .changed: return (.changed, edit, false)
            case .same: break
            }
            guard result.refused.isEmpty, !result.removed.isEmpty else {
                return (.trash(result.refused.first?.reason ?? .systemRefused), edit, false)
            }
            guard writer.claim(edit.url, as: original.url) else {
                HelmLog.shared.warn(category, "the original's name was taken before the edit could have it; the edit keeps its own")
                return (nil, edit, false)
            }
            // The reading of the object the module wrote, not of the name: another file may stand under the name by
            // now, and the next edit's checks would then be answered by a stranger's reading.
            return (nil, WrittenShot(url: original.url, reading: edit.reading), true)
        }
        delivery.written[delivery.written.count - 1] = outcome.file
        if let refusal = outcome.refusal {
            HelmLog.shared.warn(category, "the original was not replaced (\(refusal)); the edit is beside it")
            delivery.refusals.append(.notReplaced(refusal))
        } else {
            delivery.replaced = outcome.named
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
    public static func encode(_ image: CGImage, as format: ShotFormat) -> Data? {
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

    /// The colour spaces to try an 8-bit bitmap of `image` in: its own when that is an RGB one a bitmap can be
    /// made in, then sRGB.
    static func bitmapSpaces(for image: CGImage) -> [CGColorSpace] {
        var spaces = [CGColorSpace(name: CGColorSpace.sRGB)!]
        if let own = image.colorSpace, own.model == .rgb, own.supportsOutput { spaces.insert(own, at: 0) }
        return spaces
    }

    /// The picture over `jpegGround`, in its own colour space when that is an RGB
    /// one an 8-bit bitmap can be made in, sRGB otherwise — an extended-range
    /// space (a display's HDR or wide-gamut reading) cannot hold one, and a PNG
    /// of the same picture is fine, so the JPEG falls back rather than refuses.
    static func flattened(_ image: CGImage) -> CGImage? {
        for space in bitmapSpaces(for: image) {
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
