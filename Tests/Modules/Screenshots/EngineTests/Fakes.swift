import CoreGraphics
import Foundation
import HelmRuntime
import HelmTestSupport
import ImageIO
import XCTest
@testable import Module_Screenshots_Engine

// Every state the real port has, and no state it does not. The capture fake can
// be denied, lose a display, lose a window between the freeze and the click, and
// hand back a black window — each of those is something the real one does.

extension ShotWrite {
    /// The file that was written, nil for a refusal; the product reads the `.written` case itself.
    var url: URL? {
        if case .written(let shot) = self { shot.url } else { nil }
    }
}

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

/// The Screenshots settings over `backing`, seeded with `raw` values written the way the plist holds them, at their full
/// key, so a value no setter would write still lands.
func screenshotsStore(_ raw: [String: Any] = [:], backing: InMemoryKeyValueStore = InMemoryKeyValueStore()) -> NamespacedStore {
    for (key, value) in raw { backing.set(value, forKey: "module.screenshots.\(key)") }
    return NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: backing)
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

/// The bytes of a picture drawn into an RGBA8 premultiplied context in `space`, which a test reads in place of the picture.
func rgbaBytes(_ image: CGImage, space: CGColorSpace = CGColorSpaceCreateDeviceRGB()) -> [UInt8] {
    let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
}

/// The same pixels packed as 0xRRGGBB, one to a pixel.
func packedRGB(_ image: CGImage, space: CGColorSpace = CGColorSpaceCreateDeviceRGB()) -> [UInt32] {
    let bytes = rgbaBytes(image, space: space)
    return (0..<(image.width * image.height)).map { UInt32(bytes[$0 * 4]) << 16 | UInt32(bytes[$0 * 4 + 1]) << 8 | UInt32(bytes[$0 * 4 + 2]) }
}

/// One pixel of a picture as red, green, blue, read at (x, y) from the top left, in the picture's own colour space:
/// reading it in another converts it, and a ground that was composed in sRGB would read as a stranger to itself.
func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
    let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
    let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
    return (bytes[0], bytes[1], bytes[2])
}

/// The width of the picture a PNG holds.
func width(of png: Data) throws -> Int {
    let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil), "a write that is no picture")
    return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil)).width
}

/// A picture in which every pixel has a colour of its own, in `space` at `bits` a channel.
func hashedPattern(width: Int, height: Int, space: CGColorSpace? = nil, bits: Int = 8) -> CGImage {
    let space = space ?? CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: bits, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setShouldAntialias(false)
    for y in 0..<height { for x in 0..<width {
        let colour = (UInt32(y * width + x) &* 2_654_435_761 &+ 12_345) & 0xFF_FFFF
        context.setFillColor(CGColor(colorSpace: space, components: [CGFloat(colour >> 16) / 255, CGFloat(colour >> 8 & 0xFF) / 255,
                                                                     CGFloat(colour & 0xFF) / 255, 1])!)
        context.fill(CGRect(x: x, y: height - 1 - y, width: 1, height: 1))
    } }
    return context.makeImage()!
}

/// One recognised line of text, with `matches` found in it.
func reading(_ matches: [PrivateMatch], line string: String = "line") -> [RecognizedLine] {
    [RecognizedLine(string: string, box: CGRect(x: 0, y: 0, width: 1, height: 1), matches: matches)]
}

/// A layer of `tool` over `rect`, the standard style unless `filled`.
func layer(_ tool: AnnotationTool, _ rect: CGRect, filled: Bool = false, id: Annotation.ID = 1) -> Annotation {
    Annotation(tool: tool, start: rect.origin, end: CGPoint(x: rect.maxX, y: rect.maxY),
               style: AnnotationStyle(filled: filled), id: id)
}

/// A recognised line with a box at (`x`, `y`) of `size` in the picture's unit square.
func line(_ string: String, x: CGFloat = 0.1, y: CGFloat = 0.5, size: CGSize = CGSize(width: 0.3, height: 0.05)) -> RecognizedLine {
    RecognizedLine(string: string, box: CGRect(origin: CGPoint(x: x, y: y), size: size))
}

// A scratch home with its Desktop folder made, for a test that resolves a save folder against real directories.
extension XCTestCase {
    func homeWithDesktop(_ label: String) -> (home: URL, desktop: URL) {
        let home = scratchDirectory(label)
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        try? FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        return (home, desktop)
    }
}

final class FakeCapture: ScreenCapturing, @unchecked Sendable {
    private let lock = NSLock()
    private let _access = Locked<CaptureAccess>(.granted)
    private var _freeze: FreezeOutcome = .failed
    private var _windows: [UInt32: WindowShot] = [:]
    private var _freezeCalls = 0, _requestCalls = 0, _windowCalls = 0
    private var _freezeCursors: [Bool] = [], _windowCursors: [Bool] = [], _windowShadows: [Bool] = []

