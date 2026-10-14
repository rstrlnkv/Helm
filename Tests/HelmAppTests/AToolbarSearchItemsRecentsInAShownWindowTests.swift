import AppKit
import XCTest

/// **A search item built the way `SettingsToolbar.makeSearchItem` builds it, in a window asked to
/// be ordered front and key, with a word committed by Return: does AppKit put anything into the
/// process's defaults, and under which key?** A window family (`--tier windows`): it asks for the
/// test app to be activated and orders its window front on the screen, and a second one once the
/// first is key, so it may take the focus of whoever runs it.
///
/// The sibling `AToolbarSearchItemsRecentsAreMeasuredTests` asks the question for a window that
/// is never ordered front. A window ordered front while the app is not active is on the screen
/// and still not key, so this file first asks for the app to be active, as the product's settings
/// window does (`.regular` activation policy, `NSApp.activate()`, then `makeKeyAndOrderFront`),
/// waits for the window to become key, and fails with `key=` in its message if it does not. Only
/// then does it type and commit. The rows look for `<identifier>.recents`, the key AppKit might
/// derive from the identifier when the field has no name.
///
/// **What the rows do.** They record; they decide nothing about which answer is right. Every
/// identifier, word and autosave name carries a token drawn afresh at each run, and the
/// identifier is **not** `helm.search`: committing a word through that identifier could put it
/// into the key the product's own item would use. The process's persistent domain is read before
/// the case and after each of four moments — the commit, the field ending editing, a second
/// window being made key, the window closing — and each of those readings is printed as one line
/// with the prefix `[recents-shown]`: every new key and whether its value carries the word, every
/// changed and every removed existing key, every key whose value carries the word, and whether
/// `<identifier>.recents` appeared.
///
/// **What fails.** A broken precondition: the window not key (the first assertion of each test,
/// printing `key=`, `visible=` and `appActive=`; when it fails the row stops before it types), the
/// item not holding the field built for it, the window not visible, the field never taking first
/// responder, no commit (the action did not fire exactly once, or the field's own
/// `recentSearches` is not the word alone), a name on the nil row's field or a moment without a
/// reading; and in the control row the name not kept on the field, no write seen under the
/// explicit name at any moment, or the explicit key not carrying the word after the commit or
/// after the window closes. The control row is the nil row with `recentsAutosaveName` set to a
/// unique name; if it writes, the instrument sees a write in this very state, so silence in the
/// nil row is silence of the product's shape.
///
/// **What is the same as the product, and what is not.** The field and the item take
/// `makeSearchItem`'s lines one for one (whole-string sending, no action on end editing, the
/// autosave name line, a delegate, target and action, accessibility label, placeholder, string
/// value, frame notifications, the two width caps, label/palette label/tool tip), with this
/// file's own values where the product's come from the bar or the app: the item's identifier is
/// the row's unique one rather than `helm.search`, the delegate and the target are one stand-in
/// that implements no delegate method and whose action is its own `submitted(_:)`, the labels are
/// the literal `"Search"`, the placeholder and the string value are empty, the offer cap's
/// constant is this file's literal rather than `ShellBarLayout.searchWidth`, and neither cap is
/// ever made active. Not here: the three stores into the bar (`searchRestCap`, `searchOfferCap`,
/// `searchItem`), the bar's other items, `restSearch`, `watchSearchFieldFrame`, and the window
/// itself (`SettingsWindow`) — a plain titled window with a one-item toolbar stands in.
///
/// **Cleanup.** In-process `UserDefaults.standard.removeObject(forKey:)` only, registered as a
/// teardown block before the first write is possible: the two exact names the run can write
/// (`<identifier>.recents`, and the control's explicit name) and any other key that was absent
/// before the case and carries this run's token in its name or its value. A key present before
/// the case is never removed. The process's activation policy is asked back to what it was when
/// the row began.
@MainActor
final class AToolbarSearchItemsRecentsInAShownWindowTests: XCTestCase {

    private static let prefix = "[recents-shown]"

    private let token = UUID().uuidString.prefix(8).lowercased()
    private var domainName: String { Bundle.main.bundleIdentifier ?? "?" }

    private func domain() -> [String: Any] {
        UserDefaults.standard.persistentDomain(forName: domainName) ?? [:]
    }

    private func say(_ text: String) {
        print("\(Self.prefix) \(text)")
    }

    // MARK: - Pieces

