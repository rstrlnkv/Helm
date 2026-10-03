import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The dot on the "System shortcuts" tab is up exactly while a box of ⇧⌘3 or ⇧⌘4 reads "Still on in macOS" — the
/// reading beside the one that offers "Use ⇧⌘3 and ⇧⌘4" — never together with that offer, and never over a reading nobody
/// made.** `ScreenshotsSettingsPage.holdsSystemKeys` and `offersToUseSystemKeys` are asked of every combination of the
/// states a capture box can be in (on, off, unknown, and no reading at all); then the page is mounted over a channel,
/// and what it *declares* to the window's toolbar is read — the tabs, which of them carries the dot, and the words the
/// dot says — and again after a new reading arrives without a remount, because a dot that stays after the boxes were
/// unticked is the page saying something the system no longer does.
///
/// Where a render cannot read: the segment's drawing is `TheSwitcherDrawsADotOnlyWhereAskedTests` (HelmUITests); the
/// folded switcher's menu is there too; the live bar belongs to `HelmApp`.
@MainActor
final class TheDotSaysWhatTheSystemTabSaysTests: XCTestCase {

    private var mount: MountedRender?

    override func tearDown() {
        mount?.drop()
        mount = nil
        AppLanguage.override = nil
        super.tearDown()
    }

    private let states: [BoxState?] = [.on, .off, .unknown, nil]

    private func reading(_ box: SystemBox, _ state: BoxState?) -> [SystemBoxReading] {
        guard let state else { return [] }
        return SystemShortcuts.boxes(from: .absent).filter { $0.box == box }.map {
            SystemBoxReading(box: $0.box, state: state, keyCode: $0.keyCode, modifiers: $0.modifiers)
        }
    }

    /// Every capture box in every state, and every box of the table in the states `absent` and `unreadable` read as.
    private func everyReading() -> [(label: String, boxes: [SystemBoxReading])] {
        var all: [(String, [SystemBoxReading])] = []
        let capture = SystemBox.capture
        XCTAssertEqual(capture.count, 2, "the subject: ⇧⌘3 and ⇧⌘4 are the two boxes the dot is about")
        for first in states {
            for second in states {
                all.append(("\(capture[0]) \(String(describing: first)) / \(capture[1]) \(String(describing: second))",
                            reading(capture[0], first) + reading(capture[1], second)))
            }
        }
        all.append(("absent", SystemShortcuts.boxes(from: .absent)))
        all.append(("unreadable", SystemShortcuts.boxes(from: .unreadable)))
        all.append(("nothing", []))
        let off = SystemShortcuts.boxes(from: .read(["28": ["enabled": false], "30": ["enabled": false]]))
        all.append(("both off", off))
        return all
    }

    // MARK: - The two expressions

    func testTheDotAndTheOfferAreNeverTrueTogetherAndTheDotIsOnlyWhatIsReadOn() {
        var sawDot = false, sawOffer = false, sawNeither = false
        for (label, boxes) in everyReading() {
            let dot = ScreenshotsSettingsPage.holdsSystemKeys(boxes)
            let offer = ScreenshotsSettingsPage.offersToUseSystemKeys(boxes)
            XCTAssertFalse(dot && offer, "\(label): the tab says «Still on in macOS» while the page offers to take the keys")
            let anyOn = SystemBox.capture.contains { box in boxes.first { $0.box == box }?.state == .on }
            XCTAssertEqual(dot, anyOn, "\(label): the dot is not «a capture box reads on»")
            sawDot = sawDot || dot; sawOffer = sawOffer || offer; sawNeither = sawNeither || (!dot && !offer)
        }
        XCTAssertTrue(sawDot && sawOffer && sawNeither, "the control: the sweep must come out dot, offer and neither (\(sawDot) \(sawOffer) \(sawNeither))")
    }

