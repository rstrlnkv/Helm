import AppKit
import XCTest

/// **A search field configured with some of `SettingsToolbar.makeSearchItem`'s lines (`configured`),
/// with no `recentsAutosaveName`, writes nothing into the process's defaults when a word is
/// committed — measured in a window that is never ordered front.**
///
/// A guard that sweeps the defaults domain for a typed word cannot say who wrote a key it finds.
/// Here every identifier, every word and every autosave name carries a token drawn afresh at each
/// run, so a key or a value that carries it is this run's and nobody else's, and the domain is
/// diffed key by key around each case. The item's identifier is **not** `helm.search`: committing
/// a word through that identifier could put it into the key the product's own item would use.
///
/// **What the rows show.** One test holds the cases with a nil name — the item in a window's
/// toolbar committed with Return, a bare field in a window committed the same way, a recent list
/// assigned by hand to each instead of a commit, and an item that keeps the field AppKit gave it —
/// and in every one the domain gains no key, changes no key, holds no key carrying the word and no
/// key spelled `<identifier>.recents`, the spelling AppKit might derive from the identifier; a key
/// removed from it is not read. The word is in the field's in-memory list in every case, so the
/// commit or the assignment reached AppKit's recording and the silence is silence after it. The
/// other test is the instrument's own proof: the same item and the same Return with a name on the
/// field puts the word into the domain, under that name and under no other key, so a write would
/// have shown. In the cases with a nil name the name is still nil after the field is attached and
/// at the end of each case.
///
/// **What they do not show.** The window is never ordered front and never key: a toolbar item in
/// a window that is on the screen and key may take a path these cases do not.
/// `AToolbarSearchItemsRecentsInAShownWindowTests` asks for that state, with a field configured from
/// more of `makeSearchItem`'s lines, and fails first if the window does not become key.
///
/// The teardown removes only keys that were not in the domain before a case and whose name or
/// value carries that run's token.
@MainActor
final class AToolbarSearchItemsRecentsAreMeasuredTests: XCTestCase {

    // MARK: - The probe

    /// One unique token per test run. It is in every identifier, every autosave name and every
    /// typed word below, so a key or a value that carries it can only be this run's.
    private let token = UUID().uuidString.prefix(8).lowercased()

    private var domainName: String { Bundle.main.bundleIdentifier ?? "?" }

    /// The process's own persistent domain, as a dictionary; empty if the process has none.
    private func domain() -> [String: Any] {
        UserDefaults.standard.persistentDomain(forName: domainName) ?? [:]
    }

    @objc private final class Target: NSObject {
        var submits = 0
        @objc func submitted(_ sender: Any?) { submits += 1 }
    }

