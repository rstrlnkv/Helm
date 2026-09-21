import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **A placeholder is not a name, and this control has nothing else.**
///
/// The two search bars are one control now — SwiftUI's `.searchable`, bridged
/// into the settings window's toolbar (`helmSearchable`). The prompt survives
/// that bridge whole; the name does not exist to survive. Measured on macOS 27
/// (2026-09-20) on the mounted `AppKitSearchField`: `accessibilityLabel()` nil
/// and `accessibilityTitle()` nil in every state, and a SwiftUI
/// `.accessibilityLabel` on the searchable view does not reach it at all, since
/// the field is AppKit's and is not in that view's tree. `ToolbarSearchName` is
/// what puts the name back, and this reads it off the control.
///
/// **This file moved out of `Tests/HelmUITests` with the control it watches.**
/// It used to mount `HelmSearchField` — an `NSViewRepresentable` — and read the
/// label off the one `NSSearchField` in `mount.host`. Nothing mounts that type
/// any more, so the same file left where it was would have been a green test
/// standing over something nobody draws. It is here because the name is set
/// here: the field is built by the bridge and named from the app layer, and a
/// test in the UI target cannot see either half.
///
/// **Why the readings are off a mounted window and not off a notification.**
/// The label has to survive the bridge, the toolbar and a page change, and only
/// the control can say whether it did. The states below are the ones a person
/// meets: the field open and empty — this file's own bare fixture (a
/// `ToolbarSpacer` and the search item, nothing else in the toolbar) rests
/// open at the window's default width, since `ToolbarSearchName` pins no
/// resting width any more and leaves AppKit's own leftover-room decision be —
/// the field collapsed, forced there directly the way
/// `TheSearchFieldRestsNarrowerAndWidensOnFocusTests`'s floor case forces it,
/// since reaching collapse honestly needs a crowded toolbar and this file's is
/// deliberately bare — and, once a click has opened it
/// (`beginSearchInteraction()`), the field with a word in it. Collapse itself
/// cannot be asked for or refused by this code on macOS
/// (`SearchToolbarBehavior.minimize` is `@available(macOS, unavailable)`); it
/// is read off `NSSearchField.isHidden` because there is no `isCollapsed` to
/// ask, whichever put it there.
@MainActor
final class ASearchFieldSaysWhatItIsTests: XCTestCase {

    /// A pane with the settings window's own bridge on it, carrying a
    /// `.searchable` under a gate the way both pages carry theirs.
    private final class Page: ObservableObject {
        @Published var searching = true
        @Published var text = ""
    }

    private struct Pane: View {
        @ObservedObject var page: Page
        var body: some View {
            VStack(spacing: 0) {
                if page.searching {
                    Color.clear.frame(height: 0)
                        .helmSearchable(text: Binding(get: { page.text },
                                                      set: { page.text = $0 }),
                                        prompt: "Search apps")
                }
                Text("the list").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Every settings page has one, and a page without it drops the
            // window's toolbar altogether (`SettingsSplitViewController`).
            .toolbar { ToolbarSpacer(.fixed, placement: .navigation) }
        }
    }

    /// The window, its bridge and the namer, wired the way `SettingsWindow`
    /// wires them — the namer built **before** the first turn of the run loop,
    /// because the first item arrives on that turn.
    @MainActor
    private final class Mount {
        let window: NSWindow
        let page = Page()
        let name: ToolbarSearchName?
        private let controller: NSHostingController<Pane>

        /// `naming: false` builds the window with **no** namer of its own,
        /// which is the only way to ask whether somebody else named its field
        /// — see `testANamerLeavesEveryOtherWindowsSearchFieldAlone`. A window
        /// whose namer merely pointed somewhere else would be a fixture making
        /// its own subject unrepresentable, so there is genuinely none.
        init(width: CGFloat, naming: Bool = true) {
            controller = NSHostingController(rootView: Pane(page: page))
            controller.sceneBridgingOptions = [.toolbars]
            controller.sizingOptions = []
            window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
            window.setContentSize(NSSize(width: width, height: 700))
            window.appearance = NSAppearance(named: .aqua)
            name = naming ? ToolbarSearchName(namingIn: window) : nil
        }

        func settle(_ turns: Int = 20) {
            for _ in 0..<turns {
                window.contentView?.layoutSubtreeIfNeeded()
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            }
        }

        var field: NSSearchField? {
            (window.toolbar?.items ?? []).compactMap { $0 as? NSSearchToolbarItem }
                .first?.searchField
        }

