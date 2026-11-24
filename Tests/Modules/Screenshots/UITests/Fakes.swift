import CoreGraphics
import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

// One fake per port of the Screenshots engine, for the whole UI test target: `FakeScreen` (`ScreenCapturing`),
// `CountingBoard` (`ShotPasteboard`), `AsideTrash` (`ShotTrashing`) and `CountingShutter` (`ShutterPlaying`). A
// scene says what it needs when it builds one; it does not carry a class of its own.

/// The screen of a fake session: counts its freezes, answers with the outcome it was given, and may hold each freeze
/// at a gate (`gate`, which the test may set after building) or hold the next ones until `release()` (`hold()`).
/// A grant nobody asks about is `access: .denied` with `outcome: .failed`.
final class FakeScreen: ScreenCapturing, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var holding = false
    private var waiting: CheckedContinuation<Void, Never>?
    private let outcome: FreezeOutcome
    private let granted: CaptureAccess
    private let windowShot: WindowShot
    private let _gate: Locked<PromptGate?>
    private let _onFreeze = Locked<() -> Void>({})
    /// Held freezes wait here; nil answers at once.
    var gate: PromptGate? { get { _gate.value } set { _gate.value = newValue } }
    /// Called inside each freeze, so a test can read what the countdown had reached.
    var onFreeze: () -> Void { get { _onFreeze.value } set { _onFreeze.value = newValue } }

    init(outcome: FreezeOutcome, access: CaptureAccess = .granted, window: WindowShot = .gone, gate: PromptGate? = nil) {
        self.outcome = outcome
        self.granted = access
        self.windowShot = window
        self._gate = Locked(gate)
    }

    var freezes: Int { lock.withLock { count } }
    var isHeld: Bool { lock.withLock { waiting != nil } }
    func hold() { lock.withLock { holding = true } }
    func release() {
        let next: CheckedContinuation<Void, Never>? = lock.withLock { holding = false; defer { waiting = nil }; return waiting }
        next?.resume()
    }
    func access() -> CaptureAccess { granted }
    func requestAccess() {}
    func freeze(cursor: Bool) async -> FreezeOutcome {
        lock.withLock { count += 1 }
        onFreeze()
        if let gate { await gate.arrive() }
        if lock.withLock({ holding }) {
            await withCheckedContinuation { continuation in lock.withLock { waiting = continuation } }
        }
        return outcome
    }
    func window(_ id: UInt32, cursor: Bool, shadow: Bool) async -> WindowShot { windowShot }

    /// A frozen picture of every real screen (built into panels that are never ordered in) or, when `real` is
    /// false, of a display id no screen carries, which nothing can reach.
    @MainActor
    static func frozen(real: Bool) throws -> FreezeOutcome {
        if real { return .frozen(Freeze(displays: try OverlayRig.frames().map { .image($0) }, windows: [])) }
        let context = try XCTUnwrap(CGContext(data: nil, width: 20, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        return .frozen(Freeze(displays: [.image(FrozenDisplay(id: DisplayID(0xDEAD_BEEF),
                                                              frame: CGRect(x: 0, y: 0, width: 10, height: 5),
                                                              scale: 2, image: image))],
                              windows: []))
    }
}

/// The clipboard of a scene: it counts every single copy (`copies`) and keeps every group written, one entry a write
/// (`lists`); it takes everything unless `accepts` is set false. **A group is taught only to a board built with
/// `groups: true`:** a group written to any other fails the test that wrote it, as a port that was never shown a group
/// would. A scene whose board must hold or cancel keeps its own.
final class CountingBoard: ShotPasteboard, @unchecked Sendable {
    private let lock = NSLock()
    private let groups: Bool
    private var _copies = 0
    private var _lists: [[Data]] = []
    private var _accepts = true
    init(groups: Bool = false) { self.groups = groups }
    var copies: Int { lock.withLock { _copies } }
    var lists: [[Data]] { lock.withLock { _lists } }
    var accepts: Bool {
        get { lock.withLock { _accepts } }
        set { lock.withLock { _accepts = newValue } }
    }
    func copy(png: Data) -> PasteOutcome {
        lock.withLock {
            guard _accepts else { return .refused }
            _copies += 1
            return .accepted
        }
    }
    func copy(pngs: [Data]) -> PasteOutcome {
        guard groups else { XCTFail("this test's board was never taught a group"); return .refused }
        return lock.withLock {
            guard _accepts else { return .refused }
            _lists.append(pngs)
            return .accepted
        }
    }
    func copy(text: String) -> PasteOutcome { .accepted }
}

/// The Trash as a folder of the test's: what the session moves there is really moved, and listed; it can hold a
/// move at its door, fail it, or run something in the moment after it. Shared by the editor's and the pile's scenes.
/// `refusing()` is the Trash of a session whose test replaces nothing: it refuses every move, as the real one does on
/// a volume that is read-only, so a test that reached it by mistake would move nothing and say so.
final class AsideTrash: ShotTrashing, @unchecked Sendable {
    let folder: URL
    private let lock = NSLock()
    private var _moved: [URL] = [], _asked: [URL] = []
    private var _holding = false
    private let _failure = Locked<NSError?>(nil)
    private let _after = Locked<((URL) -> Void)?>(nil)
    private let gate = DispatchSemaphore(value: 0)
    init(_ folder: URL) { self.folder = folder }
    static func refusing() -> AsideTrash {
        let trash = AsideTrash(URL(fileURLWithPath: "/dev/null"))
        trash.failure = CocoaError(.fileWriteVolumeReadOnly) as NSError
        return trash
    }
    /// Run in the moment between the Trash and the claim, with the path that was moved.
    var after: ((URL) -> Void)? { get { _after.value } set { _after.value = newValue } }
    var moved: [URL] { lock.withLock { _moved } }
    var asked: [URL] { lock.withLock { _asked } }
    var failure: NSError? { get { _failure.value } set { _failure.value = newValue } }
    func hold() { lock.withLock { _holding = true } }
    func release() { lock.withLock { _holding = false }; gate.signal() }
    func trash(_ url: URL) throws {
        lock.withLock { _asked.append(url) }
        if lock.withLock({ _holding }) { gate.wait() }
        if let failure { throw failure }
        try FileManager.default.moveItem(at: url, to: folder.appendingPathComponent(UUID().uuidString))
        lock.withLock { _moved.append(url) }
        after?(url)
    }
}

/// The shutter of a scene: counts the plays and plays nothing. A scene that does not listen for it never reads `plays`.
final class CountingShutter: ShutterPlaying, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var plays: Int { lock.withLock { count } }
    func play() { lock.withLock { count += 1 } }
}
