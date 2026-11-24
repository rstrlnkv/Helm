import Foundation
import HelmContract
import HelmRuntime

/// What macOS is withholding, counted once.
///
/// The settings page and the panel both need this, and one copy cannot
/// disagree with itself about how many permissions are missing.
@MainActor
enum PermissionSummary {

    /// The permissions an enabled module actually uses, in table order.
    static func needed() -> [PermissionNeed] {
        let declared = ModuleRegistry.all
            .filter { ModuleHost.shared.isEnabled($0) }
            .flatMap { $0.currentPermissions() }
        let wanted = Set(declared.compactMap(PermissionNeed.init))
        return PermissionNeed.allCases.filter(wanted.contains)
    }

    static func withheld(accessibility: PermissionState, fullDisk: PermissionState,
                         screenRecording: PermissionState) -> [PermissionNeed] {
        needed().filter {
            $0.state(accessibility: accessibility, fullDisk: fullDisk,
                     screenRecording: screenRecording) != .granted
        }
    }

    /// Enabled modules that declared one of the withheld permissions.
    ///
    /// Counted from `permissions` rather than `inertWithout`: the sidebar's
    /// triangle is about a module that can do nothing, and this is about every
    /// module the gap reaches — the Full Disk ones do work, and they find less.
    static func affected(by withheld: [PermissionNeed]) -> Int {
        affected(by: withheld, among: ModuleRegistry.all
            .filter { ModuleHost.shared.isEnabled($0) }
            .map { $0.moduleMetadata.permissions })
    }

    /// How many of the given modules' declared lists reach a withheld gate.
    static func affected(by withheld: [PermissionNeed],
                         among declared: [[ModulePermission]]) -> Int {
        declared.filter { list in
            list.contains { PermissionNeed($0).map(withheld.contains) ?? false }
        }.count
    }
}
