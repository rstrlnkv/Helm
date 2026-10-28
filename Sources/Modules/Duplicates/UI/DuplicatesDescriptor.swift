import HelmContract
import HelmRuntime
import HelmUI
import Module_Duplicates_Engine
import SwiftUI

@MainActor public final class DuplicatesDescriptor: ModuleDescriptor {
    public static let id = ModuleID(DuplicatesEngine.moduleID)
    public static var metadata: ModuleMetadata { ModuleMetadata(
        id: id, name: DupStr.moduleName, summary: DupStr.summary,
        sfSymbol: "doc.on.doc", permissions: [.fullDisk]) }
    public static let category: ModuleCategory = .files
    public static let tint = ModuleTint(
        ordinary: (light: (0.000, 0.645, 0.688), dark: (0.000, 0.646, 0.690)),
        increasedContrast: (light: (0.000, 0.516, 0.550), dark: (0.000, 0.516, 0.551)))
    public static let glyph = ShellGlyph(
        body: ShellGlyph.box(8, 8, 12.5, 12.5, 3.5),
        extra: {
            var back = Path()
            back.move(to: ShellGlyph.pt(7.5, 16))
            back.addArc(tangent1End: ShellGlyph.pt(3.5, 16), tangent2End: ShellGlyph.pt(3.5, 3.5), radius: 3.5)
            back.addArc(tangent1End: ShellGlyph.pt(3.5, 3.5), tangent2End: ShellGlyph.pt(16, 3.5), radius: 3.5)
            back.addArc(tangent1End: ShellGlyph.pt(16, 3.5), tangent2End: ShellGlyph.pt(16, 16), radius: 3.5)
            back.addLine(to: ShellGlyph.pt(16, 7.5))
            return back
        }())
    /// The page draws across the pane; its header must not centre itself.
    public var pageBleeds: Bool { true }

    public init() {}

    private var store: NamespacedStore?

    /// The store reaches the engine because a background scan reads the folder
    /// the person chose, and there is no view model awake when the timer fires.
    public func makeEngine(store: NamespacedStore) -> any ModuleEngine {
        self.store = store
        return DuplicatesEngine(store: store)
    }
    public func menuBar(_ vm: ModuleViewModel) -> MenuBarContribution? { .utility }
    public func settingsPage(_ vm: ModuleViewModel) -> AnyView {
        AnyView(DuplicatesSettingsPage(vm: vm, store: settingsStore))
    }

    /// The module's own defaults, whether or not the engine has been built yet —
    /// the seam `VPNDescriptor` and `KeepAwakeDescriptor` already keep. The page
    /// building its own UserDefaults-backed store here meant the store the host
    /// handed `makeEngine` was read by the engine and by nobody else: the page
    /// and the engine could be opened on two different rule sets, and no harness
    /// could seed what the page reads.
    private var settingsStore: NamespacedStore {
        store ?? NamespacedStore(namespace: Self.id.rawValue, backing: UserDefaults.standard)
    }
}

/// The same, for the duplicate finder.
public typealias DuplicatesCommand = Module_Duplicates_Engine.DuplicatesCommand
