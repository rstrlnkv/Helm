import HelmContract
import HelmRuntime
import XCTest
@testable import HelmApp

/// `PermissionSummary` turns what a module declares into the macOS gate behind
/// it. The panel and the settings page both count from this mapping, so a
/// swapped case would send the person to the wrong pane.
@MainActor
final class ADeclaredPermissionMapsToItsPrivacyPaneTests: XCTestCase {

    func testEachDeclaredPermissionMapsToItsOwnGate() {
        XCTAssertEqual(PermissionSummary.need(for: .fullDisk), .fullDiskAccess)
        XCTAssertEqual(PermissionSummary.need(for: .accessibility), .accessibility)
        XCTAssertEqual(PermissionSummary.need(for: .screenRecording), .screenRecording)
    }

    /// The admin helper is a sudoers rule, not a privacy pane.
    func testTheAdminHelperHasNoPrivacyPane() {
        XCTAssertNil(PermissionSummary.need(for: .adminHelper))
    }

    /// The call sites: a swapped flag would ask about the wrong pane.
    func testTheAuditListsOnlyTheDeniedGateTheModulesNeed() {
        for need in PermissionNeed.allCases {
            let got = PermissionAudit.missing(
                needs: [need], fullDisk: .denied, accessibility: .denied,
                screenRecording: .denied)
            XCTAssertEqual(got, [need])
        }
        XCTAssertEqual(PermissionAudit.missing(
            needs: [.fullDiskAccess], fullDisk: .granted, accessibility: .denied,
            screenRecording: .denied), [])
        XCTAssertEqual(PermissionAudit.missing(
            needs: [], fullDisk: .denied, accessibility: .denied,
            screenRecording: .denied), [])
    }

    func testAModuleCountsOnlyWhenItsDeclaredGateIsWithheld() {
        let lists: [[ModulePermission]] = [[.fullDisk], [.accessibility, .adminHelper],
                                           [.adminHelper], []]
        XCTAssertEqual(PermissionSummary.affected(by: [.fullDiskAccess], among: lists), 1)
        XCTAssertEqual(PermissionSummary.affected(by: [.accessibility], among: lists), 1)
        XCTAssertEqual(PermissionSummary.affected(by: [.screenRecording], among: lists), 0)
        XCTAssertEqual(PermissionSummary.affected(by: [], among: lists), 0)
    }
}
