import AppKit
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
@testable import HelmApp

/// **`SettingsToolbar.identifiers` leads with what its `lead` says: the sidebar's
/// tracking separator for `.sidebarSeparator`, the name for `.spacer`; the `.sidebarSeparator` bar stays
/// exactly what it was.** The window constructs `.spacer`; `.sidebarSeparator` is the initialiser's default,
/// so every test that builds a `SettingsToolbar` without `lead:` gets it, and only this file names it.
///
/// The tests above the mark "a toolbar told where the pane is" need no window, no `NSWindow`, no screen:
/// `SettingsToolbar.identifiers` and `SettingsToolbar.nameInset` are pure, and
/// the content shapes are plain values. Those between it and the mark "what only a visible window can run, read from the source" build a `SettingsToolbar`
/// with no window and tell it where the pane is through `paneMoved(leading:width:rail:)`, its `rail` left at the default;
/// they read its lists and numbers (`barIdentifiers`, `currentNameInset`,
/// `itemsStart`, `offeredRoom`), and still no window exists. Those below that mark read `SettingsToolbar.swift` as text.
///
/// The `.sidebarSeparator` lists below are pinned LITERALLY, read from
/// `SettingsToolbar.identifiers(content:style:)` as it stood at c753c864
/// (that commit's `Sources/HelmApp/SettingsToolbar.swift`): the tracking separator
/// first; the name item only under `.moduleName`; then, with nothing declared,
/// `flexibleSpace, status` (`.moduleName` only); otherwise `flexibleSpace`,
/// `tabs, flexibleSpace` when there are tabs, `actions`, `search`. The `.spacer` lists are pinned
/// literally beside them: the same list without its first item under `.moduleName`, and under
/// `.windowTitle` the name in front of that list, the status staying out; in both, where the bar has tabs, the
/// flexible space in front of the tabs is the tabs' lead item `helm.tabsLead`. They are not
/// computed through the function under test, so a lead that is ignored or a
/// list that moved goes red here (a moved tail also in
/// `TheStatusBadgeMovesToTheWindowsTrailingEdgeTests`, which compares the tail
/// of `toolbar.itemIdentifiers`).
///
/// The numbers: 92.5 is where the toolbar can start its items (`itemsStart`),
/// an input these tests feed, taken from one measurement on macOS 27.2 with a
/// 200 pt sidebar, not a fact they establish; 123.5 = 200 + 16 - 92.5 is the
/// expectation derived from it, not a second measurement. For a pane whose
/// leading edge is at 56 the items already start past 56 + 16, so the inset is
/// 0: the name starts where the items do, which is AppKit's to decide.
@MainActor
final class TheToolbarLeadsWithWhatItsShellGivesTests: XCTestCase {

    private typealias ID = NSToolbarItem.Identifier
    private static let sep = ID.sidebarTrackingSeparator
    private static let flex = ID.flexibleSpace
    private static let name = ID("helm.name")
    private static let status = ID("helm.status")
    private static let tabs = ID("helm.tabs")
    private static let tabsLead = ID("helm.tabsLead")
    private static let actions = ID("helm.actions")
    private static let search = ID("helm.search")

    // MARK: - content shapes

    private static func content(tabs: Bool, actions: Bool, search: Bool) -> HelmPageToolbarContent? {
        if !tabs && !actions && !search { return nil }
        return HelmPageToolbarContent(
            tabs: tabs ? [HelmToolbarTab(id: "a", title: "Alpha", symbol: "circle"),
                          HelmToolbarTab(id: "b", title: "Beta", symbol: "square")] : [],
            selectedTab: tabs ? .constant("a") : nil,
            actions: actions ? [HelmToolbarAction(id: "go", title: "Go", symbol: "arrow.clockwise") {}] : [],
            search: search ? HelmToolbarSearch(prompt: "Search", text: .constant("")) : nil)
    }

