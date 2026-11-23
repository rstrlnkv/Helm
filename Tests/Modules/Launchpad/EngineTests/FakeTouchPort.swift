import Foundation
import HelmTestSupport
@testable import Module_Launchpad_Engine

/// Stands for the trackpad side of `TrackpadTouchPort`, whose port answers are the three of `TouchWatchStart` a port gives (the fourth, a layout refused, only the engine records): a test sets what the next
/// start answers, and `send` stands for the framework's thread delivering a frame. It never reaches a real trackpad.
final class FakeTouchPort: TrackpadTouchPort, @unchecked Sendable {
    private struct State {
        var answer: TouchWatchStart = .watching(devices: 1)
        var starts = 0
        var stops = 0
        var running = false
        var onFrame: (@Sendable (TouchFrame) -> Void)?
        var onStandDown: (@Sendable () -> Void)?
        var whileStarting: (@Sendable () -> Void)?
        var whileStopping: (@Sendable () -> Void)?
        var everyOnFrame: [@Sendable (TouchFrame) -> Void] = []
        var everyOnStandDown: [@Sendable () -> Void] = []
    }
    private let state = Locked(State())

    var answer: TouchWatchStart {
        get { state.withLock { $0.answer } }
        set { state.withLock { $0.answer = newValue } }
    }
    var starts: Int { state.withLock { $0.starts } }
    var stops: Int { state.withLock { $0.stops } }
    var running: Bool { state.withLock { $0.running } }

    /// Runs inside `start`, before it answers: a test holds the start in flight here (the framework takes its time) while another thread acts.
    var whileStarting: (@Sendable () -> Void)? {
        get { state.withLock { $0.whileStarting } }
        set { state.withLock { $0.whileStarting = newValue } }
    }

    func start(onFrame: @escaping @Sendable (TouchFrame) -> Void, onStandDown: @escaping @Sendable () -> Void) -> TouchWatchStart {
        state.withLock { $0.whileStarting }?()
        return state.withLock {
            $0.starts += 1
            $0.onFrame = onFrame
            $0.onStandDown = onStandDown
            $0.everyOnFrame.append(onFrame)
            $0.everyOnStandDown.append(onStandDown)
            if case .watching = $0.answer { $0.running = true }
            return $0.answer
        }
    }

    /// Runs inside `stop`, before it takes effect: a test holds a stop in flight here while another thread acts.
    var whileStopping: (@Sendable () -> Void)? {
        get { state.withLock { $0.whileStopping } }
        set { state.withLock { $0.whileStopping = newValue } }
    }

    func stop() {
        state.withLock { $0.whileStopping }?()
        state.withLock { $0.stops += 1; $0.running = false }
    }

    /// Delivers a frame as the framework would, whether or not anybody still wants it.
    func send(_ frame: TouchFrame) { state.withLock { $0.onFrame }?(frame) }
    func standDown() { state.withLock { $0.onStandDown }?() }
    /// The framework's thread delivering late, to the callbacks of the `n`th start (0 is the first), whichever watch owns the port now.
    func send(_ frame: TouchFrame, toStart n: Int) { state.withLock { $0.everyOnFrame.indices.contains(n) ? $0.everyOnFrame[n] : nil }?(frame) }
    func standDown(start n: Int) { state.withLock { $0.everyOnStandDown.indices.contains(n) ? $0.everyOnStandDown[n] : nil }?() }
}

/// Frames of a hand: `fingers` fingers on a circle of `radius` around `centre`, in the pad's 0 to 1.
enum Hand {
    static func frame(_ time: Double, radius: Double, fingers: Int = 5, centre: (x: Double, y: Double) = (0.5, 0.5), device: Int = 0) -> TouchFrame {
        TouchFrame(device: device, time: time, count: fingers) { i in
            let angle = 2 * Double.pi * Double(i) / Double(max(fingers, 1))
            return (centre.x + radius * cos(angle), centre.y + radius * sin(angle), TouchFrame.touchingState)
        }!
    }

    /// A hand that lands at `radius` and holds for a tenth of a second.
    static func landing(radius: Double = 0.2, fingers: Int = 5, device: Int = 0) -> [TouchFrame] {
        (0...10).map { frame(Double($0) / 100, radius: radius, fingers: fingers, device: device) }
    }
}

extension Hand {
    /// A hand moving from `from` to `to` in `steps` frames 0.01 s apart, the first one 0.01 s after `after` (a landing ends at 0.10).
    static func sweep(from: Double, to: Double, steps: Int, after: Double = 0.10, fingers: Int = 5, device: Int = 0) -> [TouchFrame] {
        (1...steps).map { frame(after + Double($0) / 100, radius: from + (to - from) * Double($0) / Double(steps), fingers: fingers, device: device) }
    }

    /// The frames of a hand held still at `radius` from `after` for `steps` frames 0.01 s apart.
    static func still(radius: Double, steps: Int, after: Double, fingers: Int = 5, device: Int = 0) -> [TouchFrame] {
        (1...steps).map { frame(after + Double($0) / 100, radius: radius, fingers: fingers, device: device) }
    }

    /// Every finger up, at `time`.
    static func lift(at time: Double, device: Int = 0) -> TouchFrame { TouchFrame(device: device, time: time, count: 0) { _ in (0, 0, 0) }! }

    /// A whole pinch the engine reads as one scrub that completes: lands, closes to under the ratio over 0.2 s and lifts.
    static func completedPinch(device: Int = 0) -> [TouchFrame] {
        landing(device: device) + sweep(from: 0.2, to: 0.05, steps: 20, device: device) + [lift(at: 0.32, device: device)]
    }
}

extension Sequence where Element == PinchEvent {
    /// The directions of the scrubs that ended complete, in order.
    var completed: [PinchDirection] {
        var direction: PinchDirection?
        var done: [PinchDirection] = []
        for event in self {
            switch event {
            case .began(let d, _): direction = d
            case .moved: break
            case .ended(let outcome): if outcome == .complete, let direction { done.append(direction) }
            }
        }
        return done
    }
}