        /// **Whether AppKit has collapsed the control to its magnifier.**
        ///
        /// There is no `isCollapsed` to ask and no `SearchToolbarBehavior` to
        /// set — `minimize` is `@available(macOS, unavailable)` — so the state
        /// is read off what AppKit did to the views. Measured on macOS 27
        /// (2026-09-20) in this fixture: expanded, the `AppKitSearchField` is
        /// 325 pt wide and visible and the `NSButton` beside it under
        /// `NSSearchToolbarItemView` is hidden; collapsed, the field is 36 pt
        /// and **hidden** and that button is the visible one. `isHidden` on the
        /// field is therefore the crossing itself and not a proxy for it.
        var collapsed: Bool { field?.isHidden ?? false }

        /// Forces the field under AppKit's own 160 pt floor directly, the way
        /// `TheSearchFieldRestsNarrowerAndWidensOnFocusTests`'s floor case
        /// does — this file's own fixture is bare (a `ToolbarSpacer` and the
        /// search item, nothing else) and rests open at any width the window
        /// can reach, so a case that needs the collapsed state has to make it
        /// rather than find it.
        func forceCollapsed() {
            guard let field else { return }
            field.constraints
                .filter { $0.firstItem === field && $0.firstAttribute == .width }
                .forEach { $0.isActive = false }
            field.widthAnchor.constraint(equalToConstant: 40).isActive = true
            settle(15)
        }

        func drop() { window.contentViewController = nil }
    }

    private var mounts: [Mount] = []

    override func tearDown() {
        mounts.forEach { $0.drop() }
        mounts = []
        super.tearDown()
    }

    /// The window's own default width, so a reading is taken at the size the
    /// app actually opens at rather than at one chosen to make a number come
    /// out. Read from the window rather than spelled again.
    private func mounted(width: CGFloat = SettingsWindow.defaultSize.width) -> Mount {
        let mount = Mount(width: width)
        mounts.append(mount)
        mount.settle()
        return mount
    }

    /// The bridged field, or a failure saying there is nothing to read a name
    /// off — never nil quietly. A walk that found no control would satisfy an
    /// assertion on an optional chain by never running.
    private func field(_ mount: Mount, _ what: String,
                       file: StaticString = #filePath, line: UInt = #line) -> NSSearchField? {
        guard let field = mount.field else {
            XCTFail("""
                \(what): the toolbar holds no search field at all, so there is nothing here \
                whose name could be read. Either `helmSearchable` stopped reaching the window's \
                toolbar or the bridge stopped publishing the item
                """, file: file, line: line)
            return nil
        }
        return field
    }

    /// **Empty, at rest — open, in this file's bare fixture at the window's
    /// own default width.** Nothing here pins a resting width any more
    /// (`ToolbarSearchName.size(_:)`), so a toolbar with nothing else in it
    /// rests open; a real page's own field can rest collapsed instead, which
    /// is `testTheCollapsedControlsFieldHasAName` below.
    func testAnEmptyFieldHasAName() throws {
        let mount = mounted()
        XCTAssertFalse(mount.collapsed, """
            precondition: the control is collapsed at \(SettingsWindow.defaultSize.width) pt, \
            the window's own default width, in a toolbar with nothing else in it — this fixture \
            is not reaching the state this case means to read
            """)
        let field = try XCTUnwrap(field(mount, "collapsed and empty"))
        XCTAssertEqual(field.placeholderString, "Search apps",
                       "precondition: the prompt did not survive the bridge")
        XCTAssertEqual(field.accessibilityLabel(), HelmA11y.searchField, """
            the search field is read aloud with no name. AppKit gives the bridged \
            `NSSearchField` none of its own, so whatever `ToolbarSearchName` does not set is \
            not set
            """)
    }

    /// **And with a value in it, which is the half the prompt never covered.**
    /// This is the state the defect was about: the prompt is gone from the
    /// screen and from the accessibility tree the moment somebody types.
    /// Typing opens the control (`beginSearchInteraction()` is what a click
    /// on the magnifier does), so this reading is taken after that rather
    /// than pretending a person can type into a field still resting collapsed.
    func testAFieldWithSomethingInItStillHasAName() throws {
        let mount = mounted()
        guard let item = mount.window.toolbar?.items.compactMap({ $0 as? NSSearchToolbarItem }).first
        else {
            XCTFail("no search item in the toolbar")
            return
        }
        item.beginSearchInteraction()
        mount.settle(20)
        let field = try XCTUnwrap(field(mount, "open with text"))
        field.stringValue = "wget"
        NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: field)
        mount.settle(10)
        XCTAssertEqual(mount.page.text, "wget", "precondition: the value never reached the binding")
        XCTAssertEqual(field.accessibilityLabel(), HelmA11y.searchField, """
            the field has a value and no name — which is the defect, since a prompt is what \
            AppKit drops first
            """)
    }

