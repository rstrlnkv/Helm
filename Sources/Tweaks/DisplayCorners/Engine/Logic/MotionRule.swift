import Foundation
import HelmRuntime

/// A display's masks are rounded while its windows rest, and shrink while a Space slides.
/// The clock is injected, so the rule is tested without a timer. The live port is `UptimeClock`
/// (`ProcessInfo.systemUptime`, monotonic); should a clock go backwards or not be a number all the same,
/// that sample counts as motion, so the masks cannot stay unrounded.
struct DisplayMotion {
    /// A display counts as settled this long after its windows last moved.
    static let settle: TimeInterval = 0.05

    private var lastMotion: TimeInterval = -.infinity
    private(set) var rounded = true

    /// The new rounded state when this sample changed it, nil when it did not.
    mutating func update(atRest: Bool, now: TimeInterval) -> Bool? {
        var atRest = atRest
        if now < lastMotion { atRest = false }
        if !atRest, now.isFinite { lastMotion = now }
        let shouldRound = now.isFinite && atRest && now - lastMotion > Self.settle
        guard shouldRound != rounded else { return nil }
        rounded = shouldRound
        return shouldRound
    }
}

/// How often the window list is asked for. Review finding 4: the standalone app asked WindowServer at
/// up to 120 Hz for every mask window with nothing moving; at rest the sampler runs slowly and speeds up
/// only while a display is unsettled. A display whose masks are all off screen is away, not unsettled: the
/// engine leaves it unrounded and holding no pointer, and it does not raise the rate by itself. The rate is
/// still fast for one second after a Space change, and from a relayout (which forgets which displays are
/// away) until the next sample finds them away again.
enum SamplingRate {
    static let idleHz = 20.0

    /// The ticks per second to sample at.
    static func next(unsettled: Bool, maxFPS: Int) -> Double {
        unsettled ? Double(maxFPS.clamped(to: 60...120)) : idleHz
    }
}
