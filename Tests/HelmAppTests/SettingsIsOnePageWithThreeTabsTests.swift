import SwiftUI
import XCTest
@testable import HelmRuntime
import HelmTestSupport
import HelmUI
@testable import HelmApp

/// Settings is one page with three tabs: General, Log and About each carry the
/// same three tabs in the window's toolbar, a tab press writes the selection,
/// and all three pages are named Settings.
///
/// **Nothing here opens a window.** The tabs are a value (`SettingsTabs`), the
/// selection they write is a binding over a plain variable, and what a source
/// reading can say — which page hands the tabs to which, which name a page
/// publishes — is read from the files. That the switcher stands still across the
/// three bars, and that the swap between two bars is a cut, is for a photograph.
final class SettingsIsOnePageWithThreeTabsTests: XCTestCase {

    /// What every failure below means when the whole mechanism is missing.
    private static let nothing = "the Settings page has no tabs: General, Log and About are not one page"

    override func tearDown() {
        AppLanguage.override = nil
        super.tearDown()
    }

    /// A selection held in a box, and the binding over it the page would hold.
    private final class Held {
        var selection: SettingsSelection?
        init(_ selection: SettingsSelection?) { self.selection = selection }
        var binding: Binding<SettingsSelection?> {
            Binding(get: { self.selection }, set: { self.selection = $0 })
        }
    }

    // MARK: - The press

    @MainActor
    func testAPressedTabChangesThePage() {
        let held = Held(.general)
        let tabs = SettingsTabs.binding(held.binding)

        XCTAssertEqual(SettingsTabs.all.map(\.id), ["general", "log", "about"], Self.nothing)

        held.selection = .log
        XCTAssertEqual(tabs.wrappedValue, "log", Self.nothing)
        held.selection = .about
        XCTAssertEqual(tabs.wrappedValue, "about", Self.nothing)

        tabs.wrappedValue = "about"
        XCTAssertEqual(held.selection, .about, Self.nothing)
        tabs.wrappedValue = "log"
        XCTAssertEqual(held.selection, .log, Self.nothing)
        tabs.wrappedValue = "general"
        XCTAssertEqual(held.selection, .general, Self.nothing)

        // Written, not merely read: the press took effect on the selection, so a
        // reader of the same binding sees it too.
        XCTAssertEqual(tabs.wrappedValue, "general", Self.nothing)
    }

    @MainActor
    func testAStringThatIsNoTabWritesNothing() {
        for unknown in ["nonsense", "", "Log", "LOG", " about", "module"] {
            for start: SettingsSelection? in [.log, .about, .general, .module("disk"), nil] {
                let held = Held(start)
                SettingsTabs.binding(held.binding).wrappedValue = unknown
                XCTAssertEqual(held.selection, start,
                               "writing \"\(unknown)\" over \(String(describing: start)) moved the selection")
            }
        }
    }

    @MainActor
    func testAModuleSelectionReadsGeneral() {
        for start: SettingsSelection? in [.module("disk"), .module(""), .module("no-such-module"), nil] {
            let held = Held(start)
            XCTAssertEqual(SettingsTabs.binding(held.binding).wrappedValue, "general",
                           "\(String(describing: start)): \(Self.nothing)")
        }
    }

    @MainActor
    func testTheBindingFollowsTheSelectionAfterItWasMade() {
        // A binding that copied the selection when it was built would read the
        // first value forever.
        let held = Held(.general)
        let tabs = SettingsTabs.binding(held.binding)
        for (selection, id) in [(SettingsSelection.about, "about"), (.log, "log"), (.general, "general")] {
            held.selection = selection
            XCTAssertEqual(tabs.wrappedValue, id)
        }
    }

    // MARK: - The tabs