    private struct Shape {
        let label: String
        let content: HelmPageToolbarContent?
        let moduleName: [ID]
        let windowTitle: [ID]
        /// The `.spacer` lead's list under `.windowTitle`: the name opens it, the status stays out.
        let spacerWindowTitle: [ID]
        /// The `.spacer` lead's list under `.moduleName`: the `.sidebarSeparator` list without its separator, the
        /// flexible space in front of the tabs standing as the tabs' lead item where the bar has tabs.
        let spacerModuleName: [ID]
    }

    /// The `.sidebarSeparator` columns are pinned from the c753c864 source and the `.spacer` columns as this file's header
    /// states them, one row per reachable content shape.
    private static let shapes: [Shape] = [
        Shape(label: "nothing declared (nil)", content: nil,
              moduleName: [sep, name, flex, status], windowTitle: [sep], spacerWindowTitle: [name],
              spacerModuleName: [name, flex, status]),
        Shape(label: "declared but empty", content: HelmPageToolbarContent(),
              moduleName: [sep, name, flex, status], windowTitle: [sep], spacerWindowTitle: [name],
              spacerModuleName: [name, flex, status]),
        Shape(label: "tabs", content: content(tabs: true, actions: false, search: false),
              moduleName: [sep, name, flex, tabs, flex], windowTitle: [sep, flex, tabs, flex],
              spacerWindowTitle: [name, tabsLead, tabs, flex],
              spacerModuleName: [name, tabsLead, tabs, flex]),
        Shape(label: "actions", content: content(tabs: false, actions: true, search: false),
              moduleName: [sep, name, flex, actions], windowTitle: [sep, flex, actions], spacerWindowTitle: [name, flex, actions],
              spacerModuleName: [name, flex, actions]),
        Shape(label: "search", content: content(tabs: false, actions: false, search: true),
              moduleName: [sep, name, flex, search], windowTitle: [sep, flex, search], spacerWindowTitle: [name, flex, search],
              spacerModuleName: [name, flex, search]),
        Shape(label: "tabs + actions", content: content(tabs: true, actions: true, search: false),
              moduleName: [sep, name, flex, tabs, flex, actions], windowTitle: [sep, flex, tabs, flex, actions],
              spacerWindowTitle: [name, tabsLead, tabs, flex, actions],
              spacerModuleName: [name, tabsLead, tabs, flex, actions]),
        Shape(label: "tabs + search", content: content(tabs: true, actions: false, search: true),
              moduleName: [sep, name, flex, tabs, flex, search], windowTitle: [sep, flex, tabs, flex, search],
              spacerWindowTitle: [name, tabsLead, tabs, flex, search],
              spacerModuleName: [name, tabsLead, tabs, flex, search]),
        Shape(label: "actions + search", content: content(tabs: false, actions: true, search: true),
              moduleName: [sep, name, flex, actions, search], windowTitle: [sep, flex, actions, search],
              spacerWindowTitle: [name, flex, actions, search],
              spacerModuleName: [name, flex, actions, search]),
        Shape(label: "tabs + actions + search", content: content(tabs: true, actions: true, search: true),
              moduleName: [sep, name, flex, tabs, flex, actions, search],
              windowTitle: [sep, flex, tabs, flex, actions, search],
              spacerWindowTitle: [name, tabsLead, tabs, flex, actions, search],
              spacerModuleName: [name, tabsLead, tabs, flex, actions, search]),
    ]

    private func raw(_ list: [ID]) -> [String] { list.map(\.rawValue) }

    // MARK: - the bar led by `.spacer`

    /// Total failure prints: "a pane whose leading edge is at 56 gets an inset of <x>: the name is pushed past
    /// where the items start" / "a bar led by `.spacer` still leads with the tracking separator, which
    /// tracks nothing without a split view; got <list>" (the list starts with the separator, or with
    /// anything but the name).
    func testWhereTheItemsStartPastThePaneTheNameHasNoInset() {
        let inset = SettingsToolbar.nameInset(paneLeading: 56, itemsStart: 92.5)
        XCTAssertEqual(inset, 0, accuracy: 0.0001,
                       "a pane whose leading edge is at 56 gets an inset of \(inset): the name is pushed past where the items start")
        let list = SettingsToolbar.identifiers(content: nil, style: .moduleName, lead: .spacer)
        XCTAssertEqual(raw(list), raw([Self.name, Self.flex, Self.status]),
                       "a bar led by `.spacer` still leads with the tracking separator, which tracks nothing without a split view; got \(raw(list))")
    }

