import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine

/// A bundle's own `InfoPlist.strings` for the person's language wins over the `Info.plist` names.
/// The expected language is asked of `Bundle.preferredLocalizations` over the codes the fixture has, not of the catalog under test.
final class ACatalogNamesAnAppAsFinderDoesTests: XCTestCase {
    func testTheLocalizedNameIsTheOneShown() throws {
        let root = scratchDirectory("localized")
        let app = root.appendingPathComponent("Plain.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "x.plain", "CFBundleName": "Plain",
                                                              "CFBundleDevelopmentRegion": "en"] as [String: Any],
                                           format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        let codes = ["en", "de", "fr", "ja", "ru", "zh-Hans", "es", "pt"]
        for code in codes {
            let lproj = contents.appendingPathComponent("Resources/\(code).lproj")
            try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
            try "\"CFBundleDisplayName\" = \"Shown-\(code)\";".write(to: lproj.appendingPathComponent("InfoPlist.strings"), atomically: true, encoding: .utf8)
        }
        let expected = try XCTUnwrap(Bundle.preferredLocalizations(from: codes).first)
        XCTAssertEqual(FileSystemAppCatalog(roots: [root]).read().apps.map(\.name), ["Shown-\(expected)"])
    }
}