    func testAnUnknownAndAnEmptyReadingRaiseNoDot() {
        XCTAssertFalse(ScreenshotsSettingsPage.holdsSystemKeys([]), "no reading at all raised the dot")
        XCTAssertFalse(ScreenshotsSettingsPage.holdsSystemKeys(SystemShortcuts.boxes(from: .unreadable)), "an unreadable reading raised the dot")
        let onlyThePanel = SystemShortcuts.boxes(from: .absent).filter { $0.box == .panel }
        XCTAssertEqual(onlyThePanel.first?.state, .on, "the subject: box 184 on")
        XCTAssertFalse(ScreenshotsSettingsPage.holdsSystemKeys(onlyThePanel), "the panel's box is not ⇧⌘3 or ⇧⌘4")
    }

    // MARK: - What the page declares

    private func declare(_ boxes: [SystemBoxReading], language: AppLanguage = .en, tab: ScreenshotsSettingsPage.Tab = .capturing,
                         channel: HelmWindowToolbarChannel = HelmWindowToolbarChannel(),
                         transport: LocalTransport = LocalTransport()) -> (HelmWindowToolbarChannel, LocalTransport) {
        AppLanguage.override = language
        var state = ScreenshotsPageRender.untouched
        state.boxes = boxes
        transport.emit(ScreenshotsEvent.screenshotsState, encoding: state)
        let store = NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
        let mounted = MountedRender(
            ScreenshotsSettingsPage(vm: ModuleViewModel(transport: transport), store: store, tab: tab)
                .environment(\.helmGrants, HelmGrants(accessibility: .granted, fullDisk: .granted, screenRecording: .granted)),
            width: 744, height: 900, appearance: .aqua, channel: channel)
        mounted.settle(40)
        mount?.drop()
        mount = mounted
        return (channel, transport)
    }

    private func content(_ channel: HelmWindowToolbarChannel) throws -> HelmPageToolbarContent {
        try XCTUnwrap(channel.content(for: ScreenshotsDescriptor.id.rawValue), "the page declared nothing to the toolbar")
    }

    func testThreeTabsAndOnlyTheSystemOneCarriesTheDot() throws {
        for (label, boxes) in everyReading() {
            let (channel, _) = declare(boxes)
            let tabs = try content(channel).tabs
            XCTAssertEqual(tabs.map(\.id), ScreenshotsSettingsPage.Tab.allCases.map(\.rawValue), "\(label): the tabs are not the page's three in order")
            XCTAssertEqual(Set(tabs.map(\.id)).count, tabs.count)
            XCTAssertEqual(tabs.map(\.needsAttention), ScreenshotsSettingsPage.Tab.allCases.map { tab in
                tab == .system && ScreenshotsSettingsPage.holdsSystemKeys(boxes)
            }, "\(label): the dot is on the wrong tab or at the wrong time")
            for tab in tabs where !tab.needsAttention {
                XCTAssertNil(tab.attentionNote, "\(label): \(tab.id) carries a note without a dot")
            }
        }
    }

    /// The dot's words are the status the rows say, in the language the page is in.
    func testTheDotSaysWhatTheRowsSayInEveryLanguage() throws {
        AppLanguage.each { language in
            do {
                let (on, _) = declare(SystemShortcuts.boxes(from: .absent), language: language)
                let system = try XCTUnwrap(content(on).tabs.last)
                XCTAssertTrue(system.needsAttention, "\(language): the subject: the boxes are on and there is no dot")
                XCTAssertEqual(system.attentionNote, ScStr.stillOn, "\(language): the dot says another thing than the rows")
                XCTAssertFalse((system.attentionNote ?? "").isEmpty, "\(language)")
                XCTAssertEqual(ScreenshotsSettingsPage.say(.on), ScStr.stillOn, "\(language): the rows' own word moved")
                let (off, _) = declare(SystemShortcuts.boxes(from: .read(["28": ["enabled": false], "30": ["enabled": false]])), language: language)
                XCTAssertNil(try XCTUnwrap(content(off).tabs.last).attentionNote, "\(language): a note with no dot")
            } catch { XCTFail("\(language): \(error)") }
        }
    }

