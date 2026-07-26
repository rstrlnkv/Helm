import XCTest
@testable import Module_Leftovers_Engine

/// The identifier a label-less job falls back to is not cosmetic: it is what
/// `launchctl disable` is handed when the user flips the row off, what the
/// owner check compares against the installed apps, and what decides whether
/// the item is offered for deletion at all. A mangled one turns off the wrong
/// label and offers a live app's job as a leftover.
final class LaunchAgentLabelTests: XCTestCase {
    /// ".plist" is stripped with `replacingOccurrences`, which removes EVERY
    /// occurrence — including one in the middle of the name.
    /// `com.vendor.plistwatcher.plist` → `com.vendorwatcher`.
    /// `OrphanDetector.stripKnownSuffix` does the same job with
    /// `hasSuffix` + `dropLast`; this is the sibling that never got it.
    func testOnlyTheTrailingExtensionIsStripped() {
        let info = LaunchAgentReader.read(plist: [:],
                                          path: "/Library/LaunchAgents/com.vendor.plistwatcher.plist")
        XCTAssertEqual(info.identifier, "com.vendor.plistwatcher")
    }

    func testAnExtensionShapedComponentSurvives() {
        let info = LaunchAgentReader.read(plist: [:],
                                          path: "/Library/LaunchAgents/com.plistedit.helper.plist")
        XCTAssertEqual(info.identifier, "com.plistedit.helper")
    }

    /// A `Label` key that is present but blank is not a label. Falling through
    /// to the empty string gives the row no name, and an empty identifier is
    /// what every downstream rule (`isRemovable`, `canToggle`) has to special-
    /// case instead of never seeing.
    func testABlankLabelFallsBackToTheFilename() {
        let info = LaunchAgentReader.read(plist: ["Label": ""],
                                          path: "/Library/LaunchAgents/com.vendor.agent.plist")
        XCTAssertEqual(info.identifier, "com.vendor.agent")
    }
}
