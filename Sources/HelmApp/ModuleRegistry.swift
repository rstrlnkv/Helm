import HelmContract
import HelmUI
import Module_KeepAwake_UI
import Module_VPN_UI
import Module_Uninstaller_UI
import Module_Homebrew_UI
import Module_Leftovers_UI
import Module_Disk_UI
import Module_Layout_UI

/// All compiled-in module descriptors. Add future modules here.
@MainActor enum ModuleRegistry {
    static let all: [any ModuleDescriptor] = [KeepAwakeDescriptor(), VPNDescriptor(), UninstallerDescriptor(), HomebrewDescriptor(), LeftoversDescriptor(), DiskDescriptor(), LayoutDescriptor()]
}

extension ModuleDescriptor {
    /// `id`/`metadata`/`category` are static requirements and aren't reachable
    /// directly on the `any ModuleDescriptor` existential; these instance
    /// forwarders go through the concrete type via `type(of:)` in one place.
    var idRaw: String { type(of: self).id.rawValue }
    var moduleMetadata: HelmContract.ModuleMetadata { type(of: self).metadata }
    var moduleCategory: HelmUI.ModuleCategory { type(of: self).category }
}
