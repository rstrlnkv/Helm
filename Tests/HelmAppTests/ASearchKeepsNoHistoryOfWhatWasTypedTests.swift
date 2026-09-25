import AppKit
import SwiftUI
import HelmTestSupport
import XCTest
@testable import HelmApp
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
/// **Moved here from `Tests/HelmUITests`, and one reading changed by the move
/// rather than merely relocated — measured 2026-09-25, not assumed.** This
/// file used to watch the field SwiftUI's `.searchable` bridged into the
/// toolbar, whose `target`/`action` were both nil — SwiftUI hung the submit
/// off its own field editor, so no commit ever reached AppKit's own recording
/// path and `recentSearches` stayed `[]` through everything this fixture could
/// do to the field, Return included. `SettingsToolbar.makeSearchItem` wires a
/// real `target`/`action` (`searchSubmitted(_:)`), so a Return now *is* a
/// commit AppKit's own control recognises — and measured on this field,
/// `recentSearches` reads `["wget"]` after one, in memory, whatever
/// `recentsAutosaveName` is set to. `testTheFieldCarriesNoAutosaveNameAndRecordsNoRecents`
/// reads that in full: empty at mount, still empty after typing without a
/// commit, and holding the committed word only after one — the in-memory
/// list this control keeps regardless of persistence.
///
/// **`recentsAutosaveName` is the load-bearing reading, and the in-memory list
/// is not.** `field.recentsAutosaveName = nil` (`makeSearchItem`) is what
/// there is no key for AppKit to persist under — measured nil at mount, after
/// typing and after the commit that populates `recentSearches` — and the
/// defaults-domain sweep at the end of the same test is what actually answers
/// the question this file exists to ask: did the word reach a file anything
/// running as this user can read. `testAnAutosaveNameOnThisFieldWouldPutTypedWordsInTheSettingsFile`
/// is the canary that shows the other half of the mechanism working end to
/// end on this very control, so the guard above it is standing in front of
/// something measured rather than something quoted from documentation.
@MainActor
final class ASearchKeepsNoHistoryOfWhatWasTypedTests: XCTestCase {

    /// The page's side: the binding that moves per keystroke and the press
    /// that is the search, counted so that "the word landed" and "the commit
    /// happened" are assertions and not assumptions.
    private final class Page {
        var text = ""
        var submits = 0
    }

    private struct Pane: View {
        let page: Page
        let token: String
        var body: some View {
            Text("the list")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .helmWindowToolbar(HelmPageToolbarContent(search: HelmToolbarSearch(
                    prompt: "Search packages",
                    text: Binding(get: { page.text }, set: { page.text = $0 }),
                    onSubmit: { page.submits += 1 })), token: token)
        }
    }

    /// What gets typed. Not a visible string and not looked up: it stands for a
    /// word off somebody's own Mac, and it is searched for by name in the
    /// defaults domain below, so it has to be a word this fixture is the only
    /// plausible source of.
    private static let word = "wget"

