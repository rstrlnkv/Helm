import XCTest
import HelmRuntime
@testable import Module_VPN_Engine

/// The one name the per-app rules have on disk.
///
/// One spelling of the key and its `"{}"` default, which the settings page
/// reads through, and one silent way to lose every rule somebody wrote:
/// renaming it. A rename reads a key no install has, `VPNRules.decode` finds
/// nothing, and the automation stops firing with the rules still on disk
/// under the old name — nothing throws, nothing is logged.
final class RulesKeepTheirNameOnDiskTests: XCTestCase {
    private var backing: InMemoryKeyValueStore!
    private var settings: VPNSettings!

    override func setUp() {
        super.setUp()
        backing = InMemoryKeyValueStore()
        settings = VPNSettings(store: NamespacedStore(namespace: "vpn", backing: backing))
    }

    func testTheRulesAreWrittenUnderTheNameEveryInstallAlreadyHas() {
        settings.setRulesJSON(VPNRules.encode(["com.apple.Safari": VPNAppRule(vpnName: "Home")]))
        XCTAssertEqual(VPNRules.decode(backing.raw["module.vpn.vpnAppRules"] as? String ?? ""),
                       ["com.apple.Safari": VPNAppRule(vpnName: "Home")],
                       "nothing landed under \"vpnAppRules\" — every stored rule is orphaned")
        XCTAssertEqual(VPNRules.decode(settings.rulesJSON),
                       ["com.apple.Safari": VPNAppRule(vpnName: "Home")],
                       "the rules are not read back from where they were written")
    }

    /// `VPNRules.decode` answers empty for anything it cannot read, so the
    /// default has to be a document rather than "": both come out as no rules,
    /// and only one of them says so.
    func testAnUntouchedStoreReadsAsAnEmptyRuleDocument() {
        XCTAssertEqual(settings.rulesJSON, "{}")
        XCTAssertTrue(VPNRules.decode(settings.rulesJSON).isEmpty)
        XCTAssertTrue(backing.raw.isEmpty, "reading the default wrote \(backing.raw.keys.sorted())")
    }
}
