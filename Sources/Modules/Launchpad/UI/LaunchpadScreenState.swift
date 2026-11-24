import Combine
import SwiftUI
import HelmRuntime
import HelmUI
import Module_Launchpad_Engine

/// What the window knows, made when it opens (its geometry again when the grid changes) and dropped when it closes: the geometry, the icons, the search, the
/// page, the arrow keys' choice and the open folder. The model's snapshot comes in by `update(snapshot:)`, the only way in.
///
/// Everything the views draw from is **derived here and assigned only when it differs**, never in a `body`: a snapshot that
/// changed nothing the window shows redraws nothing. Pages are slices of one list (`LaunchpadPaging`), all held here; the views make
/// only the live ones (the shown page and its two neighbours).
@MainActor final class LaunchpadScreenState: ObservableObject {
    enum Mode: Equatable { case busy, noApps, noMatch, grid }

    /// What everything reads: the grid's own geometry, or in the category view the grid made again with names on and an even number of columns (`pairedColumns`).
    @Published var geometry: LaunchpadGeometry
    /// The grid the settings and the screen make, whatever view is shown: `regrid` compares with it and the icon cache is sized by it.
    var gridGeometry: LaunchpadGeometry
    /// The view the person chose; the category view is drawn only while `categoriesShown`, which a search turns off.
    @Published private(set) var view: LaunchpadViewMode
    /// The tiles are category blocks (folder-shaped entries): lift, rename and resize are off, and the geometry is paired.
    @Published var categoriesShown = false
    /// The apps moved to another category, as the snapshot has them. Published because the snapshot is not: the menus' check marks read it.
    @Published var moved: [AppID: LaunchpadCategoryTarget] = [:]
    let icons: LaunchpadIcons
    /// The page's drag, apart from the state so a swipe republishes nothing else.
    let drag = LaunchpadPageDrag()
    /// The open card's page, and its drag: the same, for the card's own pages.
    let cardDrag = LaunchpadPageDrag()
    @Published var search = "" {
        didSet {
            guard search != oldValue else { return }
            // The page goes to the first at once, outside the animation below (`reflow`'s own reset is for its callers that
            // pass `selectFirst` and would slide it); the tiles slide to their new places. A held drag is let go with it.
            assign(\.page, 0)
            drag.offset = 0
            if machine.isEngaged { cancelLift() }
            endEditing()
            withAnimation(HelmMotion.interface) {
                closeFolderQuietly()
                reflow(selectFirst: true)
            }
        }
    }
    @Published var mode = Mode.busy
    @Published var pages: [[LaunchpadEntry]] = [[]]
    @Published var page = 0
    /// The open folder's card page (0 with no card open); the choice and the lift's gap are indices into the folder's whole list.
    @Published var cardPage = 0
    /// The arrow keys' choice, as an index into what is shown; `selectedID` is what it stands for, so a snapshot that moves
    /// or removes tiles moves the index with the tile, or clears it, and never lets it point at another app.
    @Published var selection: Int? {
        didSet { rememberSelected() }
    }
    var selectedID: String?
    func rememberSelected() { selectedID = selection.flatMap { shownIDs.indices.contains($0) ? shownIDs[$0] : nil } }
    @Published private(set) var openFolder: UUID?
    @Published var folderName = ""
    @Published var folderApps: [CatalogApp] = []
    /// What the open card draws: the folder's apps, and while a tile is carried over it the gap where a release would put it.
    @Published var cardEntries: [LaunchpadEntry] = []
    /// The name field's text, which is the folder's name until a person types in it.
    @Published var nameDraft = ""
    /// The name field holds the keyboard: the panel then gives `handleNameKey` Return (36, 76) and Esc (53) and leaves every
    /// other key to the field (`LaunchpadPanel`).
    @Published var renaming = false
    /// The field takes the keyboard with its text selected (a folder just made).
    var selectNameOnFocus = false
    /// The lift gate's flag (a tile may be lifted only while it is true): set when the window is presented or a pinch's scrub commits, false again as it closes. A spread's scrub that reverts leaves it true, as it never cleared it.
    @Published private(set) var shown = false
    /// Counts the asks for the search field to take the keyboard: the window asks when it becomes key after the screen appeared.
    @Published private(set) var searchFocusRequest = 0
    /// The window's reveal, apart from the state so a scrub republishes nothing else.
    let reveal = LaunchpadReveal()
    /// The app whose launch is under way, whose icon swells until the window goes or the launch fails.
    @Published private(set) var launching: AppID?
    /// The block whose icon that launch came from: an app in two blocks (Recently Added and its category) swells in this one only.
    @Published private(set) var launchingBlock: String?
    /// The tile carried by the pointer, and what a release would drop it onto; nil when nothing is carried.
    @Published var lift: LaunchpadLiftView?
    /// The tile the press is on, until it is let go or lifted: its wash, since the panel takes the press before the button.
    @Published var pressedID: String? {
        didSet { if pressedID == nil { pressedIcon = nil } }
    }
    /// The app of the mini icon the press is on, when the press is on a large folder's icon: that icon takes the wash, and the
    /// release launches it. nil with a press elsewhere on the tile (the whole tile washes and its release opens the folder).
    @Published var pressedIcon: AppID?
    let liftPoint = LaunchpadLiftPoint()
    /// The edit mode (`beginEditing`, `endEditing`): the tiles wiggle and wear badges, a click on an app launches nothing.
    @Published var editing = false
    /// The apps the Uninstaller itself offers to remove, asked once when the mode begins and again when the snapshot's apps or their paths change; empty until the answer comes.
    @Published var removable: Set<AppID> = []
    /// What `onVerdicts` was last asked about (id to path), so an unchanged snapshot asks nothing again.
    var removableFor: [AppID: String]?
    var verdictTask: Task<Void, Never>?
    /// Asks the removal door which of these apps it would remove (the model resolves the door at each use; no answer is an empty one).
    var onVerdicts: (([AppRemovalCandidate]) async -> [AppRemovalVerdict])?
    /// What the card of a removal counts (nil: the door refused, and the model has said so), and the removal itself, handed on with the
    /// card's `running` as the consent to quit; the model owns it from there, so a window that closes cancels nothing already out.
    var onPreview: ((AppRemovalCandidate) async -> AppRemovalPreview?)?
    var onRemove: ((AppRemovalCandidate, _ quittingIfRunning: Bool) -> Void)?
    /// The removal the person was asked about and has not answered: counting what it takes, then the card's question. Only the answer to the
    /// card removes anything.
    @Published var removalAsk: RemovalAsk?
    var previewTask: Task<Void, Never>?
    /// The app the card was counted for, as the snapshot held it then: the button removes only if the snapshot still holds exactly this.
    var askedFor: AppRemovalCandidate?
    /// When the card turned to its question: the button does nothing for `removalDwell` after, so a click aimed at the cross lands on nothing.
    var askedAt: TimeInterval = 0
    static let removalDwell: TimeInterval = 0.4