    @objc private final class Target: NSObject, NSSearchFieldDelegate {
        var submits = 0
        @objc func submitted(_ sender: Any?) { submits += 1 }
    }

    private final class OneItemToolbar: NSObject, NSToolbarDelegate {
        let item: NSToolbarItem
        init(_ item: NSToolbarItem) { self.item = item }
        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [item.itemIdentifier] }
        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [item.itemIdentifier] }
        func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                     willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? { item }
    }

    private func turns(_ count: Int = 30) {
        for _ in 0..<count { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02)) }
        _ = UserDefaults.standard.synchronize()
    }

    /// Turns the run loop until `done` holds or `seconds` have passed; whether it held.
    private func spin(_ seconds: TimeInterval, until done: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while !done() && Date() < end {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return done()
    }

    /// A text a value carries, whatever its type.
    private func text(of value: Any) -> String {
        if let data = value as? Data { return String(decoding: data, as: UTF8.self) + "\(value)" }
        return "\(value)"
    }

    /// One reading of the domain against the one taken before the case.
    private struct Reading {
        var newKeys: [String]
        var changedKeys: [String]
        var removedKeys: [String]
        var keysWhoseValueCarriesTheWord: [String]
        var recentsKeyAppeared: Bool
        var recentsKeyValue: String?
    }

    private func read(before: [String: Any], word: String, recentsKey: String) -> Reading {
        let after = domain()
        let newKeys = after.keys.filter { before[$0] == nil }.sorted()
        let changed = after.keys.filter { key in
            guard let was = before[key] else { return false }
            return !(was as AnyObject).isEqual(after[key] as AnyObject)
        }.sorted()
        let removed = before.keys.filter { after[$0] == nil }.sorted()
        let carrying = after.filter { text(of: $0.value).contains(word) }.map(\.key).sorted()
        return Reading(newKeys: newKeys, changedKeys: changed, removedKeys: removed,
                       keysWhoseValueCarriesTheWord: carrying,
                       recentsKeyAppeared: before[recentsKey] == nil && after[recentsKey] != nil,
                       recentsKeyValue: after[recentsKey].map { "\($0)" })
    }

    private func report(_ row: String, _ moment: String, _ r: Reading, word: String, recentsKey: String) {
        let valuesOfNew = r.newKeys.map { key in
            "\(key)=<carriesWord:\(text(of: domain()[key] as Any).contains(word))>"
        }
        say("row=\(row) moment=\(moment) newKeys=\(r.newKeys) newKeyValues=\(valuesOfNew) "
            + "changedKeys=\(r.changedKeys) removedKeys=\(r.removedKeys) "
            + "keysWhoseValueCarriesTheWord=\(r.keysWhoseValueCarriesTheWord) "
            + "recentsKey=\(recentsKey) recentsKeyAppeared=\(r.recentsKeyAppeared) "
            + "recentsKeyValue=\(r.recentsKeyValue ?? "nil")")
    }

    // MARK: - One row

    /// What one row saw, for the assertions of the two tests.
    private struct Outcome {
        var fieldFound = false
        var windowShown = false
        var windowWasKey = false
        var appWasActive = false
        var fieldHadEditor = false
        var submits = 0
        var inMemory: [String] = []
        var word = ""
        var afterCommit: Reading?
        var afterEndEditing: Reading?
        var afterResignKey: Reading?
        var afterClose: Reading?
        var nameOnField: String?
    }

    /// Builds the item as `makeSearchItem` does, asks for the app to be activated and shows its
    /// window, waits for the window to be key, types, commits, and reads the domain at the four
    /// moments. A window that did not become key ends the row before it types.
    private func row(_ name: String, explicitName: String?) -> Outcome {
        let policyBefore = NSApplication.shared.activationPolicy()
        let identifier = "helm.tests.recentsShown.\(name).\(token)"
        let recentsKey = "\(identifier).recents"
        let word = "zqshown\(name)\(token)"
        var outcome = Outcome()
        outcome.word = word

        let before = domain()
        // Registered before anything can write.
        addTeardownBlock { [token, before, recentsKey, explicitName] in
            let defaults = UserDefaults.standard
            let now = defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "?") ?? [:]
            for exact in [recentsKey, explicitName].compactMap({ $0 }) where before[exact] == nil {
                defaults.removeObject(forKey: exact)
            }
            for (key, value) in now where before[key] == nil {
                if key.contains(token) || "\(value)".contains(token) { defaults.removeObject(forKey: key) }
            }
        }
        say("row=\(name) start domain=\(domainName) identifier=\(identifier) word=\(word) "
            + "explicitName=\(explicitName ?? "nil") keyCountBefore=\(before.count) "
            + "recentsKeyPresentBefore=\(before[recentsKey] != nil)")

        // --- `SettingsToolbar.makeSearchItem`'s lines, one for one, with this file's own values (the header says which) ---
        let target = Target()
        let item = NSSearchToolbarItem(itemIdentifier: NSToolbarItem.Identifier(identifier))
        let field = NSSearchField()
        field.sendsWholeSearchString = true
        field.cell?.sendsActionOnEndEditing = false
        field.recentsAutosaveName = explicitName          // the product: nil
        field.delegate = target
        field.target = target
        field.action = #selector(Target.submitted(_:))
        field.setAccessibilityLabel("Search")
        field.placeholderString = ""
        field.stringValue = ""
        field.postsFrameChangedNotifications = true
        let cap = field.widthAnchor.constraint(lessThanOrEqualToConstant: 0)
        cap.priority = .defaultLow
        cap.identifier = "helm.search.restCap"
        let offerCap = field.widthAnchor.constraint(lessThanOrEqualToConstant: 240)
        offerCap.priority = .defaultLow
        offerCap.identifier = "helm.search.offerCap"
        offerCap.isActive = false
        item.searchField = field
        item.label = "Search"
        item.paletteLabel = "Search"
        item.toolTip = "Search"
        // --- end ---
        outcome.fieldFound = item.searchField === field
        outcome.nameOnField = field.recentsAutosaveName

        let delegate = OneItemToolbar(item)
        let bar = NSToolbar(identifier: "helm.tests.recentsShown.bar.\(name).\(token)")
        bar.delegate = delegate
        bar.autosavesConfiguration = false
        let window = NSWindow(contentRect: NSRect(x: 80, y: 200, width: 700, height: 200),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.toolbar = bar
        let other = NSWindow(contentRect: NSRect(x: 820, y: 200, width: 300, height: 120),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        defer {
            window.toolbar = nil
            window.close()
            other.close()
            NSApp.setActivationPolicy(policyBefore)
            withExtendedLifetime((target, delegate, bar, item)) {}
        }

        // The product's own order (`SettingsWindow.show`): a regular app, activated, then the
        // window ordered front and key. Without the activation the window is shown and not key.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        _ = spin(5) { window.isKeyWindow }
        turns(15)
        outcome.windowShown = window.isVisible
        outcome.windowWasKey = window.isKeyWindow
        outcome.appWasActive = NSApp.isActive
        say("row=\(name) window visible=\(window.isVisible) key=\(window.isKeyWindow) "
            + "toolbarItems=\(bar.items.count) appActive=\(NSApp.isActive)")
        guard window.isKeyWindow else { return outcome }

        // The field made first responder: the item's own entry first, the window's after.
        item.beginSearchInteraction()
        turns(10)
        if field.currentEditor() == nil { _ = window.makeFirstResponder(field) }
        turns(5)
        guard let editor = field.currentEditor() as? NSTextView else { return outcome }
        outcome.fieldHadEditor = true

        editor.insertText(word, replacementRange: NSRange(location: NSNotFound, length: 0))
        turns(5)
        guard let ret = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                         windowNumber: window.windowNumber, context: nil, characters: "\r",
                                         charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)
        else { return outcome }
        editor.keyDown(with: ret)
        turns(30)
        outcome.submits = target.submits
        outcome.inMemory = field.recentSearches
        say("row=\(name) committed stringValue=\(field.stringValue) submits=\(target.submits) "
            + "inMemory=\(field.recentSearches) nameOnField=\(field.recentsAutosaveName ?? "nil")")
        let one = read(before: before, word: word, recentsKey: recentsKey)
        outcome.afterCommit = one
        report(name, "afterCommit", one, word: word, recentsKey: recentsKey)

        // The field ends editing.
        _ = window.makeFirstResponder(nil)
        turns(30)
        let two = read(before: before, word: word, recentsKey: recentsKey)
        outcome.afterEndEditing = two
        report(name, "afterFieldEndsEditing", two, word: word, recentsKey: recentsKey)

        // Another window is made key, so this one should resign it; the line below prints whether it did.
        other.makeKeyAndOrderFront(nil)
        turns(30)
        say("row=\(name) after resign: window.key=\(window.isKeyWindow) other.key=\(other.isKeyWindow)")
        let three = read(before: before, word: word, recentsKey: recentsKey)
        outcome.afterResignKey = three
        report(name, "afterWindowResignsKey", three, word: word, recentsKey: recentsKey)

        // The window closes.
        window.toolbar = nil
        window.close()
        turns(30)
        let four = read(before: before, word: word, recentsKey: recentsKey)
        outcome.afterClose = four
        report(name, "afterWindowCloses", four, word: word, recentsKey: recentsKey)
        return outcome
    }

    /// The first assertion of each test: the window became key. Whether the test goes on.
    private func reachedKey(_ o: Outcome, row name: String) -> Bool {
        XCTAssertTrue(o.windowWasKey,
                      "precondition: key=\(o.windowWasKey) visible=\(o.windowShown) appActive=\(o.appWasActive) — "
                      + "the window is not key although activation was asked for and the window ordered front, "
                      + "so nothing below says anything about a key window. row \(name)")
        return o.windowWasKey
    }

    private func preconditions(_ o: Outcome, row name: String) {
        XCTAssertTrue(o.fieldFound, "precondition: the item does not hold the field built for it. row \(name)")
        XCTAssertTrue(o.windowShown, "precondition: the window is not shown. row \(name)")
        XCTAssertTrue(o.fieldHadEditor, "precondition: the field never took first responder. row \(name)")
        XCTAssertEqual(o.submits, 1, "precondition: the action did not fire exactly once. row \(name)")
        XCTAssertEqual(o.inMemory, [o.word],
                       "precondition: the field's own recent searches are not the word alone. row \(name)")
    }

    // MARK: - The rows

    /// **Row N: the product's shape, a nil `recentsAutosaveName`.** Records; fails only on a
    /// broken precondition.
    func testTheProductsShapeInAShownKeyWindowRecordsWhatItWrites() throws {
        let o = row("n", explicitName: nil)
        guard reachedKey(o, row: "n") else { return }
        preconditions(o, row: "n")
        XCTAssertNil(o.nameOnField, "precondition: the product's shape has a name on the field")
        for (moment, reading) in [("afterCommit", o.afterCommit), ("afterFieldEndsEditing", o.afterEndEditing),
                                  ("afterWindowResignsKey", o.afterResignKey), ("afterWindowCloses", o.afterClose)] {
            XCTAssertNotNil(reading, "precondition: no reading at \(moment)")
        }
        let last = o.afterClose
        say("row=n VERDICT-INPUT recentsKeyAppearedAtAnyMoment="
            + "\([o.afterCommit, o.afterEndEditing, o.afterResignKey, o.afterClose].contains { $0?.recentsKeyAppeared == true}) "
            + "newKeysAtTheEnd=\(last?.newKeys ?? []) "
            + "keysCarryingTheWordAtTheEnd=\(last?.keysWhoseValueCarriesTheWord ?? [])")
    }

    /// **Row C: the control.** The same, with a unique explicit name. The instrument must see a
    /// write under that name in this state, or silence in row N means nothing.
    func testTheSameWithAnExplicitNameShowsTheInstrumentSeesAWrite() throws {
        let explicit = "com.helm.tests.recentsShown.named.c.\(token)"
        let o = row("c", explicitName: explicit)
        guard reachedKey(o, row: "c") else { return }
        preconditions(o, row: "c")
        XCTAssertEqual(o.nameOnField, explicit, "precondition: the name was not kept on the field")
        let seenAt = [("afterCommit", o.afterCommit), ("afterFieldEndsEditing", o.afterEndEditing),
                      ("afterWindowResignsKey", o.afterResignKey), ("afterWindowCloses", o.afterClose)]
            .filter { $0.1?.newKeys.contains(explicit) == true || $0.1?.keysWhoseValueCarriesTheWord.contains(explicit) == true }
            .map(\.0)
        say("row=c VERDICT-INPUT explicitKey=\(explicit) wroteAtMoments=\(seenAt)")
        XCTAssertFalse(seenAt.isEmpty,
                       "the control row saw no write under the explicit name at any moment: the instrument is blind in this state")
        XCTAssertTrue(o.afterClose?.keysWhoseValueCarriesTheWord.contains(explicit) == true
                      || o.afterCommit?.keysWhoseValueCarriesTheWord.contains(explicit) == true,
                      "the explicit key does not carry the word")
    }
}