    /// **The guard.** Nothing about the field this toolbar builds carries a
    /// history.
    func testTheFieldCarriesNoAutosaveNameAndRecordsNoRecents() throws {
        let page = Page()
        let fixture = LivePageToolbarFixture(Pane(page: page, token: "test.searchHistory"), selection: .module("test.searchHistory"),
                                             width: 1060, height: 400)
        defer { fixture.drop() }
        fixture.settle(20)

        // The subject, before any absence is read off it. A walk that found no
        // control would satisfy every assertion below by never running, and an
        // empty history is exactly what "there was no field" looks like.
        let field = try XCTUnwrap(fixture.mount.searchField, """
            the window's toolbar holds no search field at all, so there is nothing here whose \
            history could be read and every reading below would be of nothing
            """)
        XCTAssertNil(field.recentsAutosaveName, """
            the field arrived already carrying the autosave name \
            «\(field.recentsAutosaveName ?? "")» — before anything here touched it. AppKit \
            writes the searched-for words into the user defaults domain under that key, and \
            this app's two search bars are typed with the names of somebody's applications and \
            the packages they looked for
            """)

        // And the word has to actually land, or "no history" is a reading of a
        // field nobody typed into.
        XCTAssertTrue(fixture.mount.type(Self.word),
                      "the field went away before «\(Self.word)» was typed")
        XCTAssertEqual(field.stringValue, Self.word, """
            precondition: «\(Self.word)» never reached the control — it reads «\
            \(field.stringValue)» — so nothing below is a reading about a field with a word in it
            """)
        XCTAssertEqual(page.text, Self.word, """
            precondition: the keystrokes never reached the binding, so this is not the control \
            the page is wired to and its history is not the one at stake
            """)

        XCTAssertNil(field.recentsAutosaveName, """
            typing into the field gave it the autosave name «\(field.recentsAutosaveName ?? "")»
            """)
        XCTAssertEqual(field.recentSearches, [], """
            typing alone put \(field.recentSearches) into the field's recent-search list
            """)

        // A recent is recorded on commit and not per keystroke, so a check that
        // only typed would be reading before there was anything to read.
        XCTAssertTrue(fixture.mount.pressReturn(), "Return never reached the field")
        XCTAssertEqual(page.submits, 1, """
            precondition: Return fired `onSubmit` \(page.submits) times, so the commit this \
            case exists to read the aftermath of did not happen
            """)

        XCTAssertNil(field.recentsAutosaveName, """
            the search was committed and the field came away with the autosave name \
            «\(field.recentsAutosaveName ?? "")». From here AppKit persists every word searched \
            for into the settings file
            """)
        // **Measured, not the bridge's own reading.** The bridged field's
        // `target`/`action` were both nil, so no commit ever reached AppKit's
        // recording path and this stayed `[]` no matter what was done to the
        // field. This field's action really fires on Return
        // (`searchSubmitted(_:)`), and AppKit keeps its own in-memory list of
        // what has been committed regardless of `recentsAutosaveName` — that
        // flag governs persistence, not the in-memory list. The word landing
        // here is not the leak this file guards against; the next assertion,
        // against the defaults domain itself, is.
        XCTAssertEqual(field.recentSearches, [Self.word], """
            \(field.recentSearches) — committing "wget" no longer lands in the field's own \
            in-memory recent-search list, which is a real change in how this control commits \
            and worth noticing on its own even though it is not the leak this file exists to \
            catch
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
    /// on macOS 27. So the defect is put back here, on the field this toolbar
    /// builds, and the cost of it is measured: the typed word in the settings
    /// domain, under the planted key.
    func testAnAutosaveNameOnThisFieldWouldPutTypedWordsInTheSettingsFile() throws {
        let page = Page()
        let fixture = LivePageToolbarFixture(Pane(page: page, token: "test.searchHistoryCanary"), selection: .module("test.searchHistoryCanary"),
                                             width: 1060, height: 400)
        defer { fixture.drop() }
        fixture.settle(20)
        let field = try XCTUnwrap(fixture.mount.searchField, """
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
            the field would not take an autosave name at all, which means the guard beside \
            this one is reading a property that does nothing on this system and proves nothing
            """)

        XCTAssertTrue(fixture.mount.type(Self.word), "the field went away before the word was typed")
        XCTAssertEqual(page.text, Self.word, "precondition: the word never reached the binding")
        XCTAssertTrue(fixture.mount.pressReturn(), "Return never reached the field")

        // A Return here would exercise the same real commit path the guard
        // above already measured, landing the same word in `recentSearches` —
        // this canary is not about the commit at all, only about what a
        // *named* field then does with a recent it already holds, so the
        // recent is handed over directly, deterministically, rather than
        // typed and committed a second time for a fact this file already
        // established.
        field.recentSearches = [Self.word]
        fixture.settle(10)

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