    /// Total failure prints: "at sidebar 200 the inset is <x>, not 123.5: the name does not land 16 pt past the pane's edge".
    func testAtSidebar200TheInsetIs123Point5() {
        let inset = SettingsToolbar.nameInset(paneLeading: 200, itemsStart: 92.5)
        XCTAssertEqual(inset, 123.5, accuracy: 0.0001, "at sidebar 200 the inset is \(inset), not 123.5: the name does not land 16 pt past the pane's edge")
    }

    // MARK: - the separator-led bar is byte-for-byte today's

    /// Total failure prints: "the separator-led bar moved under <shape> / moduleName: want […] got […]"
    /// and "the separator-led bar no longer starts with the tracking separator under <shape>".
    func testTheSeparatorLeadEqualsTodaysPinnedListForEveryShape() {
        for shape in Self.shapes {
            let m = SettingsToolbar.identifiers(content: shape.content, style: .moduleName, lead: .sidebarSeparator)
            XCTAssertEqual(raw(m), raw(shape.moduleName),
                           "the separator-led bar moved under \(shape.label) / moduleName: want \(raw(shape.moduleName)) got \(raw(m))")
            XCTAssertEqual(m.first, Self.sep, "the separator-led bar no longer starts with the tracking separator under \(shape.label)")
            let t = SettingsToolbar.identifiers(content: shape.content, style: .windowTitle, lead: .sidebarSeparator)
            XCTAssertEqual(raw(t), raw(shape.windowTitle),
                           "the separator-led bar moved under \(shape.label) / windowTitle: want \(raw(shape.windowTitle)) got \(raw(t))")
            XCTAssertEqual(t.first, Self.sep, "the separator-led bar no longer starts with the tracking separator under \(shape.label) / windowTitle")
        }
    }

    /// The `.spacer` lead under `.moduleName` is the `.sidebarSeparator` list with its first item gone and, where the
    /// bar has tabs, the lead item `helm.tabsLead` in the place of the flexible space in front of the tabs — nothing else
    /// moves — and under `.windowTitle` the name opens the list, pinned literally, the status staying out. The
    /// `.sidebarSeparator` lead keeps its lists as they were: its bars are the test rigs', and keep the flexible space.
    /// Total failure prints: "the `.spacer` lead under <shape> / moduleName is […], not the pinned […]" /
    /// "the `.spacer` lead under <shape> / windowTitle is […], not the pinned […]".
    func testTheSpacerLeadIsTodaysListMinusItsSeparator() {
        for shape in Self.shapes {
            let m = SettingsToolbar.identifiers(content: shape.content, style: .moduleName, lead: .spacer)
            XCTAssertEqual(raw(m), raw(shape.spacerModuleName),
                           "the `.spacer` lead under \(shape.label) / moduleName is \(raw(m)), not the pinned \(raw(shape.spacerModuleName))")
            let t = SettingsToolbar.identifiers(content: shape.content, style: .windowTitle, lead: .spacer)
            XCTAssertEqual(raw(t), raw(shape.spacerWindowTitle),
                           "the `.spacer` lead under \(shape.label) / windowTitle is \(raw(t)), not the pinned \(raw(shape.spacerWindowTitle))")
            XCTAssertFalse(t.contains(Self.status), "the `.spacer` lead lists the status under \(shape.label) / windowTitle")
            XCTAssertFalse(t.contains(Self.sep) || m.contains(Self.sep),
                           "a bar led by `.spacer` carries the sidebar tracking separator under \(shape.label)")
        }
    }

    // MARK: - boundaries and hostile inputs

