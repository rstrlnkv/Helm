import AppKit
import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// What the capture panel's test families share: a controller over fake ports whose freezes can be counted, held,
/// recoloured and reshaped call by call, a window shot that can answer, and a disk that keeps what it was given.
/// The overlay is **built and not ordered in** (`CaptureOverlay.build`), the bar seam puts nothing on a screen unless
/// a test asks for the real one.
@MainActor
enum PanelRig {

    /// The screen: every call to `freeze` is numbered from 1, may be held on a gate, and may be answered with other
    /// displays than the first call's (a display plugged out, a resolution changed) and other pixels (a window moved).
    final class Screen: ScreenCapturing, @unchecked Sendable {
        private let lock = NSLock()
        private var freezeCount = 0, windowCount = 0
        let base: [FrozenDisplay]
        let windows: [FrozenWindow]
        /// What the n-th freeze (from 1) sees of the displays.
        var shape: @Sendable (Int, [FrozenDisplay]) -> [FrozenDisplay]
        /// Called as the n-th freeze starts, on whatever thread took it.
        var onFreeze: @Sendable (Int) -> Void = { _ in }
        /// A held freeze: the n-th call waits for the gate, if one is set for it.
        var hold: @Sendable (Int) -> PromptGate? = { _ in nil }
        var windowAnswer: @Sendable (UInt32) -> WindowShot = { _ in .gone }
        /// What the n-th freeze answers instead of the displays: a grant withdrawn, a capture that failed. Nil is a freeze.
        var outcome: @Sendable (Int) -> FreezeOutcome? = { _ in nil }

        init(base: [FrozenDisplay], windows: [FrozenWindow], shape: @escaping @Sendable (Int, [FrozenDisplay]) -> [FrozenDisplay]) {
            self.base = base; self.windows = windows; self.shape = shape
        }
        var freezes: Int { lock.withLock { freezeCount } }
        var windowAsks: Int { lock.withLock { windowCount } }
        func access() -> CaptureAccess { .granted }
        func requestAccess() {}
        func freeze(cursor: Bool) async -> FreezeOutcome {
            let n = lock.withLock { freezeCount += 1; return freezeCount }
            onFreeze(n)
            if let gate = hold(n) { await gate.arrive() }
            if let other = outcome(n) { return other }
            return .frozen(Freeze(displays: shape(n, base).map { .image($0) }, windows: windows))
        }
        func window(_ id: UInt32, cursor: Bool, shadow: Bool) async -> WindowShot {
            lock.withLock { windowCount += 1 }
            return windowAnswer(id)
        }
    }