    var grant: CaptureAccess { get { _access.value } set { _access.value = newValue } }
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
    /// Whether each window call asked for the shadow, in order.
    var windowShadows: [Bool] { lock.withLock { _windowShadows } }

    func access() -> CaptureAccess { _access.value }
    func requestAccess() { lock.withLock { _requestCalls += 1 } }
    func freeze(cursor: Bool) async -> FreezeOutcome {
        lock.withLock { _freezeCalls += 1; _freezeCursors.append(cursor); return _freeze }
    }
    func window(_ id: UInt32, cursor: Bool, shadow: Bool) async -> WindowShot {
        lock.withLock {
            _windowCalls += 1; _windowCursors.append(cursor); _windowShadows.append(shadow)
            return _windows[id] ?? .gone
        }
    }
}

/// What moved, in the order it moved: the reverse channel of the writer and the trash, which share one, so that a
/// test reads the three steps of a replacement as one sequence.
final class ShotMoves: @unchecked Sendable {
    enum Move: Equatable {
        case wrote(URL)
        case trashed(URL)
        case claimed(URL, as: URL)
    }
    private let lock = NSLock()
    private var _all: [Move] = []
    var all: [Move] { lock.withLock { _all } }
    func note(_ move: Move) { lock.withLock { _all.append(move) } }
}

/// Holds the set of names already taken, as a folder would, and refuses as told.
/// It walks `ShotNames.candidate` exactly as the real writer does, so the ladder
/// is the one under test and not a second copy of it.
///
/// It also holds what `lstat` would say of each file it wrote, which a test changes to stand for a file that was
/// renamed away (`nil`), written into, replaced by another or turned into a link, and it can refuse a claim.
final class FakeWriter: ShotWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var _taken: Set<String> = []
    private var _refuse: WriteRefusal?
    private var _written: [(url: URL, bytes: Int)] = []
    private var _readings: [String: ShotReading] = [:]
    private var _inode: UInt64 = 100
    let moves: ShotMoves

    init(moves: ShotMoves = ShotMoves()) { self.moves = moves }

    /// The file left: its name is free and nothing is read at it. What a trash that succeeded does to the folder.
    func vanish(_ url: URL) {
        lock.withLock {
            _readings[url.path] = nil
            _taken.remove(url.lastPathComponent)
        }
    }

    var taken: Set<String> {
        get { lock.withLock { _taken } }
        set { lock.withLock { _taken = newValue } }
    }
    var refuse: WriteRefusal? {
        get { lock.withLock { _refuse } }
        set { lock.withLock { _refuse = newValue } }
    }
    var written: [(url: URL, bytes: Int)] { lock.withLock { _written } }

    func write(_ png: Data, into folder: URL, base: String, pathExtension: String) -> ShotWrite {
        lock.withLock {
            if let refusal = _refuse { return .refused(refusal) }
            for attempt in 0..<ShotNames.limit {
                let name = ShotNames.candidate(base: base, pathExtension: pathExtension, attempt: attempt)
                if _taken.contains(name) { continue }
                _taken.insert(name)
                let url = folder.appendingPathComponent(name)
                _written.append((url, png.count))
                _inode += 1
                let reading = ShotReading(identity: PathCanonical.FileIdentity(device: 1, inode: _inode), size: Int64(png.count),
                                          modifiedSeconds: 1_790_000_000, modifiedNanoseconds: Int64(_inode), isRegularFile: true)
                _readings[url.path] = reading
                moves.note(.wrote(url))
                return .written(WrittenShot(url: url, reading: reading))
            }
            return .refused(.namesExhausted)
        }
    }

    func reading(of url: URL) -> ShotReading? { lock.withLock { _readings[url.path] } }

    func claim(_ written: URL, as name: URL) -> Bool {
        lock.withLock {
            guard let reading = _readings[written.path],
                  _readings[name.path] == nil, !_taken.contains(name.lastPathComponent) else { return false }
            _readings[written.path] = nil
            _readings[name.path] = reading
            _taken.remove(written.lastPathComponent)
            _taken.insert(name.lastPathComponent)
            moves.note(.claimed(written, as: name))
            return true
        }
    }
}

/// The Trash in the two states the real one has: the file leaves, or the move throws what `FileManager` throws.
/// Every path it was asked to move is recorded, a refused one too.
final class FakeTrash: ShotTrashing, @unchecked Sendable {
    private let lock = NSLock()
    private let folder: FakeWriter
    private var _failure: NSError?
    private var _asked: [URL] = []

    init(folder: FakeWriter) { self.folder = folder }

    /// The Cocoa error the next moves throw; nil and they succeed.
    var failure: NSError? {
        get { lock.withLock { _failure } }
        set { lock.withLock { _failure = newValue } }
    }
    var asked: [URL] { lock.withLock { _asked } }

    func trash(_ url: URL) throws {
        let failure = lock.withLock { _asked.append(url); return _failure }
        if let failure { throw failure }
        folder.vanish(url)
        folder.moves.note(.trashed(url))
    }
}

