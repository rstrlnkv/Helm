import CoreGraphics
import Foundation

/// **What Display Corners' engine asks of the machine, one boundary each.**
///
/// All of them are `AnyObject` and main-actor: the engine runs on main, and every system call behind them
/// (screens, event monitors, observers, a timer) is a main-thread call. `SystemPorts.swift` holds the live
/// ones, the only file here that names AppKit. The ports that can answer with an empty read, `DisplayPort`,
/// `WindowSamplePort` and `PointerPort` (`location`, `warp`), say in their doc comments which reasons collapse
/// into it; the engine never needs to tell them apart (`Architecture/ModulePattern.md` § Ports and logic).
/// `SystemEventsPort`, `TickerPort` and `MonotonicClock` have no empty read.

@MainActor protocol DisplayPort: AnyObject {
    /// Every attached display, mirrored ones included (a mirror member is still a neighbour for the pointer),
    /// in `NSScreen` order: the first is the primary.
    /// `[]` is "no screen answered", "nothing attached" and "no screen carried a display number"; the engine
    /// reads all three as "no masks".
    func displays() -> [DisplayDescriptor]
}

@MainActor protocol WindowSamplePort: AnyObject {
    /// Quartz bounds of those windows that are on screen. A number absent from the answer is a window that
    /// is off screen, closed, or one the system did not answer for; the engine reads all three as "not at rest".
    func onScreenBounds(of windowNumbers: [Int]) -> [Int: CGRect]
}

@MainActor protocol PointerPort: AnyObject {
    /// Starts listening to the pointer, stopping any earlier listening first. `onMove` is given the pointer's
    /// Quartz position; `onModeChange` is called when the system takes the event tap away for good, with
    /// `.monitorsOnly` when the monitors stand in and `.unavailable` when none could be made either. Returns what is listening now: `.unavailable` when neither a tap nor a monitor could be made.
    func start(onMove: @escaping @MainActor (CGPoint) -> Void,
               onModeChange: @escaping @MainActor (PointerMode) -> Void) -> PointerMode
    /// Idempotent.
    func stop()
    /// The pointer's Quartz position now; nil when the system did not answer.
    func location() -> CGPoint?
    /// Puts the pointer at a Quartz position. False when the system refused.
    func warp(to point: CGPoint) -> Bool
}

enum SystemEvent: Equatable {
    case screensChanged, displaysSlept, displaysWoke, spaceChanged
}

@MainActor protocol SystemEventsPort: AnyObject {
    /// Stops any earlier listening first, so a second start stacks nothing.
    func start(_ onEvent: @escaping @MainActor (SystemEvent) -> Void)
    /// Idempotent.
    func stop()
}

@MainActor protocol TickerPort: AnyObject {
    /// Replaces a running tick, at the new rate.
    func start(hz: Double, _ onTick: @escaping @MainActor () -> Void)
    /// Idempotent.
    func stop()
    var isRunning: Bool { get }
}

@MainActor protocol MonotonicClock: AnyObject {
    /// Seconds from a clock that is not the wall clock: setting the time cannot move it.
    func now() -> TimeInterval
}
