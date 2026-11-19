import CoreGraphics
import Foundation
import HelmContract
import HelmRuntime

/// **Display Corners' engine: decides which masks stand, keeps them rounded while the windows rest, and
/// holds the pointer off them.**
///
/// Everything runs on the main actor: the ports call back on main, and every call behind them is a main-thread
/// call. The host calls `activate()` and `deactivate()` on main too, which the protocol cannot say, so both
/// enter the actor with `MainActor.assumeIsolated` as `TweaksEngine` does.
///
/// **One start path.** Everything that starts something goes through `reconcile()`, which decides from the
/// engine being active, the displays being awake, the two switches and the calibration what runs. It is
/// reached from `activate()` on an engine that is not yet active, from a switch or radius command on an active
/// engine, from a calibration command that changes something (a begin when none runs, a colour that differs
/// from the last, an end when one runs), from a screen change while the displays are awake, and from a wake.
/// Nothing is started from
/// `activate()` directly, so a switch that was off at activation and turned on later starts the same things the
/// same way. The other events only stop or sample: sleep tears the visuals down, a Space change takes a sample,
/// and a command on an engine that is not active stops at the store.
///
/// **The tap and the monitors are alternatives** (`EventPointer`), and the pointer is looked at only when it
/// moves: the timer does not run the correction. The one pass it does run is when the set of displays that hold
/// the pointer changes (a display becomes rounded and at rest, or stops being so, or the layout was laid out
/// again), since the pointer may already be inside a corner then.
///
/// **A callback that arrives after `deactivate()` does nothing**: every closure handed to a port checks `active`
/// first, because a callback already queued on the run loop lands after the port was told to stop.
///
/// There is no `deinit` here: a port that holds a system resource (`EventPointer`, `WorkspaceSystemEvents`,
/// `CommonModeTicker`) stops itself in its own.
@MainActor public final class DisplayCornersEngine: ModuleEngine {
    /// This tweak's id, and the only place it is written down: it reaches disk in the
    /// `tweak.<id>` namespace of its store, so the descriptor builds its id from this.
    /// **The string never changes.**
    public nonisolated static let moduleID = "display-corners"

    private let store: NamespacedStore
    private let masks: any CornerMasks
    private let display: any DisplayPort
    private let windowSampler: any WindowSamplePort
    private let pointer: any PointerPort
    private let events: any SystemEventsPort
    private let ticker: any TickerPort
    private let clock: any MonotonicClock

    private nonisolated let news = EngineNews<CornerState>()
    /// What was last said; a payload equal to it is not said again.
    private var last: CornerState?

    private var settings: StoredCornerSettings
    private var active = false
    private var asleep = false
    private var calibration: CalibrationColour?
    private var eventsStarted = false
    private var pointerMode = PointerMode.off
    private var reference: CGFloat = 1

    private var specs: [MaskSpec] = []
    private var windows: [MaskKey: Int] = [:]
    private var motion: [UInt32: DisplayMotion] = [:]
    /// Where each window rests, in Quartz's coordinates, by window number.
    private var resting: [Int: CGRect] = [:]
    private var geometry: [MaskKey: CornerGeometry] = [:]
    /// Per display: rounded and at rest, the state in which its masks hold the pointer.
    private var holding: [UInt32: Bool] = [:]
    /// The displays whose masks were all off screen at the last sample: away, as in a native full-screen Space,
    /// where the masks are not shown (`.fullScreenNone`). An away display is not rounded and holds no pointer,
    /// but it is not unsettled either: nothing on it moves, so it does not raise the sampling rate.
    private var away: Set<UInt32> = []
    private var activeCorners: [(key: MaskKey, window: Int, frame: CGRect)] = []
    private var contact: CursorContact?
    private var currentHz: Double?
    /// The sampler stays fast until this time after a Space change, whether or not a window has moved yet.
    private var fastUntil: TimeInterval = -.infinity
    private var warnedWarp = false

