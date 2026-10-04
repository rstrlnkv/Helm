import Combine
import Foundation
import HelmRuntime
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **A write announces itself, and whoever hears it reads the store as it stands between two writes.** The timer cell
/// writes two keys (`timerLength` and `timer`); every state the settings can be read as in between — at each
/// announcement and in each value the model publishes — must be one of the two whole states, before or after, and in
/// particular must never lose the length the timer had. Started from the store a version before `timerLength` left
/// (only `timer`), the one that has the length, and a fresh one.
@MainActor
final class TheTimerCellNeverShowsAHalfWrittenStoreTests: XCTestCase {

    private struct Seen { var timers: Set<CaptureTimer> = [], lengths: Set<CaptureTimer> = [] }
    private final class Log: @unchecked Sendable { var announced = Seen(), published = Seen() }

    private func run(_ values: [String: Any], _ press: (CapturePanelModel) -> Void) -> (before: ScreenshotsSettings, after: ScreenshotsSettings, announced: Seen, published: Seen) {
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        for (key, value) in values { store.set(value, for: key) }
        let model = CapturePanelModel(store: store)
        let before = model.settings
        let log = Log()
        let heard = NotificationCenter.default.addObserver(forName: .helmStoreChanged, object: nil, queue: nil) { _ in
            let now = ScreenshotsSettings.read(store)
            log.announced.timers.insert(now.timer); log.announced.lengths.insert(now.timerLength)
        }
        let sink = model.$settings.dropFirst().sink { now in log.published.timers.insert(now.timer); log.published.lengths.insert(now.timerLength) }
        press(model)
        NotificationCenter.default.removeObserver(heard)
        sink.cancel()
        return (before, model.settings, log.announced, log.published)
    }

    private func check(_ values: [String: Any], _ what: String, _ press: (CapturePanelModel) -> Void,
                       file: StaticString = #filePath, line: UInt = #line) {
        let r = run(values, press)
        for (name, seen) in [("announcement", r.announced), ("published value", r.published)] {
            XCTAssertTrue(seen.lengths.isSubset(of: [r.before.timerLength, r.after.timerLength]),
                          "\(what): a \(name) read the length as \(seen.lengths), between \(r.before.timerLength) and \(r.after.timerLength)", file: file, line: line)
            XCTAssertTrue(seen.timers.isSubset(of: [r.before.timer, r.after.timer]),
                          "\(what): a \(name) read the timer as \(seen.timers), between \(r.before.timer) and \(r.after.timer)", file: file, line: line)
        }
        XCTAssertFalse(r.announced.timers.isEmpty, "\(what): nothing was announced, so nothing was checked", file: file, line: line)
    }

    private typealias Key = ScreenshotsSettings.Key

    func testSwitchingOffFromAStoreThatHasOnlyTheTimerKeepsTheLengthInEveryState() {
        for length in [CaptureTimer.five, .ten, .thirty] {
            // The cell's own press never switches a lit timer off (it opens the lengths), so the one way off is «No timer».
            check([Key.timer: length.rawValue], "None picked from a store with only timer \(length)") { $0.choose(.none) }
            // And the cell's press on a lit timer, were it ever sent to `toggleTimer()`, changes nothing and shows no half state.
            check([Key.timer: length.rawValue], "a press sent to toggleTimer on a lit timer, store with only timer \(length)") { $0.toggleTimer() }
            let lit = run([Key.timer: length.rawValue]) { $0.toggleTimer() }
            XCTAssertEqual(lit.after.timer, length, "toggleTimer switched a lit timer off or changed its length")
            XCTAssertEqual(lit.after.timerLength, length)
            let r = run([Key.timer: length.rawValue]) { $0.choose(.none) }
            XCTAssertEqual(r.after.timerLength, length, "the length was lost by switching off")
            XCTAssertEqual(r.after.timer, .none)
        }
    }

    func testSwitchingOnAndPickingALengthNeverShowsTheOldTimerWithTheNewLengthAndBack() {
        check([Key.timer: 0, Key.timerLength: 30], "on with the last length") { $0.toggleTimer() }
        check([Key.timer: 10, Key.timerLength: 10], "a new length while on") { $0.choose(.thirty) }
        check([:], "a length on a fresh store") { $0.choose(.ten) }
        check([Key.timer: 5], "a length on a store with only timer") { $0.choose(.thirty) }
    }

    func testAFullRoundOfPressesEndsWhereTheCellSaysAndKeepsItsLength() {
        let r = run([Key.timer: 10]) { model in
            model.toggleTimer(); model.toggleTimer(); model.choose(.thirty); model.choose(.none); model.toggleTimer()
        }
        XCTAssertEqual(r.after.timer, .thirty)
        XCTAssertEqual(r.after.timerLength, .thirty)
    }
}
