import CoreGraphics
import Foundation
import HelmRuntime
import XCTest
@testable import Module_Screenshots_Engine

// Every state the real port has, and no state it does not. The capture fake can
// be denied, lose a display, lose a window between the freeze and the click, and
// hand back a black window — each of those is something the real one does.

/// A picture of one colour, so a test can tell one display's frame from another's.
func makeImage(width: Int, height: Int, red: UInt8 = 0, green: UInt8 = 0, blue: UInt8 = 0) -> CGImage {
    let space = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: CGFloat(red) / 255, green: CGFloat(green) / 255,
                                 blue: CGFloat(blue) / 255, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

/// A picture whose left half is one colour and right half another, so a crop's
/// position can be told from its size.
func makeSplitImage(width: Int, height: Int) -> CGImage {
    let space = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
    context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
    return context.makeImage()!
}

/// The first pixel of a picture as red, green, blue.
func firstPixel(_ image: CGImage) -> (UInt8, UInt8, UInt8) {
    let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // The image's top-left pixel onto the one pixel: CG's origin is the lower-left.
    context.draw(image, in: CGRect(x: 0, y: 1 - image.height, width: image.width, height: image.height))
    let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
    return (bytes[0], bytes[1], bytes[2])
}

final class FakeCapture: ScreenCapturing, @unchecked Sendable {
    private let lock = NSLock()
    private var _access: CaptureAccess = .granted
    private var _freeze: FreezeOutcome = .failed
    private var _windows: [UInt32: WindowShot] = [:]
    private var _freezeCalls = 0, _requestCalls = 0, _windowCalls = 0
    private var _freezeCursors: [Bool] = [], _windowCursors: [Bool] = []

    var grant: CaptureAccess {
        get { lock.withLock { _access } }
        set { lock.withLock { _access = newValue } }
    }
    var outcome: FreezeOutcome {
        get { lock.withLock { _freeze } }
        set { lock.withLock { _freeze = newValue } }
    }
    var windows: [UInt32: WindowShot] {
        get { lock.withLock { _windows } }
        set { lock.withLock { _windows = newValue } }
    }
    var freezeCalls: Int { lock.withLock { _freezeCalls } }
    var requestCalls: Int { lock.withLock { _requestCalls } }
    var windowCalls: Int { lock.withLock { _windowCalls } }
    /// What each call was asked about the pointer, in order — what a session
    /// reads from the setting and hands the port.
    var freezeCursors: [Bool] { lock.withLock { _freezeCursors } }
    var windowCursors: [Bool] { lock.withLock { _windowCursors } }

    func access() -> CaptureAccess { lock.withLock { _access } }
    func requestAccess() { lock.withLock { _requestCalls += 1 } }
    func freeze(cursor: Bool) async -> FreezeOutcome {
        lock.withLock { _freezeCalls += 1; _freezeCursors.append(cursor); return _freeze }
    }
    func window(_ id: UInt32, cursor: Bool) async -> WindowShot {
        lock.withLock { _windowCalls += 1; _windowCursors.append(cursor); return _windows[id] ?? .gone }
    }
}

/// Holds the set of names already taken, as a folder would, and refuses as told.
/// It walks `ShotNames.candidate` exactly as the real writer does, so the ladder
/// is the one under test and not a second copy of it.
final class FakeWriter: ShotWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var _taken: Set<String> = []
    private var _refuse: WriteRefusal?
    private var _written: [(url: URL, bytes: Int)] = []
    private var _data: [Data] = []

    var taken: Set<String> {
        get { lock.withLock { _taken } }
        set { lock.withLock { _taken = newValue } }
    }
    var refuse: WriteRefusal? {
        get { lock.withLock { _refuse } }
        set { lock.withLock { _refuse = newValue } }
    }
    var written: [(url: URL, bytes: Int)] { lock.withLock { _written } }
    /// The bytes of each file written, in order.
    var contents: [Data] { lock.withLock { _data } }

    func write(_ png: Data, into folder: URL, base: String, pathExtension: String) -> ShotWrite {
        lock.withLock {
            if let refusal = _refuse { return .refused(refusal) }
            for attempt in 0..<ShotNames.limit {
                let name = ShotNames.candidate(base: base, pathExtension: pathExtension, attempt: attempt)
                if _taken.contains(name) { continue }
                _taken.insert(name)
                let url = folder.appendingPathComponent(name)
                _written.append((url, png.count))
                _data.append(png)
                return .written(url)
            }
            return .refused(.namesExhausted)
        }
    }
}