    /// `paneLeading + 16 <= itemsStart` reads 0: the boundary itself and below read 0, a hair over reads the hair.
    /// Total failure prints: "at paneLeading + 16 == itemsStart the inset is <x>, not 0" /
    /// "a quarter point past the boundary the inset is <x>, not 0.25" / "a quarter point before the boundary the inset is <x>".
    func testTheBoundaryPaneLeadingPlus16EqualsItemsStart() {
        let at = SettingsToolbar.nameInset(paneLeading: 76.5, itemsStart: 92.5)
        XCTAssertEqual(at, 0, accuracy: 0.0001, "at paneLeading + 16 == itemsStart the inset is \(at), not 0")
        let over = SettingsToolbar.nameInset(paneLeading: 76.75, itemsStart: 92.5)
        XCTAssertEqual(over, 0.25, accuracy: 0.0001, "a quarter point past the boundary the inset is \(over), not 0.25")
        let under = SettingsToolbar.nameInset(paneLeading: 76.25, itemsStart: 92.5)
        XCTAssertEqual(under, 0, accuracy: 0.0001, "a quarter point before the boundary the inset is \(under), not 0")
    }

    /// An inset is a finite number not below zero — never negative, infinite or not-a-number,
    /// whatever arrives, finite pairs whose difference overflows included; hostile inputs read 0.
    /// Total failure prints: "nameInset(paneLeading: <p>, itemsStart: <i>) answered <x>: a negative, infinite or not-a-number inset reaches the toolbar".
    func testNoInputMakesAnUnusableInset() {
        let hostile: [(CGFloat, CGFloat)] = [
            (-10, 92.5), (-.greatestFiniteMagnitude, 92.5), (0, 92.5),
            (.nan, 92.5), (200, .nan), (.nan, .nan),
            (.infinity, 92.5), (-.infinity, 92.5), (200, .infinity), (200, -.infinity),
            (200, -5), (200, 0), (0, 0), (-1, -1),
            // Both finite, the difference is not: 1e308 + 16 - (-1e308) overflows to +infinity.
            (.greatestFiniteMagnitude, -.greatestFiniteMagnitude), (1e308, -1e308),
        ]
        for (p, i) in hostile {
            let w = SettingsToolbar.nameInset(paneLeading: p, itemsStart: i)
            XCTAssertTrue(w.isFinite && w >= 0,
                          "nameInset(paneLeading: \(p), itemsStart: \(i)) answered \(w): a negative, infinite or not-a-number inset reaches the toolbar")
        }
        for p: CGFloat in [-10, 0, .nan, -.infinity] {
            XCTAssertEqual(SettingsToolbar.nameInset(paneLeading: p, itemsStart: 92.5), 0, accuracy: 0.0001,
                           "a pane leading of \(p) left of the buttons gets an inset instead of 0")
        }
        for p: CGFloat in [.greatestFiniteMagnitude, 1e308] {
            XCTAssertEqual(SettingsToolbar.nameInset(paneLeading: p, itemsStart: -.greatestFiniteMagnitude), 0, accuracy: 0.0001,
                           "a pair whose difference overflows (\(p)) gets a wide inset instead of 0")
        }
        XCTAssertEqual(SettingsToolbar.nameInset(paneLeading: 200, itemsStart: .nan), 0, accuracy: 0.0001,
                       "a not-a-number items start gets a number: the inset is a guess")
    }

    /// The sidebar's widest (`ShellGeometry.sidebarRange`, 320) is the sidebar's business, not this function's: 320 → 243.5, wider keeps growing, finite.
    /// Total failure prints: "a pane at 320 gets <x>, not 243.5" /
    /// "a pane wider than 320 (<p>) shrank or went non-finite: …".
    func testAPaneWiderThanTheMaximumStaysArithmetic() {
        let max = SettingsToolbar.nameInset(paneLeading: 320, itemsStart: 92.5)
        XCTAssertEqual(max, 243.5, accuracy: 0.0001, "a pane at 320 gets \(max), not 243.5")
        var last = max
        for p: CGFloat in [321, 400, 5000] {
            let w = SettingsToolbar.nameInset(paneLeading: p, itemsStart: 92.5)
            XCTAssertTrue(w.isFinite && w > last, "a pane wider than 320 (\(p)) shrank or went non-finite: \(w) after \(last)")
            last = w
        }
    }

