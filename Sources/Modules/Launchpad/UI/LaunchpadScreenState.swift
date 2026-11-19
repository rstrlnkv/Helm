import SwiftUI
import HelmUI
import Module_Launchpad_Engine

/// One tile of the window: an app, or a folder with the apps it holds as the snapshot resolved them.
enum LaunchpadEntry: Equatable, Identifiable {
    case app(CatalogApp)
    case folder(id: UUID, name: String, apps: [CatalogApp])

    var id: String {
        switch self {
        case .app(let app): app.id
        case .folder(let id, _, _): id.uuidString
        }
    }
}

/// Where the fingers hold the page, in points from its place. Its own object so that the 120 Hz of a swipe republishes this
/// and nothing else: the state's views do not re-run for it, only what reads `offset` (`PageDragOffset`).
@MainActor final class LaunchpadPageDrag: ObservableObject {
    @Published var offset: CGFloat = 0
}

/// What the window knows, made once when it opens and dropped when it closes: the geometry, the icons, the search, the
/// page, the arrow keys' choice and the open folder. The model's snapshot comes in by `update(snapshot:)`, the only way in.
///
/// Everything the views draw from is **derived here and assigned only when it differs**, never in a `body`: a snapshot that
/// changed nothing the window shows redraws nothing. Pages are slices of one list (`LaunchpadPaging`), all held here; the views make
/// only the live ones (the shown page and its two neighbours).
@MainActor final class LaunchpadScreenState: ObservableObject {
    enum Mode: Equatable { case busy, noApps, noMatch, grid }

    let geometry: LaunchpadGeometry
    let icons: LaunchpadIcons
    /// The page's drag, apart from the state so a swipe republishes nothing else.
    let drag = LaunchpadPageDrag()
    @Published var search = "" {
        didSet {
            guard search != oldValue else { return }
            // The page goes to the first at once, outside the animation below (`reflow`'s own reset is for its callers that
            // pass `selectFirst` and would slide it); the tiles slide to their new places. A held drag is let go with it.
            assign(\.page, 0)
            drag.offset = 0
            withAnimation(HelmMotion.interface) {
                closeFolderQuietly()
                reflow(selectFirst: true)
            }
        }
    }
    @Published private(set) var mode = Mode.busy
    @Published private(set) var pages: [[LaunchpadEntry]] = [[]]
    @Published private(set) var page = 0
    /// The arrow keys' choice, as an index into what is shown; `selectedID` is what it stands for, so a snapshot that moves
    /// or removes tiles moves the index with the tile, or clears it, and never lets it point at another app.
    @Published private(set) var selection: Int? {
        didSet { rememberSelected() }
    }
    private var selectedID: String?
    private func rememberSelected() { selectedID = selection.flatMap { shownIDs.indices.contains($0) ? shownIDs[$0] : nil } }
    @Published private(set) var openFolder: UUID?
    @Published private(set) var folderName = ""
    @Published private(set) var folderApps: [CatalogApp] = []
    /// Whether the window's content is settled in: false until it appears, false again as it closes.
    @Published private(set) var shown = false
    /// The app whose launch is under way, whose icon swells until the window goes or the launch fails.
    @Published private(set) var launching: AppID?

    var onLaunch: ((AppID, String) -> Void)?
    var onHide: ((AppID) -> Void)?
    var onClose: (() -> Void)?
    /// Said once, when the first snapshot has come in.
    var onLoaded: ((LaunchpadSnapshot, LaunchpadScreenState) -> Void)?
    private var loadedOnce = false

    private var snapshot: LaunchpadSnapshot?
    /// The top level as the snapshot gave it (a search's hits, or the layout's tiles).
    private var top: [LaunchpadEntry] = []
    /// Where the open folder's tile is in `top`, for Esc to come back to.
    private var folderTile: Int?

    init(geometry: LaunchpadGeometry) {
        self.geometry = geometry
        icons = LaunchpadIcons(capacity: geometry.capacity, size: geometry.icon)
    }

    var pageCount: Int { pages.count }

    func setShown(_ value: Bool) { assign(\.shown, value) }
    func launched(_ id: AppID) { assign(\.launching, id) }
    func launchFailed() { assign(\.launching, nil) }

