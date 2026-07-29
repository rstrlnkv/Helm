import XCTest
import HelmRuntime

/// A module must declare the grants its features actually need.
///
/// `PermissionAudit` builds the after-update alert out of the enabled modules'
/// declared permissions, and nothing else. Keep Awake's pointer nudge posts a
/// synthetic `CGEvent`, which macOS drops without Accessibility — and every
/// ad-hoc signed build is a new app to TCC, so the grant lapses on every
/// update while the checkbox stays ticked. Declaring only `.adminHelper` meant
/// a Keep Awake user who does not also run Layout was never told.
///
/// A source scan because the descriptor lives in the UI target, which this
/// test target cannot import, and because the fact worth pinning is the link
/// between the two files rather than either one alone.
final class DeclaredPermissionsTests: XCTestCase {

    private var moduleRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // EngineTests
            .deletingLastPathComponent()   // KeepAwake
            .deletingLastPathComponent()   // Modules
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo
            .appendingPathComponent("Sources/Modules/KeepAwake")
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: moduleRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func test_a_module_that_posts_synthetic_events_declares_accessibility() throws {
        // The premise, not an assumption: if the nudge stops posting events,
        // this test stops demanding the grant.
        guard try source("Engine/SystemPorts.swift").contains(".post(tap:") else {
            return XCTAssertFalse(try declaredPermissions().contains("accessibility"),
                                  "nothing posts events any more — drop the declaration too")
        }
        guard let need = PermissionNeed.of(.pointerNudge) else {
            return XCTFail("the runtime table no longer says what the pointer nudge needs")
        }
        // `declaredName`, not `rawValue`: the contract spells Full Disk Access
        // `fullDisk` and the runtime spells it `fullDiskAccess`, so a rawValue
        // comparison happens to be right here and would fail open for any
        // module needing the other grant.
        XCTAssertTrue(try declaredPermissions().contains(need.declaredName))
    }

    /// The admin prompt for the sudoers rule is the other one, and it stays.
    func test_the_admin_helper_declaration_survives() throws {
        XCTAssertTrue(try declaredPermissions().contains("adminHelper"))
    }

    private func declaredPermissions() throws -> [String] {
        let descriptor = try source("UI/KeepAwakeDescriptor.swift")
        guard let open = descriptor.range(of: "permissions: ["),
              let close = descriptor.range(of: "]", range: open.upperBound..<descriptor.endIndex)
        else {
            XCTFail("no permissions list in the descriptor")
            return []
        }
        return descriptor[open.upperBound..<close.lowerBound]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ".", with: "") }
    }
}