    enum RemovalAsk: Equatable {
        case counting(AppID, name: String)
        case asking(AppID, name: String, AppRemovalPreview)
    }

    var onLaunch: ((AppID, String) -> Void)?
    var onHide: ((AppID) -> Void)?
    var onClose: (() -> Void)?
    /// Brings an app out of the Hidden card (it shows in the grid again).
    var onUnhide: ((AppID) -> Void)?
    /// An app's file, by its path: shown in Finder, or put on the pasteboard as the plain path.
    var onRevealApp: ((String) -> Void)?
    /// The path to copy and whether the copy is of a hidden app, which the pasteboard writer marks as not to be kept.
    var onCopyPath: ((String, _ concealed: Bool) -> Void)?
    /// A menu is to be popped at a point of the window, from the top left (VoiceOver's "show menu"); the panel pops it (`LaunchpadPanel.pop(_:at:)`).
    var onPopMenu: ((LaunchpadMenu, CGPoint) -> Void)?
    /// The person used the window's switch; the model keeps the choice.
    var onViewChange: ((LaunchpadViewMode) -> Void)?
    /// What "recently added" is measured from, replaced in a test.
    var wallClock: () -> Date = Date.init
    /// Writes a drop's edit and answers the snapshot that is shown after it.
    var onPlace: ((LaunchpadEdit) async -> LaunchpadSnapshot?)?
    /// Writes a folder's new name.
    var onRename: ((UUID, String) -> Void)?
    /// Writes a folder's size (true: large).
    var onResize: ((UUID, Bool) -> Void)?
    /// Writes an app's category (nil: its own).
    var onMove: ((AppID, LaunchpadCategoryTarget?) -> Void)?
    /// A resize or a move that changes what is shown is on its way: the next update moves the tiles with the reorder curve, and
    /// spends the flag, answer or not. A resize to the size the folder has, or a move to the category the app is in (or of an app
    /// that is not moved back to its own), is never armed: the engine refuses it and no update comes to spend the flag.
    var animateNextUpdate = false
    /// Said once, when the first snapshot has come in.
    var onLoaded: ((LaunchpadSnapshot, LaunchpadScreenState) -> Void)?
    var loadedOnce = false
    /// Whether the first snapshot waits for page 0's icons (the window's state does, a test's does not).
    let gated: Bool
    var firstSnapshot: LaunchpadSnapshot?
    var firstLoad: Task<Void, Never>?
    /// The first icons are drawn: how long after the snapshot came in, how many landed, the pixels of a tile's side, and whether the deadline ended the wait.
    var onIconsWarmed: ((_ took: Duration, _ drawn: Int, _ pixels: Int, _ timedOut: Bool) -> Void)?

