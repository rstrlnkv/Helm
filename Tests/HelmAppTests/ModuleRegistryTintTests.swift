import XCTest
@testable import HelmApp
@testable import HelmUI

/// `ModuleTintTests` measures the nine colours; this measures the nine
/// *modules*. The protocol makes every module declare a tint, and the compiler
/// enforces that — but nothing stops two of them declaring the same one, which
/// would put the app back where it started with four modules in one blue.
@MainActor
final class ModuleRegistryTintTests: XCTestCase {

    func testNoTwoModulesShareATint() {
        let tints = ModuleRegistry.all.map { $0.moduleTint }
        XCTAssertEqual(Set(tints.map(\.rawValue)).count, ModuleRegistry.all.count,
                       "two modules share a tint: \(tints.map(\.rawValue).sorted())")
    }

    /// One case per module and no spares. A case nobody uses is a colour that
    /// was measured, documented and then left for a module that never came;
    /// a module without a case cannot compile, so this only ever fails one way.
    func testTheTintsAndTheModulesAreTheSameCount() {
        XCTAssertEqual(ModuleTint.allCases.count, ModuleRegistry.all.count)
    }
}
