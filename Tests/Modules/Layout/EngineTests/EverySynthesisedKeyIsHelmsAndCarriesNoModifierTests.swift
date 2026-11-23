import CoreGraphics
import XCTest
@testable import Module_Layout_Engine

/// Every key this module synthesises is Helm's own, and goes out with no modifier on it.
///
/// **No modifier. Reported live: «pressing Option converts the word and deletes
/// one more».** The event source carries the *live* modifier state, and the gesture
/// this module ships with is a tap of a modifier. Release ⌥ a moment late and every
/// synthesised Delete goes out as ⌥Delete, which removes a whole word rather than a
/// character; ⌘ is worse, a synthesised ⌘-letter is a menu command in the app in
/// front. The factory here hands back events whose flags are already ⌥⌘, standing
/// for that live state, and none may come out carrying it.
///
/// **Helm's own.** The tap drops events whose source data is `helmEventMarker`;
/// an event built from an unmarked source is read back as the person's typing.
///
/// Nothing is posted: posting a Delete from a test types into the window in front.
final class EverySynthesisedKeyIsHelmsAndCarriesNoModifierTests: XCTestCase {

    private let plan = SwitchPlan(backspaces: 7, insert: "привет ")

    func testNoEventCarriesTheModifiersThatWereHeld() throws {
        let held: CGEventFlags = [.maskAlternate, .maskCommand]
        let events = try XCTUnwrap(SynthesisTyping.events(for: plan) { key, down in
            let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down)
            event?.flags = held
            return event
        })
        XCTAssertFalse(events.isEmpty, "precondition: nothing was built, so nothing below is checked")
        let modifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskShift, .maskControl,
                                       .maskSecondaryFn, .maskAlphaShift]
        for event in events {
            XCTAssertTrue(event.flags.intersection(modifiers).isEmpty,
                          "an event inherited the live modifier state: \(event.flags)")
        }
    }

    func testEveryEventCarriesHelmsMarker() throws {
        let events = try XCTUnwrap(SynthesisTyping.events(for: plan),
                                   "the events were not built (no event source in this process)")
        XCTAssertEqual(events.count, 2 * (plan.backspaces + plan.insert.count))
        for event in events {
            XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), helmEventMarker,
                           "an event is not marked as Helm's own, and the tap would read it as typing")
        }
    }
}
