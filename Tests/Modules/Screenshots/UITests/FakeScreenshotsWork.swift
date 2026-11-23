import CoreGraphics
import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

// One side of the boundary the Screenshots view model stands on: the engine, as `ScreenshotsWork` names it.
// It carries what that port can do and nothing more: a stream that replays the last state and then every later
// one, a refresh that answers on the stream, and a factory that hands out a session once asked. Every session it
// builds stands on `FakeScreen` (`Fakes.swift`), which constructs no `SCKCapture` and reaches no real screen; a session never
// asked for is a call this fake never saw, which is what `calls` is for.

/// A disk that counts its writes and keeps no file.
final class FakeWorkDisk: ShotWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var written: Int { lock.withLock { count } }
    func reading(of url: URL) -> ShotReading? { nil }
    func claim(_ written: URL, as name: URL) -> Bool { false }
    func write(_ png: Data, into folder: URL, base: String, pathExtension: String) -> ShotWrite {
        lock.withLock { count += 1 }
        return .written(WrittenShot(url: folder.appendingPathComponent(base + "." + pathExtension), reading: NoFile.reading))
    }
}

final class FakeScreenshotsWork: ScreenshotsWork, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    private var last: ScreenshotsState?
    private var continuations: [UUID: AsyncStream<ScreenshotsState>.Continuation] = [:]
    private var _opened = 0, _said = 0

    let screen: FakeScreen
    let disk = FakeWorkDisk()
    let board = CountingBoard()
    /// Where its sessions think home is; the test's scratch directory, which its disk never writes into.
    let home: URL

    init(screen: FakeScreen, home: URL) { self.screen = screen; self.home = home }

    /// Every call the model made, in order: "stream", "refresh", "session".
    var calls: [String] { lock.withLock { _calls } }
    func count(_ call: String) -> Int { calls.filter { $0 == call }.count }
    /// Streams handed out and not yet let go (finished, or terminated by their consumer).
    var openStreams: Int { lock.withLock { continuations.count } }
    /// Streams ever handed out.
    var streamsOpened: Int { lock.withLock { _opened } }
    /// States said, whether or not anybody was listening.
    var said: Int { lock.withLock { _said } }

    func stream() -> AsyncStream<ScreenshotsState> {
        let key = UUID()
        return AsyncStream { continuation in
            lock.withLock {
                _calls.append("stream")
                _opened += 1
                continuations[key] = continuation
                // The last state first, as the engine's stream does.
                if let last { continuation.yield(last) }
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.withLock { _ = self.continuations.removeValue(forKey: key) }
            }
        }
    }

    func refresh() { lock.withLock { _calls.append("refresh") } }

    func session(store: NamespacedStore, naming: @escaping () -> ShotNaming) -> CaptureSession {
        lock.withLock { _calls.append("session") }
        return CaptureSession(capture: screen, writer: disk, trash: AsideTrash.refusing(), pasteboard: board,
                              preferences: NoPreferences(), shutter: CountingShutter(), textReader: NoTextReader(),
                              settings: { ScreenshotsSettings.read(store) }, naming: naming,
                              locations: ScreenshotsLocations(home: home, desktop: home))
    }

    /// The engine says a new state: every open stream gets it, and a stream opened later gets it first.
    func say(_ state: ScreenshotsState) {
        let open = lock.withLock { () -> [AsyncStream<ScreenshotsState>.Continuation] in
            _said += 1
            last = state
            return Array(continuations.values)
        }
        for continuation in open { continuation.yield(state) }
    }
}

/// A model over the fake with every window it could raise held back: the overlay is built and never shown (or
/// declined), the bar is counted and never ordered in, the toast has no panel and a clock the test holds, the pins
/// are never presented. Nothing here reaches a screen, and nothing constructs `SCKCapture`.
@MainActor
final class FakeScreenshotsScene {
    let work: FakeScreenshotsWork
    let model: ScreenshotsViewModel
    let store: NamespacedStore
    let clock = StepClock()
    /// The controller the model built, once it did; nil before the first press.
    private(set) var controller: CaptureController?
    private(set) var overlay: CaptureOverlay?
    private(set) var overlaysPresented = 0
    private(set) var barsPresented = 0
    private(set) var controllersBuilt = 0

    /// `buildOverlay`: the overlay is built (panels on the real screens, never ordered in) and so is `isOpen`;
    /// false declines it, which counts the presentation and builds nothing.
    init(screen: FakeScreen, home: URL, target: SaveTarget = .clipboard, buildOverlay: Bool = false) {
        work = FakeScreenshotsWork(screen: screen, home: home)
        store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        store.set(false, for: ScreenshotsSettings.Key.thumbnail)
        store.set(target.rawValue, for: ScreenshotsSettings.Key.saveTarget)
        let holder = Holder()
        model = ScreenshotsViewModel(work: work, store: store, makeController: { store, session in
            let made = CaptureController(
                store: store, session: session,
                presentOverlay: { overlay in
                    holder.scene?.overlaysPresented += 1
                    holder.scene?.overlay = overlay
                    overlay.reducesMotion = { false }
                    return buildOverlay ? overlay.build() : false
                },
                presentBar: { _ in holder.scene?.barsPresented += 1 },
                toast: ShotToast(tick: { try await holder.scene?.clock.tick($0) }, windowed: false))
            holder.scene?.controller = made
            holder.scene?.controllersBuilt += 1
            return made
        })
        holder.scene = self
    }

    private final class Holder { weak var scene: FakeScreenshotsScene? }

    /// A scene over a screen that freezes one blank frame per real screen at once, no overlay built.
    static func plain(in test: XCTestCase) throws -> FakeScreenshotsScene {
        FakeScreenshotsScene(screen: FakeScreen(outcome: try FakeScreen.frozen(real: false)), home: test.scratchDirectory("shots-scene"))
    }

    /// A scene whose screen's freeze waits on the returned gate (`held`), over frames of the real screens when the
    /// overlay is built.
    static func withGate(in test: XCTestCase, held: Bool = true, buildOverlay: Bool = false) throws -> (FakeScreenshotsScene, PromptGate) {
        let gate = PromptGate()
        let screen = FakeScreen(outcome: try FakeScreen.frozen(real: buildOverlay), gate: held ? gate : nil)
        return (FakeScreenshotsScene(screen: screen, home: test.scratchDirectory("shots-scene"), buildOverlay: buildOverlay), gate)
    }

    /// Brings the area press to an open overlay and returns it.
    func openOverlay(_ gate: PromptGate, in test: XCTestCase, pageFirst: Bool = false) async throws -> CaptureOverlay {
        if pageFirst { model.refresh() }
        model.press(.area)
        await gate.reached()
        await gate.open()
        await test.waitUntil("the overlay reached the seam") { self.overlay != nil }
        let overlay = try XCTUnwrap(self.overlay)
        XCTAssertTrue(overlay.isOpen, "the control: the overlay is up before the switch")
        return overlay
    }
}
