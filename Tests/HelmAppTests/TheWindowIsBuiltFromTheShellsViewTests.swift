import AppKit
import Combine
import XCTest
import HelmTestSupport
import Module_KeepAwake_UI
@testable import HelmUI
@testable import HelmApp

/// **The settings window wears the shell: a card beside a column of rows, the
/// bar's first item over the card — not a split view with a section of switched
/// off modules.**
///
/// Two kinds of check. The first are readings of the source: the old
/// construction is gone, the new one is called, and the pieces that other guards
/// read as text are still where they read them. The second, under "What the
/// built window does", drive the real `SettingsWindow` and
/// `SettingsShellViewController` without ever ordering a window front: the weak
/// receiver, the report outside the layout pass, the sidebar's width and its one
/// hosting view, and a selection whose module goes off. `show(selecting:)` itself
/// orders the window front, so it is only read.
///
/// Every reading first asserts that it found its subject — a file that moved,
/// or a block whose opening line was renamed, fails here instead of reading
/// clean.
final class TheWindowIsBuiltFromTheShellsViewTests: XCTestCase {

    private struct Unbalanced: Error { let header: String }

    private let windowFile = "Sources/HelmApp/SettingsWindow.swift"

    private func windowCode() throws -> String {
        let code = SwiftSource.code(try RepoSource.text(of: windowFile))
        XCTAssertTrue(code.contains("final class SettingsModel"),
                      "\(windowFile) no longer holds SettingsModel — every reading below would be of the wrong file")
        return code
    }

    /// The text between the `{` that follows `header` and its match.
    private func block(after header: String, in code: String, from start: String.Index? = nil) throws -> Substring {
        let found = try XCTUnwrap(code.range(of: header, range: (start ?? code.startIndex)..<code.endIndex),
                                  "no `\(header)` to read a block from")
        let open = try XCTUnwrap(code[found.upperBound...].firstIndex(of: "{"), "`\(header)` opens no block")
        var depth = 0
        var index = open
        while index < code.endIndex {
            if code[index] == "{" { depth += 1 }
            if code[index] == "}" {
                depth -= 1
                if depth == 0 { return code[code.index(after: open)..<index] }
            }
            index = code.index(after: index)
        }
        throw Unbalanced(header: header)
    }

    // MARK: - What is gone

    func testTheWindowBuildsNoSplitView() throws {
        let code = try windowCode()
        for name in ["NSSplitView", "SettingsSplitViewController", "NSSplitViewItem"] {
            XCTAssertFalse(code.contains(name), """
                the window still builds a split view (`\(name)`): the page's name sits over a \
                system sidebar and the card shell is not what a person sees
                """)
        }
    }

    func testTheWindowDrawsNoSwitchedOffSection() throws {
        let code = try windowCode()
        XCTAssertFalse(code.contains("layout.off("), """
            the sidebar still lists switched-off modules in a section of their own: a module \
            that is off keeps a row and a door the shell has no place for
            """)
        XCTAssertFalse(code.contains("switchedOffSection"), """
            the window still names the Switched off section — the heading draws over the rows
            """)
        XCTAssertFalse(code.contains("SettingsSidebar"), "the old sidebar type is still in the window file")
    }

    func testTheLayoutHoldsNoDoorToAnOffModule() throws {
        let code = SwiftSource.code(try RepoSource.text(of: "Sources/HelmUI/SidebarLayout.swift"))
        XCTAssertTrue(code.contains("func live(in"),
                      "SidebarLayout lost `live(in:enabled:)` too — the half that stays")
        XCTAssertFalse(code.contains("off(enabled:"),
                       "SidebarLayout still answers which modules are off: nothing may draw them")
    }

    func testNoStringCarriesTheSwitchedOffHeading() throws {
        let strings = SwiftSource.uncommented(try RepoSource.text(of: "Sources/HelmApp/AppStrings.swift"))
        XCTAssertTrue(strings.contains("enum AppStr"), "AppStrings.swift is not the file it was")
        XCTAssertFalse(strings.contains("\"Switched off\""),
                       "AppStrings still asks for \"Switched off\": an orphan key in eight languages")

        let resources = RepoSource.root.appendingPathComponent("Sources/HelmUI/Resources")
        let folders = try FileManager.default.contentsOfDirectory(atPath: resources.path)
            .filter { $0.hasSuffix(".lproj") }.sorted()
        XCTAssertEqual(folders.count, 8, "the eight languages' folders were not all found: \(folders)")
        for folder in folders {
            let table = try RepoSource.text(of: "Sources/HelmUI/Resources/\(folder)/Localizable.strings")
            XCTAssertTrue(table.contains("\"Cancel\" ="), "\(folder) read as an empty table")
            XCTAssertFalse(table.contains("\"Switched off\" ="),
                           "\(folder) still translates \"Switched off\": a key nothing asks for")
        }
    }