    /// The live engine: the system's ports, and the UI's masks.
    public convenience init(store: NamespacedStore, masks: any CornerMasks) {
        self.init(store: store, masks: masks, displays: ScreenDisplays(), windows: WindowSampler(),
                  pointer: EventPointer(), events: WorkspaceSystemEvents(), ticker: CommonModeTicker(),
                  clock: UptimeClock())
    }

    /// Every port is passed, none defaulted: a test that forgot one would reach the real machine.
    init(store: NamespacedStore, masks: any CornerMasks, displays: any DisplayPort, windows: any WindowSamplePort,
         pointer: any PointerPort, events: any SystemEventsPort, ticker: any TickerPort, clock: any MonotonicClock) {
        self.store = store
        self.masks = masks
        self.display = displays
        self.windowSampler = windows
        self.pointer = pointer
        self.events = events
        self.ticker = ticker
        self.clock = clock
        settings = StoredCornerSettings(store: store)
        reference = RadiusScale.reference(builtInNow: nil, remembered: settings.builtInScale, main: nil)
    }

    // MARK: What the card reads

    public var state: CornerState { last ?? CornerState() }

    public func stream() -> AsyncStream<CornerState> { news.stream() }

    public nonisolated var subscriberCount: Int { news.subscriberCount }

    // MARK: Commands

    /// A command on an engine that is not active writes the store and does nothing else: the next `activate()` reads it.
    /// A radius command converts at `reference`, the scale the engine last settled on: at construction and at each
    /// `activate()` the built-in scale remembered in the store, else 1; after a layout the live built-in display's,
    /// else the remembered one, else the main display's. `stop()` leaves it as it was, so after an activation that
    /// saw only an external display it stays that display's scale.
    public func setBuiltIn(_ on: Bool) {
        settings.setBuiltIn(on)
        changed()
    }

    public func setExternal(_ on: Bool) {
        settings.setExternal(on)
        changed()
    }

    public func setPreset(points: Double) {
        settings.setRadiusPixels(RadiusMath.preset(points: points, scale: reference))
        changed()
    }

    public func stepRadius(direction: Int) {
        let now = RadiusMath.pixels(stored: settings.radiusPixels, scale: reference)
        settings.setRadiusPixels(RadiusMath.stepped(now, direction: direction, scale: reference))
        changed()
    }

    /// Starts previewing the radius with coloured masks; nothing on an engine that is not active.
    public func beginCalibration() {
        guard active, calibration == nil else { return }
        calibration = .default
        changed()
    }

    /// Components are clamped on the way in. A colour equal to the last changes nothing.
    public func setCalibration(r: Double, g: Double, b: Double) {
        guard active, calibration != nil else { return }
        let colour = CalibrationColour(clamping: r, g, b)
        guard colour != calibration else { return }
        calibration = colour
        changed()
    }

    public func endCalibration() {
        guard active, calibration != nil else { return }
        calibration = nil
        changed()
    }

    private func changed() {
        guard active else { return }
        reconcile()
        publish()
    }

    // MARK: Lifecycle

    public nonisolated func activate() { MainActor.assumeIsolated { start() } }

    public nonisolated func deactivate() { MainActor.assumeIsolated { stop() } }

    private func start() {
        guard !active else { return }
        active = true
        asleep = false
        calibration = nil
        warnedWarp = false
        settings = StoredCornerSettings(store: store)
        reference = RadiusScale.reference(builtInNow: nil, remembered: settings.builtInScale, main: nil)
        reconcile()
        publish()
    }

    /// Events, ticker and pointer before the masks: the tap's callback reads the masks. Safe twice, and safe
    /// without `activate()`. Nothing is published: whoever listened is going too.
    private func stop() {
        active = false
        calibration = nil
        events.stop()
        eventsStarted = false
        teardownVisuals()
    }

    // MARK: Deciding what runs

    private func reconcile() {
        guard active, !asleep else { return }
        guard settings.builtIn || settings.external || calibration != nil else {
            events.stop()
            eventsStarted = false
            teardownVisuals()
            return
        }
        if !eventsStarted {
            eventsStarted = true
            events.start { [weak self] event in self?.handle(event) }
        }
        relayout()
    }