    final class Disk: ShotWriting, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private var data: Data?
        var written: Int { lock.withLock { count } }
        var last: Data? { lock.withLock { data } }
        // A disk that keeps no file: nothing is read at any path and no name is claimed.
        func reading(of url: URL) -> ShotReading? { nil }
        func claim(_ written: URL, as name: URL) -> Bool { false }
        func write(_ data: Data, into folder: URL, base: String, pathExtension: String) -> ShotWrite {
            lock.withLock { count += 1; self.data = data }
            return .written(WrittenShot(url: folder.appendingPathComponent(base + "." + pathExtension), reading: NoFile.reading))
        }
    }
    struct Board: ShotPasteboard {
        func copy(png: Data) -> PasteOutcome { .accepted }
        func copy(pngs: [Data]) -> PasteOutcome { .accepted }
        func copy(text: String) -> PasteOutcome { .accepted }
    }
    struct NoPreferences: CapturePreferences {
        func location() -> RawSetting { RawSetting(nil) }
        func symbolicHotkeys() -> SymbolicHotkeysReading { .absent }
        func uiSounds() -> RawSetting { RawSetting(nil) }
    }
    struct NoShutter: ShutterPlaying { func play() {} }

    @MainActor final class Held { var overlay: CaptureOverlay?; var overlays = 0; var bars = 0 }

    struct Rig {
        let controller: CaptureController
        let screen: Screen
        let disk: Disk
        let held: Held
        let store: NamespacedStore
        let display: DisplayID
        let gate: PromptGate
    }

    /// One flat colour as a picture of `width` x `height` pixels.
    nonisolated static func solid(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// The colour of the centre pixel of a PNG by its dominant channel (colour management moves the numbers, not the order).
    nonisolated static func colourAtCentre(of data: Data?) -> String? {
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: -CGFloat(image.width / 2), y: -CGFloat(image.height / 2),
                                       width: CGFloat(image.width), height: CGFloat(image.height)))
        guard let pixel = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let (red, green, blue) = (pixel[0], pixel[1], pixel[2])
        if red > 150, green < 100, blue < 100 { return "red" }
        if green > 150, red < 100, blue < 100 { return "green" }
        if blue > 150, red < 100, green < 100 { return "blue" }
        return "mixed \(red),\(green),\(blue)"
    }

    nonisolated static func size(of data: Data?) -> CGSize? {
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return CGSize(width: image.width, height: image.height)
    }

    /// Every real screen, 1000 x 800 points at scale 1, each with a UUID; the first holds a window at (100,100,300,200).
    /// Freeze 1 is painted green, freeze 2 red, freeze 3 blue (and so round), so a picture says which freeze it was cut from.
    static func rig(timer: CaptureTimer = .none, values: [String: Any] = [:], presentBar: @escaping (CapturePanel) -> Void = { _ in },
                    tick: @escaping @Sendable (Duration) async throws -> Void = { _ in }) throws -> Rig {
        let shown = try OverlayRig.frames(scale: 1)
        let base = shown.enumerated().map { index, frame in
            FrozenDisplay(id: frame.id, frame: frame.frame, scale: 1, image: frame.image, uuid: "UUID-\(index)")
        }
        let window = FrozenWindow(id: 7, frame: CGRect(x: 100, y: 100, width: 300, height: 200),
                                  layer: WindowPick.lowestLevel, ownerName: "Notes")
        let screen = Screen(base: base, windows: [window]) { n, frames in
            frames.map { FrozenDisplay(id: $0.id, frame: $0.frame, scale: $0.scale,
                                       image: paint(n, width: Int($0.frame.width), height: Int($0.frame.height)),
                                       uuid: $0.uuid) }
        }
        let disk = Disk(), held = Held(), gate = PromptGate()
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        store.set(false, for: ScreenshotsSettings.Key.thumbnail)
        store.set(SaveTarget.desktop.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        store.set(timer.seconds, for: ScreenshotsSettings.Key.timer)
        for (key, value) in values { store.set(value, for: key) }
        let home = FileManager.default.temporaryDirectory
        let session = CaptureSession(capture: screen, writer: disk, trash: NoTrash(), pasteboard: Board(), preferences: NoPreferences(),
                                     shutter: NoShutter(), textReader: NoTextReader(), settings: { ScreenshotsSettings.read(store) },
                                     naming: { .english }, locations: ScreenshotsLocations(home: home, desktop: home))
        let controller = CaptureController(owner: ModuleViewModel(transport: LocalTransport()), store: store, session: session,
                                           presentOverlay: { overlay in held.overlays += 1; held.overlay = overlay; return overlay.build() },
                                           presentBar: { bar in held.bars += 1; presentBar(bar) }, tick: tick)
        return Rig(controller: controller, screen: screen, disk: disk, held: held, store: store,
                   display: try XCTUnwrap(base.first?.id), gate: gate)
    }

    nonisolated static func paint(_ n: Int, width: Int, height: Int) -> CGImage {
        switch (n - 1) % 3 {
        case 0: return solid(0, 1, 0, width: width, height: height)
        case 1: return solid(1, 0, 0, width: width, height: height)
        default: return solid(0, 0, 1, width: width, height: height)
        }
    }

    static func drag(_ overlay: CaptureOverlay, on display: DisplayID, _ area: CGRect) {
        overlay.mouseDown(on: display, at: area.origin, flags: [])
        overlay.mouseDragged(on: display, at: CGPoint(x: area.maxX, y: area.maxY), flags: [])
        overlay.mouseUp(on: display)
    }

    static let area = CGRect(x: 50, y: 60, width: 400, height: 300)

    /// What the controller's toast says now, read through the controller's `toast` (private, and the only place a refusal
    /// is told): the body of a refusal, or nil where the toast shows a picture or nothing. A teardown dismisses it, so a
    /// test reads it before.
    static func refusalBody(of controller: CaptureController) -> String? {
        for child in Mirror(reflecting: controller).children where child.label == "toast" {
            if case .refusal(_, let body, _)? = (child.value as? ShotToast)?.model.content { return body }
        }
        return nil
    }

    /// Whether the controller still has a toast to read: false would mean the reader above looks at nothing (a rename).
    static func hasToast(_ controller: CaptureController) -> Bool {
        Mirror(reflecting: controller).children.contains { $0.label == "toast" && $0.value is ShotToast }
    }
}
