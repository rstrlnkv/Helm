import CoreGraphics
import Foundation
import HelmRuntime
@testable import Tweak_DisplayCorners_Engine

// The ports of Display Corners' engine, each with every state the real one has: running or not, how many times
// it was started and stopped, and the reverse channel (what the system says unasked). A fake keeps the closure
// it was given after `stop()`, as the system can deliver one already queued, so a test can fire it late.

@MainActor final class FakeDisplays: DisplayPort {
    var list: [DisplayDescriptor] = []
    private(set) var reads = 0
    func displays() -> [DisplayDescriptor] {
        reads += 1
        return list
    }
}

@MainActor final class FakeWindows: WindowSamplePort {
    /// What the window list answers: absent is off screen.
    var bounds: [Int: CGRect] = [:]
    private(set) var asked: [[Int]] = []
    func onScreenBounds(of windowNumbers: [Int]) -> [Int: CGRect] {
        asked.append(windowNumbers.sorted())
        return bounds.filter { windowNumbers.contains($0.key) }
    }
}

@MainActor final class FakePointer: PointerPort {
    /// What `start` answers: `.tap`, `.monitorsOnly` or `.unavailable`.
    var answers = PointerMode.tap
    private(set) var running = false
    private(set) var starts = 0
    private(set) var onMove: (@MainActor (CGPoint) -> Void)?
    private(set) var onModeChange: (@MainActor (PointerMode) -> Void)?
    var position: CGPoint?
    private(set) var locationReads = 0
    var refusesWarp = false
    private(set) var warps: [CGPoint] = []

    func start(onMove: @escaping @MainActor (CGPoint) -> Void,
               onModeChange: @escaping @MainActor (PointerMode) -> Void) -> PointerMode {
        starts += 1
        running = answers != .unavailable
        self.onMove = onMove
        self.onModeChange = onModeChange
        return answers
    }
    func stop() {
        running = false
    }
    func location() -> CGPoint? {
        locationReads += 1
        return position
    }
    func warp(to point: CGPoint) -> Bool {
        guard !refusesWarp else { return false }
        warps.append(point)
        return true
    }
    /// The pointer moved to `point`, as the listener says. Works after `stop()`.
    func move(to point: CGPoint) { onMove?(point) }
    /// The system took the tap away for good, and the monitors stand in.
    func drop() { onModeChange?(.monitorsOnly) }
}

@MainActor final class FakeEvents: SystemEventsPort {
    private(set) var running = false
    private(set) var starts = 0
    private var onEvent: (@MainActor (SystemEvent) -> Void)?
    func start(_ onEvent: @escaping @MainActor (SystemEvent) -> Void) {
        starts += 1
        running = true
        self.onEvent = onEvent
    }
    func stop() {
        running = false
    }
    /// Works after `stop()`.
    func fire(_ event: SystemEvent) { onEvent?(event) }
}

@MainActor final class FakeTicker: TickerPort {
    private(set) var isRunning = false
    private(set) var starts = 0
    private(set) var hz: Double?
    private var onTick: (@MainActor () -> Void)?
    func start(hz: Double, _ onTick: @escaping @MainActor () -> Void) {
        starts += 1
        isRunning = true
        self.hz = hz
        self.onTick = onTick
    }
    func stop() {
        isRunning = false
    }
    /// Works after `stop()`.
    func tick() { onTick?() }
}

@MainActor final class FakeClock: MonotonicClock {
    /// Settable both ways: a clock that goes backwards is a state the engine must hold.
    var time: TimeInterval = 100
    func now() -> TimeInterval { time }
}

@MainActor final class FakeMasks: CornerMasks {
    private(set) var shows: [MaskDiff] = []
    private(set) var standing: [MaskKey: Int] = [:]
    private var next = 1000
    private(set) var rounding: [(rounded: Bool, display: UInt32)] = []
    private(set) var removals = 0

    func show(_ diff: MaskDiff) -> [MaskKey: Int] {
        shows.append(diff)
        for key in diff.removed { standing[key] = nil }
        for spec in diff.added {
            standing[spec.key] = next
            next += 1
        }
        return standing
    }
    func setRounded(_ rounded: Bool, display: UInt32) { rounding.append((rounded, display)) }
    func presentation(of key: MaskKey) -> MaskPresentation? { standing[key] == nil ? nil : MaskPresentation(scale: 1, opacity: 1, ready: true) }
    func removeAll() {
        removals += 1
        standing = [:]
    }
}

/// An engine over fakes, and the fakes.
@MainActor struct Rig {
    static let builtIn = DisplayDescriptor(
        id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), quartzBounds: CGRect(x: 0, y: 0, width: 1512, height: 982),
        backingScale: 2, pixelsPerPoint: 2, isBuiltIn: true, isMirrored: false, maxFPS: 120)
    /// To the right of the built-in one, its bottom edges level with it.
    static let external = DisplayDescriptor(
        id: 2, frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080), quartzBounds: CGRect(x: 1512, y: -98, width: 1920, height: 1080),
        backingScale: 1, pixelsPerPoint: 1, isBuiltIn: false, isMirrored: false, maxFPS: 60)

    let store: NamespacedStore
    let engine: DisplayCornersEngine
    let displays = FakeDisplays()
    let windows = FakeWindows()
    let pointer = FakePointer()
    let events = FakeEvents()
    let ticker = FakeTicker()
    let clock = FakeClock()
    let masks = FakeMasks()

    /// The tweak's own store, as the host builds it: the namespace comes from the engine's id. The namespace
    /// is a copy of `TweakHost.namespace(for:)`, since this target cannot import HelmApp. If the host's form
    /// drifted, `ASwitchedOffTweakRunsNothingTests.testTwoTweaksKeepSeparateFlagsUnderTheirOwnNamespaces` would go red on its
    /// pinned `tweak.beta`, and this copy would then be changed by hand: no test here compares the two.
    static func store(over backing: KeyValueStore = InMemoryKeyValueStore()) -> NamespacedStore {
        NamespacedStore(namespace: namespace(), backing: backing)
    }
    private static func namespace() -> String { "tweak.\(DisplayCornersEngine.moduleID)" }

    init(store: NamespacedStore = Rig.store(), displays shown: [DisplayDescriptor] = [Rig.builtIn]) {
        self.store = store
        displays.list = shown
        engine = DisplayCornersEngine(store: store, masks: masks, displays: displays, windows: windows,
                                      pointer: pointer, events: events, ticker: ticker, clock: clock)
    }

    /// Where a mask window rests, in Quartz's coordinates: what the window list says while nothing moves.
    func resting(_ key: MaskKey) -> CGRect? {
        guard let spec = engine.state.masks.first(where: { $0.key == key }),
              let owner = displays.list.first(where: { $0.id == key.display }) else { return nil }
        return CornerFrames.restingQuartzFrame(window: spec.frame, display: owner.frame, quartzBounds: owner.quartzBounds)
    }

    /// Every mask window at rest in the window list.
    func settle() {
        for (key, number) in masks.standing { windows.bounds[number] = resting(key) }
    }
}
