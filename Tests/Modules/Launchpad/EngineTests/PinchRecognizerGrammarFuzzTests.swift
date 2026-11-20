import XCTest
@testable import Module_Launchpad_Engine

/// Whatever frames arrive (counts 0 to 10, any radius, drifting centres, a clock that stutters and runs back), the recognizer's events keep
/// their grammar: a `began` is followed by `moved`s and exactly one `ended`, a `moved` and an `ended` never come with no scrub, and every
/// progress is a number from 0 to 1.
final class PinchRecognizerGrammarFuzzTests: XCTestCase {
    private struct Lcg { var s: UInt64
        mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) }
    }

    private var began = 0
    private func run(seed: UInt64) -> String? {
        var rng = Lcg(s: seed)
        var r = PinchRecognizer()
        var t = 0.0
        var count = 5
        var radius = 0.2
        var cx = 0.5
        var scrubbing = false
        var log: [String] = []
        for i in 0..<600 {
            let roll = rng.next()
            let landing = i < 12
            if landing { t += 0.01 } else { t += roll < 0.03 ? -rng.next() * 0.5 : roll < 0.1 ? 0 : 0.005 + rng.next() * 0.03 }
            if !landing, rng.next() < 0.04 { count = Int(rng.next() * 11) }
            if !landing, rng.next() < 0.04 { count = [4, 5][Int(rng.next() * 2)] }
            if !landing, rng.next() < 0.6 { radius = max(0.0005, radius + (rng.next() - 0.55) * 0.02) }
            if !landing, rng.next() < 0.1 { cx = min(max(cx + (rng.next() - 0.5) * 0.1, 0.1), 0.9) }
            let n = count
            let rad = radius, c = cx
            guard let frame = TouchFrame(device: 0, time: t, count: n, touch: { k in
                let a = 2 * Double.pi * Double(k) / Double(max(n, 1))
                return (c + rad * cos(a), 0.5 + rad * sin(a), TouchFrame.touchingState)
            }) else { continue }
            let e = r.feed(frame)
            log.append("\(i) t=\(t) n=\(n) -> \(String(describing: e))")
            switch e {
            case .began(_, let p)?:
                if scrubbing { return "seed \(seed): began inside a scrub\n" + log.suffix(6).joined(separator: "\n") }
                if !(0...1).contains(p) { return "seed \(seed): began progress \(p)" }
                scrubbing = true
                began += 1
            case .moved(let p)?:
                if !scrubbing { return "seed \(seed): moved with no scrub\n" + log.suffix(6).joined(separator: "\n") }
                if !(0...1).contains(p) { return "seed \(seed): moved progress \(p)" }
            case .ended?:
                if !scrubbing { return "seed \(seed): ended with no scrub\n" + log.suffix(6).joined(separator: "\n") }
                scrubbing = false
            case nil: break
            }
        }
        return nil
    }

    func testRandomHandsKeepTheEventGrammar() {
        var bad: [String] = []
        for seed in UInt64(1)...3000 { if let b = run(seed: seed) { bad.append(b); if bad.count > 3 { break } } }
        XCTAssertGreaterThan(began, 300, "the subject: random hands must reach scrubs, or this checks nothing")
        XCTAssertTrue(bad.isEmpty, bad.joined(separator: "\n---\n"))
    }
}
