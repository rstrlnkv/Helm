import SwiftUI
import HelmRuntime
import HelmUI
import Module_Uninstaller_Engine

/// The Leftovers tab's state and its two doors to the engine, the view model's
/// `scanOrphans` and `trashPaths`. Out of the view, so its guards can be driven
/// by a test. The view model owns it, so the scan and the ticks outlive a
/// sidebar click, and `UninstallerViewModel.stop()` clears it; the view model
/// outlives it, hence `unowned`.
@MainActor final class OrphansModel: ObservableObject {
    private unowned let uvm: UninstallerViewModel

    @Published private(set) var groups: [OrphanGroup] = []
    @Published private(set) var scanned = false
    @Published private(set) var scanning = false
    @Published var selected: Set<String> = []
    @Published private(set) var failures: [TrashFailureInfo] = []
    @Published private(set) var removedCount = 0
    @Published private(set) var busy = false
    @Published private(set) var banner: String?

    /// Bumped by `clear()`: a scan that was in flight when the module stopped
    /// answers into a model that has been emptied, and must not refill it.
    private var generation = 0

    init(uvm: UninstallerViewModel) { self.uvm = uvm }

    var selectedBytes: Int {
        groups.flatMap(\.leftovers).filter { selected.contains($0.path) }.reduce(0) { $0 + $1.sizeBytes }
    }

    // Every leftover on screen: the sections do not collapse, so "select all"
    // reaches nothing the person cannot scroll to, and the confirmation names
    // the count and total before anything moves.
    private var allPaths: [String] { groups.flatMap(\.leftovers).map(\.path) }
    var allSelected: Bool { selected.count == allPaths.count && !allPaths.isEmpty }

    /// One toggle covers both: "select all" flips to "deselect all" when
    /// everything is already checked.
    func toggleAll() { selected = allSelected ? [] : Set(allPaths) }

    /// Back to the state of a tab nobody has opened: the module was switched off.
    func clear() {
        generation += 1
        groups = []; scanned = false; scanning = false; selected = []
        failures = []; removedCount = 0; banner = nil
    }

    func scan() async {
        scanning = true; banner = nil
        // Nil only when the module has been stopped: nothing to show then.
        let mine = generation
        let found = await uvm.scanOrphans() ?? []
        guard mine == generation else { return }
        groups = found
        // Nothing is pre-selected: a ticked list is a button that deletes
        // whatever the scan got wrong.
        selected = []
        scanning = false; scanned = true
    }

    func trashSelected() async {
        // Refused here, not trusted to the dimmed button: `.disabled(busy)` is
        // a redraw away, and the `confirmationDialog` holds its own copy of the
        // view. A second round would find every path gone and its report would
        // replace the first's.
        guard !busy else { return }
        busy = true
        // Down when the round is over, the rescan below included.
        defer { busy = false }
        let result = await uvm.trashPaths(Array(selected))
        // The rescan first: it begins with `banner = nil` and runs synchronously
        // to its first await, so an outcome set before it would be wiped
        // before any frame is drawn.
        await scan()
        // Nil only when the module was stopped under the page: nothing moved.
        guard let result else { return }
        failures = result.failures
        removedCount = result.trashed.count
        banner = HelmBasket.movedToTrash(Bytes(result.freedBytes))
    }

    func binding(for path: String) -> Binding<Bool> {
        Binding(get: { self.selected.contains(path) },
                set: { on in
                    if on { self.selected.insert(path) } else { self.selected.remove(path) }
                })
    }
}