    /// The ticker, the pointer and every mask gone, and what was kept about them.
    private func teardownVisuals() {
        ticker.stop()
        currentHz = nil
        pointer.stop()
        pointerMode = .off
        masks.removeAll()
        specs = []
        windows = [:]
        motion = [:]
        resting = [:]
        geometry = [:]
        holding = [:]
        away = [] // no mask stands, so none is away; `relayout()` resets it too, this keeps the teardown whole
        activeCorners = []
        contact = nil
    }

    private func relayout() {
        let attached = display.displays()
        let builtInNow = attached.first { $0.isBuiltIn && !$0.isMirrored }?.pixelsPerPoint
        reference = RadiusScale.reference(builtInNow: builtInNow, remembered: settings.builtInScale,
                                          main: attached.first?.pixelsPerPoint)
        if let builtInNow, builtInNow.isFinite, builtInNow > 0 { settings.setBuiltInScale(builtInNow) }

        let pixels = RadiusMath.pixels(stored: settings.radiusPixels, scale: reference)
        let wanted = LayoutDecision.decide(
            displays: attached,
            settings: CornerSettings(builtIn: settings.builtIn, external: settings.external, radiusPixels: pixels),
            calibration: calibration)
        let diff = MaskDiff.between(specs, wanted)
        // A step of the radius is a changed spec, which resizes its window: nothing stops, nothing reopens.
        guard !diff.isEmpty else { return }

        let standing = masks.show(diff)
        specs = wanted
        windows = standing.filter { key, _ in wanted.contains { $0.key == key } }
        let byDisplay = Dictionary(attached.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        resting = [:]
        geometry = [:]
        for spec in wanted {
            geometry[spec.key] = CornerGeometry(size: spec.frame.width, radius: spec.radius, corner: spec.key.corner,
                                                constrainsCursor: spec.constrainsCursor)
            if let window = windows[spec.key], let owner = byDisplay[spec.key.display] {
                resting[window] = CornerFrames.restingQuartzFrame(window: spec.frame, display: owner.frame,
                                                                  quartzBounds: owner.quartzBounds)
            }
        }
        let shown = Set(wanted.map(\.key.display))
        motion = motion.filter { shown.contains($0.key) }
        for id in shown where motion[id] == nil { motion[id] = DisplayMotion() }
        // A window opens rounded; on a display whose Space is sliding that is wrong until the next sample.
        for id in Set(diff.added.map(\.key.display)) where motion[id]?.rounded == false {
            masks.setRounded(false, display: id)
        }
        holding = [:]
        away = []
        activeCorners = []
        contact = nil

        if windows.isEmpty {
            ticker.stop()
            currentHz = nil
        } else {
            tune()
        }
        if windows.keys.contains(where: { geometry[$0]?.boundary != nil }) {
            if pointerMode == .off || pointerMode == .unavailable { startPointer() }
        } else {
            pointer.stop()
            pointerMode = .off
        }
    }

    private func startPointer() {
        pointerMode = pointer.start(
            onMove: { [weak self] location in
                guard let self, self.active else { return }
                self.constrainCursor(near: location)
            },
            onModeChange: { [weak self] mode in
                guard let self, self.active else { return }
                self.pointerMode = mode
                self.publish()
            })
    }

    // MARK: System events

    private func handle(_ event: SystemEvent) {
        guard active else { return }
        switch event {
        case .screensChanged:
            // Nothing while asleep: a screen that goes away with the lid shut is not a reason to open masks.
            guard !asleep else { return }
            reconcile()
            publish()
        case .displaysSlept:
            asleep = true
            teardownVisuals()
            publish()
        case .displaysWoke:
            asleep = false
            reconcile()
            publish()
        case .spaceChanged:
            guard !asleep, !windows.isEmpty else { return }
            let now = clock.now()
            if now.isFinite { fastUntil = now + 1 }
            tick()
        }
    }

    // MARK: Sampling

    /// The ticker at the rate the displays need now; started again only when the rate differs.
    private func tune() {
        let now = clock.now()
        let unsettled = motion.contains { !$0.value.rounded && !away.contains($0.key) } || (now.isFinite && now < fastUntil)
        let hz = SamplingRate.next(unsettled: unsettled, maxFPS: specs.map(\.maxFPS).max() ?? 60)
        guard hz != currentHz || !ticker.isRunning else { return }
        currentHz = hz
        ticker.start(hz: hz) { [weak self] in self?.tick() }
    }

    private func tick() {
        guard active, !asleep, !windows.isEmpty else { return }
        let sampled = windowSampler.onScreenBounds(of: Array(windows.values))
        let now = clock.now()
        var roundedChanged = false
        var holdingNow: [UInt32: Bool] = [:]
        var awayNow: Set<UInt32> = []
        for id in motion.keys {
            let own = specs.filter { $0.key.display == id }.compactMap { windows[$0.key] }
            if !own.isEmpty && own.allSatisfy({ sampled[$0] == nil }) { awayNow.insert(id) }
            let atRest = !own.isEmpty && own.allSatisfy { resting[$0] != nil && sampled[$0] == resting[$0] }
            if let rounded = motion[id]?.update(atRest: atRest, now: now) {
                masks.setRounded(rounded, display: id)
                roundedChanged = true
            }
            holdingNow[id] = atRest && motion[id]?.rounded == true
        }
        away = awayNow
        if holdingNow != holding {
            holding = holdingNow
            activeCorners = specs.compactMap { spec in
                guard holding[spec.key.display] == true, spec.constrainsCursor, let window = windows[spec.key],
                      let frame = resting[window] else { return nil }
                return (spec.key, window, frame)
            }
            if let contact, !activeCorners.contains(where: { $0.window == contact.window }) { self.contact = nil }
            constrainCursor(near: nil)
        }
        tune()
        if roundedChanged { publish() }
    }

    // MARK: The pointer

    /// The standalone app's correction, ported: `event` is where the pointer was when the event was made, nil
    /// when the pass is not for an event.
    private func constrainCursor(near event: CGPoint?) {
        guard !activeCorners.isEmpty else { return }
        // The cheap refusal: a pointer away from every corner, and not on a correction, costs a few comparisons.
        if contact == nil, let event, !activeCorners.contains(where: { $0.frame.contains(event) }) { return }
        // The current position, since a queued event may describe movement from before the last correction.
        guard let at = pointer.location() else { return }
        if contact?.position == at { return }
        for corner in activeCorners where corner.frame.contains(at) {
            let local = CGPoint(x: at.x - corner.frame.minX, y: corner.frame.maxY - at.y)
            let own = contact?.window == corner.window ? contact : nil
            guard let geometry = geometry[corner.key], let presentation = masks.presentation(of: corner.key),
                  let correction = CursorCorrection.correct(local: local, remainder: own?.remainder ?? .zero,
                                                            geometry: geometry, presentation: presentation)
            else {
                if own?.isNear(at) == true { return }
                break
            }
            let target = CGPoint(x: corner.frame.minX + correction.position.x,
                                 y: corner.frame.maxY - correction.position.y)
            if pointer.warp(to: target) {
                contact = CursorContact(window: corner.window, position: target, remainder: correction.remainder)
                return
            }
            if !warnedWarp {
                warnedWarp = true
                HelmLog.shared.warn(Self.moduleID, "the system refused to move the pointer back onto the curve")
            }
            break
        }
        contact = nil
    }

    // MARK: What is said

    private func publish() {
        let radius = RadiusMath.pixels(stored: settings.radiusPixels, scale: reference)
        let preset = RadiusMath.presetPoints.first { abs(RadiusMath.preset(points: Double($0), scale: reference) - radius) <= 0.001 }
        let new = CornerState(
            masks: specs, rounded: motion.mapValues(\.rounded),
            radiusPixels: radius,
            referenceScale: reference, pointer: pointerMode, calibrating: calibration != nil,
            builtIn: settings.builtIn, external: settings.external, calibrationColour: calibration,
            selectedPreset: preset)
        guard new != last else { return }
        last = new
        news.say(new)
    }
}
