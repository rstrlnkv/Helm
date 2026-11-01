import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Autopilot_Engine

/// The two keychain items the rule seal lives in are deployed, and Helm Dev has
/// accounts of its own.
///
/// **Keyed on the bundle identifier, not on `AppBuild.isDev`.** `isDev` reads the
/// version string and is true of every published dev-channel build, the person's
/// own installed Helm among them: keyed on it, the real Helm moves to new
/// accounts, finds no key, makes one, and reads its rules as «somebody rewrote
/// your rules».
///
/// No test here asks the keychain anything: the names are read off values and
/// off the source.
final class TheRuleItemsAreTheOnesThatShippedTests: XCTestCase {

    /// Spelled as literals on purpose: a test that built them from the subject's
    /// own constants would pass whatever they became.
    private let deployed = RuleKeychainItems(seal: "rule-seal", sequence: "rule-seq")

    func testEveryIdentifierButHelmDevReadsTheDeployedItems() {
        for identifier in ["com.helm.app", AppBuild.releaseIdentifier, nil,
                           "com.apple.dt.xctest.tool", "com.helm.app.dev.other", ""] as [String?] {
            XCTAssertEqual(RuleKeychainItems.of(bundle: identifier), deployed,
                           "\(identifier ?? "nil") left the deployed items")
        }
        XCTAssertEqual(RuleKeychainItems.service, "com.helm.autopilot")
    }

    func testHelmDevReadsItsOwnAccountsAndNeverADeployedOne() {
        let dev = RuleKeychainItems.of(bundle: "com.helm.app.dev")
        XCTAssertEqual(dev, RuleKeychainItems(seal: "dev-rule-seal", sequence: "dev-rule-seq"))
        XCTAssertNotEqual(dev.seal, deployed.seal)
        XCTAssertNotEqual(dev.sequence, deployed.sequence)
        XCTAssertNotEqual(dev.seal, deployed.sequence)
        XCTAssertNotEqual(dev.sequence, deployed.seal)
    }

    func testThePortsAreBuiltOverTheRunningBundlesItems() {
        let expected = RuleKeychainItems.of(bundle: Bundle.main.bundleIdentifier)
        XCTAssertEqual(KeychainRuleKey().items, expected)
        XCTAssertEqual(KeychainRuleSequence().items, expected)
        let dev = RuleKeychainItems.of(bundle: AppBuild.devIdentifier)
        XCTAssertEqual(KeychainRuleKey(items: dev).items, dev)
        XCTAssertEqual(KeychainRuleSequence(items: dev).items, dev)
    }

    private func code(_ path: String) throws -> [String] {
        try RepoSource.lines(of: path).map(RepoSource.code)
    }

    func testTheSourceSpellsTheDeployedNamesOnceAndAddressesThroughItems() throws {
        let lines = try code("Sources/Modules/Autopilot/Engine/RuleKeychain.swift")
        let text = lines.joined(separator: "\n")
        for literal in [#""com.helm.autopilot""#, #""rule-seal""#, #""rule-seq""#] {
            XCTAssertTrue(text.contains(literal), "\(literal) is no longer spelled where it shipped")
        }
        XCTAssertTrue(text.contains("account: items.seal"))
        XCTAssertTrue(text.contains("kSecAttrAccount as String: items.sequence"))
        XCTAssertFalse(text.contains("SecItemDelete"), "an item is deleted")

        var naming: [String] = []
        for path in try RepoSource.swiftFiles(under: "Sources") {
            let hits = try code(path).filter {
                $0.contains(#""com.helm.autopilot""#) || $0.contains(#""rule-seal""#) || $0.contains(#""rule-seq""#)
            }
            if !hits.isEmpty { naming.append(path) }
        }
        XCTAssertEqual(naming, ["Sources/Modules/Autopilot/Engine/RuleKeychain.swift"])
    }

    /// Without this a rename of the Dev bundle silently puts Dev back on the
    /// deployed items.
    func testTheDevScriptWritesTheIdentifierTheItemsAreKeyedOn() throws {
        let script = try RepoSource.text(of: "Scripts/package-dev.sh")
        XCTAssertTrue(script.contains("Set :CFBundleIdentifier \(AppBuild.devIdentifier)"))
    }

    func testNoVersionEntersTheChoice() throws {
        let text = try code("Sources/Modules/Autopilot/Engine/RuleKeychain.swift").joined(separator: "\n")
        XCTAssertFalse(text.contains("isDev "), "the choice reads the version string")
        XCTAssertFalse(text.contains("AppBuild.isDev\n"))
        XCTAssertTrue(text.contains("AppBuild.isDevIdentifier"))
    }
}
