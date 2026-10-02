import AppKit
import HelmRuntime
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **Return and Space on the bar while it counts down start nothing.** The
/// Capture button is still in the layout under the digit, hidden and disabled;
/// the keyboard reaches the bar's panel directly, and the panel must drop the
/// press itself rather than trust that the button cannot be reached. The panel
/// is built and never ordered in.
@MainActor
final class ReturnOnTheBarWhileItCountsIsDroppedTests: XCTestCase {

    private func key(_ code: UInt16, _ characters: String) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                         context: nil, characters: characters, charactersIgnoringModifiers: characters,
                         isARepeat: false, keyCode: code)!
    }

    func testReturnAndSpaceDuringTheCountdownCaptureNothingAndReturnIdleDoes() {
        let bar = CapturePanel(store: NamespacedStore(namespace: ScreenshotsEngine.moduleID,
                                                      backing: InMemoryKeyValueStore()))
        var presses: [PanelMode] = []
        bar.model.capture = { presses.append($0) }
        let panel = bar.makePanel()
        defer { panel.contentView = nil }

        bar.model.countdown = 5
        for (code, characters) in [(UInt16(36), "\r"), (76, "\u{3}"), (49, " ")] {
            panel.keyDown(with: key(code, characters))
        }
        XCTAssertTrue(presses.isEmpty, "a key during the countdown started a capture: \(presses)")

        // The control: the same Return with nothing counting does start one.
        bar.model.countdown = nil
        panel.keyDown(with: key(36, "\r"))
        XCTAssertEqual(presses, [bar.model.mode], "Return on an idle bar did not reach the capture")
    }
}
