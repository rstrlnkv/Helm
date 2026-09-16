import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmUI

/// **A placeholder is not a name, and this control had nothing else.**
///
/// `HelmSearchField` set `placeholderString` and stopped there. A placeholder
/// disappears the moment there is a value, so the field was anonymous to
/// VoiceOver exactly while somebody was using it — read aloud as "search text
/// field" with nothing to say which of the two lists in this app it searches.
/// Homebrew's package search and the Uninstaller's app filter are the same
/// omission twice, which is why the name is on the control rather than at either
/// call site.
///
/// **What made it invisible.** `NamedControlsTests` is the guard for an unnamed
/// control and cannot see this one: it scans source for `Picker("")` /
/// `TextField("")` and for `Button`/`Toggle`/`Menu` whose label is an image, and
/// an `NSViewRepresentable` is none of those. So the reading here is off the
/// **mounted control**, not off the source — the label has to survive
/// `makeNSView`, the window, and an `updateNSView` pass, and a source scan would
/// pass on a line that AppKit ignored.
///
/// Measured on a bare `NSSearchField` before the fix (2026-09-16):
/// `accessibilityLabel()` nil with the field empty, and still nil with `wget`
/// typed into it — AppKit promotes neither the placeholder nor the string value,
/// so there was no name at either moment.
@MainActor
final class ASearchFieldSaysWhatItIsTests: XCTestCase {

    private var renders: [MountedRender] = []

    override func tearDown() {
        renders.forEach { $0.drop() }
        renders = []
        super.tearDown()
    }

    /// The one `NSSearchField` a mounted `HelmSearchField` produces.
    ///
    /// Fails rather than returns nil when there is none: every assertion below
    /// is about a control, and a walk that found no control would satisfy an
    /// `XCTAssertNotNil` on an optional chain by never running.
    private func field(text: String, file: StaticString = #filePath,
                       line: UInt = #line) -> NSSearchField? {
        let mount = MountedRender(HelmSearchField(text: .constant(text),
                                                  placeholder: "Search formulae and casks")
                                      .frame(height: 22),
                                  width: 320, height: 60, appearance: .aqua)
        renders.append(mount)
        mount.settle(10)
        let fields = mount.host.everyView(ofType: NSSearchField.self)
        guard fields.count == 1 else {
            XCTFail("""
                the mount produced \(fields.count) search fields where it draws exactly one — \
                there is nothing here whose name could be read
                """, file: file, line: line)
            return nil
        }
        return fields.first
    }

    /// **Empty, which is the state the placeholder covers and the easy half.**
    func testAnEmptyFieldHasAName() throws {
        let field = try XCTUnwrap(field(text: ""))
        XCTAssertEqual(field.accessibilityLabel(), HelmA11y.searchField, """
            the search field is read aloud with no name. AppKit gives an \
            `NSSearchField` none of its own, so whatever `HelmSearchField` does not \
            set is not set
            """)
    }

    /// **And with a value in it, which is the half the placeholder never
    /// covered.** This is the state the defect was actually about: the
    /// placeholder is gone from the screen and from the accessibility tree the
    /// moment somebody types.
    func testAFieldWithSomethingInItStillHasAName() throws {
        let field = try XCTUnwrap(field(text: "wget"))
        XCTAssertEqual(field.stringValue, "wget", "precondition: the value never reached the field")
        XCTAssertEqual(field.accessibilityLabel(), HelmA11y.searchField, """
            the field has a value and no name — which is the defect, since a \
            placeholder is what AppKit drops first
            """)
    }

    /// **The name is not the role said twice.**
    ///
    /// VoiceOver announces the role itself, so a label reading "search field"
    /// comes out as "search field search field". The word is macOS's own for this
    /// control, and it is checked in every language rather than in whichever one
    /// this Mac is set to — this machine runs in Russian, so a bare assertion
    /// exercises one of eight.
    func testTheNameIsAWordAndNotTheRole() {
        AppLanguage.each { language in
            let name = HelmA11y.searchField
            XCTAssertFalse(name.isEmpty, "\(language.rawValue): the search field's name is empty")
            XCTAssertFalse(name.lowercased().contains("field"),
                           "\(language.rawValue): «\(name)» says the role VoiceOver already says")
        }
    }
}