final class FakePasteboard: ShotPasteboard, @unchecked Sendable {
    private let lock = NSLock()
    private var _accepts = true
    private var _copies: [Data] = []
    private var _texts: [String] = []
    var accepts: Bool {
        get { lock.withLock { _accepts } }
        set { lock.withLock { _accepts = newValue } }
    }
    var copies: [Data] { lock.withLock { _copies } }
    /// Every list that was written, one entry a write: a group copied in one write is one entry here.
    private var _lists: [[Data]] = []
    var lists: [[Data]] { lock.withLock { _lists } }
    /// The text of each copy that was taken, in order.
    var texts: [String] { lock.withLock { _texts } }
    func copy(png: Data) -> PasteOutcome {
        lock.withLock {
            guard _accepts else { return .refused }
            _copies.append(png)
            return .accepted
        }
    }
    func copy(pngs: [Data]) -> PasteOutcome {
        lock.withLock {
            guard _accepts else { return .refused }
            _lists.append(pngs)
            return .accepted
        }
    }
    func copy(text: String) -> PasteOutcome {
        lock.withLock {
            guard _accepts else { return .refused }
            _texts.append(text)
            return .accepted
        }
    }
}

/// Reads what it was told to and counts the pictures it was handed. It answers at once;
/// `held` makes it wait for `release()` first, which is how a test has a reading still in flight when the
/// editor goes away.
final class FakeTextReader: ScreenTextReading, @unchecked Sendable {
    private let lock = NSLock()
    private let _reading = Locked<TextReading>(.read([]))
    private var _calls = 0
    private var _held = false
    private var _waiting: [CheckedContinuation<Void, Never>] = []

    var reading: TextReading { get { _reading.value } set { _reading.value = newValue } }
    var held: Bool {
        get { lock.withLock { _held } }
        set { lock.withLock { _held = newValue } }
    }
    var calls: Int { lock.withLock { _calls } }

    func read(_ image: CGImage) async -> TextReading {
        // The call is counted and the wait begun in one step, so a `release()` cannot fall between them.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let answersNow = lock.withLock { () -> Bool in
                _calls += 1
                guard _held else { return true }
                _waiting.append(continuation)
                return false
            }
            if answersNow { continuation.resume() }
        }
        return _reading.value
    }

    /// Lets every call that is waiting answer.
    func release() {
        let waiting = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            _held = false
            defer { _waiting = [] }
            return _waiting
        }
        waiting.forEach { $0.resume() }
    }
}

final class FakePreferences: CapturePreferences, @unchecked Sendable {
    private let lock = NSLock()
    private var _location: RawSetting = RawSetting(nil)
    private let _hotkeys = Locked<SymbolicHotkeysReading>(.absent)
    private var _uiSounds: RawSetting = RawSetting(nil)
    var savedLocation: Any? {
        get { lock.withLock { _location.value } }
        set { lock.withLock { _location = RawSetting(newValue) } }
    }
    var hotkeys: SymbolicHotkeysReading { get { _hotkeys.value } set { _hotkeys.value = newValue } }
    /// `com.apple.sound.uiaudio.enabled`: absent, 0, 1 or anything a file can hold.
    var uiAudio: Any? {
        get { lock.withLock { _uiSounds.value } }
        set { lock.withLock { _uiSounds = RawSetting(newValue) } }
    }
    func uiSounds() -> RawSetting { lock.withLock { _uiSounds } }
    func location() -> RawSetting { lock.withLock { _location } }
    func symbolicHotkeys() -> SymbolicHotkeysReading { _hotkeys.value }
}

/// Counts the shutters it was asked to play, and plays nothing.
final class FakeShutter: ShutterPlaying, @unchecked Sendable {
    private let _plays = LockedCount()
    var plays: Int { _plays.value }
    func play() { _plays.bump() }
}

/// Everything a capture needs, every port named at the construction — a
/// defaulted port is the machine's own, and this one would write a file on the
/// Desktop of whoever runs the suite.
struct Rig {
    let capture = FakeCapture()
    let writer: FakeWriter
    let trash: FakeTrash
    let pasteboard = FakePasteboard()
    let preferences = FakePreferences()
    let shutter = FakeShutter()
    let reader = FakeTextReader()
    let home: URL
    let desktop: URL
    let session: CaptureSession

    init(home: URL, settings: ScreenshotsSettings = .defaults) {
        self.home = home
        let writer = FakeWriter()
        self.writer = writer
        self.trash = FakeTrash(folder: writer)
        self.desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        try? FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        let fixed = Date(timeIntervalSince1970: 1_790_000_000)
        session = CaptureSession(
            capture: capture, writer: writer, trash: trash, pasteboard: pasteboard, preferences: preferences, shutter: shutter, textReader: reader,
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
///
/// Not `tailTheLog()` and `loggedLines`: those are `XCTestCase` methods that
/// register their own teardown, and this enum is called from a `defer` and
/// re-armed in the middle of a test (`TheChosenFolderIsJudgedLikeMacOSsTests`).
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