    /// A new reading arrives with no remount: the dot goes, and comes back, on the same declaration slot.
    func testTheDotGoesWhenTheBoxesAreUntickedAndComesBackWithoutAMount() throws {
        let on = SystemShortcuts.boxes(from: .absent)
        let off = SystemShortcuts.boxes(from: .read(["28": ["enabled": false], "30": ["enabled": false]]))
        let (channel, transport) = declare(on)
        func dot() throws -> Bool { try XCTUnwrap(content(channel).tabs.last).needsAttention }
        func say(_ boxes: [SystemBoxReading]) {
            var state = ScreenshotsPageRender.untouched
            state.boxes = boxes
            transport.emit(ScreenshotsEvent.screenshotsState, encoding: state)
            mount?.settle(40)
        }
        XCTAssertTrue(try dot(), "the subject: the dot is up while macOS holds the keys")
        say(off)
        XCTAssertFalse(try dot(), "the boxes were unticked and the dot stayed")
        say(on)
        XCTAssertTrue(try dot(), "the boxes were ticked again and the dot did not come back")
        say(SystemShortcuts.boxes(from: .unreadable))
        XCTAssertFalse(try dot(), "a reading nobody could make left the dot up")
        say(on)
        say([])
        XCTAssertFalse(try dot(), "an empty reading left the dot up")
    }

    /// One box on and one off: the dot says the one that is still held, and the offer is not made.
    func testOneBoxOnAndOneOffIsADotAndNoOffer() throws {
        let boxes = reading(SystemBox.capture[0], .on) + reading(SystemBox.capture[1], .off)
        XCTAssertEqual(boxes.count, 2, "the subject: two readings")
        let (channel, _) = declare(boxes)
        XCTAssertTrue(try XCTUnwrap(content(channel).tabs.last).needsAttention)
        XCTAssertFalse(ScreenshotsSettingsPage.offersToUseSystemKeys(boxes))
    }

    // MARK: - The tabs switch the body

    /// The switcher's binding moves the page between its three bodies; an id the page does not know moves nothing.
    func testTheSwitchersBindingMovesThePageAndAnUnknownIdMovesNothing() throws {
        let (channel, _) = declare(SystemShortcuts.boxes(from: .absent))
        func height() -> CGFloat { ScreenshotsPageRender.height(of: mount!) }
        let binding = try XCTUnwrap(content(channel).selectedTab, "no selected tab")
        XCTAssertEqual(binding.wrappedValue, ScreenshotsSettingsPage.Tab.capturing.rawValue, "the page opens on the first tab")
        var heights: [String: CGFloat] = [binding.wrappedValue: height()]
        for tab in ScreenshotsSettingsPage.Tab.allCases {
            binding.wrappedValue = tab.rawValue
            mount?.settle(30)
            let now = try XCTUnwrap(content(channel).selectedTab)
            XCTAssertEqual(now.wrappedValue, tab.rawValue, "\(tab): the selection did not move")
            heights[tab.rawValue] = height()
        }
        XCTAssertEqual(Set(heights.values.map { ($0 / 4).rounded() }).count, heights.count,
                       "two tabs drew bodies of one height: the switch moved nothing visible — \(heights)")
        let before = height()
        let current = try XCTUnwrap(content(channel).selectedTab).wrappedValue
        try XCTUnwrap(content(channel).selectedTab).wrappedValue = "no-such-tab"
        mount?.settle(30)
        XCTAssertEqual(try XCTUnwrap(content(channel).selectedTab).wrappedValue, current, "an unknown id moved the selection")
        XCTAssertEqual(height(), before, accuracy: 1, "an unknown id changed the body")
    }

    /// The tab the page opens on is the one named; the tab declared as selected is the tab drawn.
    func testEachTabOpensWhereItIsNamed() throws {
        for tab in ScreenshotsSettingsPage.Tab.allCases {
            let (channel, _) = declare(SystemShortcuts.boxes(from: .absent), tab: tab)
            XCTAssertEqual(try XCTUnwrap(content(channel).selectedTab).wrappedValue, tab.rawValue)
        }
    }
}
