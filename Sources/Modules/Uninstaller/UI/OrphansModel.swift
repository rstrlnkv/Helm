import SwiftUI
import HelmRuntime
import HelmUI
import Module_Uninstaller_Engine

/// The Leftovers tab's state and its two doors to the engine, which are the view
/// model's `scanOrphans` and `trashPaths`. Eight of the view's nine `@State`s moved here, and
/// a `@State` inside a `View` struct has no seam: the guard below could be read
/// from the source and never driven. Its lifetime is the module's: the view model
/// owns it, so the scan and the ticks outlive a sidebar click (Q10a), and
/// `UninstallerViewModel.stop()` clears it. The view model outlives it, hence `unowned`.
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

    // Every group's leftovers, which is every leftover on screen: the sections
    // here do not collapse (a plain inset `List`, no disclosure state), so
    // "select all" reaches nothing the user cannot scroll to. The confirmation
    // names the exact count and total before anything moves, and the engine gate
    // runs on top — so this is the whole visible set, honestly counted.
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
        // Nothing is pre-selected. A ticked list of 251 items is a button that
        // deletes whatever the scan got wrong, and this scan was wrong: apps
        // one folder down in /Applications read as uninstalled.
        selected = []
        scanning = false; scanned = true
    }

    func trashSelected() async {
        // The page refuses a second run itself rather than trusting the footer to
        // have dimmed the button: `.disabled(busy)` is a redraw away, and the
        // press comes out of a `confirmationDialog` that holds its own copy of
        // this view. What a second press costs is not a second deletion — the
        // files are already in the Trash — but a wrong report about the first:
        // every path comes back refused, and whichever round answers last is
        // what this page draws.
        guard !busy else { return }
        busy = true
        // Down when the round is over, the rescan below included: a page that
        // says it is idle over a list it is still rebuilding is the flag
        // describing something other than the work.
        defer { busy = false }
        let result = await uvm.trashPaths(Array(selected))
        // The rescan first. Its own first statement is `banner = nil`, and it
        // runs synchronously up to its own await — so an outcome set before it
        // was wiped inside the same main-actor turn and SwiftUI never drew a
        // frame in between. This screen has been reporting nothing at all,
        // including refusals somebody could have acted on.
        await scan()
        // Nil only when the module was stopped under the page: nothing moved.
        guard let result else { return }
        failures = result.failures
        removedCount = result.trashed.count
        banner = UnStr.movedToTrash(Bytes(result.freedBytes))
    }

    func binding(for path: String) -> Binding<Bool> {
        Binding(get: { self.selected.contains(path) },
                set: { on in
                    if on { self.selected.insert(path) } else { self.selected.remove(path) }
                })
    }
}
