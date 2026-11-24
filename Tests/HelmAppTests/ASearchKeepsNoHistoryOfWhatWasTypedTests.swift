import AppKit
import SwiftUI
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **What somebody typed into the search bar does not go into the settings
/// file.**
///
/// `NSSearchField` has a persisted history: give the control a
/// `recentsAutosaveName` and AppKit writes the searched-for words into the
/// user defaults domain under that key, where any process running as this
/// user can read them. The Uninstaller's filter is typed with the names of
/// the applications on somebody's Mac, and Homebrew's with the packages they
/// looked for: the class of value `Redact` and `PrivateFile` exist for, written
/// by AppKit underneath them.
///
/// `HelmHeaderSearch` wires a real `target`/`action`
/// (`Coordinator.submitted(_:)`), so Return is a commit AppKit records in
/// `recentSearches`, in memory, whatever `recentsAutosaveName` says.
///
/// **`recentsAutosaveName` is the load-bearing reading, and the in-memory list
/// is not.** With `field.recentsAutosaveName = nil` (`HelmHeaderSearch.makeNSView`)
/// there is no key to persist under, and the defaults-domain sweep answers the
/// question this file asks: did the word reach a file anything running as this
/// user can read. `testAnAutosaveNameOnThisFieldWouldPutTypedWordsInTheSettingsFile`
/// is the canary that shows the mechanism working on this very control.
///
/// **The row.** Every row reads the field `LivePageUnderTheHeaderFixture` mounts
/// under the card's header row (`HelmHeaderSearch`), and asserts it is there before it types.
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
        var body: some View {
            Text("the list")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .helmHeaderContent(HelmHeaderContent(search: HelmHeaderQuery(
                    prompt: "Search packages",
                    text: Binding(get: { page.text }, set: { page.text = $0 }),
                    onSubmit: { page.submits += 1 })))
        }
    }

    /// What gets typed. Not a visible string and not looked up: it stands for a
    /// word off somebody's own Mac, and it is searched for by name in the
    /// defaults domain below, so it has to be a word this fixture is the only
    /// plausible source of.
    private static let word = "wget"

    /// **The guard.** Nothing about the field the header row draws carries a
    /// history.
    func testTheFieldCarriesNoAutosaveNameAndRecordsNoRecents() async throws {
        let page = Page()
        let fixture = LivePageUnderTheHeaderFixture(Pane(page: page), selection: .module("test.searchHistory"),
                                                  width: 1060, height: 400)
        defer { fixture.drop() }
        await waitUntil("the header row draws its search field") { fixture.searchField != nil }
        await grace(0.4)                            // the declaration reaches the row after the field is there

        // The subject, before any absence is read off it. A walk that found no
        // control would satisfy every assertion below by never running, and an
        // empty history is exactly what "there was no field" looks like.
        let field = try XCTUnwrap(fixture.searchField, """
            the header row holds no search field at all, so there is nothing here whose \
            history could be read and every reading below would be of nothing
            """)
        XCTAssertNil(field.recentsAutosaveName, """
            the field arrived already carrying the autosave name \
            «\(field.recentsAutosaveName ?? "")» — before anything here touched it. AppKit \
            writes the searched-for words into the user defaults domain under that key, and \
            this app's two search bars are typed with the names of somebody's applications and \
            the packages they looked for
            """)

        // The guard below reads the whole domain for the word, so it reads only
        // what this run wrote when nothing carrying it was there before.
        let leftovers = Self.keysCarrying(Self.word)
        XCTAssertEqual(leftovers, [], """
            precondition: «\(Self.word)» is already in the defaults domain under \(leftovers), so \
            the reading below would be of somebody else's leftovers
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
        // This field's action fires on Return
        // (`HelmHeaderSearch.Coordinator.submitted(_:)`), and AppKit keeps an
        // in-memory list of commits whatever `recentsAutosaveName` says. The
        // word landing here is not the leak; the defaults domain below is.
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
    /// Without this the guard above would read the same whether
    /// `recentsAutosaveName` were a live property of the mounted control or a
    /// name that does nothing. So the defect is put back on the field the
    /// header row draws, and its cost is read: the typed word in the settings
    /// domain, under the planted key.
    func testAnAutosaveNameOnThisFieldWouldPutTypedWordsInTheSettingsFile() async throws {
        let page = Page()
        let fixture = LivePageUnderTheHeaderFixture(Pane(page: page), selection: .module("test.searchHistoryCanary"),
                                                  width: 1060, height: 400)
        defer { fixture.drop() }
        await waitUntil("the header row draws its search field") { fixture.searchField != nil }
        await grace(0.4)                            // the declaration reaches the row after the field is there
        let field = try XCTUnwrap(fixture.searchField, """
            no search field in the header row, so the guard beside this one has no subject either
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

        // The canary is about what a *named* field does with a recent it
        // holds, not about the commit the guard already reads, so the recent
        // is handed over directly.
        field.recentSearches = [Self.word]
        await grace(0.2)

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
    /// Strings and arrays of strings only: the shape a recents autosave writes.
    /// Every value of every type would turn the global domain into noise.
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