    /// A toolbar that vends exactly one item, the one handed to it.
    private final class OneItemToolbar: NSObject, NSToolbarDelegate {
        let item: NSToolbarItem
        init(_ item: NSToolbarItem) { self.item = item }
        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [item.itemIdentifier] }
        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [item.itemIdentifier] }
        func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                     willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? { item }
    }

    /// Where the field sits.
    private enum Place { case inAWindowsToolbar, inAWindowsContentView }

    /// What one case saw.
    private struct Seen {
        var identifier: String
        var word: String
        var submits: Int
        var recentsInMemory: [String]
        var newKeys: [String]
        var changedExistingKeys: [String]
        var keysCarryingTheWord: [String]
        var toolbarItemCount: Int?
        var nameAfterAttach: String?
        var nameAfterCommit: String?
    }

    /// Builds the field with some of `SettingsToolbar.makeSearchItem`'s lines: whole-string sending,
    /// no action on end editing, `recentsAutosaveName` as asked, a real target and action. Not here:
    /// its delegate, accessibility label, placeholder, string value, frame notifications and width caps.
    private func configured(_ autosave: String?, target: Target) -> NSSearchField {
        let field = NSSearchField()
        field.sendsWholeSearchString = true
        field.cell?.sendsActionOnEndEditing = false
        field.recentsAutosaveName = autosave
        field.target = target
        field.action = #selector(Target.submitted(_:))
        return field
    }

    /// Builds and places the field, puts the word in it, commits it with Return unless
    /// `commitWithReturn` is false, hands it the recent list when `handRecents` is true, turns the run
    /// loop, and diffs the process's persistent domain against its reading before the case.
    private func run(_ name: String, place: Place, autosave: String?, handRecents: Bool = false,
                     commitWithReturn: Bool = true, itsOwnDefaultField: Bool = false) throws -> Seen {
        let identifier = "helm.tests.recentsProbe.\(name).\(token)"
        let word = "zqprobe\(name)\(token)"

        let before = domain()
        // Registered before anything can write: removes only a key that was not in the domain
        // before this case and whose name or value carries this run's token.
        addTeardownBlock { [token, before] in
            let now = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "?") ?? [:]
            for (key, value) in now where before[key] == nil {
                if key.contains(token) || "\(value)".contains(token) {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }

        let target = Target()
        var field = configured(autosave, target: target)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        var toolbar: NSToolbar?
        var toolbarDelegate: OneItemToolbar?
        var itemCount: Int?
        switch place {
        case .inAWindowsToolbar:
            let item = NSSearchToolbarItem(itemIdentifier: NSToolbarItem.Identifier(identifier))
            if itsOwnDefaultField {
                field = item.searchField
                field.target = target
                field.action = #selector(Target.submitted(_:))
            } else {
                item.searchField = field
            }
            let delegate = OneItemToolbar(item)
            let bar = NSToolbar(identifier: "helm.tests.recentsProbe.bar.\(name).\(token)")
            bar.delegate = delegate
            bar.autosavesConfiguration = false
            window.toolbar = bar
            toolbar = bar
            toolbarDelegate = delegate
            itemCount = bar.items.count
        case .inAWindowsContentView:
            let content = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 300))
            field.frame = NSRect(x: 20, y: 130, width: 300, height: 28)
            content.addSubview(field)
            window.contentView = content
        }
        defer {
            window.toolbar = nil
            window.close()
            withExtendedLifetime((toolbar, toolbarDelegate)) {}
        }
        for _ in 0..<10 { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
        let nameAfterAttach = field.recentsAutosaveName

        field.stringValue = word
        NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: field)
        if commitWithReturn {
            let editorReady = window.makeFirstResponder(field)
            let editor = field.currentEditor() as? NSTextView
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                         windowNumber: window.windowNumber, context: nil, characters: "\r",
                                         charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)
            XCTAssertTrue(editorReady && editor != nil && event != nil,
                          "precondition: Return could not be delivered to the field in case \(name)")
            if let editor, let event { editor.keyDown(with: event) }
        }
        if handRecents { field.recentSearches = [word] }
        // AppKit's write, if there is one, may be deferred a few turns.
        for _ in 0..<30 { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
        _ = UserDefaults.standard.synchronize()

        let after = domain()
        let newKeys = after.keys.filter { before[$0] == nil }.sorted()
        let changed = after.keys.filter { key in
            guard let was = before[key] else { return false }
            return !(was as AnyObject).isEqual(after[key] as AnyObject)
        }.sorted()
        let carrying = UserDefaults.standard.dictionaryRepresentation().compactMap { key, value -> String? in
            switch value {
            case let text as String: return text.contains(word) ? key : nil
            case let list as [String]: return list.contains(where: { $0.contains(word) }) ? key : nil
            default: return nil
            }
        }.sorted()
        return Seen(identifier: identifier, word: word, submits: target.submits,
                    recentsInMemory: field.recentSearches, newKeys: newKeys,
                    changedExistingKeys: changed, keysCarryingTheWord: carrying,
                    toolbarItemCount: itemCount, nameAfterAttach: nameAfterAttach,
                    nameAfterCommit: field.recentsAutosaveName)
    }

    private func show(_ label: String, _ s: Seen) -> String {
        "PROBE[\(label)] domain=\(domainName) id=\(s.identifier) submits=\(s.submits) "
              + "inMemory=\(s.recentsInMemory.count) toolbarItems=\(String(describing: s.toolbarItemCount)) "
              + "newKeys=\(s.newKeys) changedExisting=\(s.changedExistingKeys) "
              + "keysCarryingTheWord=\(s.keysCarryingTheWord) "
              + "nameAfterAttach=\(String(describing: s.nameAfterAttach)) nameAfterCommit=\(String(describing: s.nameAfterCommit))"
    }

    /// **A nil name writes nothing, in a window's toolbar or in its content view.**
    func testANilAutosaveNameWritesNothingInAnUnshownWindow() throws {
        let cases: [(String, Seen)] = [
            ("A item in a window's toolbar, Return",
             try run("a", place: .inAWindowsToolbar, autosave: nil)),
            ("B bare field in a window, Return",
             try run("b", place: .inAWindowsContentView, autosave: nil)),
            ("D item in a toolbar, recentSearches assigned",
             try run("d", place: .inAWindowsToolbar, autosave: nil, handRecents: true, commitWithReturn: false)),
            ("E bare field, recentSearches assigned",
             try run("e", place: .inAWindowsContentView, autosave: nil, handRecents: true, commitWithReturn: false)),
            ("G item keeping its own default field, Return",
             try run("g", place: .inAWindowsToolbar, autosave: nil, itsOwnDefaultField: true)),
            ("H own default field, Return and recentSearches assigned",
             try run("h", place: .inAWindowsToolbar, autosave: nil, handRecents: true, itsOwnDefaultField: true)),
        ]
        for (label, seen) in cases {
            let line = show(label, seen)
            // The subject happened: the word is in the field's own list, so a commit or an
            // assignment reached AppKit's recording, and silence below is silence after it.
            XCTAssertEqual(seen.recentsInMemory, [seen.word], "precondition: the field's in-memory list is not the word alone. \(line)")
            XCTAssertNil(seen.nameAfterAttach, "attaching the field gave it a name. \(line)")
            XCTAssertNil(seen.nameAfterCommit, "committing gave the field a name. \(line)")
            XCTAssertEqual(seen.newKeys, [], "a key appeared in the process's defaults domain. \(line)")
            XCTAssertEqual(seen.changedExistingKeys, [], "an existing key changed. \(line)")
            XCTAssertEqual(seen.keysCarryingTheWord, [], "the word reached the defaults. \(line)")
            XCTAssertFalse(domain().keys.contains("\(seen.identifier).recents"),
                           "AppKit wrote the identifier's own «.recents» key. \(line)")
            if label.contains("item in a window's toolbar") {
                XCTAssertEqual(seen.toolbarItemCount, 1, "precondition: the toolbar does not hold exactly one item. \(line)")
            }
        }
    }

    /// **The instrument can see a write.** The same item, the same Return, a name on the field:
    /// the key appears under that name and under nothing else.
    func testTheSameCommitWithAnExplicitNameDoesWriteUnderThatNameOnly() throws {
        let name = "com.helm.tests.recentsProbe.named.c.\(token)"
        let seen = try run("c", place: .inAWindowsToolbar, autosave: name)
        let line = show("C item in a toolbar, explicit name, Return", seen)
        XCTAssertEqual(seen.submits, 1, "precondition: the commit did not fire. \(line)")
        XCTAssertEqual(seen.newKeys, [name], "the key is not the name given, or there are others. \(line)")
        XCTAssertEqual(seen.keysCarryingTheWord, [name], line)
        XCTAssertEqual(seen.changedExistingKeys, [], line)
    }
}
