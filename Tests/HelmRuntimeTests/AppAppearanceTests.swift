import XCTest
@testable import HelmRuntime

final class AppAppearanceTests: XCTestCase {
    /// A missing or unreadable setting must land on the system's choice, which
    /// is the one answer that is never wrong.
    func testUnknownValuesFallBackToTheSystem() {
        for raw in [nil, "", "Dark", "auto", "1", "система"] {
            XCTAssertEqual(AppAppearance.from(raw), .system, String(describing: raw))
        }
    }

    func testTheThreeChoicesRoundTrip() {
        for choice in AppAppearance.allCases {
            XCTAssertEqual(AppAppearance.from(choice.rawValue), choice)
        }
    }

    /// "System" is the absence of a forced appearance, not a third appearance:
    /// forcing one would freeze the app at whatever the system was when it
    /// launched.
    func testSystemForcesNothing() {
        XCTAssertNil(AppAppearance.system.appearanceName)
        XCTAssertEqual(AppAppearance.light.appearanceName, "NSAppearanceNameAqua")
        XCTAssertEqual(AppAppearance.dark.appearanceName, "NSAppearanceNameDarkAqua")
    }

    /// The stored values are what a settings file will contain forever; a
    /// rename is a silent reset of everybody's choice.
    func testStoredNamesAreStable() {
        XCTAssertEqual(AppAppearance.allCases.map(\.rawValue), ["system", "light", "dark"])
    }
}
