import Foundation
import XCTest
import HelmTestSupport
@testable import Module_Homebrew_Engine

/// **A package name cannot point the Cellar walk anywhere else.**
///
/// `name` reaches `CellarWeight` from `brew`'s own stdout and from a search box
/// somebody types into, and it is appended to a path that is then **walked**: `..`
/// would point the walk at the prefix, and an absolute-looking name at whatever it
/// names. With the guard removed, `bytes(ofPackage: "..")` walked 3 GB of a real
/// Homebrew installation and reported it as one package's size.
final class ACellarWalkStaysInTheCellarTests: XCTestCase {

    private struct FixedLocator: BrewLocator {
        let prefix: URL
        func brewPath() -> String? { prefix.appendingPathComponent("bin/brew").path }
    }

    func testANameThatWouldLeaveTheCellarIsNotAPackage() throws {
        let prefix = scratchDirectory("brew-size-escape")
        let file = prefix.appendingPathComponent("Cellar/openssl@3/3.6.4/bin/openssl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(count: 10_000).write(to: file)
        let weight = CellarWeight(locator: FixedLocator(prefix: prefix))

        for name in ["..", ".", "", "../Cellar/openssl@3", "openssl@3/3.6.4", "/etc"] {
            XCTAssertNil(weight.bytes(ofPackage: name, isCask: false),
                         "«\(name)» was walked as though it named a package")
        }
        XCTAssertNotNil(weight.bytes(ofPackage: "openssl@3", isCask: false),
                        "nothing here is measurable, so the nils above say nothing")
    }
}
