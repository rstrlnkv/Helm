import Foundation
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **The shutter sounds when Helm's switch and the system's both allow it.**
/// `com.apple.sound.uiaudio.enabled` absent is the ordinary state and means on;
/// a zero means off; a value of any other kind is not a decision and means on.
/// The fake counts the plays, so a shutter that never sounds and one that always
/// does are both red, and the four combinations are all asked.
final class TheShutterHonoursBothSwitchesTests: XCTestCase {

    private func plays(setting: Bool, uiAudio: Any?) -> Int {
        let rig = Rig(home: scratchDirectory("shots-shutter"), settings: ScreenshotsSettings(shutterSound: setting))
        rig.preferences.uiAudio = uiAudio
        rig.session.shutter()
        return rig.shutter.plays
    }

    func testTheFourCombinations() {
        XCTAssertEqual(plays(setting: true, uiAudio: nil), 1, "Helm on, system absent")
        XCTAssertEqual(plays(setting: true, uiAudio: 1), 1, "Helm on, system on")
        XCTAssertEqual(plays(setting: true, uiAudio: 0), 0, "Helm on, system off")
        XCTAssertEqual(plays(setting: false, uiAudio: nil), 0, "Helm off, system absent")
        XCTAssertEqual(plays(setting: false, uiAudio: 1), 0, "Helm off, system on")
        XCTAssertEqual(plays(setting: false, uiAudio: 0), 0, "Helm off, system off")
    }

    func testSystemOffIsAnyKindOfZero() {
        XCTAssertEqual(plays(setting: true, uiAudio: false), 0, "a false is a zero")
        XCTAssertEqual(plays(setting: true, uiAudio: 0.0), 0)
    }

    func testAValueOfAnyOtherKindIsNotADecisionAndTheSoundPlays() {
        for garbage: Any in ["no", "0", Data([0]), ["x"], 7, 1e300, Double.nan] {
            XCTAssertEqual(plays(setting: true, uiAudio: garbage), 1, "\(garbage)")
        }
    }

    /// A capture sounds once, at the freeze — not once per display — and never for a press that froze nothing.
    func testACaptureSoundsOnceAtTheFreezeBeforeAnythingIsWritten() async throws {
        let rig = Rig(home: scratchDirectory("shots-shutter-press"))
        rig.capture.outcome = .frozen(Freeze(
            displays: [Rig.display(1), Rig.display(2, origin: CGPoint(x: 100, y: 0))], windows: []))
        let atPlay = Probe(rig.writer)
        let session = CaptureSession(capture: rig.capture, writer: rig.writer, trash: rig.trash, pasteboard: rig.pasteboard,
                                     preferences: rig.preferences, shutter: atPlay, textReader: rig.reader,
                                     settings: { .defaults }, naming: { .english },
                                     locations: ScreenshotsLocations(home: rig.home, desktop: rig.desktop))
        _ = await session.captureScreens()
        XCTAssertEqual(atPlay.written, [0], "the shutter did not sound exactly once, before the first file")
        XCTAssertEqual(rig.writer.written.count, 2)
    }

    func testAPressThatFrozeNothingIsSilent() async throws {
        for (what, setup) in [("denied before", { (rig: Rig) in rig.capture.grant = .denied }),
                              ("denied during", { (rig: Rig) in rig.capture.outcome = .denied }),
                              ("failed", { (rig: Rig) in rig.capture.outcome = .failed })] {
            let rig = Rig(home: scratchDirectory("shots-shutter-silent"))
            setup(rig)
            _ = await rig.session.captureScreens()
            XCTAssertEqual(rig.shutter.plays, 0, what)
        }
    }

    /// Records how many files existed when it was asked to sound.
    private final class Probe: ShutterPlaying, @unchecked Sendable {
        private let lock = NSLock()
        private let writer: FakeWriter
        private var seen: [Int] = []
        init(_ writer: FakeWriter) { self.writer = writer }
        var written: [Int] { lock.withLock { seen } }
        func play() { let count = writer.written.count; lock.withLock { seen.append(count) } }
    }
}
