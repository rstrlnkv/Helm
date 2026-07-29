import XCTest
import Carbon
import Module_Layout_Engine
@testable import Module_Layout_UI

/// `InputSourceInfo` re-implemented the Text Input Sources lookup the engine's
/// `InputSources` already owned in the same module — the same
/// `TISCreateInputSourceList`, the same `kTISPropertyUnicodeKeyLayoutData`
/// filter, and a byte-identical `string(_:_:)`. `InputSources`' own comment says
/// it exists because "every other port here needs the same lookup", and the
/// indicator was the one that did not read it.
///
/// The assertion is that the two agree on *which sources exist*, not on how
/// many there are: the answer is whatever this machine has installed, and a
/// count would pass for the wrong reason on a Mac with one layout.
final class InputSourceLookupTests: XCTestCase {

    func testTheIndicatorAndTheEnginePickTheSameLayouts() {
        let fromUI = Set(InputSourceInfo.all().map(\.id))
        let fromEngine = Set(TISLayoutSources().installed())

        XCTAssertEqual(fromUI, fromEngine,
                       "the indicator and the translator disagree about what is installed")
    }

    /// An input method (Chinese, Japanese) composes rather than maps and has no
    /// key table, so it must not reach either list — this is the filter both
    /// copies carried.
    func testOnlyKeyboardLayoutsAreOffered() {
        for source in InputSources.keyboardLayouts() {
            XCTAssertNotNil(TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData),
                            "a source with no key table reached the list")
        }
    }

    /// Every Mac has at least one keyboard layout, so an empty answer here means
    /// the lookup broke rather than that the machine is unusual.
    func testTheMachineHasAtLeastOneLayoutAndItIsNamed() throws {
        let layouts = InputSourceInfo.all()
        XCTAssertFalse(layouts.isEmpty)
        for layout in layouts {
            XCTAssertFalse(layout.id.isEmpty, "a layout with no identifier cannot be selected")
            XCTAssertFalse(layout.name.isEmpty, "a layout with no name shows as blank")
        }
    }

    /// The current source is one of the installed ones. It came from a separate
    /// Carbon call in each copy, which is exactly where the two could drift.
    func testTheCurrentSourceIsOneOfTheInstalledOnes() {
        let current = InputSourceInfo.current()
        guard !current.id.isEmpty else { return }   // no keyboard source in a headless run

        XCTAssertTrue(InputSourceInfo.all().map(\.id).contains(current.id),
                      "the current layout is not in the list the indicator draws")
    }
}
