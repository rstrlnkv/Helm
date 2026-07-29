import XCTest
import HelmContract
import HelmRuntime
@testable import HelmUI

/// `PermissionNeed.Feature` is the table that says what each capability needs
/// before the user is allowed to believe a switch is doing something. It was
/// designed for that and then asked by exactly one guard — Keep Awake's — so
/// six of its seven entries were a comment with a `switch` around them.
///
/// This is the guard for all of them: a module that provides a feature needing
/// a grant must declare that grant, or `PermissionAudit` — which reads nothing
/// but the declarations — cannot tell the user their switch stopped working.
/// That is not hypothetical: three modules needed Full Disk Access and none
/// declared it, which is why the after-update alert once asked about half of
/// what had broken.
final class FeaturePermissionsTests: XCTestCase {

    /// Which module provides each capability. A feature with no module is a
    /// table entry nothing answers to, which is how this table went inert in
    /// the first place.
    private static let providers: [PermissionNeed.Feature: String] = [
        .pointerNudge: "KeepAwake",
        .appContainers: "Uninstaller",
        .leftoverRemoval: "Leftovers",
        .wholeDiskScan: "Disk",
        .vpnControl: "VPN",
        .homebrew: "Homebrew",
        .layoutSwitch: "Layout",
    ]

    private var sourcesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // HelmUITests
            .deletingLastPathComponent()    // Tests
            .deletingLastPathComponent()    // repo
            .appendingPathComponent("Sources/Modules")
    }

    func testEveryFeatureNamesAModuleThatExists() throws {
        for feature in PermissionNeed.Feature.allCases {
            let module = try XCTUnwrap(Self.providers[feature],
                                       "\(feature) names no module — nothing can ask for it")
            var isDirectory: ObjCBool = false
            let path = sourcesRoot.appendingPathComponent(module).path
            XCTAssertTrue(FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                          && isDirectory.boolValue,
                          "\(feature) points at \(module), which is not a module")
        }
    }

    /// The declaration is what the audit reads, so the declaration is what has
    /// to agree with the table.
    func testAModuleDeclaresTheGrantItsFeatureNeeds() throws {
        for (feature, module) in Self.providers {
            guard let need = PermissionNeed.of(feature) else { continue }
            let declared = try declaredPermissions(ofModule: module)
            XCTAssertTrue(declared.contains(need.declaredName),
                          """
                          \(module) provides \(feature), which macOS gates behind \
                          \(need.declaredName), and its descriptor declares \(declared). \
                          Without the declaration PermissionAudit stays silent \
                          after an update and the switch quietly does nothing.
                          """)
        }
    }

    /// The runtime spells the grant `fullDiskAccess` and the contract spells it
    /// `fullDisk`, so the bridge between them is a string — and a string that
    /// names no case would make the assertion above vacuously kind. Keep Awake's
    /// guard compared `rawValue`s, which coincide for Accessibility and never
    /// could for the disk.
    func testTheBridgeNamesARealContractCase() {
        let contract = Set(ModulePermission.allCases.map(\.rawValue))
        for need in PermissionNeed.allCases {
            XCTAssertTrue(contract.contains(need.declaredName),
                          "\(need) declares itself as '\(need.declaredName)', which no "
                          + "ModulePermission case answers to")
        }
    }

    private func declaredPermissions(ofModule module: String) throws -> [String] {
        let descriptor = sourcesRoot
            .appendingPathComponent("\(module)/UI/\(module)Descriptor.swift")
        let source = try String(contentsOf: descriptor, encoding: .utf8)
        guard let open = source.range(of: "permissions: ["),
              let close = source.range(of: "]", range: open.upperBound..<source.endIndex)
        else { return [] }
        return source[open.upperBound..<close.lowerBound]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".", with: "") }
            .filter { !$0.isEmpty }
    }
}