    /// 200 → 123.5 holds on both sides of it: the inset is the pane leading plus 16 less the items' start, linear.
    /// Total failure prints: "the inset is not linear in the pane's leading edge: at <p> got <x>, want <y>".
    func testTheInsetFollowsThePaneOneForOne() {
        for (p, want) in [(150.0, 73.5), (200.0, 123.5), (250.0, 173.5)] as [(CGFloat, CGFloat)] {
            let w = SettingsToolbar.nameInset(paneLeading: p, itemsStart: 92.5)
            XCTAssertEqual(w, want, accuracy: 0.0001, "the inset is not linear in the pane's leading edge: at \(p) got \(w), want \(want)")
        }
    }

    /// A pane leading below zero is no position, however far left the items start: the arithmetic alone
    /// (-10 + 16 - (-200) = 206) would answer a width. Total failure prints:
    /// "a pane leading of <p> with items at <i> got a <w> pt inset".
    func testANegativePaneLeadingGetsNoInsetWhateverTheItemsStart() {
        for (p, i) in [(-10, -200), (-1, -1), (-0.5, -100), (-.greatestFiniteMagnitude, -.greatestFiniteMagnitude)] as [(CGFloat, CGFloat)] {
            let w = SettingsToolbar.nameInset(paneLeading: p, itemsStart: i)
            XCTAssertEqual(w, 0, accuracy: 0.0001, "a pane leading of \(p) with items at \(i) got a \(w) pt inset")
        }
    }

    // MARK: - a toolbar told where the pane is (no window)

    private func makeToolbar(lead: SettingsToolbar.Lead) -> SettingsToolbar {
        SettingsToolbar(model: SettingsModel(host: ModuleHost.shared),
                        channel: HelmWindowToolbarChannel(), lead: lead)
    }

    /// Total failure prints: "the list at sidebar 200 is […], not [name, flex, status]" / "the inset at sidebar 200 is <x>, not 123.5:
    /// the name does not land 16 pt past the pane's edge" / "the list moved when the pane went to the rail: a bar is rebuilt by a fold" /
    /// "an inset of <w> at the rail: the name lands past where the bar could put it".
    func testTheNamesInsetIsWhatThePaneLeavesAndTheListNeverMoves() {
        let toolbar = makeToolbar(lead: .spacer)
        toolbar.paneMoved(leading: 200, width: 856)
        let at200 = toolbar.barIdentifiers(content: nil, style: .moduleName)
        XCTAssertEqual(raw(at200), raw([Self.name, Self.flex, Self.status]), "the list at sidebar 200 is \(raw(at200)), not [name, flex, status]")
        XCTAssertEqual(toolbar.currentNameInset, 123.5, accuracy: 0.0001,
                       "the inset at sidebar 200 is \(toolbar.currentNameInset), not 123.5: the name does not land 16 pt past the pane's edge")
        toolbar.paneMoved(leading: 56, width: 1000)
        let at56 = toolbar.barIdentifiers(content: nil, style: .moduleName)
        XCTAssertEqual(raw(at56), raw(at200), "the list moved when the pane went to the rail: a bar is rebuilt by a fold; got \(raw(at56))")
        XCTAssertEqual(toolbar.currentNameInset, 0, accuracy: 0.0001,
                       "an inset of \(toolbar.currentNameInset) at the rail: the name lands past where the bar could put it")
    }

    /// Total failure prints: "a bar nobody told where the pane is holds an inset of <w>" (or reads another
    /// seed, or offers room before there is a pane).
    func testBeforeThePaneIsToldTheNameHasNoInsetAndStartsFromTheSeed() {
        let toolbar = makeToolbar(lead: .spacer)
        XCTAssertEqual(toolbar.currentNameInset, 0, accuracy: 0.0001,
                       "a bar nobody told where the pane is holds an inset of \(toolbar.currentNameInset)")
        XCTAssertEqual(toolbar.itemsStart, 92.5, accuracy: 0.0001,
                       "a bar nobody measured starts its items at \(toolbar.itemsStart), not at the seed 92.5")
        XCTAssertEqual(SettingsToolbar.itemsStartSeed, 92.5, accuracy: 0.0001,
                       "the seed is \(SettingsToolbar.itemsStartSeed), not 92.5")
        XCTAssertEqual(toolbar.offeredRoom(), 0, accuracy: 0.0001,
                       "a bar with no window and no pane offers room \(toolbar.offeredRoom()), not 0: the tabs unfold into room nobody measured")
    }

