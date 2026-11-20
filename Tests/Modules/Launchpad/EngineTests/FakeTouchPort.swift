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
