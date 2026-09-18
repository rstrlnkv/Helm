import Foundation
import HelmTestSupport
import XCTest
@testable import HelmRuntime

/// One keychain item, one cache over it.
///
/// `SealKeyCache` serialises the callers that share the instance and nobody
/// else, so two instances over one item are two `SecItemCopyMatching` calls —
/// and on an ad-hoc signed build, where the item's access list names a build
/// that no longer exists, the second is a second modal dialog for anyone who
/// answers the first with "Allow" rather than "Always Allow". That is what
/// shipped: `AppSettings.scanGuard` and `DuplicatesSettings.guardOfScanSettings`
/// each built one, each documenting at length that the item was shared.
///
/// Read out of the source because there is nowhere else to read it — the guard
/// keeps its port private, and a test that asked the real keychain would write
/// to the person's own. `TheScanSettingsSealDoesNotMoveTests` records module
/// store keys the same way and for the same reason.
final class TheSettingsSealKeyIsAskedOnceTests: XCTestCase {

    private func sealKeySource() throws -> String {
        try RepoSource.text(of: "Sources/HelmRuntime/SettingsSealKey.swift")
    }

    /// The three strings are stored data on every Mac that has run a background
    /// scan: change one and the item is *absent*, `KeychainSealKey` makes a new
    /// one, and every setting the person really did save then reads as tampered
    /// with. Nothing is an error anywhere.
    func testTheKeychainItemIsTheOneThatShipped() throws {
        let source = try sealKeySource()

        XCTAssertTrue(source.contains(#"service: "com.helm.app""#),
                      "the app's own namespace, deliberately not Autopilot's")
        XCTAssertTrue(source.contains(#"account: "settings-seal""#))
        XCTAssertTrue(source.contains(#"category: "scan""#),
                      "the log category names the feature that lost its key")
    }

    /// And nowhere else. Two spellings of one item is the defect this file is
    /// named after, and it is invisible in either file on its own — each one
    /// reads correctly, and says so in its own doc comment.
    func testNothingElseAddressesTheItem() throws {
        var naming: [String] = []
        for path in try RepoSource.swiftFiles(under: "Sources") {
            let hits = try RepoSource.lines(of: path)
                .map(RepoSource.code)
                .filter { $0.contains(#""settings-seal""#) }
            if !hits.isEmpty { naming.append(path) }
        }

        XCTAssertEqual(naming, ["Sources/HelmRuntime/SettingsSealKey.swift"],
                       "the item is addressed in more than one place: \(naming)")
    }

    /// One cache in the whole tree, for the same reason: the cost is per
    /// instance, not per item.
    func testThereIsOneCacheOverIt() throws {
        var built: [String] = []
        for path in try RepoSource.swiftFiles(under: "Sources") {
            for line in try RepoSource.lines(of: path) where RepoSource.code(line).contains("SealKeyCache(") {
                built.append("\(path): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }

        XCTAssertEqual(built.count, 1, "found: \(built)")
    }
}
