import SwiftUI
import HelmUI
import Module_Launchpad_Engine

/// One tile of the window: an app, or a folder with the apps it holds as the snapshot resolved them; or the gap a lifted
/// tile leaves, which draws nothing and keeps one identity for as long as it is shown.
enum LaunchpadEntry: Equatable, Identifiable {
    case app(CatalogApp)
    case folder(id: UUID, name: String, apps: [CatalogApp])
    case gap

    /// The gap's id: a space, which no bundle id can hold, so that no app's id is it.
    static let gapID = " gap"

    var id: String {
        switch self {
        case .app(let app): app.id
        case .folder(let id, _, _): id.uuidString
        case .gap: Self.gapID
        }
    }
}

/// What the page needs of a lift, and republishes only when it changes: the tile carried, and the tile a release would drop
/// it onto. The pointer's place is not here (`LaunchpadLiftPoint`).
struct LaunchpadLiftView: Equatable {
    let entry: LaunchpadEntry
    var onto: String?
}

/// Where the pointer is while a tile is carried, in the window's coordinates (top left), at the event rate. Its own object,
/// as the page's drag is: only the overlay that reads it runs again.
@MainActor final class LaunchpadLiftPoint: ObservableObject {
    @Published var point = CGPoint.zero
    /// From the pointer to the middle of the carried tile's cell, taken when it was lifted.
    var grab = CGPoint.zero
}

/// Where the fingers hold the page, in points from its place. Its own object so that the 120 Hz of a swipe republishes this
/// and nothing else: the state's views do not re-run for it, only what reads `offset` (`PageDragOffset`).
@MainActor final class LaunchpadPageDrag: ObservableObject {
    @Published var offset: CGFloat = 0
}

/// How far the window is revealed, 0 (nothing) to 1 (whole): the window's one writer (`LaunchpadWindow.apply`) sets it with the panel's
/// alpha, from a gesture's progress or from a settle's own clock. Its own object, as the page's drag is: a scrub at 120 Hz
/// republishes this and nothing else, and only the effect that reads it runs again.
@MainActor final class LaunchpadReveal: ObservableObject {
    @Published var progress: Double = 1

    /// Where the window is for a scrub at `gesture` (0 to 1 of the pinch or spread): a pinch opens from nothing, so the reveal is the
    /// gesture; a spread closes from where the window was (`base`), so the reveal is what is left of it.
    static func value(direction: PinchDirection, base: Double, gesture: Double) -> Double {
        let g = min(max(gesture.isFinite ? gesture : 0, 0), 1)
        return direction == .pinch ? g : base * (1 - g)
    }

    /// Where a settle from `from` to `to` is at `fraction` of its time, along the interface curve.
    static func settled(from: Double, to: Double, fraction: Double) -> Double {
        from + (to - from) * HelmMotion.interfaceProgress(at: fraction)
    }
}

/// What the window knows, made when it opens (its geometry again when the grid changes) and dropped when it closes: the geometry, the icons, the search, the
/// page, the arrow keys' choice and the open folder. The model's snapshot comes in by `update(snapshot:)`, the only way in.
///
/// Everything the views draw from is **derived here and assigned only when it differs**, never in a `body`: a snapshot that
/// changed nothing the window shows redraws nothing. Pages are slices of one list (`LaunchpadPaging`), all held here; the views make
/// only the live ones (the shown page and its two neighbours).
@MainActor final class LaunchpadScreenState: ObservableObject {
    enum Mode: Equatable { case busy, noApps, noMatch, grid }

