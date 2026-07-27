import HelmUI
import HelmRuntime

/// The user's module order, applied inside a category.
///
/// The stored order is one flat list; both the sidebar and the status menu show
/// groups, and a second copy of this would be a second answer to "which
/// modules are Files, and in what order".
@MainActor
enum ModuleGrouping {
    static func ordered(in category: ModuleCategory) -> [any ModuleDescriptor] {
        let inCategory = ModuleRegistry.all.filter { $0.moduleCategory == category }
        let ordered = ModuleOrder.apply(saved: AppSettings.moduleOrder,
                                        to: inCategory.map(\.idRaw))
        return ordered.compactMap { id in inCategory.first { $0.idRaw == id } }
    }
}
