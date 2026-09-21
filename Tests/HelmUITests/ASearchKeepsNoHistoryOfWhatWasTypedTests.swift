import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmUI

/// **What somebody typed into the search bar does not go into the settings
/// file.**
///
/// `NSSearchField` has a history of its own, and it is a *persisted* one: give
/// the control a `recentsAutosaveName` and AppKit writes the words that were
/// searched for into the user defaults domain under exactly that key, where any
/// process running as this user can read them. The two search bars this app has
/// are fed the worst possible material for that — the Uninstaller's filter is
/// typed against **the names of the applications on somebody's Mac**, and
/// Homebrew's is **the packages they went looking for**. Both are the class of
/// value `Redact` and `PrivateFile` exist for in this tree, and neither would go
/// through either: the history is written by AppKit, underneath us.
///
/// Nothing in the app asks for one — `command grep -rnE 'recentsAutosaveName|
/// recentSearches|searchCompletion|searchSuggestion' Sources` answers with two
/// lines, both of them prose in `HelmSearchable.swift`, and no code at all — and
/// `.searchable` exposes no API that could; but the control is not ours. (The
/// `-E` is the point: without it `grep` reads the `|` as a literal and the
/// command comes back empty whatever the tree holds, which is what stood here.)
/// It is built by SwiftUI's toolbar bridge (`helmSearchable`), and what a
/// framework sets on a control it builds is not readable from this repository at
/// all. It is only readable off the mounted control, which is what this file
/// does, and it is the kind of fact an SDK can change under us in a release
/// note nobody reads.
///
/// **Measured on macOS 27 (2026-09-21) on the bridged field in this fixture:**
/// `recentsAutosaveName` nil and `recentSearches` empty — at mount, after four
/// keystrokes, and after a Return that fired `onSubmit` once.
///
/// **What the empty `recentSearches` reading is worth, which is less than it
/// looks.** Driven from this fixture the list stays empty *whatever* is done to
/// the field: with an autosave name planted and a recents menu template set, a
/// word typed key by key through the field editor, a real Return, a resignation
/// of first responder and a `sendAction` all left it `[]` (measured the same
/// day). AppKit records a recent from a commit path this headless fixture never
/// reaches — the bridged field's `target` and `action` are both nil, SwiftUI
/// hangs the submit off its own field editor. So the emptiness of that list is
/// **not** evidence that nothing would be recorded in the running app, and it is
/// asserted below only because a non-empty read would be a real alarm.
///
/// The load-bearing reading is the other one: with no autosave name there is no
/// key for AppKit to write under, and
/// `testAnAutosaveNameOnThisFieldWouldPutTypedWordsInTheSettingsFile` is that
/// half of the mechanism shown end to end on this very control, so the guard
/// above it is standing in front of something measured rather than something
/// quoted from documentation.
///
/// **Why this is in `HelmUITests` and `ASearchFieldSaysWhatItIsTests` is not.**
/// The whole subject here is `helmSearchable`, which is this target's; nothing
/// in this file touches the app layer. The name is the other way round — it is
/// set by `ToolbarSearchName` in `HelmApp` — so that file moved there with the
/// half it watches. The mechanism is shared either way and decides nothing:
/// `MountedRender.pressReturn` lives in `Tests/Support`, spelled once, and is
/// reachable from both targets.
@MainActor
final class ASearchKeepsNoHistoryOfWhatWasTypedTests: XCTestCase {

    /// The page's side of the bridge: the binding that moves per keystroke and
    /// the press that is the search, counted so that "the word landed" and "the
    /// commit happened" are assertions and not assumptions.
    private final class Page: ObservableObject {
        @Published var text = ""
        var submits = 0
    }

    private struct Pane: View {
        @ObservedObject var page: Page
        var body: some View {
            Text("the list")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .helmSearchable(text: Binding(get: { page.text }, set: { page.text = $0 }),
                                prompt: "Search packages",
                                onSubmit: { page.submits += 1 })
                // A pane with no toolbar of its own publishes no toolbar at all,
                // and then there is no field to read anything off.
                .toolbar { ToolbarSpacer(.fixed, placement: .navigation) }
        }
    }

    /// What gets typed. Not a visible string and not looked up: it stands for a
    /// word off somebody's own Mac, and it is searched for by name in the
    /// defaults domain below, so it has to be a word this fixture is the only
    /// plausible source of.
    private static let word = "wget"