final class FakePasteboard: ShotPasteboard, @unchecked Sendable {
    private let lock = NSLock()
    private var _accepts = true
    private var _copies: [Data] = []
    var accepts: Bool {
        get { lock.withLock { _accepts } }
        set { lock.withLock { _accepts = newValue } }
    }
    var copies: [Data] { lock.withLock { _copies } }
    func copy(png: Data) -> PasteOutcome {
        lock.withLock {
            guard _accepts else { return .refused }
            _copies.append(png)
            return .accepted
        }
    }
}

final class FakePreferences: CapturePreferences, @unchecked Sendable {
    private let lock = NSLock()
    private var _location: RawSetting = RawSetting(nil)
    private var _hotkeys: SymbolicHotkeysReading = .absent
    private var _uiSounds: RawSetting = RawSetting(nil)
    var savedLocation: Any? {
        get { lock.withLock { _location.value } }
        set { lock.withLock { _location = RawSetting(newValue) } }
    }
    var hotkeys: SymbolicHotkeysReading {
        get { lock.withLock { _hotkeys } }
        set { lock.withLock { _hotkeys = newValue } }
    }
    /// `com.apple.sound.uiaudio.enabled`: absent, 0, 1 or anything a file can hold.
    var uiAudio: Any? {
        get { lock.withLock { _uiSounds.value } }
        set { lock.withLock { _uiSounds = RawSetting(newValue) } }
    }
    func uiSounds() -> RawSetting { lock.withLock { _uiSounds } }
    func location() -> RawSetting { lock.withLock { _location } }
    func symbolicHotkeys() -> SymbolicHotkeysReading { lock.withLock { _hotkeys } }
}

/// Counts the shutters it was asked to play, and plays nothing.
final class FakeShutter: ShutterPlaying, @unchecked Sendable {
    private let lock = NSLock()
    private var _plays = 0
    var plays: Int { lock.withLock { _plays } }
    func play() { lock.withLock { _plays += 1 } }
}

/// Everything a capture needs, every port named at the construction — a
/// defaulted port is the machine's own, and this one would write a file on the
/// Desktop of whoever runs the suite.
struct Rig {
    let capture = FakeCapture()
    let writer = FakeWriter()
    let pasteboard = FakePasteboard()
    let preferences = FakePreferences()
    let shutter = FakeShutter()
    let home: URL
    let desktop: URL
    var settings: ScreenshotsSettings = .defaults
    let session: CaptureSession

    init(home: URL, settings: ScreenshotsSettings = .defaults) {
        self.home = home
        self.desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        try? FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        let fixed = Date(timeIntervalSince1970: 1_790_000_000)
        session = CaptureSession(
            capture: capture, writer: writer, pasteboard: pasteboard, preferences: preferences, shutter: shutter,
            settings: { settings }, naming: { .english }, now: { fixed },
            locations: ScreenshotsLocations(home: home, desktop: desktop))
    }

    /// One 100×50 point display at 2× (200×100 pixels), main, at the origin.
    static func display(_ id: UInt32, origin: CGPoint = .zero, red: UInt8 = 0) -> DisplayShot {
        .image(FrozenDisplay(id: DisplayID(id),
                             frame: CGRect(x: origin.x, y: origin.y, width: 100, height: 50),
                             scale: 2, image: makeImage(width: 200, height: 100, red: red)))
    }
}

/// The log, read for this module only, with a subject-exists guard: an absence
/// is green when nothing was logged at all, which is the default in a test
/// process because the log is off outside a dev build.
enum ScreenshotsLog {
    static func begin() {
        HelmLog.shared.setEnabled(true)
        HelmLog.shared.clearTail()
    }
    static func end() {
        HelmLog.shared.clearTail()
        HelmLog.shared.setEnabled(false)
    }
    static var lines: [String] {
        HelmLog.shared.recentEntries().filter { $0.category == "screenshots" }.map(\.message)
    }
    /// Proves the log is on, so "nothing was logged" means nothing was logged.
    static func proveTheLogIsOn(file: StaticString = #filePath, line: UInt = #line) {
        HelmLog.shared.info("screenshots", "probe")
        XCTAssertTrue(lines.contains("probe"), "the log is not recording, so an absence proves nothing",
                      file: file, line: line)
        HelmLog.shared.clearTail()
    }
}