    /// **Collapsed, forced directly under AppKit's own 160 pt floor** — this
    /// file's own fixture is bare and rests open at any width the window can
    /// reach, so this case makes the collapsed state itself rather than
    /// finding it, the way `TheSearchFieldRestsNarrowerAndWidensOnFocusTests`'s
    /// floor case does. What is asserted is that the field a click opens
    /// carries the name **before** anybody clicks, not only after.
    func testTheCollapsedControlsFieldHasAName() throws {
        let mount = mounted()
        mount.forceCollapsed()
        XCTAssertTrue(mount.collapsed, """
            precondition: the control is still open after forcing its width under 160 pt — \
            AppKit's own floor has moved, and this file's forcing needs to move with it
            """)

        let field = try XCTUnwrap(field(mount, "collapsed"))
        XCTAssertEqual(field.accessibilityLabel(), HelmA11y.searchField, """
            the control's magnifier opens onto a field with no name — the system names the \
            button and nothing names what it opens
            """)
    }

    /// **And narrowing an already-named, already-collapsed control must not
    /// lose the name.**
    ///
    /// The collapse itself is forced the same way `testTheCollapsedControlsFieldHasAName`
    /// forces it, and what is worth proving is that a resize while already
    /// collapsed is not a silent rebuild. Measured, the same `NSSearchField`
    /// object survives a resize either way, so no `willAddItem` fires and
    /// nothing calls `nameWhatIsThere` — if AppKit ever started rebuilding the
    /// item on a resize instead, the name would go with the old one and there
    /// is no channel that would notice.
    func testTheNameSurvivesTheWindowBeingResizedWhileCollapsed() throws {
        let mount = mounted()
        mount.forceCollapsed()
        let before = try XCTUnwrap(field(mount, "before resizing"))
        XCTAssertTrue(mount.collapsed, """
            precondition: the control is still open after forcing its width under 160 pt, so \
            this case does not start from the state it means to read
            """)

        mount.window.setContentSize(NSSize(width: Self.collapsing, height: 700))
        mount.settle()

        XCTAssertTrue(mount.collapsed, """
            precondition: the control opened back up at \(Self.collapsing) pt — the forced \
            width constraint did not survive the resize
            """)
        let after = try XCTUnwrap(field(mount, "after resizing"))
        // Which of the two it is decides where the repair goes, so the message
        // says it rather than leaving the next reader to measure it again.
        let same = after === before
            ? "It is the same object, so something cleared the label."
            : "AppKit rebuilt the field on a plain resize, and no channel here names a field "
                + "that arrives without a `willAddItem`."
        XCTAssertEqual(after.accessibilityLabel(), HelmA11y.searchField, """
            the control lost its name across a resize. \(same)
            """)
    }

    /// **A page change builds a new field, and the name has to be on that
    /// one.** Measured: switching away from a page that searches and back gives
    /// a different `NSSearchField` object every time, so a name set once at
    /// window setup is a name on an object nobody will ever see again.
    func testTheNameSurvivesAPageChange() throws {
        let mount = mounted()
        let first = try XCTUnwrap(field(mount, "before the page change"))
        mount.page.searching = false
        mount.settle()
        XCTAssertNil(mount.field, """
            precondition: the control stayed in the toolbar after the page stopped asking for \
            it, so this test never sees a rebuilt field and proves nothing
            """)
        mount.page.searching = true
        mount.settle()
        let second = try XCTUnwrap(field(mount, "after the page change"))
        XCTAssertFalse(first === second, """
            precondition: the same field came back, so this test would pass over a one-off \
            naming — the thing it exists to catch
            """)
        XCTAssertEqual(second.accessibilityLabel(), HelmA11y.searchField, """
            the field the toolbar built for the page it came back to has no name: the name was \
            set once, on an object that is gone
            """)
    }

    /// **The app's language changes while it runs**, and the name is a string
    /// in it. The field is not rebuilt by the change, so the name has to be
    /// re-read — which is the reason `HelmSearchField` re-read it beside the
    /// placeholder rather than setting it in `makeNSView`.
    func testTheNameIsInTodaysLanguage() throws {
        let mount = mounted()
        _ = try XCTUnwrap(field(mount, "before the language change"))
        AppLanguage.each { language in
            mount.name?.nameWhatIsThere()
            XCTAssertEqual(mount.field?.accessibilityLabel(), HelmA11y.searchField,
                           "\(language.rawValue): the field answers in another language")
        }
    }

    /// **A narrower width, to resize into.** The collapse itself is forced
    /// directly (`Mount.forceCollapsed`) rather than read off this width, so
    /// what this constant has to be is only visibly different from the
    /// window's own default — so `testTheNameSurvivesTheWindowBeingResizedWhileCollapsed`
    /// is reading an actual resize and not the same width read twice.
    private static let collapsing: CGFloat = 300

