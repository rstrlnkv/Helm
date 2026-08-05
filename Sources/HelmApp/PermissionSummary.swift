import Foundation
import HelmRuntime
import HelmUI

/// What macOS is withholding, counted once.
///
/// The settings page and the panel both need this and had it written out in
/// one of them; the second copy would have been the first place the two could
/// disagree about how many permissions are missing.
@MainActor
enum PermissionSummary {

    /// The permissions an enabled module actually uses, in table order.
    static func needed() -> [PermissionNeed] {
        let declared = ModuleRegistry.all
            .filter { ModuleHost.shared.isEnabled($0) }
            .flatMap { $0.moduleMetadata.permissions }
        return PermissionNeed.allCases.filter { need in
            switch need {
            case .fullDiskAccess: return declared.contains(.fullDisk)
            case .accessibility: return declared.contains(.accessibility)
            }
        }
    }

    static func withheld(accessibility: PermissionState, fullDisk: PermissionState) -> [PermissionNeed] {
        needed().filter { $0.state(accessibility: accessibility, fullDisk: fullDisk) != .granted }
    }

    /// Enabled modules that declared one of the withheld permissions.
    ///
    /// Counted from `permissions` rather than `inertWithout`: the sidebar's
    /// triangle is about a module that can do nothing, and this is about every
    /// module the gap reaches — the Full Disk ones do work, and they find less.
    static func affected(by withheld: [PermissionNeed]) -> Int {
        ModuleRegistry.all.filter { descriptor in
            ModuleHost.shared.isEnabled(descriptor)
                && descriptor.moduleMetadata.permissions.contains { declared in
                    withheld.contains { need in
                        switch need {
                        case .fullDiskAccess: return declared == .fullDisk
                        case .accessibility: return declared == .accessibility
                        }
                    }
                }
        }.count
    }
}
