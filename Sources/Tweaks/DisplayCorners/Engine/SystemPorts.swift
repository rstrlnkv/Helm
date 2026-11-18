import AppKit
import HelmRuntime
import IOKit.graphics

// The live ports of Display Corners, and the only file of this engine that names AppKit.

// MARK: - ScreenDisplays

/// The attached displays, read fresh on every call: the frame, the scale and the refresh rate change with the
/// mode somebody picks, so nothing here is kept between calls.
@MainActor final class ScreenDisplays: DisplayPort {
    func displays() -> [DisplayDescriptor] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return nil }
            let id = number.uint32Value
            let modes = (CGDisplayCopyAllDisplayModes(id, nil) as? [CGDisplayMode] ?? []).map {
                DisplayModeInfo(pixelWidth: $0.pixelWidth, pixelHeight: $0.pixelHeight,
                                isNative: $0.ioFlags & UInt32(kDisplayModeNativeFlag) != 0)
            }
            return DisplayDescriptor(
                id: id, frame: screen.frame, quartzBounds: CGDisplayBounds(id),
                backingScale: screen.backingScaleFactor,
                pixelsPerPoint: PixelsPerPoint.resolve(modes: modes, pointSize: screen.frame.size,
                                                       backing: screen.backingScaleFactor),
                isBuiltIn: CGDisplayIsBuiltin(id) != 0, isMirrored: CGDisplayIsInMirrorSet(id) != 0,
                maxFPS: screen.maximumFramesPerSecond)
        }
    }
}

// MARK: - WindowSampler

/// The Quartz bounds of the mask windows. Quartz expects a `CFArray` of raw window numbers rather than
/// `CFNumber`s; it is built again only when the list of numbers changes, since the sampler asks many times a second.
@MainActor final class WindowSampler: WindowSamplePort {
    private var numbers: [Int] = []
    private var list: CFArray?

    func onScreenBounds(of windowNumbers: [Int]) -> [Int: CGRect] {
        if windowNumbers != numbers || (list == nil && !windowNumbers.isEmpty) {
            numbers = windowNumbers
            var raw = windowNumbers.map { UnsafeRawPointer(bitPattern: $0) }
            list = windowNumbers.isEmpty ? nil : CFArrayCreate(nil, &raw, raw.count, nil)
        }
        guard let list else { return [:] }
        var bounds: [Int: CGRect] = [:]
        for window in CGWindowListCreateDescriptionFromArray(list) as? [[String: Any]] ?? [] {
            if window[kCGWindowIsOnscreen as String] as? Bool == true,
               let number = window[kCGWindowNumber as String] as? Int,
               let dictionary = window[kCGWindowBounds as String] as? NSDictionary,
               let rect = CGRect(dictionaryRepresentation: dictionary as CFDictionary) {
                bounds[number] = rect
            }
        }
        return bounds
    }
}

// MARK: - EventPointer

/// A box for what `stop()` takes out under the lock and hands to main, which is not `Sendable` by itself.
private struct Tokens: @unchecked Sendable {
    let values: [Any]
}

/// The live pointer: a listen-only event tap on the main run loop, and the warp.
///
/// **A tap or the monitors, never both.** The tap is made first, and only when Input Monitoring is already
/// granted (`CGPreflightListenEventAccess`, which only reads the grant: `CGRequestListenEventAccess` would
/// raise the dialog nobody asked for, and the monitors need no grant). Without the grant, when the system
/// refuses the tap, or takes it away and will not give it back, the `NSEvent` monitors stand in, and the mode
/// says which one is listening (`PointerMode`). Both at once would hand the engine every move twice.
///
/// The tap is at the session (`.cgSessionEventTap`), as `CGKeyTap` has it: the pointer guarded is the
/// logged-in session's, and a tap at the HID level sits before the session routes events, which this does not need.
///
/// Built after `CGKeyTap` (`Modules/Layout/Engine/SystemPorts.swift`): `userInfo` is unretained, so the tap
/// does not keep this object alive and `deinit` is reachable; the fields are under a lock; the teardown runs
/// outside it. The teardown order is: tap disabled, source removed from the main run loop, source invalidated,
/// port invalidated. What `CGKeyTap`'s comment measured is only that stopping without `CFMachPortInvalidate`
/// already stops delivery, and that the invalidation frees the port and its source and is not the repair for a
/// callback on a freed object; nothing here or in a test shows whether disabling or removing alone would do.
final class EventPointer: @unchecked Sendable {
    private let lock = NSLock()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var tokens: [Any] = []
    private var onMove: (@MainActor (CGPoint) -> Void)?
    private var onModeChange: (@MainActor (PointerMode) -> Void)?

