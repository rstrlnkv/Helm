import AppKit
import HelmRuntime
import HelmUI
import SwiftUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The panel is one width in a language, whatever it shows.** Idle, with a target, counting from 5 or from 30, with
/// the timer off or on at 5, 10 and 30, in each of the three modes: the natural width of the content, as the real panel
/// asks for it (a hosting view with nobody telling it how wide to be), is the same in all of those states, in every
/// language, and the widest language is named in the run. A change of width under the pointer moves ✕ and the cells it
/// was crossing.
@MainActor
final class ThePanelIsOneWidthInEveryStateAndLanguageTests: XCTestCase {
    override func tearDown() { AppLanguage.override = nil; super.tearDown() }

    private func natural(_ model: CapturePanelModel) -> CGSize {
        let host = NSHostingView(rootView: CapturePanelView(model: model))
        host.sizingOptions = [.intrinsicContentSize]
        return host.fittingSize
    }

    private func state(mode: PanelMode, timer: CaptureTimer, target: Bool, counting: Int?) -> CapturePanelModel {
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        let model = CapturePanelModel(store: store)
        model.choose(mode)
        model.choose(timer)
        model.hasTarget = target
        model.countdown = counting
        model.countdownLength = counting.map { $0 > 5 ? 30 : 5 } ?? 0
        return model
    }

    func testOneWidthInEveryStateInEveryLanguage() {
        var widest: (AppLanguage, CGFloat)?
        var compared = 0
        AppLanguage.each { language in
            let idle = natural(state(mode: .screen, timer: .none, target: false, counting: nil))
            XCTAssertEqual(idle.height, CapturePanelView.height, accuracy: 0.5, "\(language): the panel is not \(CapturePanelView.height) tall")
            if widest == nil || idle.width > widest!.1 { widest = (language, idle.width) }
            for mode in [PanelMode.screen, .window, .area] {
                for timer in [CaptureTimer.none, .five, .ten, .thirty] {
                    for target in [false, true] {
                        for counting in [nil, 5, 2, 30, 1] as [Int?] {
                            let size = natural(state(mode: mode, timer: timer, target: target, counting: counting))
                            compared += 1
                            XCTAssertEqual(size.width, idle.width, accuracy: 0.01,
                                           "\(language): \(mode) timer \(timer) target \(target) counting \(String(describing: counting)) is \(size.width) wide, idle is \(idle.width)")
                            XCTAssertEqual(size.height, idle.height, accuracy: 0.01, "\(language): \(mode) \(timer) \(target) \(String(describing: counting))")
                        }
                    }
                }
            }
        }
        XCTAssertEqual(compared, AppLanguage.allCases.count * 3 * 4 * 2 * 5, "the loop compared \(compared) states: the check watched less than it says")
        print("PANEL-WIDTH widest language \(String(describing: widest?.0)) \(widest?.1 ?? 0) pt")
    }

    /// The timer cell is as wide off as on, whatever the seconds: its width is the constant, in every language.
    func testTheTimerCellHoldsItsWidthBecauseThePanelDoesNot() {
        AppLanguage.each { language in
            let off = natural(state(mode: .screen, timer: .none, target: false, counting: nil)).width
            for timer in [CaptureTimer.five, .ten, .thirty] {
                XCTAssertEqual(natural(state(mode: .screen, timer: timer, target: false, counting: nil)).width, off, accuracy: 0.01,
                               "\(language): the timer at \(timer.seconds) moved the panel's edge")
            }
        }
    }
}