    /// Where the open folder's tile is in the window's coordinates, for its card to grow from and fold back to; the
    /// window's middle when there is no folder.
    var folderOrigin: CGPoint {
        guard let folderTile else { return CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2) }
        return geometry.center(ofSlot: folderTile % geometry.capacity)
    }

    /// The columns the arrow keys move over: the page's, or the open folder's.
    var columns: Int { openFolder == nil ? geometry.columns : folderColumns }
    var folderColumns: Int { max(1, min(folderApps.count, geometry.columns - 1)) }

    private var count: Int { openFolder == nil ? top.count : folderApps.count }
    private var shownIDs: [String] { openFolder == nil ? top.map(\.id) : folderApps.map(\.id) }

    // MARK: - The snapshot

    func update(snapshot: LaunchpadSnapshot?) {
        self.snapshot = snapshot
        reflow(selectFirst: false)
        if let snapshot, !loadedOnce {
            loadedOnce = true
            onLoaded?(snapshot, self)
        }
    }

    func reflow(selectFirst: Bool) {
        guard let snapshot else {
            top = []
            assign(\.mode, .busy)
            assign(\.pages, [[]])
            return
        }
        let hits = snapshot.search(search)
        if let hits {
            top = hits.compactMap { snapshot.apps[$0] }.map(LaunchpadEntry.app)
        } else {
            top = snapshot.layout.items.compactMap { item in
                switch item {
                case .app(let id): return snapshot.apps[id].map(LaunchpadEntry.app)
                case .folder(let folder):
                    let apps = folder.apps.compactMap { snapshot.apps[$0] }
                    return apps.isEmpty ? nil : .folder(id: folder.id, name: folder.name, apps: apps)
                }
            }
        }
        if let open = openFolder {
            if let at = top.firstIndex(where: { $0.id == open.uuidString }), case .folder(_, let name, let apps) = top[at] {
                folderTile = at
                assign(\.folderName, name)
                assign(\.folderApps, apps)
            } else {
                closeFolderQuietly()
                assign(\.selection, nil)
            }
        }
        assign(\.mode, snapshot.apps.isEmpty || (hits == nil && top.isEmpty) ? .noApps : hits != nil && top.isEmpty ? .noMatch : .grid)
        let chunks = (0..<LaunchpadPaging.pageCount(items: top.count, capacity: geometry.capacity)).map {
            LaunchpadPaging.slice(top, page: $0, capacity: geometry.capacity)
        }
        assign(\.pages, chunks)
        if selectFirst {
            assign(\.selection, hits != nil && !top.isEmpty ? 0 : nil)
            assign(\.page, 0)
        } else {
            if let selectedID { assign(\.selection, shownIDs.firstIndex(of: selectedID)) }
            assign(\.page, LaunchpadPaging.clamped(page, count: pages.count))
        }
        // An equal index over other tiles (a new search) is no assignment: the name it stands for is read again here.
        rememberSelected()
    }

    // MARK: - Input

    func move(dx: Int, dy: Int) {
        guard let next = LaunchpadPaging.moved(selection, dx: dx, dy: dy, columns: columns, count: count) else { return }
        assign(\.selection, next)
        if openFolder == nil { assign(\.page, LaunchpadPaging.page(of: next, capacity: geometry.capacity)) }
    }

    /// Where the fingers hold the page, `raw` points from its place; a rubber band past the first and last page, and nothing
    /// while a folder is open. Not animated: the page follows.
    func drag(raw: CGFloat) {
        guard openFolder == nil else { return }
        let next = LaunchpadSwipe.offset(raw: raw, canBack: page > 0, canForward: page < pageCount - 1, width: geometry.pageWidth)
        if drag.offset != next { drag.offset = next }
    }

    /// The fingers let go: the page turns by `step` (or stays) and the drag goes to nothing, in one transaction, on a spring
    /// that takes up `velocity` (pt/s, along the page's travel) over the distance left.
    func settle(step: Int, velocity: CGFloat) {
        let at = drag.offset
        let next = openFolder == nil ? LaunchpadPaging.clamped(page + step, count: pages.count) : page
        let target = -CGFloat(next - page) * geometry.pageWidth
        let along = velocity * (target >= at ? 1 : -1)
        withAnimation(HelmMotion.pageSettle(velocity: along, distance: abs(target - at))) {
            go(to: next)
            drag.offset = 0
        }
    }

    /// One page back or forward; the choice stays only if it is still on the shown page.
    func turn(_ step: Int) { go(to: page + step) }

    func go(to target: Int) {
        guard openFolder == nil else { return }
        let next = LaunchpadPaging.clamped(target, count: pages.count)
        assign(\.page, next)
        if let selection, LaunchpadPaging.page(of: selection, capacity: geometry.capacity) != next { assign(\.selection, nil) }
    }

    /// Return on the arrow keys' choice: an app opens, a folder opens its card.
    func activate() {
        guard let selection else { return }
        if openFolder != nil {
            guard selection < folderApps.count else { return }
            onLaunch?(folderApps[selection].id, folderApps[selection].name)
            return
        }
        guard selection < top.count else { return }
        switch top[selection] {
        case .app(let app): onLaunch?(app.id, app.name)
        case .folder(let id, _, _): open(folder: id)
        }
    }

    func open(folder id: UUID) {
        guard let at = top.firstIndex(where: { $0.id == id.uuidString }), case .folder(_, let name, let apps) = top[at] else { return }
        folderTile = at
        assign(\.folderName, name)
        assign(\.folderApps, apps)
        assign(\.openFolder, id)
        assign(\.selection, nil)
        // No release comes for a drag under a card (the window stops feeding the swipe), so the page is let go here.
        drag.offset = 0
    }

    /// Esc: the folder first, then the search, then the window.
    func escape() {
        if openFolder != nil { closeFolder() }
        else if !search.trimmingCharacters(in: .whitespaces).isEmpty { search = "" }
        else { onClose?() }
    }

    /// A click on the window's own background: the folder card if one is open, else the window.
    func backgroundClicked() {
        if openFolder != nil { closeFolder() } else { onClose?() }
    }

    func closeFolder() {
        let back = folderTile
        closeFolderQuietly()
        assign(\.selection, back.flatMap { $0 < top.count ? $0 : nil })
    }

    private func closeFolderQuietly() {
        assign(\.openFolder, nil)
        assign(\.folderApps, [])
        assign(\.folderName, "")
        folderTile = nil
    }

    private func assign<T: Equatable>(_ path: ReferenceWritableKeyPath<LaunchpadScreenState, T>, _ value: T) {
        if self[keyPath: path] != value { self[keyPath: path] = value }
    }
}