    var snapshot: LaunchpadSnapshot?
    /// The top level as the snapshot gave it (a search's hits, or the layout's tiles), cut at the layout's page breaks.
    var segments: [[LaunchpadEntry]] = [[]]
    /// The same, flat: what the arrow keys and the folder's tile count over.
    var top: [LaunchpadEntry] = []
    /// What is shown instead of `segments` while a tile is carried (the gap in its place) and until its drop is answered.
    var preview: [[LaunchpadEntry]]?
    /// The cells each page's tiles cover, published with `pages` in one block: the page draws from them and the pointer's hit test reads them.
    @Published var slots: [[LaunchpadPlacement.Slot]] = [[]]
    var pageStarts = [0]
    /// The drawn order as a reorder by key reads it: rebuilt with the pages.
    var keyOrder = LaunchpadKeyMove.empty
    var gapAddress: Int?
    var machine = LaunchpadLift()
    var lastPoint = CGPoint.zero
    /// Where the press that may become a click began: which icon of a large folder it was on.
    var pressPoint = CGPoint.zero
    var timer: Task<Void, Never>?
    var scheduled: TimeInterval?
    var placing: Task<Void, Never>?
    /// What a person's pointer needs read from outside, replaced in a test.
    var buttonDown: () -> Bool = { NSEvent.pressedMouseButtons & 1 != 0 }
    var clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    /// Where the carried tile was lifted from: the grid, or the card of the folder with this id.
    var liftSource = LaunchpadDropSource.top
    /// The open card's entries while a tile is carried over it (the gap in them), instead of the folder's apps.
    var cardPreview: [LaunchpadEntry]?
    /// The folder tiles' addresses, which a dwell on one of them opens.
    var folderAddresses: Set<Int> = []
    /// Where the open folder's tile is in `top`, for Esc to come back to.
    var folderTile: Int?

    /// The lock in front of the Hidden block's card. A state made without one asks the system's port, which a test process refuses.
    let hidden: LaunchpadHiddenGate
    /// The gate's changes are this state's: the screen observes the state only, and the unavailable banner reads the gate.
    private var hiddenChanges: AnyCancellable?

