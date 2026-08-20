import XCTest
@testable import Module_Homebrew_Engine

/// A pinned formula is in `brew outdated` and cannot be upgraded.
///
/// Pinning is how somebody says "leave this version alone" — usually because
/// the new one broke something. brew still reports it as outdated, and the
/// parser dropped the `pinned` field, so the row offered an Upgrade button that
/// `brew upgrade` answers with "…is pinned". A button that cannot work is worse
/// than no button: it says the app does not know what the Mac is doing.
///
/// The shape below is `brew outdated --json=v2` as Homebrew 6 writes it,
/// checked against the real command on this machine.
final class BrewPinnedTests: XCTestCase {

    /// `parse` answers nil for a document it cannot read, and a `?? []` here
    /// would turn that into the same empty list these tests then count — so the
    /// unreadable case fails by name instead.
    private func parse(_ json: String,
                       file: StaticString = #filePath, line: UInt = #line) -> [OutdatedPackage] {
        guard let parsed = BrewOutdatedParser.parse(Data(json.utf8)) else {
            XCTFail("the parser could not read this document at all", file: file, line: line)
            return []
        }
        return parsed
    }

    func testAPinnedFormulaIsMarkedAsSuch() {
        let packages = parse("""
        {"formulae":[
          {"name":"held","installed_versions":["1.0"],"current_version":"2.0","pinned":true},
          {"name":"free","installed_versions":["1.0"],"current_version":"2.0","pinned":false}
        ],"casks":[]}
        """)
        XCTAssertEqual(packages.first(where: { $0.name == "held" })?.pinned, true)
        XCTAssertEqual(packages.first(where: { $0.name == "free" })?.pinned, false)
    }

    /// Both are still listed. Pinned is not hidden — somebody who pinned a
    /// formula still wants to see that a newer one exists.
    func testAPinnedFormulaIsStillListed() {
        XCTAssertEqual(parse("""
        {"formulae":[{"name":"held","installed_versions":["1.0"],
                      "current_version":"2.0","pinned":true}],"casks":[]}
        """).count, 1)
    }

    /// A cask carries no `pinned` key at all, and absent is not pinned.
    func testAnAbsentFieldIsNotPinned() {
        XCTAssertEqual(parse("""
        {"formulae":[],"casks":[{"name":"app","installed_versions":["1"],"current_version":"2"}]}
        """).first?.pinned, false)
    }
}