    // MARK: - What is built

    func testTheWindowBuildsTheShellAndLeadsTheBarWithASpacer() throws {
        let code = try windowCode()
        XCTAssertTrue(code.contains("ShellContentView("), """
            the window never builds `ShellContentView`: the card, the corner and the sidebar's \
            frame are drawn by nobody
            """)
        XCTAssertTrue(code.contains("lead: .spacer"), """
            the bar is not told to lead with a spacer: the page's name sits over the sidebar, not \
            on the card
            """)
    }

    // MARK: - What a person's choice of a page goes through

    func testTheSelectionIsSettledWhereTheLiveModulesMoveAndWhereAPageIsShown() throws {
        let code = try windowCode()

        let show = try block(after: "func show(selecting", in: code)
        XCTAssertTrue(show.contains("ShellSidebarRows.settled("), """
            `show(selecting:)` hands a module's id to the model as it is: a module that is off \
            opens to a page with no row, and the sidebar highlights nothing
            """)

        let model = try block(after: "final class SettingsModel", in: code)
        XCTAssertTrue(model.contains("ShellSidebarRows.settled("), """
            the model never settles its selection when modules go off: switching the selected \
            module off leaves the pane on its page and the sidebar with no row to show it
            """)
        XCTAssertTrue(model.contains("$live"), """
            the model does not listen to the set of live modules: a module switched off \
            elsewhere changes nothing in the open window
            """)
    }