    /// `icons`: the window's, drawing the system's icons off main, which also gates the first snapshot on page 0's icons (`update(snapshot:)`);
    /// none (a test) draws nothing, gates nothing and lands the snapshot at once.
    init(geometry: LaunchpadGeometry, view: LaunchpadViewMode = .apps, hidden: LaunchpadHiddenGate = LaunchpadHiddenGate(port: SystemLaunchpadAuth()),
         icons: LaunchpadIcons? = nil) {
        self.hidden = hidden
        self.geometry = geometry
        gridGeometry = geometry
        self.view = view
        gated = icons != nil
        self.icons = icons ?? LaunchpadIcons(capacity: geometry.capacity, side: geometry.icon, scale: 2) { _, _ in nil }
        hiddenChanges = hidden.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        // Weak, and the cache is the state's own: the queue and the pending asks must keep nothing of the window alive (pass 19's leak).
        self.icons.onArrival = { [weak self] in self?.objectWillChange.send() }
    }

    var pageCount: Int { pages.count }

    /// The width of what a swipe turns: the open card's page, else the grid's.
    var swipeWidth: CGFloat { card?.pageWidth ?? geometry.pageWidth }

    func setShown(_ value: Bool) { assign(\.shown, value) }
    func requestSearchFocus() { searchFocusRequest &+= 1 }
    func launched(_ id: AppID) { assign(\.launching, id) }
    /// Which of a category block's large icons swells: the launched app's, and only in the block the launch came from, since one app
    /// sits in several blocks.
    func popped(block: String, among large: ArraySlice<CatalogApp>) -> Int? {
        launchingBlock == block ? large.firstIndex { $0.id == launching } : nil
    }
    func launchFailed() { assign(\.launching, nil); assign(\.launchingBlock, nil) }