    @MainActor
    func testTheTabsAreGeneralLogAboutAndNameThemselvesInEveryLanguage() {
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            let tabs = SettingsTabs.all
            XCTAssertEqual(tabs.map(\.id), ["general", "log", "about"], "\(language.rawValue): \(Self.nothing)")
            // Log and About are the strings those pages already go by.
            XCTAssertEqual(tabs[1].title, AppStr.logPane, language.rawValue)
            XCTAssertEqual(tabs[2].title, AppStr.aboutHelm, language.rawValue)
            XCTAssertEqual(tabs[0].title, AppStr.settingsTabGeneral, language.rawValue)
            for tab in tabs {
                XCTAssertFalse(tab.title.isEmpty, "\(language.rawValue): tab \(tab.id) has no title")
                XCTAssertFalse(tab.symbol.isEmpty, "\(language.rawValue): tab \(tab.id) has no glyph")
            }
            XCTAssertEqual(Set(tabs.map(\.title)).count, 3, "\(language.rawValue): two tabs share a title")
        }
    }

    /// The first tab's title is a key of its own: the existing «General» is a
    /// glyph category's name, a different meaning, and the strings table is
    /// keyed by English.
    @MainActor
    func testTheFirstTabsTitleIsNotTheGlyphCategorysGeneral() {
        AppLanguage.override = .en
        XCTAssertNotEqual(AppStr.settingsTabGeneral, "General")
        XCTAssertNotEqual(AppStr.settingsTabGeneral, L("General"))
        XCTAssertNotEqual(AppStr.settingsTabGeneral, AppStr.settingsPane,
                          "the first tab must not read as the page's own name")
        XCTAssertEqual(SettingsTabs.all.first?.title, AppStr.settingsTabGeneral)
    }

    // MARK: - The Log page

    /// Built with no tabs handed — `command grep -rlE '\bLogView\(' Tests` lists
    /// who does — the page has none, and its toolbar content is what it always was.
    @MainActor
    func testTheLogPageBuiltWithNoTabsHasNone() throws {
        XCTAssertNil(LogView().settingsTabs, Self.nothing)

        let source = SwiftSource.uncommented(try RepoSource.text(of: "Sources/HelmApp/LogView.swift"))
        XCTAssertTrue(source.contains("var settingsTabs"),
                      "LogView takes its tabs as a stored parameter named settingsTabs")
        let content = try XCTUnwrap(SwiftSource.body(of: "toolbarContent", in: source),
                                    "LogView has no toolbarContent")
        XCTAssertTrue(content.contains("settingsTabs"),
                      "the handed tabs never reach the page's toolbar content: \(Self.nothing)")
    }

    // MARK: - The Log bar with and without the tabs

    /// `toolbarContent` is private and needs a built page, so it cannot be
    /// called from here; what it does is read from the file, by the function
    /// that does each part.
    private func logBodies() throws -> (content: String, level: String, plain: String, source: String) {
        let source = SwiftSource.uncommented(try RepoSource.text(of: "Sources/HelmApp/LogView.swift"))
        func one(_ name: String) throws -> String {
            let found = SwiftSource.bodiesNamed(name, in: source)
            XCTAssertEqual(found.count, 1, "\(name) is not one declaration any more")
            return try XCTUnwrap(found.first, "LogView has no \(name)")
        }
        // `levelAction` is a computed property, which the function walk does not
        // list: it is the text between its declaration and the next function.
        let start = try XCTUnwrap(source.range(of: "var levelAction: HelmToolbarAction {"), "LogView has no levelAction")
        let end = try XCTUnwrap(source.range(of: "func levelToolbarContent", range: start.upperBound..<source.endIndex),
                                "levelToolbarContent is not declared after levelAction")
        let action = String(source[start.upperBound..<end.lowerBound])
        return (try one("toolbarContent"), action, try one("levelToolbarContent"), source)
    }

    /// Handed the tabs, the page's bar carries them, and the level filter moves
    /// into the actions as the first of them.
    func testHandedTheTabsTheLogBarCarriesThemAndTheLevelFilterIsTheFirstAction() throws {
        let (content, _, _, _) = try logBodies()
        let squeezed = content.filter { !$0.isWhitespace }
        XCTAssertTrue(squeezed.contains("guardletsettingsTabselse{return"),
                      "the bar is changed whether or not tabs were handed")
        XCTAssertTrue(squeezed.contains("content.tabs=settingsTabs.tabs"), "the handed tabs are not the bar's tabs")
        XCTAssertTrue(squeezed.contains("content.selectedTab=settingsTabs.selectedTab"),
                      "the handed selection is not the bar's selection")
        XCTAssertTrue(squeezed.contains("content.actions.insert(levelAction,at:0)"),
                      "the level filter is not the first action")
        // The guard comes before every change, so nil leaves the content as built.
        let guardAt = try XCTUnwrap(squeezed.range(of: "guardletsettingsTabselse"))
        let tabsAt = try XCTUnwrap(squeezed.range(of: "content.tabs="))
        XCTAssertLessThan(guardAt.lowerBound, tabsAt.lowerBound)
    }

    /// The level filter: three items, the three levels, each one on exactly
    /// when it is the level in force, and choosing one sets the level.
    func testTheLevelActionIsAMenuOfThreeLevelsOneOnAndChoosingSetsTheLevel() throws {
        let (_, level, _, source) = try logBodies()
        let squeezed = level.filter { !$0.isWhitespace }
        XCTAssertTrue(squeezed.contains("menu:Self.levelTabs.map"), "the level action is not a menu over the three levels")
        XCTAssertTrue(squeezed.contains("isOn:tab.level==minimumLevel"),
                      "an item is not on exactly when its level is the one in force")
        XCTAssertTrue(squeezed.contains("{minimumLevel=tab.level}"), "choosing an item does not set the level")
        XCTAssertTrue(squeezed.contains("id:\"level\""))
        XCTAssertTrue(squeezed.contains("title:tab.title"), "an item does not say the level's word")
        XCTAssertTrue(squeezed.contains("title:levelInForce.title"),
                      "the level action does not carry the level in force as its title")
        // The level in force is read from the one list, falling to the first.
        let force = try XCTUnwrap(source.range(of: "var levelInForce:"), "LogView has no levelInForce")
        let forceBody = String(source[force.upperBound...].prefix(260)).filter { !$0.isWhitespace }
        XCTAssertTrue(forceBody.contains("Self.levelTabs.first{$0.level==minimumLevel}??Self.levelTabs[0]"),
                      "the level in force is not read from the three levels")
        // Three items, one per level, the levels distinct so one is on at a time;
        // the words and glyphs are declared here once, for the tabs and the menu.
        let declaration = try XCTUnwrap(
            source.range(of: "levelTabs: [(id: String, level: LogLevel, title: String, symbol: String)] {"))
        let rest = source[declaration.upperBound...]
        let list = String(rest.prefix { $0 != "]" }).filter { !$0.isWhitespace }
        XCTAssertEqual(list, "[(\"all\",.info,AppStr.logLevelAll,\"list.bullet\"),"
                       + "(\"warn\",.warn,AppStr.logLevelWarnings,\"exclamationmark.triangle\"),"
                       + "(\"error\",.error,AppStr.logLevelErrors,\"xmark.octagon\")")
    }

    /// Built with no tabs, the content is what it was: the three level tabs,
    /// bound to the level, and no level action among the others.
    func testBuiltWithNoTabsTheLogBarStillHasTheThreeLevelTabs() throws {
        let (_, _, plain, _) = try logBodies()
        let squeezed = plain.filter { !$0.isWhitespace }
        XCTAssertTrue(squeezed.contains("tabs:Self.levelTabs.map{HelmToolbarTab(id:$0.id,title:$0.title,symbol:$0.symbol)}"),
                      "the level tabs are not the three levels")
        XCTAssertTrue(squeezed.contains("get:{levelInForce.id}"), "the selected level tab is not the level in force")
        XCTAssertTrue(squeezed.contains("set:{idinminimumLevel=Self.levelTabs.first{$0.id==id}?.level??.info}"),
                      "the level tabs no longer set the level")
        XCTAssertFalse(plain.contains("settingsTabs"), "the plain bar knows of the Settings tabs")
        XCTAssertFalse(squeezed.contains("id:\"level\""), "the plain bar already carries the level action")
        for id in ["modules", "follow", "copy", "more"] {
            XCTAssertTrue(plain.contains("id: \"\(id)\""), "the \(id) action is gone")
        }
    }

    // MARK: - Who hands them to whom

    @MainActor
    func testTheDetailHandsTheTabsToAllThreePages() throws {
        let source = SwiftSource.uncommented(try RepoSource.text(of: "Sources/HelmApp/SettingsWindow.swift"))
        let detail = try XCTUnwrap(SwiftSource.typeBodies(in: source).first { $0.name == "SettingsDetail" },
                                   "SettingsDetail is gone")
        let characters = Array(source)
        let body = String(characters[(detail.open + 1)..<detail.close])

        XCTAssertTrue(body.contains("SettingsTabs.binding"),
                      "the detail never builds the tabs' selection: \(Self.nothing)")
        XCTAssertTrue(body.contains("LogView(settingsTabs:"),
                      "the Log page is built without the tabs: \(Self.nothing)")
        // General and About carry a tabs-only declaration under their own keys,
        // the keys the toolbar answers for them.
        XCTAssertTrue(body.contains("token: \"general\""), "General declares no tabs under its own key")
        XCTAssertTrue(body.contains("token: \"about\""), "About declares no tabs under its own key")
        XCTAssertTrue(body.contains("helmWindowToolbar"), "no page declares tabs to the window's toolbar")
    }

    // MARK: - The name

    /// `.about` and `.log` answer what `.general` answers, so the bar's name
    /// plate does not change under the tabs.
    func testTheBarsNameStaysSettingsOnLogAndAbout() throws {
        let source = SwiftSource.uncommented(try RepoSource.text(of: "Sources/HelmApp/SettingsToolbar.swift"))
        let bodies = SwiftSource.bodiesNamed("pageIdentity", in: source)
        XCTAssertEqual(bodies.count, 1, "pageIdentity is not one function any more")
        let identity = try XCTUnwrap(bodies.first)

        XCTAssertFalse(identity.contains("AppStr.aboutHelm"), "About still names its own bar")
        XCTAssertFalse(identity.contains("AppStr.logPane"), "Log still names its own bar")
        XCTAssertFalse(identity.contains("info.circle"), "About still has its own glyph in the bar")
        XCTAssertFalse(identity.contains("text.alignleft"), "Log still has its own glyph in the bar")
        XCTAssertTrue(identity.contains("AppStr.settingsPane"), "nothing answers with the Settings name")
        XCTAssertTrue(identity.contains("case .about") && identity.contains("case .log"),
                      "the identity no longer names the two pages it must answer for")
    }

    /// The name each page publishes for the window's title.
    func testLogAndAboutPublishTheSettingsNameForTheWindow() throws {
        for file in ["Sources/HelmApp/LogView.swift", "Sources/HelmApp/AboutPage.swift"] {
            let source = SwiftSource.uncommented(try RepoSource.text(of: file))
            XCTAssertTrue(source.contains(".helmPageBar(title: AppStr.settingsPane"),
                          "\(file) does not publish the Settings name")
            XCTAssertFalse(source.contains(".helmPageBar(title: AppStr.logPane"), "\(file) still publishes Log")
            XCTAssertFalse(source.contains(".helmPageBar(title: AppStr.aboutHelm"), "\(file) still publishes About")
        }
    }
}
