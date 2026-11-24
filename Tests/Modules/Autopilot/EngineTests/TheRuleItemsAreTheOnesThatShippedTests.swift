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
/// off the dev script.
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

    /// Without this a rename of the Dev bundle silently puts Dev back on the
    /// deployed items. `rewrite-as-dev.sh` writes the identifier; `package-dev.sh` must still run it.
    func testTheDevScriptWritesTheIdentifierTheItemsAreKeyedOn() throws {
        let rewrite = try RepoSource.text(of: "Scripts/rewrite-as-dev.sh")
        // The closing quote: the helper's `com.helm.app.dev.launchpad` line begins the same way.
        XCTAssertTrue(rewrite.contains("Set :CFBundleIdentifier \(AppBuild.devIdentifier)\""))
        let package = try RepoSource.text(of: "Scripts/package-dev.sh")
        XCTAssertTrue(package.contains("rewrite-as-dev.sh"))
    }
}