    /// Where the open folder's tile is in the window's coordinates, for its card to grow from and fold back to; the
    /// window's middle when there is no folder.
    var folderOrigin: CGPoint {
        guard let folderTile else { return CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2) }
        let at = LaunchpadPaging.page(of: folderTile, starts: pageStarts)
        let item = folderTile - pageStarts[at]
        guard slots.indices.contains(at), slots[at].indices.contains(item) else { return CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2) }
        return geometry.center(of: slots[at][item])
    }

    /// The columns the arrow keys move over: the page's, or the open folder's.
    var columns: Int { openFolder == nil ? geometry.columns : folderColumns }
    var folderColumns: Int { LaunchpadSurface.Card(geometry: geometry, count: folderApps.count).columns }

    private var count: Int { openFolder == nil ? top.count : folderApps.count }
    var shownIDs: [String] { openFolder == nil ? top.map(\.id) : folderApps.map(\.id) }

    /// The app as the snapshot holds it now, and whether it is hidden, when its file may be handed out now: **a hidden app only in the open,
    /// unlocked Hidden card** (its path is a private fact like its name, and the grid, a category, a folder and a search never draw it).
    /// No snapshot, or an app it does not hold, is nothing to hand out. Asked when the menu is built and again at each press.
    func filed(_ id: AppID) -> (app: CatalogApp, hidden: Bool)? {
        guard let snapshot, let app = snapshot.apps[id] else { return nil }
        let isHidden = snapshot.layout.hidden.contains(id)
        if isHidden && !(openFolder == LaunchpadHiddenBlock.id && hidden.phase == .unlocked) { return nil }
        return (app, isHidden)
    }

    /// Show in Finder and Copy Path for `app`'s tile. A press hands over what is true then, not what was when the menu was built: the
    /// app as the snapshot holds it (its path may have moved), and nothing if it is gone or has become hidden outside the unlocked card.
    func fileActions(for app: CatalogApp) -> LaunchpadFileActions? {
        guard filed(app.id) != nil else { return nil }
        let id = app.id
        return LaunchpadFileActions(
            reveal: { [weak self] in self?.perform(.reveal(id)) },
            copyPath: { [weak self] in self?.perform(.copyPath(id)) })
    }

    /// Whether the person asked for app names (the grid's setting, not the category view's geometry, which keeps its lines for its blocks).
    var namesAsked: Bool { gridGeometry.names }

    // MARK: - Input

    func move(dx: Int, dy: Int) {
        if let card {
            // The first press chooses the shown page's first app; then the flat order, and the page follows the choice.
            let next = selection == nil && count > 0
                ? card.range(ofPage: cardPage).lowerBound
                : LaunchpadPaging.moved(selection, dx: dx, dy: dy, columns: card.columns, count: count)
            guard let next else { return }
            assign(\.selection, next)
            goCard(to: card.page(ofIndex: next))
            return
        }
        guard let next = selection.map({ arrowTarget(from: $0, dx: dx, dy: dy) }) ?? LaunchpadPaging.moved(nil, dx: dx, dy: dy, columns: columns, count: count) else { return }
        assign(\.selection, next)
        assign(\.page, LaunchpadPaging.page(of: next, starts: pageStarts))
    }

    /// Where an arrow key takes the choice at `from` on the grid; nil when it stays. A page with a large folder has no columns an
    /// index can step by: Up and Down follow the cells, and stay when there is nothing above or below. A reorder by key goes where this goes.
    func arrowTarget(from selection: Int, dx: Int, dy: Int) -> Int? {
        if dx == 0, dy != 0, pageStarts.indices.contains(page), slots.indices.contains(page), slots[page].contains(where: { $0.span > 1 }),
           LaunchpadPaging.page(of: selection, starts: pageStarts) == page {
            return LaunchpadPlacement.vertical(from: selection - pageStarts[page], dy: dy, in: slots[page]).map { pageStarts[page] + $0 }
        }
        return LaunchpadPaging.moved(selection, dx: dx, dy: dy, columns: columns, count: count)
    }

    /// What a swipe turns: the open card's pages, else the grid's.
    private var track: (drag: LaunchpadPageDrag, page: Int, count: Int, width: CGFloat) {
        if let card { return (cardDrag, cardPage, card.pageCount, card.pageWidth) }
        return (drag, page, pages.count, geometry.pageWidth)
    }

    /// Where the fingers hold the page, `raw` points from its place; a rubber band past the first and last page. Not animated: the page follows.
    func drag(raw: CGFloat) {
        let t = track
        let next = LaunchpadSwipe.offset(raw: raw, canBack: t.page > 0, canForward: t.page < t.count - 1, width: t.width)
        if t.drag.offset != next { t.drag.offset = next }
    }

    /// The fingers let go: the page turns by `step` (or stays) and the drag goes to nothing, in one transaction, on a spring
    /// that takes up `velocity` (pt/s, along the page's travel) over the distance left.
    func settle(step: Int, velocity: CGFloat) {
        let t = track
        let at = t.drag.offset
        let next = LaunchpadPaging.clamped(t.page + step, count: t.count)
        let target = -CGFloat(next - t.page) * t.width
        let along = velocity * (target >= at ? 1 : -1)
        withAnimation(HelmMotion.pageSettle(velocity: along, distance: abs(target - at))) {
            go(to: next)
            t.drag.offset = 0
        }
    }

    /// One page back or forward (the open card's, with one open); the choice stays only if it is still on the shown page.
    func turn(_ step: Int) { go(to: (openFolder == nil ? page : cardPage) + step) }

    func go(to target: Int) {
        guard openFolder == nil else { goCard(to: target); return }
        let next = LaunchpadPaging.clamped(target, count: pages.count)
        assign(\.page, next)
        if let selection, LaunchpadPaging.page(of: selection, starts: pageStarts) != next { assign(\.selection, nil) }
    }

    func goCard(to target: Int) {
        guard let card else { return }
        let next = LaunchpadPaging.clamped(target, count: card.pageCount)
        assign(\.cardPage, next)
        if let selection, card.page(ofIndex: selection) != next { assign(\.selection, nil) }
    }

    /// The window moved to a screen of another scale: what was drawn for the old one is drawn again at its own pixels. The system also
    /// says it when the scale is the same (a colour space, the first ordering on screen), and then nothing is dropped: what is under way lands.
    func rescale(_ scale: CGFloat) {
        guard scale != icons.scale else { return }
        icons.reconfigure(capacity: gridGeometry.capacity, side: gridGeometry.icon, scale: scale)
    }

    /// A new grid (the person's settings changed while the window is open): the same order cut again by the new capacity. Writes
    /// nothing, the layout stores order and not pages. A cell's address is `page * capacity + slot`, which means nothing
    /// after the capacity changed, so a lift or a press ends first (a drop already out lands through `update`). The page
    /// stays on the choice, or on the tile the shown page began with. An open folder's card stays open and follows the grid, its page
    /// on its choice or on the tile its shown page began with.
    func regrid(_ settings: LaunchpadGridSettings) {
        let next = LaunchpadGeometry.make(for: gridGeometry.size, topSafe: gridGeometry.topSafe, settings: settings)
        guard next != gridGeometry else { return }
        let anchor = pageStarts.indices.contains(page) ? pageStarts[page] : 0
        let cardAnchor = (card?.page ?? 0) * (card?.capacity ?? 1)
        cancelLift()
        drag.offset = 0
        cardDrag.offset = 0
        withAnimation(HelmMotion.interface) {
            gridGeometry = next
            geometry = categoriesShown ? next.pairedColumns : next
            icons.reconfigure(capacity: next.capacity, side: next.icon, scale: icons.scale)
            publishPages()
            publishCard()
            if let card { goCard(to: card.page(ofIndex: selection ?? cardAnchor)) }
        }
        // With a card open the selection counts the card's apps, not the grid's.
        assign(\.page, LaunchpadPaging.page(of: openFolder == nil ? selection ?? anchor : anchor, starts: pageStarts))
    }

    /// The window's switch: the other view from the first page, with no card open and no tile chosen, the arrangement untouched. Equal does nothing.
    func setView(_ new: LaunchpadViewMode) {
        guard new != view else { return }
        cancelLift()
        endEditing()
        drag.offset = 0
        cardDrag.offset = 0
        withAnimation(HelmMotion.interface) {
            closeFolderQuietly()
            assign(\.selection, nil)
            assign(\.page, 0)
            assign(\.view, new)
            reflow(selectFirst: false)
        }
        onViewChange?(new)
        requestSearchFocus()
    }

    /// The folder's menu: its size changes, and the tiles around it make room as they do for a drop.
    func resize(_ id: UUID, large: Bool) {
        if case .folder(_, _, _, let now)? = top.first(where: { $0.id == id.uuidString }), now != large { animateNextUpdate = true }
        onResize?(id, large)
    }

    /// An app's menu: in the category view it changes the blocks, and they make room under the reorder curve; in the grid nothing visible moves.
    func move(_ id: AppID, to target: LaunchpadCategoryTarget?) {
        if categoriesShown, let app = snapshot?.apps[id],
           target == nil ? moved[id] != nil : target != LaunchpadMenu.effective(moved: moved[id], raw: app.category) { animateNextUpdate = true }
        onMove?(id, target)
    }

    /// Return on the arrow keys' choice: an app opens, a folder opens its card.
    func activate() {
        guard removalAsk == nil else { return }
        guard let selection else { return }
        if openFolder != nil {
            guard selection < folderApps.count else { return }
            openApp(folderApps[selection].id, folderApps[selection].name)
            return
        }
        guard selection < top.count else { return }
        click(top[selection])
    }

    /// A press on an icon of a large folder launches that app, if the same app is under the press's point when it is let go; a
    /// press elsewhere on the tile, or a block that moved since so that another app (or none) is under the point, is the tile's
    /// own click: the folder opens and no app is launched.
    func click(_ entry: LaunchpadEntry, at address: Int, icon pressed: AppID?) {
        if !editing, let pressed, let hit = miniIcon(at: pressPoint, address: address), hit.id == pressed {
            assign(\.launchingBlock, entry.id)
            onLaunch?(hit.id, hit.name)
            return
        }
        click(entry)
    }

    /// The app of the large folder's mini icon at `address` that `point` is on, as the page shows the block now.
    func miniIcon(at point: CGPoint, address: Int) -> CatalogApp? {
        let (on, item) = (address / geometry.capacity, address % geometry.capacity)
        guard case .folder(_, _, let apps, true)? = entry(at: address), on == page, slots.indices.contains(on), slots[on].indices.contains(item) else { return nil }
        let block = geometry.frame(of: slots[on][item]).offsetBy(dx: 0, dy: geometry.gridTop)
        let index = categoriesShown ? LaunchpadHit.categoryIcon(at: point, block: block, mark: geometry.largeMark, edge: geometry.largeEdge, iconTop: geometry.iconTop, apps: apps.count)
            : LaunchpadHit.icon(at: point, block: block, mark: geometry.largeMark, edge: geometry.largeEdge, iconTop: geometry.iconTop, apps: apps.count)
        return index.map { apps[$0] }
    }

    private func click(_ entry: LaunchpadEntry) {
        switch entry {
        case .app(let app): openApp(app.id, app.name)
        case .folder(let id, _, _, _): open(folder: id)
        case .gap: break
        }
    }

    /// An app is opened by a click, Return or VoiceOver's default action: nothing in the edit mode, where the tile is a thing to arrange.
    func openApp(_ id: AppID, _ name: String) {
        guard !editing else { return }
        onLaunch?(id, name)
    }

    /// The index of the tile at `slot` of page `page` in the whole list, as the arrow keys count.
    func flatIndex(page: Int, slot: Int) -> Int { pageStarts.indices.contains(page) ? pageStarts[page] + slot : slot }

    func open(folder id: UUID) {
        if id == LaunchpadHiddenBlock.id, hidden.phase != .unlocked {
            hidden.ask(reason: LpStr.hiddenAuthReason) { [weak self] in
                guard let self, shown else { self?.hidden.lock(); return }
                reflow(selectFirst: false)
                open(folder: LaunchpadHiddenBlock.id)
                if openFolder != LaunchpadHiddenBlock.id { hidden.lock() }
            }
            return
        }
        guard let at = top.firstIndex(where: { $0.id == id.uuidString }), case .folder(_, let name, let apps, _) = top[at] else { return }
        if openFolder == LaunchpadHiddenBlock.id, id != LaunchpadHiddenBlock.id { hidden.lock() }
        folderTile = at
        assign(\.renaming, false)
        assign(\.nameDraft, name)
        assign(\.folderName, name)
        assign(\.folderApps, id == LaunchpadHiddenBlock.id ? snapshot?.hiddenApps ?? [] : apps)
        assign(\.openFolder, id)
        assign(\.selection, nil)
        assign(\.cardPage, 0)
        publishCard()
        // A swipe is handed to the card's own pages when it opens, and no release comes for the grid's: its page is let go here.
        drag.offset = 0
        cardDrag.offset = 0
    }

    /// Esc: the removal's card, then a lift, then the name field, then the folder, then the edit mode, then the search, then the window.
    func escape() {
        if removalAsk != nil { cancelRemoval(); return }
        if machine.isEngaged { cancelLift(); return }
        if renaming { revertName(); return }
        if openFolder != nil { closeFolder() }
        else if editing { endEditing() }
        else if !search.trimmingCharacters(in: .whitespaces).isEmpty { search = "" }
        else { onClose?() }
    }

    /// A click on the window's own background: the folder card if one is open, else the edit mode, else the window.
    func backgroundClicked() {
        if openFolder != nil { closeFolder() } else if editing { endEditing() } else { onClose?() }
    }

    func closeFolder() {
        let back = folderTile
        if openFolder != nil { commitName() }
        closeFolderQuietly()
        assign(\.selection, back.flatMap { $0 < top.count ? $0 : nil })
    }

    func closeFolderQuietly() {
        if openFolder == LaunchpadHiddenBlock.id { hidden.lock() }
        cancelRemoval()
        assign(\.openFolder, nil)
        assign(\.folderApps, [])
        assign(\.folderName, "")
        assign(\.nameDraft, "")
        assign(\.renaming, false)
        cardPreview = nil
        folderTile = nil
        cardDrag.offset = 0
        publishCard()
    }

    func assign<T: Equatable>(_ path: ReferenceWritableKeyPath<LaunchpadScreenState, T>, _ value: T) {
        if self[keyPath: path] != value { self[keyPath: path] = value }
    }
}