    init() {}

    /// The backstop for every way out but `deactivate()`.
    deinit { stop() }

    func start(onMove: @escaping @MainActor (CGPoint) -> Void,
               onModeChange: @escaping @MainActor (PointerMode) -> Void) -> PointerMode {
        stop()
        lock.withLock {
            self.onMove = onMove
            self.onModeChange = onModeChange
        }
        if CGPreflightListenEventAccess() {
            if installTap() { return .tap }
            HelmLog.shared.warn(DisplayCornersEngine.moduleID, "the system refused the pointer tap; watching the pointer through monitors")
        } else {
            HelmLog.shared.warn(DisplayCornersEngine.moduleID, "no Input Monitoring; watching the pointer through monitors")
        }
        return standInWithMonitors()
    }

    /// The mode the monitors give, and a line when they could not be made either: the line above says why the
    /// tap was not used, this one says whether anything is listening.
    private func standInWithMonitors() -> PointerMode {
        installMonitors()
        if lock.withLock({ tokens.isEmpty }) {
            HelmLog.shared.warn(DisplayCornersEngine.moduleID, "no pointer monitor could be made; the pointer is not watched")
            return .unavailable
        }
        return .monitorsOnly
    }

    private func installTap() -> Bool {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask,
            callback: { _, type, event, info in
                if let info {
                    let pointer = Unmanaged<EventPointer>.fromOpaque(info).takeUnretainedValue()
                    switch type {
                    case .tapDisabledByTimeout, .tapDisabledByUserInput:
                        MainActor.assumeIsolated { pointer.theSystemDisabledTheTap() }
                    case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
                        let location = event.location
                        MainActor.assumeIsolated { pointer.moved(to: location) }
                    default: break
                    }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        else { return false }
        lock.withLock {
            self.tap = tap
            self.source = source
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// The monitors' handlers run on main; a local monitor's also sees the events of Helm's own windows.
    private func installMonitors() {
        let movement: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        let global = NSEvent.addGlobalMonitorForEvents(matching: movement) { [weak self] _ in
            MainActor.assumeIsolated { self?.movedByMonitor() }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: movement) { [weak self] event in
            MainActor.assumeIsolated { self?.movedByMonitor() }
            return event
        }
        lock.withLock { tokens = [global, local].compactMap { $0 } }
    }

    @MainActor private func moved(to location: CGPoint) {
        let handler = lock.withLock { onMove }
        handler?(location)
    }

    /// AppKit's bottom-left position, in Quartz's top-left, flipped about the primary display.
    @MainActor private func movedByMonitor() {
        guard let primary = NSScreen.screens.first else { return }
        let at = NSEvent.mouseLocation
        moved(to: CGPoint(x: at.x, y: primary.frame.maxY - at.y))
    }

    /// Timed out or switched off by the user's input: back on, and read whether it stayed on. A tap that will
    /// not stay on is stood down, the monitors take its place, and the engine is told.
    @MainActor private func theSystemDisabledTheTap() {
        guard let tap = lock.withLock({ self.tap }) else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        if CGEvent.tapIsEnabled(tap: tap) { return }
        let handler = lock.withLock { onModeChange }
        removeTap()
        HelmLog.shared.warn(DisplayCornersEngine.moduleID, "the system switched the pointer tap off for good; watching the pointer through monitors")
        handler?(standInWithMonitors())
    }

    /// Idempotent: `deinit` runs it again after `deactivate()`. Everything is taken out under the lock and
    /// torn down outside it, so nothing that can call back into this object runs with the lock held.
    func stop() {
        let taken = lock.withLock {
            let taken = (tap, source, tokens)
            tap = nil
            source = nil
            tokens = []
            onMove = nil
            onModeChange = nil
            return taken
        }
        tearDown(tap: taken.0, source: taken.1)
        remove(Tokens(values: taken.2))
    }

    /// The tap and its source only, for standing down: the handlers stay.
    private func removeTap() {
        let taken = lock.withLock {
            let taken = (tap, source)
            tap = nil
            source = nil
            return taken
        }
        tearDown(tap: taken.0, source: taken.1)
    }

    /// In this order: disable the tap, take the source off the main run loop, invalidate the source, invalidate the port.
    private func tearDown(tap: CFMachPort?, source: CFRunLoopSource?) {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        if let tap { CFMachPortInvalidate(tap) }
    }

    /// Monitors come off on main, which is where they were added.
    private func remove(_ tokens: Tokens) {
        guard !tokens.values.isEmpty else { return }
        if Thread.isMainThread {
            tokens.values.forEach(NSEvent.removeMonitor)
        } else {
            DispatchQueue.main.async { tokens.values.forEach(NSEvent.removeMonitor) }
        }
    }

    func location() -> CGPoint? { CGEvent(source: nil)?.location }

    /// Neither the suppression interval nor a reassociation is set: another app may have dissociated the
    /// pointer on purpose, and a call here would override it. The order is to measure first whether the pointer
    /// sticks after a warp, then reassociate, and only then reach for the interval.
    func warp(to point: CGPoint) -> Bool {
        CGWarpMouseCursorPosition(point) == .success
    }
}

/// Declared apart from the class: a conformance to a main-actor protocol in the class's own declaration would
/// make the whole class main-actor, and `deinit` could not call `stop()`. The methods are nonisolated and the
/// main actor may call them.
extension EventPointer: PointerPort {}

// MARK: - WorkspaceSystemEvents

/// The four things that move the masks: the screens, their sleep and wake, and the Space.
final class WorkspaceSystemEvents: @unchecked Sendable {
    private let lock = NSLock()
    /// Held so they can be taken back out: the centre keeps its own tokens, it does not remove them.
    private var tokens: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    init() {}

    deinit { stop() }

    func start(_ onEvent: @escaping @MainActor (SystemEvent) -> Void) {
        stop()
        let workspace = NSWorkspace.shared.notificationCenter
        let events: [(NotificationCenter, Notification.Name, SystemEvent)] = [
            (.default, NSApplication.didChangeScreenParametersNotification, .screensChanged),
            (workspace, NSWorkspace.screensDidSleepNotification, .displaysSlept),
            (workspace, NSWorkspace.screensDidWakeNotification, .displaysWoke),
            (workspace, NSWorkspace.activeSpaceDidChangeNotification, .spaceChanged),
        ]
        let added = events.map { center, name, event in
            (center: center, token: center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { onEvent(event) }
            })
        }
        lock.withLock { tokens = added }
    }

    func stop() {
        let taken = lock.withLock {
            let taken = tokens
            tokens = []
            return taken
        }
        for entry in taken { entry.center.removeObserver(entry.token) }
    }
}

extension WorkspaceSystemEvents: SystemEventsPort {}

// MARK: - CommonModeTicker

/// A repeating timer on the main run loop in the common modes, at a rate that changes while it runs.
///
/// Not `RepeatingTick`: its interval is fixed at construction and it runs in the default mode only, which
/// stops while a menu is tracked or a Space slides, the very time this sampler must run (the standalone app
/// used `.common` too). The run loop keeps the timer, so `deinit` invalidates it, and the block does the same should it fire first.
@MainActor final class CommonModeTicker: TickerPort {
    private var timer: Timer?

    var isRunning: Bool { timer?.isValid == true }

    /// The backstop for every way out but `stop()`: the run loop keeps the timer, which would otherwise
    /// invalidate itself only at its next fire.
    isolated deinit { timer?.invalidate() }

    func start(hz: Double, _ onTick: @escaping @MainActor () -> Void) {
        stop()
        let interval = 1 / hz
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
            guard self != nil else { return timer.invalidate() }
            MainActor.assumeIsolated { onTick() }
        }
        timer.tolerance = interval / 8
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - UptimeClock

/// `systemUptime` does not move when somebody sets the time, and does not count the time the Mac slept.
@MainActor final class UptimeClock: MonotonicClock {
    func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
}