    /// **The guard.** Nothing about the bridged control carries a history.
    func testTheBridgedFieldCarriesNoAutosaveNameAndRecordsNoRecents() throws {
        let page = Page()
        let mount = MountedRender(Pane(page: page), width: 1060, height: 400, appearance: .aqua)
        defer { mount.drop() }
        mount.settle(20)

        // The subject, before any absence is read off it. A walk that found no
        // control would satisfy every assertion below by never running, and an
        // empty history is exactly what "there was no field" looks like.
        let field = try XCTUnwrap(mount.searchField, """
            the window's toolbar holds no search field at all, so there is nothing here whose \
            history could be read and every reading below would be of nothing. Either \
            `helmSearchable` stopped reaching the toolbar or the bridge stopped publishing the \
            item
            """)
        XCTAssertNil(field.recentsAutosaveName, """
            the bridged search field arrived already carrying the autosave name \
            «\(field.recentsAutosaveName ?? "")» — before anything here touched it. AppKit \
            writes the searched-for words into the user defaults domain under that key, and \
            this app's two search bars are typed with the names of somebody's applications and \
            the packages they looked for
            """)

        // And the word has to actually land, or "no history" is a reading of a
        // field nobody typed into.
        XCTAssertTrue(mount.type(Self.word),
                      "the field went away before «\(Self.word)» was typed")
        XCTAssertEqual(field.stringValue, Self.word, """
            precondition: «\(Self.word)» never reached the control — it reads «\
            \(field.stringValue)» — so nothing below is a reading about a field with a word in it
            """)
        XCTAssertEqual(page.text, Self.word, """
            precondition: the keystrokes never reached the binding, so this is not the control \
            the pages are wired to and its history is not the one at stake
            """)

        XCTAssertNil(field.recentsAutosaveName, """
            typing into the field gave it the autosave name «\(field.recentsAutosaveName ?? "")»
            """)
        XCTAssertEqual(field.recentSearches, [], """
            typing alone put \(field.recentSearches) into the field's recent-search list
            """)

        // A recent is recorded on commit and not per keystroke, so a check that
        // only typed would be reading before there was anything to read.
        XCTAssertTrue(mount.pressReturn(), "Return never reached the field")
        XCTAssertEqual(page.submits, 1, """
            precondition: Return fired `onSubmit` \(page.submits) times, so the commit this \
            case exists to read the aftermath of did not happen
            """)

        XCTAssertNil(field.recentsAutosaveName, """
            the search was committed and the field came away with the autosave name \
            «\(field.recentsAutosaveName ?? "")». From here AppKit persists every word searched \
            for into the settings file
            """)
        XCTAssertEqual(field.recentSearches, [], """
            committing a search put \(field.recentSearches) into the field's recent-search \
            list. With no autosave name that list is in memory only, but it is the material \
            that gets written the moment one appears
            """)

        // And the domain itself, which is the file the whole question is about.
        let carrying = Self.keysCarrying(Self.word)
        XCTAssertEqual(carrying, [], """
            «\(Self.word)» was typed into the search bar and came out in the user defaults \
            domain under \(carrying). That is a word off somebody's Mac in a file every \
            process running as this user can read
            """)
    }

    /// **The canary: the same field with a name on it does write the words
    /// out.**
    ///
    /// Without this the guard above is a sentence about a framework rather than
    /// a measurement — it would read the same whether `recentsAutosaveName`
    /// were a live property of the mounted control or a name that does nothing
    /// on macOS 27. So the defect is put back here, on the bridged field
    /// itself, and the cost of it is measured: the typed word in the settings
    /// domain, under the planted key.
    func testAnAutosaveNameOnThisFieldWouldPutTypedWordsInTheSettingsFile() throws {
        let page = Page()
        let mount = MountedRender(Pane(page: page), width: 1060, height: 400, appearance: .aqua)
        defer { mount.drop() }
        mount.settle(20)
        let field = try XCTUnwrap(mount.searchField, """
            no search field in the toolbar, so the guard beside this one has no subject either
            """)

        // Registered before the key can exist, and as a teardown block rather
        // than a `defer`, so it outlives a failure anywhere below.
        addTeardownBlock { UserDefaults.standard.removeObject(forKey: Self.plantedName) }
        XCTAssertNil(UserDefaults.standard.object(forKey: Self.plantedName), """
            precondition: «\(Self.plantedName)» is already in the defaults domain, so the \
            reading below would be of somebody else's leftovers
            """)

        field.recentsAutosaveName = Self.plantedName
        XCTAssertEqual(field.recentsAutosaveName, Self.plantedName, """
            the bridged field would not take an autosave name at all, which means the guard \
            beside this one is reading a property that does nothing on this system and proves \
            nothing
            """)

        XCTAssertTrue(mount.type(Self.word), "the field went away before the word was typed")
        XCTAssertEqual(page.text, Self.word, "precondition: the word never reached the binding")
        XCTAssertTrue(mount.pressReturn(), "Return never reached the field")

        // The commit path AppKit records from is not reachable from a headless
        // fixture — see this file's note — so the recent is handed over rather
        // than typed into being. What is being shown is the *persistence*: a
        // name, a recent, and the word in the settings file.
        field.recentSearches = [Self.word]
        mount.settle(10)

        XCTAssertEqual(field.recentSearches, [Self.word], """
            the field did not keep the recent it was handed, so `recentSearches` is not a live \
            property of this control and the guard beside this one reads nothing
            """)
        XCTAssertTrue(Self.keysCarrying(Self.word).contains(Self.plantedName), """
            a recent on a named field did not reach the defaults domain under \
            «\(Self.plantedName)» — it holds \
            \(String(describing: UserDefaults.standard.object(forKey: Self.plantedName))). \
            Either AppKit stopped persisting recents or it moved the key, and the guard beside \
            this one is then watching for a cost that is paid somewhere else
            """)

        UserDefaults.standard.removeObject(forKey: Self.plantedName)
        XCTAssertNil(UserDefaults.standard.object(forKey: Self.plantedName),
                     "this fixture left «\(Self.plantedName)» behind in the defaults domain")
    }

    /// A name no part of the app uses, so what is found under it below was put
    /// there by this fixture and by nothing else.
    private static let plantedName = "com.helm.tests.ASearchKeepsNoHistoryOfWhatWasTyped"

    /// Every key in this process's defaults domain whose value carries `word`.
    ///
    /// Strings and arrays of strings only — that is the shape a recents autosave
    /// writes, measured, and sweeping every value of every type turns the whole
    /// global domain into noise the message would have to be read through.
    private static func keysCarrying(_ word: String) -> [String] {
        UserDefaults.standard.dictionaryRepresentation().compactMap { key, value in
            switch value {
            case let text as String: return text.contains(word) ? key : nil
            case let list as [String]:
                return list.contains(where: { $0.contains(word) }) ? key : nil
            default: return nil
            }
        }.sorted()
    }
}