    /// Total failure prints: "the bar measures room <x>, not the pane's 856: the tabs unfold against the whole
    /// window, sidebar included".
    func testTheRoomIsThePaneOnceThePaneIsTold() {
        let toolbar = makeToolbar(lead: .spacer)
        toolbar.paneMoved(leading: 200, width: 856)
        XCTAssertEqual(toolbar.offeredRoom(), 856, accuracy: 0.0001,
                       "the bar measures room \(toolbar.offeredRoom()), not the pane's 856: the tabs unfold against the whole window, sidebar included")
        toolbar.paneMoved(leading: 56, width: 1000)
        XCTAssertEqual(toolbar.offeredRoom(), 1000, accuracy: 0.0001,
                       "the bar measures room \(toolbar.offeredRoom()), not the pane's 1000: the tabs unfold against the whole window, sidebar included")
    }

    /// Total failure prints: "a separator-led bar's list moved after paneMoved: the split rigs' bars would be
    /// rebuilt on every report" / "a separator-led bar holds an inset of <w>: the tracking separator places its name".
    func testTheSeparatorLedListIsTheSameWhateverItIsTold() {
        let toolbar = makeToolbar(lead: .sidebarSeparator)
        toolbar.paneMoved(leading: 200, width: 856)
        let list = toolbar.barIdentifiers(content: nil, style: .moduleName)
        XCTAssertEqual(raw(list), raw([Self.sep, Self.name, Self.flex, Self.status]),
                       "a separator-led bar's list moved after paneMoved: the split rigs' bars would be rebuilt on every report; got \(raw(list))")
        XCTAssertEqual(toolbar.currentNameInset, 0, accuracy: 0.0001,
                       "a separator-led bar holds an inset of \(toolbar.currentNameInset): the tracking separator places its name")
        XCTAssertEqual(toolbar.offeredRoom(), 856, accuracy: 0.0001,
                       "a separator-led bar measures room \(toolbar.offeredRoom()), not the pane's 856, once the pane is told")
    }

    /// Both signs of infinity are required: +infinity must not become the upper bound of a room.
    /// Total failure prints: "a pane width of <w> reads as room <x>: the tabs unfold into room nobody measured" /
    /// "a pane leading of <p> holds an inset of <w>: a position nobody measured moves the name".
    func testAPaneThatIsNotANumberIsNoRoomAndNoInset() {
        for width: CGFloat in [.nan, .infinity, -.infinity, -1] {
            let toolbar = makeToolbar(lead: .spacer)
            toolbar.paneMoved(leading: 200, width: width)
            XCTAssertEqual(toolbar.offeredRoom(), 0, accuracy: 0.0001,
                           "a pane width of \(width) reads as room \(toolbar.offeredRoom()): the tabs unfold into room nobody measured")
        }
        for leading: CGFloat in [.nan, .infinity, -.infinity, -1] {
            let toolbar = makeToolbar(lead: .spacer)
            toolbar.paneMoved(leading: leading, width: 856)
            XCTAssertEqual(toolbar.currentNameInset, 0, accuracy: 0.0001,
                           "a pane leading of \(leading) holds an inset of \(toolbar.currentNameInset): a position nobody measured moves the name")
        }
    }

    /// The second `.nan` pair is refused only when the comparison stands after the normalisation.
    /// Total failure prints: "the same pane was stored twice: every layout that moved nothing re-arms a settle".
    func testTheSamePaneToldTwiceIsRefused() {
        let toolbar = makeToolbar(lead: .spacer)
        XCTAssertTrue(toolbar.paneMoved(leading: 200, width: 856), "a first pane was not stored")
        XCTAssertFalse(toolbar.paneMoved(leading: 200, width: 856),
                       "the same pane was stored twice: every layout that moved nothing re-arms a settle")
        XCTAssertTrue(toolbar.paneMoved(leading: 200, width: 855),
                       "a pane whose width moved was refused: the bar keeps measuring the old room")
        let other = makeToolbar(lead: .spacer)
        other.paneMoved(leading: .nan, width: .nan)
        XCTAssertFalse(other.paneMoved(leading: .nan, width: .nan),
                       "the same pane was stored twice: not-a-number differs from itself, so every layout that moved nothing re-arms a settle")
    }