    /// **The language changes while the app runs, and the name is a string in
    /// it — over the notice, not over a direct call.**
    ///
    /// `testTheNameIsInTodaysLanguage` calls `nameWhatIsThere` itself, so it
    /// proves the walk answers in today's language and nothing about how the
    /// walk is reached. Delete `ToolbarSearchName`'s registration for
    /// `.helmLanguageChanged` and that case stays green while every open search
    /// field goes on announcing itself in the language the page was last built
    /// in. This one posts the notice.
    ///
    /// **With a word in the field**, which is the state the change is most
    /// likely to be made in and the state where the prompt — the only other
    /// thing carrying the word — is already gone.
    func testTheNoticeOfALanguageChangeReachesTheMountedField() throws {
        let mount = mounted()
        let field = try XCTUnwrap(field(mount, "before the language change"))
        field.stringValue = "wget"
        NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: field)
        mount.settle(10)
        XCTAssertEqual(mount.page.text, "wget", "precondition: the value never reached the binding")

        // A name that is neither the app's nor nil, so «nothing happened» and
        // «it was re-read» are two different readings rather than one.
        field.setAccessibilityLabel("a name from the language before")
        NotificationCenter.default.post(name: .helmLanguageChanged, object: nil)
        mount.settle(5)

        XCTAssertEqual(field.accessibilityLabel(), HelmA11y.searchField, """
            the app changed language and the field kept \
            «\(field.accessibilityLabel() ?? "no name at all")». Nothing rebuilds this control \
            on a language change — it is AppKit's, built by the bridge — so the only thing that \
            can re-read the name is the notice, and it is not connected
            """)
        XCTAssertEqual(field.stringValue, "wget", """
            the language change emptied what somebody had typed. The name is the only thing \
            that was supposed to move
            """)
    }

    /// **Another window's toolbar is not this one's business.**
    ///
    /// The namer registers for `willAddItem` with `object: nil`, because at the
    /// moment it is built its window has no toolbar to register against — so
    /// every search item added to **any** toolbar in the process is delivered
    /// to it, and the only thing keeping it off somebody else's control is the
    /// identity check at delivery. The app has one settings window today; it
    /// also has a panel, and a second window carrying a bridged page is one
    /// feature away.
    ///
    /// The second window is mounted **without a namer of its own**, which is
    /// the whole point: with one, both fields end up named and the check passes
    /// whatever the first namer did.
    func testANamerLeavesEveryOtherWindowsSearchFieldAlone() throws {
        let mine = mounted()
        _ = try XCTUnwrap(field(mine, "this window"))

        let stranger = Mount(width: SettingsWindow.defaultSize.width, naming: false)
        mounts.append(stranger)
        stranger.settle()
        let other = try XCTUnwrap(stranger.field, """
            the second window put no search field in its toolbar, so there is nothing here that \
            could be named by mistake and this case proves nothing
            """)

        XCTAssertNil(other.accessibilityLabel(), """
            a window with no `ToolbarSearchName` of its own came up with «\
            \(other.accessibilityLabel() ?? "")» on its search field. Either AppKit names the \
            bridged field after all — in which case `ToolbarSearchName` is unnecessary and every \
            case in this file passes without it — or the other window's namer reached across \
            and wrote it
            """)

        // And it stays alone through the one event the namer listens for: an
        // item joining a toolbar. Rebuilding the stranger's item delivers a
        // `willAddItem` to *this* window's namer, with a toolbar that is not
        // its window's.
        stranger.page.searching = false
        stranger.settle()
        stranger.page.searching = true
        stranger.settle()
        mine.name?.nameWhatIsThere()

        XCTAssertNil(stranger.field?.accessibilityLabel(), """
            the second window's search field was rebuilt and this window's namer named it — \
            «\(stranger.field?.accessibilityLabel() ?? "")». The notice carries every toolbar in \
            the process, so the check at delivery is the only thing that scopes it
            """)
        XCTAssertEqual(mine.field?.accessibilityLabel(), HelmA11y.searchField, """
            this window's own field lost its name while the second window's was being rebuilt
            """)
    }

    /// **The name is not the role said twice.**
    ///
    /// VoiceOver announces the role itself, so a label reading "search field"
    /// comes out as "search field search field". The word is macOS's own for
    /// this control, and it is checked in every language rather than in
    /// whichever one this Mac is set to — this machine runs in Russian, so a
    /// bare assertion exercises one of eight.
    func testTheNameIsAWordAndNotTheRole() {
        AppLanguage.each { language in
            let name = HelmA11y.searchField
            XCTAssertFalse(name.isEmpty, "\(language.rawValue): the search field's name is empty")
            XCTAssertFalse(name.lowercased().contains("field"),
                           "\(language.rawValue): «\(name)» says the role VoiceOver already says")
        }
    }
}
