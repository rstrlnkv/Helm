import XCTest
import HelmTestSupport
import Tweak_DisplayCorners_Engine
@testable import Tweak_DisplayCorners_UI

/// **Calibration ends on every way out, and the colour panel goes with it.**
///
/// Calibration paints the top corners of the built-in display and may leave the colour panel on the screen, so a way
/// out that forgets it leaves coloured corners and a floating panel after nobody is looking at them. The ways out are
/// the card's own switch, a person closing the panel, the page being left (the calibration row's `pageLeft()`), and the
/// tweak being stopped (the host's `stop()`, which also ends the model's reading of the engine). Each is driven
/// on `DisplayCornersModel` against a recording engine and a recording panel; five of the eight tests drive them and
/// each of those five first proves that calibration was running and the panel open (`calibrating()`), so a test that
/// did nothing cannot pass. Of the three others, two carry their own control (the engine's word adopted before the
/// stop; the panel opened once calibration runs) and the third needs none, its switches start off and its asserts are
/// that each shows on.
///
/// The fakes carry the states the real ones have: the engine's calibration is running or not and an end of one that is
/// not running changes nothing, as `DisplayCornersEngine.endCalibration`; the panel tells its owner of a person's
/// close and never of its owner's, as `CalibrationColourPanel`.
@MainActor
final class CalibrationEndsOnEveryWayOutTests: XCTestCase {

    private final class Events { var log: [String] = [] }

    private final class FakeEngine: CornerEngineSide {
        let events: Events
        var calibration: CalibrationColour?
        var builtIn = false
        var external = false
        var preset: Int?
        private(set) var streamEnded = false
        private var continuation: AsyncStream<CornerState>.Continuation?
        var onStreamEnd: () -> Void = {}
        init(_ events: Events) { self.events = events }

        var state: CornerState {
            CornerState(calibrating: calibration != nil, builtIn: builtIn, external: external,
                        calibrationColour: calibration, selectedPreset: preset)
        }
        func stream() -> AsyncStream<CornerState> {
            AsyncStream { continuation in
                self.continuation = continuation
                continuation.onTermination = { [weak self] _ in
                    Task { @MainActor in
                        self?.streamEnded = true
                        self?.onStreamEnd()
                    }
                }
            }
        }
        /// What the engine says unasked.
        func say() { continuation?.yield(state) }
        func setBuiltIn(_ on: Bool) { builtIn = on }
        func setExternal(_ on: Bool) { external = on }
        func setPreset(points: Double) { preset = Int(points) }
        func stepRadius(direction: Int) {}
        func beginCalibration() {
            guard calibration == nil else { return }
            calibration = .default
        }
        func setCalibration(r: Double, g: Double, b: Double) {
            guard calibration != nil else { return }
            calibration = CalibrationColour(clamping: r, g, b)
        }
        func endCalibration() {
            guard calibration != nil else { return }
            events.log.append("engine ends calibration")
            calibration = nil
        }
    }

    private final class FakePanel: CalibrationPanelSeam {
        let events: Events
        private(set) var isOpen = false
        private(set) var opened = 0
        private var onClosed: () -> Void = {}
        init(_ events: Events) { self.events = events }
        func open(showing colour: CalibrationColour, title: String,
                  onPick: @escaping (Double, Double, Double) -> Void, onClosed: @escaping () -> Void) {
            isOpen = true
            opened += 1
            self.onClosed = onClosed
        }
        func close() {
            guard isOpen else { return }
            events.log.append("panel closes")
            isOpen = false
        }
        /// Somebody pressing the panel's close button.
        func personCloses() {
            guard isOpen else { return }
            isOpen = false
            onClosed()
        }
    }

    private final class FakeMasks: CornerMasks {
        private(set) var removedAll = 0
        func show(_ diff: MaskDiff) -> [MaskKey: Int] { [:] }
        func setRounded(_ rounded: Bool, display: UInt32) {}
        func presentation(of key: MaskKey) -> MaskPresentation? { nil }
        func removeAll() { removedAll += 1 }
    }

    @MainActor private struct Rig {
        let events = Events()
        let engine: FakeEngine
        let panel: FakePanel
        let masks = FakeMasks()
        let model: DisplayCornersModel
        init() {
            let events = events
            engine = FakeEngine(events)
            panel = FakePanel(events)
            model = DisplayCornersModel(engine: engine, masks: masks, panel: panel)
        }
    }