    @Published private(set) var geometry: LaunchpadGeometry
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
            withAnimation(HelmMotion.interface) {
                closeFolderQuietly()
                reflow(selectFirst: true)
            }
        }
    }
    @Published private(set) var mode = Mode.busy
    @Published private(set) var pages: [[LaunchpadEntry]] = [[]]
    @Published private(set) var page = 0
    /// The open folder's card page (0 with no card open); the choice and the lift's gap are indices into the folder's whole list.
    @Published private(set) var cardPage = 0
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
    /// What the open card draws: the folder's apps, and while a tile is carried over it the gap where a release would put it.
    @Published private(set) var cardEntries: [LaunchpadEntry] = []
    /// The name field's text, which is the folder's name until a person types in it.
    @Published var nameDraft = ""
    /// The name field holds the keyboard: the panel then gives `handleNameKey` Return (36, 76) and Esc (53) and leaves every
    /// other key to the field (`LaunchpadPanel`).
    @Published var renaming = false
    /// The field takes the keyboard with its text selected (a folder just made).
    private(set) var selectNameOnFocus = false
    /// The lift gate's flag (a tile may be lifted only while it is true): set when the window is presented or a pinch's scrub commits, false again as it closes. A spread's scrub that reverts leaves it true, as it never cleared it.
    @Published private(set) var shown = false
    /// Counts the asks for the search field to take the keyboard: the window asks when it becomes key after the screen appeared.
    @Published private(set) var searchFocusRequest = 0
    /// The window's reveal, apart from the state so a scrub republishes nothing else.
    let reveal = LaunchpadReveal()
    /// The app whose launch is under way, whose icon swells until the window goes or the launch fails.
    @Published private(set) var launching: AppID?
    /// The tile carried by the pointer, and what a release would drop it onto; nil when nothing is carried.
    @Published private(set) var lift: LaunchpadLiftView?
    /// The tile the press is on, until it is let go or lifted: its wash, since the panel takes the press before the button.
    @Published private(set) var pressedID: String?
    let liftPoint = LaunchpadLiftPoint()

    var onLaunch: ((AppID, String) -> Void)?
    var onHide: ((AppID) -> Void)?
    var onClose: (() -> Void)?
    /// Writes a drop's edit and answers the snapshot that is shown after it.
    var onPlace: ((LaunchpadEdit) async -> LaunchpadSnapshot?)?
    /// Writes a folder's new name.
    var onRename: ((UUID, String) -> Void)?
    /// Said once, when the first snapshot has come in.
    var onLoaded: ((LaunchpadSnapshot, LaunchpadScreenState) -> Void)?
    private var loadedOnce = false

    private var snapshot: LaunchpadSnapshot?
    /// The top level as the snapshot gave it (a search's hits, or the layout's tiles), cut at the layout's page breaks.
    private var segments: [[LaunchpadEntry]] = [[]]
    /// The same, flat: what the arrow keys and the folder's tile count over.
    private var top: [LaunchpadEntry] = []
    /// What is shown instead of `segments` while a tile is carried (the gap in its place) and until its drop is answered.
    private var preview: [[LaunchpadEntry]]?
    private var pageCounts = [0]
    private var pageStarts = [0]
    private var gapAddress: Int?
    private var machine = LaunchpadLift()
    private var lastPoint = CGPoint.zero
    private var timer: Task<Void, Never>?
    private var scheduled: TimeInterval?
    private var placing: Task<Void, Never>?
    /// What a person's pointer needs read from outside, replaced in a test.
    var buttonDown: () -> Bool = { NSEvent.pressedMouseButtons & 1 != 0 }
    var clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    /// Where the carried tile was lifted from: the grid, or the card of the folder with this id.
    private var liftSource = LaunchpadDropSource.top
    /// The open card's entries while a tile is carried over it (the gap in them), instead of the folder's apps.
    private var cardPreview: [LaunchpadEntry]?
    /// The folder tiles' addresses, which a dwell on one of them opens.
    private var folderAddresses: Set<Int> = []
    /// Where the open folder's tile is in `top`, for Esc to come back to.
    private var folderTile: Int?

    init(geometry: LaunchpadGeometry) {
        self.geometry = geometry
        icons = LaunchpadIcons(capacity: geometry.capacity, size: geometry.icon)
    }

    var pageCount: Int { pages.count }

    /// The width of what a swipe turns: the open card's page, else the grid's.
    var swipeWidth: CGFloat { card?.pageWidth ?? geometry.pageWidth }

    func setShown(_ value: Bool) { assign(\.shown, value) }
    func requestSearchFocus() { searchFocusRequest &+= 1 }
    func launched(_ id: AppID) { assign(\.launching, id) }
    func launchFailed() { assign(\.launching, nil) }

    /// Where the open folder's tile is in the window's coordinates, for its card to grow from and fold back to; the
    /// window's middle when there is no folder.
    var folderOrigin: CGPoint {
        guard let folderTile else { return CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2) }
        let start = pageStarts[LaunchpadPaging.page(of: folderTile, starts: pageStarts)]
        return geometry.center(ofSlot: folderTile - start)
    }

    /// The columns the arrow keys move over: the page's, or the open folder's.
    var columns: Int { openFolder == nil ? geometry.columns : folderColumns }
    var folderColumns: Int { LaunchpadSurface.Card(geometry: geometry, count: folderApps.count).columns }

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
            segments = [[]]
            top = []
            assign(\.mode, .busy)
            publishPages()
            return
        }
        let hits = snapshot.search(search)
        if let hits {
            segments = [hits.compactMap { snapshot.apps[$0] }.map(LaunchpadEntry.app)]
        } else {
            segments = [[]]
            for item in snapshot.layout.items {
                switch item {
                case .app(let id): if let app = snapshot.apps[id] { segments[segments.count - 1].append(.app(app)) }
                case .folder(let folder):
                    let apps = folder.apps.compactMap { snapshot.apps[$0] }
                    if !apps.isEmpty { segments[segments.count - 1].append(.folder(id: folder.id, name: folder.name, apps: apps)) }
                case .pageBreak: segments.append([])
                }
            }
        }
        segments.removeAll { $0.isEmpty }
        top = Array(segments.joined())
        if let open = openFolder {
            if let at = top.firstIndex(where: { $0.id == open.uuidString }), case .folder(_, let name, let apps) = top[at] {
                folderTile = at
                setFolderName(name)
                assign(\.folderApps, apps)
            } else {
                closeFolderQuietly()
                assign(\.selection, nil)
            }
        }
        if let carried = lift?.entry.id {
            if let fresh = carriedEntry(carried) { rebuildPreview(carrying: fresh) } else { cancelLift() }
        }
        publishCard()
        if lift != nil, openFolder != nil { seatGap() }
        assign(\.mode, snapshot.apps.isEmpty || (hits == nil && top.isEmpty) ? .noApps : hits != nil && top.isEmpty ? .noMatch : .grid)
        publishPages()
        if selectFirst {
            assign(\.selection, hits != nil && !top.isEmpty ? 0 : nil)
            assign(\.page, 0)
        } else {
            if let selectedID { assign(\.selection, shownIDs.firstIndex(of: selectedID)) }
        }
        // An equal index over other tiles (a new search) is no assignment: the name it stands for is read again here.
        rememberSelected()
    }

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
        guard let next = LaunchpadPaging.moved(selection, dx: dx, dy: dy, columns: columns, count: count) else { return }
        assign(\.selection, next)
        assign(\.page, LaunchpadPaging.page(of: next, starts: pageStarts))
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

    private func goCard(to target: Int) {
        guard let card else { return }
        let next = LaunchpadPaging.clamped(target, count: card.pageCount)
        assign(\.cardPage, next)
        if let selection, card.page(ofIndex: selection) != next { assign(\.selection, nil) }
    }

    /// A new grid (the person's settings changed while the window is open): the same order cut again by the new capacity. Writes
    /// nothing, the layout stores order and not pages. A cell's address is `page * capacity + slot`, which means nothing
    /// after the capacity changed, so a lift or a press ends first (a drop already out lands through `update`). The page
    /// stays on the choice, or on the tile the shown page began with. An open folder's card stays open and follows the grid, its page
    /// on its choice or on the tile its shown page began with.
    func regrid(_ settings: LaunchpadGridSettings) {
        let next = LaunchpadGeometry.make(for: geometry.size, topSafe: geometry.topSafe, settings: settings)
        guard next != geometry else { return }
        let anchor = pageStarts.indices.contains(page) ? pageStarts[page] : 0
        let cardAnchor = (card?.page ?? 0) * (card?.capacity ?? 1)
        cancelLift()
        drag.offset = 0
        cardDrag.offset = 0
        withAnimation(HelmMotion.interface) {
            geometry = next
            icons.reconfigure(capacity: next.capacity, size: next.icon)
            publishPages()
            publishCard()
            if let card { goCard(to: card.page(ofIndex: selection ?? cardAnchor)) }
        }
        // With a card open the selection counts the card's apps, not the grid's.
        assign(\.page, LaunchpadPaging.page(of: openFolder == nil ? selection ?? anchor : anchor, starts: pageStarts))
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
        click(top[selection])
    }

    private func click(_ entry: LaunchpadEntry) {
        switch entry {
        case .app(let app): onLaunch?(app.id, app.name)
        case .folder(let id, _, _): open(folder: id)
        case .gap: break
        }
    }

    /// The index of the tile at `slot` of page `page` in the whole list, as the arrow keys count.
    func flatIndex(page: Int, slot: Int) -> Int { pageStarts.indices.contains(page) ? pageStarts[page] + slot : slot }

    func open(folder id: UUID) {
        guard let at = top.firstIndex(where: { $0.id == id.uuidString }), case .folder(_, let name, let apps) = top[at] else { return }
        folderTile = at
        assign(\.renaming, false)
        assign(\.nameDraft, name)
        assign(\.folderName, name)
        assign(\.folderApps, apps)
        assign(\.openFolder, id)
        assign(\.selection, nil)
        assign(\.cardPage, 0)
        publishCard()
        // A swipe is handed to the card's own pages when it opens, and no release comes for the grid's: its page is let go here.
        drag.offset = 0
        cardDrag.offset = 0
    }

    /// Esc: a lift, then the name field, then the folder, then the search, then the window.
    func escape() {
        if machine.isEngaged { cancelLift(); return }
        if renaming { revertName(); return }
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
        if openFolder != nil { commitName() }
        closeFolderQuietly()
        assign(\.selection, back.flatMap { $0 < top.count ? $0 : nil })
    }

    private func closeFolderQuietly() {
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

    // MARK: - The folder's name

    /// The name the card shows is the snapshot's, unless a person is typing in the field.
    private func setFolderName(_ name: String) {
        assign(\.folderName, name)
        if !renaming { assign(\.nameDraft, name) }
    }

    /// The field takes the keyboard, its text selected when `selectAll`.
    func beginRenaming(selectAll: Bool) {
        guard openFolder != nil else { return }
        selectNameOnFocus = selectAll
        assign(\.renaming, true)
    }

    /// Return, or the card closing: a changed, non-blank draft is the folder's name; a blank one is the old name again.
    func commitName() {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        assign(\.renaming, false)
        guard let id = openFolder, !name.isEmpty else { assign(\.nameDraft, folderName); return }
        guard name != folderName else { assign(\.nameDraft, name); return }
        assign(\.nameDraft, name)
        assign(\.folderName, name)
        onRename?(id, name)
    }

    /// A key while the field has the keyboard (key codes: Return 36 and 76, Esc 53): true when it was the state's, false when it
    /// goes on to the field, so the caret, the arrows and the typing are the field's.
    func handleNameKey(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 36, 76: commitName()
        case 53: revertName()
        default: return false
        }
        return true
    }

    /// Esc in the field: what was typed goes, the folder stays open.
    func revertName() {
        assign(\.nameDraft, folderName)
        assign(\.renaming, false)
    }

    // MARK: - The lift

    /// A press may become a lift only with the grid shown: no search text, no name being typed, no launch under way, and the
    /// window shown (not yet, or no longer, is not).
    var liftAllowed: Bool {
        mode == .grid && search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !renaming && launching == nil && shown
    }

    /// A press is down on a tile, lifted or not: the panel hands this window's mouse events to the state, and keys and the wheel go nowhere.
    var pointerBusy: Bool { machine.isEngaged }

    /// The open card as the pointer meets it; nil when no folder is open.
    private var card: LaunchpadSurface.Card? {
        openFolder == nil ? nil : LaunchpadSurface.Card(geometry: geometry, count: cardEntries.count, page: cardPage)
    }

    private var surface: LaunchpadSurface {
        var surface = LaunchpadSurface(geometry: geometry, page: page, pageCounts: pageCounts, gap: gapAddress)
        if let card {
            surface.card = card
            surface.gap = cardEntries.firstIndex(of: .gap)
        } else if case .app = lift?.entry {
            surface.folders = folderAddresses
        }
        return surface
    }

    /// True when the press is on a tile and the window takes it (no button sees it); false leaves it to the views.
    func pointerDown(_ point: CGPoint, time: TimeInterval) -> Bool {
        guard liftAllowed, !machine.isEngaged else { return false }
        _ = machine.feed(.down, at: point, surface: surface, time: time)
        guard let address = machine.pressedAddress else { return false }
        lastPoint = point
        assign(\.pressedID, entry(at: address)?.id)
        rearm()
        return true
    }

    func pointerMoved(_ point: CGPoint, time: TimeInterval) {
        lastPoint = point
        if machine.isLifted { liftPoint.point = point }
        apply(machine.feed(.moved, at: point, surface: surface, time: time))
        rearm()
    }

    func pointerUp(_ point: CGPoint, time: TimeInterval) {
        lastPoint = point
        apply(machine.feed(.up, at: point, surface: surface, time: time))
        rearm()
    }

    /// The timer's turn, or a test's: what the pointer has waited for comes due. A left button that is no longer down ends the lift.
    func tick(at time: TimeInterval? = nil) {
        guard machine.isEngaged else { return }
        let effect = buttonDown()
            ? machine.feed(.tick, at: lastPoint, surface: surface, time: time ?? clock())
            : machine.feed(.abort, surface: surface)
        apply(effect)
        rearm()
    }

    /// Esc, or anything else that ends a lift without a drop: nothing is written.
    func cancelLift() {
        apply(machine.feed(.escape, surface: surface))
        rearm()
    }

    /// The window is going: no timer, no lift, nothing written (a drop already out still lands).
    func shutdown() {
        timer?.cancel()
        timer = nil
        scheduled = nil
        _ = machine.feed(.abort, surface: surface)
        placing?.cancel()
        placing = nil
        lift = nil
        pressedID = nil
        preview = nil
        cardPreview = nil
        liftSource = .top
        publishCard()
        publishPages()
    }

    private func apply(_ effect: LaunchpadLift.Effect) {
        switch effect {
        case .none: break
        case .lift(let address): beginLift(at: address)
        case .moveGap(let address): moveGap(to: address)
        case .arm(let address):
            let id = address.flatMap { entry(at: $0) }.flatMap { $0 == .gap ? nil : $0.id }
            if let carried = lift { assign(\.lift, LaunchpadLiftView(entry: carried.entry, onto: id)) }
        case .turn(let step):
            withAnimation(HelmMotion.interface) {
                if openFolder == nil { go(to: page + step) } else { go(to: cardPage + step); seatGap() }
            }
        case .newPage: addPage()
        case .openFolder(let address):
            if case .folder(let id, _, _)? = entry(at: address) { openForLift(id) }
        case .closeFolder: closeForLift()
        case .release(let drop): finish(drop)
        case .cancel: endLift()
        case .click(let address):
            // The press was on the app it recorded; a snapshot that moved other tiles under the pointer since is no click on them.
            let pressed = pressedID
            assign(\.pressedID, nil)
            if let tile = entry(at: address), tile.id == pressed { click(tile) }
        }
    }

    /// One timer, armed for the machine's `wake` and left alone while that does not change.
    private func rearm() {
        guard let wake = [machine.wake, machine.stuckWake].compactMap({ $0 }).min() else {
            timer?.cancel()
            timer = nil
            scheduled = nil
            return
        }
        guard scheduled != wake else { return }
        timer?.cancel()
        scheduled = wake
        let delay = max(0, wake - clock())
        timer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.scheduled = nil
            self.tick()
        }
    }

    private func entry(at address: Int) -> LaunchpadEntry? {
        if openFolder != nil { return cardEntries.indices.contains(address) ? cardEntries[address] : nil }
        let (at, slot) = (address / geometry.capacity, address % geometry.capacity)
        return pages.indices.contains(at) && pages[at].indices.contains(slot) ? pages[at][slot] : nil
    }

    private func locate(_ id: String, in list: [[LaunchpadEntry]]) -> (segment: Int, index: Int)? {
        for (s, segment) in list.enumerated() {
            if let i = segment.firstIndex(where: { $0.id == id }) { return (s, i) }
        }
        return nil
    }

    private func beginLift(at address: Int) {
        // The tile is the one the press was on, as the page shows it now (a snapshot or a drop being written may have moved it).
        guard let tile = entry(at: address), tile != .gap, tile.id == pressedID else {
            _ = machine.feed(.abort, surface: surface)
            endLift()
            return
        }
        let shown = preview ?? segments
        let from: CGPoint
        if let open = openFolder, let card, let at = cardEntries.firstIndex(of: tile) {
            liftSource = .folder(open)
            var members = cardEntries
            members[at] = .gap
            cardPreview = members
            preview = withoutCarried(tile, in: shown, folder: open)
            from = card.center(ofSlot: at)
        } else if let at = locate(tile.id, in: shown), openFolder == nil {
            liftSource = .top
            var list = shown
            list[at.segment][at.index] = .gap
            preview = list
            from = geometry.center(ofSlot: address % geometry.capacity)
        } else {
            return
        }
        liftPoint.grab = CGPoint(x: from.x - lastPoint.x, y: from.y - lastPoint.y)
        liftPoint.point = lastPoint
        assign(\.pressedID, nil)
        assign(\.selection, nil)
        assign(\.lift, LaunchpadLiftView(entry: tile, onto: nil))
        publishCard()
        publishPages()
    }

    /// The grid's tiles with the carried app out of the folder it was lifted from; the folder's tile keeps its identity, even
    /// with one app left (the engine dissolves it when the drop lands).
    private func withoutCarried(_ carried: LaunchpadEntry, in list: [[LaunchpadEntry]], folder: UUID) -> [[LaunchpadEntry]] {
        list.map { segment in
            segment.map { entry in
                guard case .folder(folder, let name, let apps) = entry else { return entry }
                return .folder(id: folder, name: name, apps: apps.filter { $0.id != carried.id })
            }
        }
    }

    /// The carried tile as the snapshot has it now, or nil when it is gone.
    private func carriedEntry(_ id: String) -> LaunchpadEntry? {
        switch liftSource {
        case .top: return top.first { $0.id == id }
        case .folder(let folder):
            guard case .folder(_, _, let apps)? = top.first(where: { $0.id == folder.uuidString }) else { return nil }
            return apps.first { $0.id == id }.map(LaunchpadEntry.app)
        }
    }

    /// The gap takes the place of the tile at `address`: before it when that tile comes before the gap, after it when after,
    /// so the tile makes way toward where the gap was. An empty cell is the end of its page (of the card).
    private func moveGap(to address: Int) {
        if openFolder != nil { moveCardGap(to: address); return }
        guard var list = preview, let gap = locate(LaunchpadEntry.gap.id, in: list) else { return }
        let (at, slot) = (address / geometry.capacity, address % geometry.capacity)
        guard pages.indices.contains(at), let target = slot < pages[at].count ? pages[at][slot] : pages[at].last, target != .gap,
              let to = locate(target.id, in: list) else { return }
        let after = slot >= pages[at].count || (to.segment, to.index) > (gap.segment, gap.index)
        list[gap.segment].remove(at: gap.index)
        guard let moved = locate(target.id, in: list) else { return }
        list[moved.segment].insert(.gap, at: moved.index + (after ? 1 : 0))
        preview = list.filter { !$0.isEmpty }
        withAnimation(HelmMotion.reorder) { publishPages() }
    }

    private func moveCardGap(to slot: Int) {
        guard var list = cardPreview, let gap = list.firstIndex(of: .gap), let target = slot < list.count ? list[slot] : list.last,
              target != .gap, let to = list.firstIndex(of: target) else { return }
        let after = slot >= list.count || to > gap
        list.remove(at: gap)
        guard let moved = list.firstIndex(of: target) else { return }
        list.insert(.gap, at: moved + (after ? 1 : 0))
        cardPreview = list
        withAnimation(HelmMotion.reorder) { publishCard() }
    }

    /// The pointer stayed on a folder: its card opens with the gap at its end, and the lift goes on in it.
    private func openForLift(_ id: UUID) {
        guard let carried = lift?.entry else { return }
        open(folder: id)
        guard openFolder == id else { return }
        assign(\.lift, LaunchpadLiftView(entry: carried, onto: nil))
        cardPreview = folderApps.map(LaunchpadEntry.app) + [.gap]
        machine.resetDwell()
        publishCard()
        goCard(to: .max)
    }

    /// The pointer stayed outside the card: it closes, and the lift goes on over the grid. A tile lifted from the folder has
    /// no gap there yet: it takes one right after the folder's tile.
    private func closeForLift() {
        guard let open = openFolder else { return }
        closeFolderQuietly()
        if case .folder = liftSource, var list = preview, locate(LaunchpadEntry.gap.id, in: list) == nil,
           let at = locate(open.uuidString, in: list) {
            list[at.segment].insert(.gap, at: at.index + 1)
            preview = list
        }
        machine.resetDwell()
        withAnimation(HelmMotion.reorder) { publishPages() }
    }

    /// The card's entries: the folder's apps, or the lift's preview of them.
    private func publishCard() {
        assign(\.cardEntries, openFolder == nil ? [] : cardPreview ?? folderApps.map(LaunchpadEntry.app))
        assign(\.cardPage, card?.page ?? 0)
    }

    /// The card's page turned under a lift: the gap takes the nearest place on the page now shown, so the carried tile has
    /// a place where it arrived and a release lands on the page the person sees.
    private func seatGap() {
        guard let list = cardPreview, let gap = list.firstIndex(of: .gap) else { return }
        let range = LaunchpadSurface.Card(geometry: geometry, count: list.count, page: cardPage).range(ofPage: cardPage)
        guard !range.isEmpty, !range.contains(gap) else { return }
        moveCardGap(to: gap < range.lowerBound ? range.lowerBound : range.upperBound - 1)
    }

    /// The edge of the last page, held: a page of its own at the end, with the gap alone on it.
    private func addPage() {
        guard openFolder == nil, var list = preview, list.last != [.gap], let gap = locate(LaunchpadEntry.gap.id, in: list) else { return }
        list[gap.segment].remove(at: gap.index)
        preview = list.filter { !$0.isEmpty } + [[.gap]]
        withAnimation(HelmMotion.interface) {
            publishPages()
            go(to: pages.count - 1)
        }
    }

    /// A new snapshot while a tile is carried: the gap stays by its neighbour, the carried tile is the snapshot's own.
    private func rebuildPreview(carrying fresh: LaunchpadEntry) {
        machine.resetDwell()
        assign(\.lift, LaunchpadLiftView(entry: fresh, onto: nil))
        if case .folder(let source) = liftSource {
            var list = withoutCarried(fresh, in: segments, folder: source)
            if openFolder == nil, let at = locate(source.uuidString, in: list) { list[at.segment].insert(.gap, at: at.index + 1) }
            preview = list.filter { !$0.isEmpty }
            cardPreview = openFolder == source ? folderApps.map { $0.id == fresh.id ? .gap : .app($0) } : nil
            return
        }
        var before: String?, after: String?
        if let old = preview, let gap = locate(LaunchpadEntry.gap.id, in: old) {
            let segment = old[gap.segment]
            before = gap.index > 0 ? segment[gap.index - 1].id : nil
            after = gap.index + 1 < segment.count ? segment[gap.index + 1].id : nil
        }
        var list = segments
        if let own = locate(fresh.id, in: list) { list[own.segment][own.index] = .gap }
        if let anchor = before ?? after, locate(anchor, in: list) != nil, let gap = locate(LaunchpadEntry.gap.id, in: list) {
            list[gap.segment].remove(at: gap.index)
            if let moved = locate(anchor, in: list) { list[moved.segment].insert(.gap, at: moved.index + (before != nil ? 1 : 0)) }
        }
        preview = list.filter { !$0.isEmpty }
        if openFolder != nil { cardPreview = folderApps.map(LaunchpadEntry.app) + [.gap] }
    }

    /// Nothing carried any more and nothing written: the page goes back to the snapshot's.
    private func endLift() {
        assign(\.lift, nil)
        assign(\.pressedID, nil)
        guard placing == nil else { return }
        preview = nil
        cardPreview = nil
        liftSource = .top
        publishCard()
        withAnimation(HelmMotion.reorder) { publishPages() }
    }

    /// The pointer let go: one edit by anchors, or nothing when the drop changes nothing. The page shows the drop at once
    /// and takes the engine's answer when it comes. Inside the open card it is a drop into the folder; anywhere else the card
    /// closes first and it is a drop on the grid.
    private func finish(_ drop: LaunchpadLift.Drop) {
        guard let carried = lift?.entry, snapshot != nil else { endLift(); return }
        if let open = openFolder, let card {
            var inCard = card.rect.contains(lastPoint)
            if case .edge = LaunchpadHit.at(lastPoint, in: surface) { inCard = true }
            if inCard { finishInCard(carried, folder: open); return }
            closeForLift()
        }
        guard let snapshot, let list = preview, let gap = locate(LaunchpadEntry.gap.id, in: list) else { endLift(); return }
        var destination: LaunchpadDropDestination?
        var shown = list
        var name = ""
        switch drop {
        case .onto(let address):
            shown[gap.segment].remove(at: gap.index)
            if let target = entry(at: address), target != .gap {
                destination = .onto(target.id)
                name = LaunchpadCategoryName.folderName(target: snapshot.apps[target.id]?.category, dropped: snapshot.apps[carried.id]?.category)
                // A folder only reorders: it stays on the page, beside the target as the edit puts it, until the engine answers.
                if case .folder = carried, let before = locate(target.id, in: list), let at = locate(target.id, in: shown) {
                    shown[at.segment].insert(carried, at: at.index + ((before.segment, before.index) > (gap.segment, gap.index) ? 1 : 0))
                }
            }
        case .gap:
            let segment = list[gap.segment]
            if segment.count == 1 {
                destination = gap.segment == list.count - 1 ? .newPage : nil
            } else {
                destination = gap.index > 0 ? .beside(segment[gap.index - 1].id, after: true) : .beside(segment[1].id, after: false)
            }
            shown[gap.segment][gap.index] = carried
        }
        assign(\.lift, nil)
        assign(\.pressedID, nil)
        guard let destination, let edit = snapshot.layout.edit(dropping: carried.id, source: liftSource, destination: destination, folderName: name) else {
            endLift()
            return
        }
        preview = shown.filter { !$0.isEmpty }
        withAnimation(HelmMotion.reorder) { publishPages() }
        place(edit)
    }

    /// A release over the card: the carried app lands where the gap is among the folder's apps.
    private func finishInCard(_ carried: LaunchpadEntry, folder: UUID) {
        guard let snapshot, var list = cardPreview, let gap = list.firstIndex(of: .gap) else { endLift(); return }
        let anchor: (String, after: Bool)? = gap > 0 ? (list[gap - 1].id, true) : list.count > 1 ? (list[1].id, false) : nil
        assign(\.lift, nil)
        assign(\.pressedID, nil)
        guard let edit = snapshot.layout.edit(dropping: carried.id, source: liftSource,
                                              destination: .intoFolder(folder, relativeTo: anchor?.0, after: anchor?.after ?? true), folderName: "") else {
            endLift()
            return
        }
        list[gap] = carried
        cardPreview = list
        publishCard()
        if case .top = liftSource, var grid = preview, let at = locate(LaunchpadEntry.gap.id, in: grid) {
            grid[at.segment].remove(at: at.index)
            preview = grid.filter { !$0.isEmpty }
            withAnimation(HelmMotion.reorder) { publishPages() }
        }
        place(edit)
    }

    /// Writes the edit; what the engine answers replaces the preview. A folder just made opens with its name field in hand.
    private func place(_ edit: LaunchpadEdit) {
        placing = Task { @MainActor [weak self] in
            let landed = await self?.onPlace?(edit)
            guard !Task.isCancelled, let self else { return }
            self.placing = nil
            self.preview = nil
            if self.lift == nil {
                self.cardPreview = nil
                self.liftSource = .top
            }
            if let landed { self.update(snapshot: landed) } else { self.reflow(selectFirst: false) }
            if case .makeFolder(_, let target, _) = edit {
                for case .folder(let id, _, let apps) in self.top where apps.contains(where: { $0.id == target }) {
                    self.open(folder: id)
                    self.beginRenaming(selectAll: true)
                }
            }
        }
    }

    /// The pages as they are drawn: the snapshot's, or the lift's preview, cut by what a page holds; the numbers the
    /// pointer's hit test reads come with them.
    private func publishPages() {
        let chunks = LaunchpadPaging.pages(preview ?? segments, capacity: geometry.capacity)
        assign(\.pages, chunks)
        pageCounts = chunks.map(\.count)
        pageStarts = chunks.indices.map { chunks[..<$0].reduce(0) { $0 + $1.count } }
        gapAddress = chunks.enumerated().lazy.compactMap { at, list in
            list.firstIndex(of: .gap).map { at * self.geometry.capacity + $0 }
        }.first
        folderAddresses = Set(chunks.enumerated().flatMap { at, list in
            list.indices.filter { if case .folder = list[$0] { true } else { false } }.map { at * geometry.capacity + $0 }
        })
        assign(\.page, LaunchpadPaging.clamped(page, count: chunks.count))
    }

    private func assign<T: Equatable>(_ path: ReferenceWritableKeyPath<LaunchpadScreenState, T>, _ value: T) {
        if self[keyPath: path] != value { self[keyPath: path] = value }
    }
}