    /// A negative. Its positive pair is the first test of `TheBarTellsItsShellWhenItIsAttachedTests`.
    /// Total failure prints: "barAttached was called <n> times with no window: the shell is told of a toolbar
    /// nobody assigned".
    func testWithoutAWindowNoBarIsEverAttached() {
        var calls = 0
        let model = SettingsModel(host: ModuleHost.shared)
        let toolbar = SettingsToolbar(model: model,
                                      channel: HelmWindowToolbarChannel(), lead: .spacer,
                                      barAttached: { calls += 1 })
        model.selection = .about
        model.selection = .general
        toolbar.paneMoved(leading: 200, width: 856)
        toolbar.paneMoved(leading: 56, width: 1000)
        XCTAssertEqual(calls, 0,
                       "barAttached was called \(calls) times with no window: the shell is told of a toolbar nobody assigned")
    }

    /// Two toolbars over one model: where the pane is belongs to the toolbar that was told, not to the model
    /// they share. Total failure prints: "a pane told to one toolbar reached the other".
    func testTwoToolbarsOverOneModelKeepTheirOwnPane() {
        let model = SettingsModel(host: ModuleHost.shared)
        let first = SettingsToolbar(model: model, channel: HelmWindowToolbarChannel(), lead: .spacer)
        let second = SettingsToolbar(model: model, channel: HelmWindowToolbarChannel(), lead: .spacer)
        first.paneMoved(leading: 200, width: 856)
        model.selection = .about
        XCTAssertEqual(first.currentNameInset, 123.5, accuracy: 0.0001, "the toolbar that was told lost its inset: \(first.currentNameInset)")
        XCTAssertEqual(first.offeredRoom(), 856, accuracy: 0.0001, "the toolbar that was told lost its room: \(first.offeredRoom())")
        XCTAssertEqual(second.currentNameInset, 0, accuracy: 0.0001, "a pane told to one toolbar reached the other: it holds an inset of \(second.currentNameInset)")
        XCTAssertEqual(second.offeredRoom(), 0, "a pane told to one toolbar reached the other: room \(second.offeredRoom())")
        XCTAssertTrue(second.paneMoved(leading: 200, width: 856),
                      "the second toolbar refused a pane the first had stored: the last pane is shared")
    }

    // MARK: - what only a visible window can run, read from the source

    /// The code of one function of `SettingsToolbar.swift`, comments and strings gone, white space collapsed.
    private func collapsedBody(of name: String) throws -> String {
        let code = SwiftSource.code(try RepoSource.text(of: "Sources/HelmApp/SettingsToolbar.swift"))
        let bodies = SwiftSource.bodiesNamed(name, in: code)
        XCTAssertEqual(bodies.count, 1, "SettingsToolbar.swift declares \(bodies.count) functions named \(name), not one")
        return (bodies.first ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// A source reading, because the gate's `lead` half acts only where `isVisible` answers true, and the one test window wearing a `SettingsToolbar` that answers so (`ClaimedWindow`, `TheBarTellsItsShellWhenItIsAttachedTests`) is built on `.spacer` alone:
    /// under `.sidebarSeparator` an unshown window reads nothing either way. Total failure
    /// prints: "readItemsStart() does not open with the lead gate: <first 80 characters of its body>".
    func testReadItemsStartOpensWithTheLeadGateSoASeparatorLedBarIsNeverRead() throws {
        let body = try collapsedBody(of: "readItemsStart")
        XCTAssertTrue(body.hasPrefix("guard lead == .spacer, "),
                      "readItemsStart() does not open with the lead gate: \(body.prefix(80))")
    }
}