    /// Calibration on and the panel open, each checked in the engine, the panel and what the card draws.
    private func calibrating() -> Rig {
        let rig = Rig()
        rig.model.setCalibrating(true)
        rig.model.chooseCalibrationColour()
        XCTAssertNotNil(rig.engine.calibration, "the subject did not happen: calibration is not running")
        XCTAssertTrue(rig.panel.isOpen, "the subject did not happen: the panel is not open")
        XCTAssertTrue(rig.model.state.calibrating, "the card does not show calibration")
        return rig
    }

    private func assertEnded(_ rig: Rig, _ way: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(rig.engine.calibration, "\(way): the engine still calibrates", file: file, line: line)
        XCTAssertFalse(rig.panel.isOpen, "\(way): the panel is still open", file: file, line: line)
        XCTAssertFalse(rig.model.state.calibrating, "\(way): the card still shows calibration", file: file, line: line)
    }

    func testTheSwitchEndsItAndClosesThePanelFirst() {
        let rig = calibrating()
        rig.model.setCalibrating(false)
        assertEnded(rig, "switch off")
        XCTAssertEqual(rig.events.log, ["panel closes", "engine ends calibration"], "the panel is closed before the engine ends it")
    }

    func testAPersonClosingThePanelEndsIt() {
        let rig = calibrating()
        rig.panel.personCloses()
        assertEnded(rig, "the panel closed by a person")
    }

    func testLeavingThePageEndsItAndIsSafeTwice() {
        let rig = calibrating()
        rig.model.pageLeft()
        assertEnded(rig, "page left")
        rig.model.pageLeft()
        assertEnded(rig, "page left twice")
    }

    func testStoppingTheTweakEndsItOrdersTheMasksOutAndEndsTheReading() async {
        let rig = calibrating()
        XCTAssertFalse(rig.engine.streamEnded, "the subject did not happen: the reading ended before stop")
        let ended = expectation(description: "the engine's stream is no longer read")
        rig.engine.onStreamEnd = { ended.fulfill() }
        rig.model.stop()
        assertEnded(rig, "stop")
        XCTAssertEqual(rig.masks.removedAll, 1)
        await fulfillment(of: [ended], timeout: 5)
        rig.model.stop()
        assertEnded(rig, "stop twice")
    }

    func testAnEngineThatSpeaksAfterTheStopIsNotHeard() async {
        let rig = Rig()
        rig.engine.builtIn = true
        rig.engine.say()
        // The control: before the stop the same word is adopted.
        await waitUntil("the model adopted the engine's word") { rig.model.state.builtIn }
        let ended = expectation(description: "the engine's stream is no longer read")
        rig.engine.onStreamEnd = { ended.fulfill() }
        rig.model.stop()
        await fulfillment(of: [ended], timeout: 5)
        rig.engine.builtIn = false
        rig.engine.say()
        await grace()
        XCTAssertTrue(rig.model.state.builtIn, "a stopped model still reads the engine")
    }

    func testNoPanelOpensWhileNothingIsCalibrated() {
        let rig = Rig()
        rig.model.chooseCalibrationColour()
        XCTAssertEqual(rig.panel.opened, 0, "the panel opened with no calibration running")
        rig.model.setCalibrating(true)
        rig.model.chooseCalibrationColour()
        XCTAssertEqual(rig.panel.opened, 1, "the subject did not happen: a running calibration opens the panel")
    }

    func testStoppingThenLeavingThePageIsSafeAndOrdersTheMasksOutOnce() {
        let rig = calibrating()
        rig.model.stop()
        rig.model.pageLeft()
        assertEnded(rig, "stop then page left")
        XCTAssertEqual(rig.masks.removedAll, 1, "a page left after the stop ordered the masks out again")
    }

    func testEveryCommandIsShownAtOnceWithoutWaitingForTheStream() {
        let rig = Rig()
        rig.model.setBuiltIn(true)
        XCTAssertTrue(rig.model.state.builtIn, "the built-in switch shows its old value until the stream speaks")
        rig.model.setExternal(true)
        XCTAssertTrue(rig.model.state.external, "the external switch shows its old value until the stream speaks")
        rig.model.choosePreset(points: 12)
        XCTAssertEqual(rig.model.state.selectedPreset, 12, "the preset shows its old value until the stream speaks")
        rig.model.setCalibrating(true)
        XCTAssertTrue(rig.model.state.calibrating, "the calibration switch shows its old value until the stream speaks")
    }
}
