import HelmContract
import HelmUI
import XCTest
import Module_Autopilot_Engine
import Module_Autopilot_UI
import Module_Disk_Engine
import Module_Disk_UI
import Module_Duplicates_Engine
import Module_Duplicates_UI
import Module_Homebrew_Engine
import Module_Homebrew_UI
import Module_Hosts_Engine
import Module_Hosts_UI
import Module_KeepAwake_Engine
import Module_KeepAwake_UI
import Module_Layout_Engine
import Module_Layout_UI
import Module_Leftovers_Engine
import Module_Leftovers_UI
import Module_Uninstaller_Engine
import Module_Uninstaller_UI
import Module_VPN_Engine
import Module_VPN_UI
@testable import HelmApp

/// Every module's id has one spelling, and the engine owns it.
///
/// The house rule — the engine declares `moduleID`, the descriptor forwards it
/// upward — was prose until the ninth constant existed; this is the test under
/// the promise. Each row compares a descriptor's `id` with its engine's
/// constant directly, so a descriptor rewritten as a diverging literal fails
/// here and the failure names the module. The *values* are pinned elsewhere:
/// `StoreNamespacesAreModuleIdsTests` holds the ids that shipped against the
/// registry, so a rename that both sides agree on still fails there.
///
/// The rows are a hand-written list, which CLAUDE.md allows only tied to the
/// thing it names: the first test ties it to `ModuleRegistry.all`, so a module
/// gained or lost fails the guard instead of slipping past it.
@MainActor
final class EveryDescriptorForwardsItsEnginesIdTests: XCTestCase {

    private static let rows: [(descriptor: any ModuleDescriptor.Type, engineID: String)] = [
        (AutopilotDescriptor.self, AutopilotEngine.moduleID),
        (DiskDescriptor.self, DiskEngine.moduleID),
        (DuplicatesDescriptor.self, DuplicatesEngine.moduleID),
        (HomebrewDescriptor.self, HomebrewEngine.moduleID),
        (HostsDescriptor.self, HostsEngine.moduleID),
        (KeepAwakeDescriptor.self, KeepAwakeEngine.moduleID),
        (LayoutDescriptor.self, LayoutEngine.moduleID),
        (LeftoversDescriptor.self, LeftoversEngine.moduleID),
        (UninstallerDescriptor.self, UninstallerEngine.moduleID),
        (VPNDescriptor.self, VPNEngine.moduleID),
    ]

    /// The list above covers exactly the modules the app registers — a tenth
    /// module, or one dropped, fails here rather than being quietly unguarded.
    func testTheRowsAreTheRegistry() {
        let listed = Set(Self.rows.map { ObjectIdentifier($0.descriptor) })
        let registered = Set(ModuleRegistry.all.map { ObjectIdentifier(type(of: $0)) })
        XCTAssertEqual(listed.count, Self.rows.count,
                       "two rows name the same descriptor, so one module is unguarded")
        XCTAssertEqual(listed, registered,
                       "the rows and ModuleRegistry.all disagree about which modules exist — "
                       + "a module missing from the rows has no id guard at all")
    }

    func testEveryDescriptorAnswersWithItsEnginesId() {
        for row in Self.rows {
            XCTAssertEqual(row.descriptor.id, ModuleID(row.engineID),
                           "\(row.descriptor): the descriptor's id "
                           + "\"\(row.descriptor.id.rawValue)\" diverged from the engine's "
                           + "\"\(row.engineID)\" — the store namespace and the log would "
                           + "then name two different modules")
        }
    }
}