    func testNoViewPropertyWritesTheSelection() throws {
        let code = try windowCode()
        let property = try NSRegularExpression(pattern: #"var\s+\w+\s*:\s*some View"#)
        let write = try NSRegularExpression(pattern: #"\bselection\s*=[^=]"#)
        let whole = NSRange(code.startIndex..., in: code)
        var seen: [String] = []
        var readInContent = false
        for match in property.matches(in: code, range: whole) {
            let header = String(code[try XCTUnwrap(Range(match.range, in: code))])
            let inside = String(try block(after: header, in: code,
                                          from: try XCTUnwrap(Range(match.range, in: code)).lowerBound))
            seen.append(header)
            if header.contains("content") && inside.contains("settled(") { readInContent = true }
            XCTAssertNil(write.firstMatch(in: inside, range: NSRange(inside.startIndex..., in: inside)), """
                `\(header)` in \(windowFile) assigns `selection` while drawing: a state written \
                from a view property redraws the window in a loop
                """)
        }
        XCTAssertGreaterThanOrEqual(seen.count, 4, "the walk found almost no `some View` property: \(seen)")
        XCTAssertTrue(seen.contains { $0.contains("body") }, "no `var body: some View` was read: \(seen)")
        XCTAssertTrue(readInContent, """
            the known read of `settled(` in `content` was not seen: the walk reads the wrong block \
            (found \(seen))
            """)

        var calls = 0
        for file in try RepoSource.swiftFiles(under: "Sources/HelmApp") {
            calls += SwiftSource.callSites(of: "settled", in: SwiftSource.code(try RepoSource.text(of: file)),
                                           wholeWords: true).count
        }
        XCTAssertGreaterThanOrEqual(calls, 3, """
            nothing in the app calls `settled` besides its own declaration (found \(calls)): the \
            reading above found no body because there is no caller
            """)
    }

    // MARK: - What other guards read

    func testTheDetailPaneIsStillHostedAsTheOtherGuardsReadIt() throws {
        let code = try windowCode()
        let detail = try XCTUnwrap(code.range(of: "rootView: SettingsDetail(model: model)"),
                                   "the detail pane is no longer built from `SettingsDetail(model: model)`")
        let sizing = try XCTUnwrap(code.range(of: "detail.sizingOptions", range: detail.upperBound..<code.endIndex),
                                   "the detail hosting no longer sets `sizingOptions` after the root view")
        let between = code[detail.upperBound..<sizing.lowerBound]
        XCTAssertTrue(between.contains(".helmToolbarBackdrop()"),
                      "the pane lost its strip under the bar when the hosting was moved")
        XCTAssertTrue(between.contains("helmWindowToolbarChannel"),
                      "the pane no longer publishes into the channel the toolbar reads: no page names the window")
    }

    // MARK: - What the built window does

    private struct Built {
        let owner: SettingsWindow
        let window: NSWindow
        let model: SettingsModel
        let toolbar: SettingsToolbar
        var controller: SettingsShellViewController? { window.contentViewController as? SettingsShellViewController }
    }

    /// A real `SettingsWindow`, never ordered front, with the frame it autosaves put back afterwards.
    @MainActor private func built() throws -> Built {
        let frameKey = "NSWindow Frame HelmSettingsWindow.v4"
        let found = UserDefaults.standard.string(forKey: frameKey)
        let owner = SettingsWindow(host: ModuleHost.shared, band: .onMacOS(27))
        let fields = Mirror(reflecting: owner).children
        let window = try XCTUnwrap(fields.first { $0.label == "window" }?.value as? NSWindow,
                                   "SettingsWindow no longer holds `window` — this case reads it by name")
        let model = try XCTUnwrap(fields.first { $0.label == "model" }?.value as? SettingsModel,
                                  "SettingsWindow no longer holds `model` — this case reads it by name")
        let toolbar = try XCTUnwrap(fields.first { $0.label == "settingsToolbar" }?.value as? SettingsToolbar,
                                    "SettingsWindow no longer holds `settingsToolbar` — this case reads it by name")
        addTeardownBlock {
            UserDefaults.standard.set(found, forKey: frameKey)
            await MainActor.run { window.toolbar = nil }
        }
        return Built(owner: owner, window: window, model: model, toolbar: toolbar)
    }

    @MainActor private func bareController() -> SettingsShellViewController {
        let c = SettingsShellViewController(model: SettingsModel(host: ModuleHost.shared),
                                            toolbarChannel: HelmWindowToolbarChannel(), band: .onMacOS(27))
        c.loadViewIfNeeded()
        return c
    }

    /// The toolbar outlives the window and the controller; what it holds of the controller is nothing. (A window
    /// that is let go of while the owner lives keeps its content for reasons of its own, measured; one that is
    /// let go of with its owner does not, and a receiver that captured the controller would hold it.) Total failure
    /// prints: "the window's content is not the shell's controller" / "the window built no bar with a spacer: the
    /// fixture is wrong" / "the bar's receiver keeps the controller alive: it was still there after the window and
    /// its owner were gone" / "the toolbar refused a report after the controller was gone".
    @MainActor func testTheBarsReceiverDoesNotKeepTheControllerAlive() throws {
        let frameKey = "NSWindow Frame HelmSettingsWindow.v4"
        let found = UserDefaults.standard.string(forKey: frameKey)
        addTeardownBlock { UserDefaults.standard.set(found, forKey: frameKey) }
        weak var weakController: SettingsShellViewController?
        var toolbar: SettingsToolbar?
        try autoreleasepool {
            let owner = SettingsWindow(host: ModuleHost.shared, band: .onMacOS(27))
            let fields = Mirror(reflecting: owner).children
            let window = try XCTUnwrap(fields.first { $0.label == "window" }?.value as? NSWindow,
                                       "SettingsWindow no longer holds `window` — this case reads it by name")
            toolbar = try XCTUnwrap(fields.first { $0.label == "settingsToolbar" }?.value as? SettingsToolbar,
                                    "SettingsWindow no longer holds `settingsToolbar` — this case reads it by name")
            weakController = window.contentViewController as? SettingsShellViewController
            XCTAssertNotNil(weakController, "the window's content is not the shell's controller")
            XCTAssertTrue(toolbar?.hasSpacer == true, "the window built no bar with a spacer: the fixture is wrong")
            window.toolbar = nil
        }
        XCTAssertNil(weakController, """
            the bar's receiver keeps the controller alive: it was still there after the window and its \
            owner were gone
            """)
        XCTAssertEqual(toolbar?.paneMoved(leading: 0, width: 1000), true,
                       "the toolbar refused a report after the controller was gone")
    }

    /// A report that flips the bar puts a new bar on the window, which tells the shell. The shell is only asked
    /// for a layout: no card report is delivered inside the call, and the toolbar is told nothing, so the spacer
    /// the report took away does not come back from the shell's own, older, card. Total failure prints: "the
    /// fixture is wrong: …" / "the new bar's arrival did not ask the shell for a layout" / "the bar's arrival
    /// delivered <n> card reports inside the call" / "the bar's arrival put the spacer back: <w>".
    @MainActor func testTheBarsArrivalOnlyAsksForALayoutAndTellsTheToolbarNothing() throws {
        let b = try built()
        let c = try XCTUnwrap(b.controller, "the window's content is not the shell's controller")
        var frames: [CGRect] = []
        c.cardMoved = { frames.append($0) }
        let before = try XCTUnwrap(b.window.toolbar, "the fixture is wrong: the window has no bar")
        XCTAssertTrue(b.toolbar.hasSpacer, "the fixture is wrong: the bar has no spacer to lose")
        c.shell.layoutSubtreeIfNeeded()
        XCTAssertFalse(c.shell.needsLayout, "the fixture is wrong: the shell is still waiting for a layout")
        frames.removeAll()
        // The card is at 200; the toolbar is told 0, so the bar flips and a new one is taken.
        XCTAssertTrue(b.toolbar.paneMoved(leading: 0, width: 1060), "the fixture is wrong: the report was refused")
        let after = try XCTUnwrap(b.window.toolbar, "the fixture is wrong: the window lost its bar")
        XCTAssertFalse(before === after, "the fixture is wrong: the flip put no new bar on the window")
        XCTAssertTrue(c.shell.needsLayout, "the new bar's arrival did not ask the shell for a layout")
        XCTAssertEqual(frames.count, 0, "the bar's arrival delivered \(frames.count) card reports inside the call")
        XCTAssertFalse(b.toolbar.hasSpacer,
                       "the bar's arrival put the spacer back: \(String(describing: b.toolbar.leadingSpacer))")
    }

    /// Total failure prints: "the layout moved the card to <r>, not the 900 pt window's: the fixture is wrong" /
    /// "the layout pass told the toolbar <n> times: the report is made inside it" / "the delivery was <frames>, not the
    /// newest card alone" / "a second delivery repeated <frames>".
    @MainActor func testTheCardIsReportedAfterTheLayoutPassAndOnlyTheNewestOfIt() {
        let c = bareController()
        var frames: [CGRect] = []
        c.cardMoved = { frames.append($0) }
        c.shell.frame = CGRect(x: 0, y: 0, width: 1000, height: 700)
        c.shell.layoutSubtreeIfNeeded()
        c.shell.frame = CGRect(x: 0, y: 0, width: 900, height: 700)
        c.shell.layoutSubtreeIfNeeded()
        let expected = ShellGeometry.cardFrame(in: CGSize(width: 900, height: 700), sidebarWidth: 200)
        XCTAssertEqual(c.shell.card.frame, expected,
                       "the layout moved the card to \(c.shell.card.frame), not the 900 pt window's: the fixture is wrong")
        XCTAssertEqual(frames.count, 0, "the layout pass told the toolbar \(frames.count) times: the report is made inside it")
        c.deliverCard()
        XCTAssertEqual(frames, [expected], "the delivery was \(frames), not the newest card alone")
        c.deliverCard()
        XCTAssertEqual(frames, [expected], "a second delivery repeated \(frames)")
    }

    /// Total failure prints: "the sidebar opened <w> wide, not 200" / "the sidebar was <w> wide after folding (round <n>), not
    /// 56" / "the card started at <x> where the sidebar is <w>: the width did not reach the layout" / "the
    /// sidebar was <w> after unfolding (round <n>), not 200".
    @MainActor func testTheSidebarIsTwoHundredOrTheRailAndNothingBetween() {
        let c = bareController()
        c.shell.frame = CGRect(x: 0, y: 0, width: 1000, height: 700)
        XCTAssertEqual(c.shell.sidebarWidth, 200, "the sidebar opened \(c.shell.sidebarWidth) wide, not 200")
        for round in 1...3 {
            c.sidebarCollapsed = true
            c.shell.layoutSubtreeIfNeeded()
            XCTAssertEqual(c.shell.sidebarWidth, ShellGeometry.railWidth,
                           "the sidebar was \(c.shell.sidebarWidth) wide after folding (round \(round)), not 56")
            XCTAssertEqual(c.shell.card.frame.minX, ShellGeometry.railWidth,
                           "the card started at \(c.shell.card.frame.minX) where the sidebar is \(c.shell.sidebarWidth): the width did not reach the layout")
            c.sidebarCollapsed = false
            c.shell.layoutSubtreeIfNeeded()
            XCTAssertEqual(c.shell.sidebarWidth, 200,
                           "the sidebar was \(c.shell.sidebarWidth) after unfolding (round \(round)), not 200")
            XCTAssertEqual(c.shell.card.frame.minX, 200)
        }
    }

    /// Total failure prints: "the sidebar's view is not a child of the shell: the fixture is wrong" / "the
    /// language did not move: the fixture is wrong" / "the live set did not move: the fixture is wrong" / "the
    /// sidebar's hosting view was replaced by <what>: its permission states are asked again".
    @MainActor func testTheSidebarKeepsOneHostingViewAcrossASelectionALanguageAndTheLiveSet() throws {
        let model = SettingsModel(host: ModuleHost.shared)
        let c = SettingsShellViewController(model: model, toolbarChannel: HelmWindowToolbarChannel(), band: .onMacOS(27))
        c.loadViewIfNeeded()
        defer {
            ModuleHost.shared.shutdown()
            UserDefaults.standard.removeObject(forKey: "module.\(KeepAwakeDescriptor.id.rawValue).enabled")
        }
        XCTAssertEqual(c.children.count, 2, "the controller holds \(c.children.count) children, not the sidebar and the pane")
        let sidebar = try XCTUnwrap(c.children.first?.view)
        XCTAssertTrue(sidebar.superview === c.shell, "the sidebar's view is not a child of the shell: the fixture is wrong")
        let revision = model.languageRevision
        let id = KeepAwakeDescriptor.id.rawValue

        model.selection = .about
        model.selection = .log
        NotificationCenter.default.post(name: .helmLanguageChanged, object: nil)
        XCTAssertGreaterThan(model.languageRevision, revision, "the language did not move: the fixture is wrong")
        ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), true)
        XCTAssertNotNil(ModuleHost.shared.live[id], "the live set did not move: the fixture is wrong")
        ModuleHost.shared.setEnabled(KeepAwakeDescriptor(), false)
        XCTAssertNil(ModuleHost.shared.live[id], "the live set did not move back: the fixture is wrong")
        c.sidebarCollapsed = true
        c.sidebarCollapsed = false
        c.shell.layoutSubtreeIfNeeded()

        XCTAssertTrue(c.children.first?.view === sidebar, """
            the sidebar's hosting view was replaced by \(String(describing: c.children.first?.view)): \
            its permission states are asked again
            """)
        XCTAssertTrue(sidebar.superview === c.shell, "the sidebar's view left the shell")
    }

    /// Total failure prints: "the fixture is wrong: …" / "the selection is <s> as the call returns, not General: the
    /// page stayed on a module with no row".
    @MainActor func testSwitchingTheSelectedModuleOffLandsOnGeneralBeforeTheCallReturns() throws {
        let host = ModuleHost.shared
        let id = KeepAwakeDescriptor.id.rawValue
        host.shutdown()
        defer {
            host.shutdown()
            UserDefaults.standard.removeObject(forKey: "module.\(id).enabled")
        }
        host.setEnabled(KeepAwakeDescriptor(), true)
        let model = SettingsModel(host: host)
        model.selection = .module(id)
        XCTAssertEqual(model.selection, .module(id), "the fixture is wrong: the module was not left selected")
        XCTAssertTrue(host.enabledModuleIDs.contains(id), "the fixture is wrong: the module is not on")

        // Nothing turns the run loop between the call and the reading: a deferred settle would not be in time.
        host.setEnabled(KeepAwakeDescriptor(), false)
        XCTAssertFalse(host.enabledModuleIDs.contains(id), "the fixture is wrong: the module is still on")
        XCTAssertEqual(model.selection, .general, "the selection is \(String(describing: model.selection)) as the call returns, not General: the page stayed on a module with no row")
    }
}
