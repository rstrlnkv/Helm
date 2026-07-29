# Duplicates: Select Every Extra, and Space to Look — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One button that baskets the extras of every group, one that empties the basket without deleting, and Space to preview the selected file the way the Finder does.

**Architecture:** The select-all runs the existing per-group rule across every group rather than reimplementing it — the two must never be able to disagree about which copy survives. The preview is `QLPreviewPanel`, reached by the same zero-size-button-with-a-shortcut device the list already uses for Return.

**Tech Stack:** Swift 6, SwiftUI, AppKit, QuickLookUI, XCTest.

**Spec:** `docs/superpowers/specs/2026-07-29-0.8.0-features-design.md` § 3.

---

## File structure

| File | Change |
|---|---|
| `Sources/Modules/Duplicates/UI/DuplicatesViewModel.swift` | `basketAllExtras()`, `clearBasket()`. |
| `Sources/Modules/Duplicates/UI/DuplicatePreview.swift` | **New.** Which URL a preview would show, plus the panel's owner. |
| `Sources/Modules/Duplicates/UI/DuplicatesView.swift` | Space shortcut, context menu item, accessibility action. |
| `Sources/Modules/Duplicates/UI/DuplicatesSettingsPage.swift` | The two buttons. |
| `Sources/Modules/Duplicates/UI/DuplicatesStrings.swift` | New strings, eight languages. |
| `Tests/Modules/Duplicates/UITests/BasketAllExtrasTests.swift` | **New.** |
| `Tests/Modules/Duplicates/UITests/DuplicatePreviewTests.swift` | **New.** |

---

### Task 1: Basket every extra, and a way back

**Files:**
- Modify: `Sources/Modules/Duplicates/UI/DuplicatesViewModel.swift`
- Test: `Tests/Modules/Duplicates/UITests/BasketAllExtrasTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/Modules/Duplicates/UITests/BasketAllExtrasTests.swift`.

Two facts about the fixture, both taken from `DuplicateBasketArithmeticTests.swift` in the same directory rather than invented. **Read that file before writing this one.**

- The groups reach the view model through the transport, not through a property: a fake transport answers the `find` command with encoded groups, then `search()` runs and the test yields until `phase == .result`. So the fixture is `async`.
- `UserFileScope` judges real paths, and it refuses things outside the user's own files. Fixtures therefore live under `NSHomeDirectory()`, which is what the existing file does with `"\(home)/Downloads"`.

```swift
import XCTest
import HelmContract
import HelmRuntime
import HelmUI
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// The one thing this module refuses to do is offer every copy of a file. A
/// button that acts on every group at once is the likeliest place for that
/// refusal to be lost, so it is asserted rather than assumed.
@MainActor
final class BasketAllExtrasTests: XCTestCase {

    private final class OneAnswerTransport: EngineTransport, @unchecked Sendable {
        private let groups: [DuplicateGroup]
        var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }
        init(groups: [DuplicateGroup]) { self.groups = groups }
        func send(_ command: EngineCommand) async throws -> Data {
            guard command.name == "find" else { return Data() }
            return (try? JSONEncoder().encode(groups)) ?? Data()
        }
    }

    private var home: String { NSHomeDirectory() }

    private func model(_ groups: [DuplicateGroup]) async -> DuplicatesViewModel {
        let store = NamespacedStore(namespace: "duplicates", backing: InMemoryKeyValueStore())
        store.set("\(home)/Downloads", for: "folder")
        let dvm = DuplicatesViewModel(vm: ModuleViewModel(transport:
            OneAnswerTransport(groups: groups)), store: store)
        dvm.search()
        for _ in 0..<200 where dvm.phase != .result { await Task.yield() }
        return dvm
    }

    /// Under the home directory, because `UserFileScope` judges the real path
    /// and a fixture in `/tmp` would be refused for the wrong reason.
    private func group(_ names: [String], bytes: Int = 2_000_000) -> DuplicateGroup {
        DuplicateGroup(bytes: bytes, paths: names.map { "\(home)/Downloads/\($0)" })
    }

    func testTheCopyThatStaysIsNeverBasketed() async {
        let dvm = await model([group(["a1", "a2", "a3"]), group(["b1", "b2"])])
        dvm.basketAllExtras()
        XCTAssertFalse(dvm.basket.contains("\(home)/Downloads/a1"),
                       "the first copy of a group stays")
        XCTAssertFalse(dvm.basket.contains("\(home)/Downloads/b1"))
    }

    func testEveryExtraInEveryGroupIsBasketed() async {
        let dvm = await model([group(["a1", "a2", "a3"]), group(["b1", "b2"])])
        dvm.basketAllExtras()
        XCTAssertEqual(Set(dvm.basket), [
            "\(home)/Downloads/a2", "\(home)/Downloads/a3", "\(home)/Downloads/b2",
        ])
    }

    /// The same scope gate the per-group button applies. A button that baskets
    /// something the engine will refuse is a button that lies.
    func testAPathOutOfScopeIsNotBasketed() async {
        let outside = DuplicateGroup(bytes: 2_000_000, paths: [
            "\(home)/Downloads/a1", "/System/Library/CoreServices/a2",
        ])
        let dvm = await model([outside])
        dvm.basketAllExtras()
        XCTAssertFalse(dvm.basket.contains("/System/Library/CoreServices/a2"))
    }

    func testRunningItTwiceDoesNotDoubleTheBasket() async {
        let dvm = await model([group(["a1", "a2"])])
        dvm.basketAllExtras()
        dvm.basketAllExtras()
        XCTAssertEqual(dvm.basket, ["\(home)/Downloads/a2"])
    }

    func testClearEmptiesTheBasketAndTrashesNothing() async {
        let dvm = await model([group(["a1", "a2"])])
        dvm.basketAllExtras()
        XCTAssertFalse(dvm.basket.isEmpty)
        dvm.clearBasket()
        XCTAssertTrue(dvm.basket.isEmpty)
        XCTAssertEqual(dvm.removedCount, 0, "clearing is not deleting")
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `swift test --filter BasketAllExtrasTests`
Expected: FAIL — `value of type 'DuplicatesViewModel' has no member 'basketAllExtras'`.

- [ ] **Step 3: Write the implementation**

In `Sources/Modules/Duplicates/UI/DuplicatesViewModel.swift`, immediately after `basketExtras(of:)`:

```swift
    /// Every group's extras, through the same rule the per-group button uses.
    ///
    /// Deliberately a loop over `basketExtras(of:)` rather than its own walk of
    /// the groups: two implementations of "which copy survives" is two answers
    /// to the only question on this page that costs someone a file.
    public func basketAllExtras() {
        for group in groups { basketExtras(of: group) }
    }

    /// Empties the basket. Nothing is deleted, nothing is moved.
    ///
    /// The counterpart to `basketAllExtras`, and the reason it can exist: one
    /// press that ticks three hundred checkboxes needs one press that unticks
    /// them. Named apart from `emptyBasket()`, which is the one that trashes —
    /// two methods about the basket differing only in outcome must not read
    /// alike at the call site.
    public func clearBasket() {
        basket.removeAll()
    }
```

- [ ] **Step 4: Run it and watch it pass**

Run: `swift test --filter BasketAllExtrasTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/Modules/Duplicates/UI/DuplicatesViewModel.swift \
        Tests/Modules/Duplicates/UITests/BasketAllExtrasTests.swift
git commit -m "feat(duplicates): every group's extras at once, and a way back out

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Which file a preview would show

**Files:**
- Create: `Sources/Modules/Duplicates/UI/DuplicatePreview.swift`
- Test: `Tests/Modules/Duplicates/UITests/DuplicatePreviewTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/Modules/Duplicates/UITests/DuplicatePreviewTests.swift`:

`DuplicateGroup` carries `[Copy]`, each with its own size, and provides
`init(bytes:paths:)` for fixtures where every copy occupies the same amount —
which is all this test needs. Nothing here is judged by `UserFileScope`, so
`/tmp` paths are fine, unlike in Task 1.

```swift
import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// The thin decidable part of the preview: which file it would show. The panel
/// itself is AppKit responder-chain plumbing and is checked in the running app.
final class DuplicatePreviewTests: XCTestCase {
    private func group(_ paths: [String]) -> DuplicateGroup {
        DuplicateGroup(bytes: 1_000_000, paths: paths)
    }

    func testTheSelectedPathIsTheTarget() {
        let url = DuplicatePreview.target(selection: "/tmp/a2", in: [group(["/tmp/a1", "/tmp/a2"])])
        XCTAssertEqual(url?.path, "/tmp/a2")
    }

    func testNothingSelectedIsNothingToShow() {
        XCTAssertNil(DuplicatePreview.target(selection: nil, in: [group(["/tmp/a1"])]))
    }

    /// A copy that has just been trashed leaves the groups while the selection
    /// still names it. Opening a panel onto a file that is gone shows an empty
    /// frame with no explanation.
    func testAPathThatHasLeftTheGroupsIsNotShown() {
        XCTAssertNil(DuplicatePreview.target(selection: "/tmp/gone",
                                             in: [group(["/tmp/a1", "/tmp/a2"])]))
    }

    func testAnEmptyResultShowsNothing() {
        XCTAssertNil(DuplicatePreview.target(selection: "/tmp/a1", in: []))
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `swift test --filter DuplicatePreviewTests`
Expected: FAIL — `cannot find 'DuplicatePreview' in scope`.

- [ ] **Step 3: Write the decidable part**

Create `Sources/Modules/Duplicates/UI/DuplicatePreview.swift` with, for now, only the pure function:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import AppKit
import QuickLookUI
import Module_Duplicates_Engine

public enum DuplicatePreview {
    /// The file a preview would show, or nil when there is nothing to show.
    ///
    /// The selection is checked against the groups rather than trusted: a copy
    /// that has just been trashed leaves the list while the selection still
    /// names it, and a panel opened onto a file that is gone is an empty frame
    /// with no explanation.
    public static func target(selection: String?, in groups: [DuplicateGroup]) -> URL? {
        guard let selection,
              groups.contains(where: { $0.paths.contains(selection) }) else { return nil }
        return URL(fileURLWithPath: selection)
    }
}
```

- [ ] **Step 4: Run it and watch it pass**

Run: `swift test --filter DuplicatePreviewTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/Modules/Duplicates/UI/DuplicatePreview.swift \
        Tests/Modules/Duplicates/UITests/DuplicatePreviewTests.swift
git commit -m "feat(duplicates): what a preview would show, and when there is nothing

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: The panel itself

**Files:**
- Modify: `Sources/Modules/Duplicates/UI/DuplicatePreview.swift`

No unit test: this is AppKit responder-chain plumbing, verified live in Task 6.

- [ ] **Step 1: Add the owner**

Append to `Sources/Modules/Duplicates/UI/DuplicatePreview.swift`:

```swift
/// Owns the shared Quick Look panel for one file.
///
/// `QLPreviewPanel` is driven through the responder chain: something in the
/// chain has to answer `acceptsPreviewPanelControl` and then hand itself over
/// as data source and delegate. SwiftUI puts nothing there, so this is a bare
/// `NSView` inserted into the hierarchy for the sole purpose of being that
/// something.
final class PreviewPanelOwner: NSView, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    var url: URL?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { url != nil }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        url as (any QLPreviewItem)?
    }

    /// Toggles, which is what Space does in the Finder and therefore what a
    /// person will try. The panel is a shared singleton, so asking whether it
    /// is visible is asking about the whole app, not about this list — which is
    /// correct here: only one list can be in front.
    func toggle(_ url: URL?) {
        self.url = url
        guard url != nil, let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists() && panel.isVisible {
            panel.orderOut(nil)
        } else {
            window?.makeFirstResponder(self)
            panel.makeKeyAndOrderFront(nil)
        }
        panel.reloadData()
    }
}

/// Puts a `PreviewPanelOwner` in the SwiftUI hierarchy and hands the view a
/// way to drive it.
struct PreviewPanelHost: NSViewRepresentable {
    /// Called once with the owner so the view can toggle it from a button.
    let attach: (PreviewPanelOwner) -> Void

    func makeNSView(context: Context) -> PreviewPanelOwner {
        let view = PreviewPanelOwner()
        attach(view)
        return view
    }

    func updateNSView(_ nsView: PreviewPanelOwner, context: Context) {}
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds clean. If `QuickLookUI` is not found, add `.linkedFramework("QuickLookUI")` to the `Module_Duplicates_UI` target in `Package.swift` — but try the plain import first; the macOS SDK usually resolves it without help.

- [ ] **Step 3: Commit**

```bash
git add Sources/Modules/Duplicates/UI/DuplicatePreview.swift
git commit -m "feat(duplicates): an owner for the Quick Look panel

SwiftUI puts nothing in the responder chain that Quick Look can talk to, so
this is a bare NSView whose whole job is to be that something.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Space in the list

**Files:**
- Modify: `Sources/Modules/Duplicates/UI/DuplicatesStrings.swift`
- Modify: `Sources/Modules/Duplicates/UI/DuplicatesView.swift`

- [ ] **Step 1: Add the string**

In `Sources/Modules/Duplicates/UI/DuplicatesStrings.swift`, beside `reveal`:

```swift
    static var quickLook: String { L("Quick Look", [.ru: "Быстрый просмотр", .es: "Vista rápida", .fr: "Coup d’œil", .de: "Übersicht", .ja: "クイックルック", .zh: "快速查看", .pt: "Visualização rápida"]) }
```

The name is macOS's own for this feature in each language, not a translation of the English — ARCHITECTURE.md § Localization says where the system's tables are. Check the spelling against the system before committing; a feature macOS already names must be called what macOS calls it.

- [ ] **Step 2: Hold the owner and drive it**

In `Sources/Modules/Duplicates/UI/DuplicatesView.swift`, add a state property beside `selection`:

```swift
    /// Held so the Space shortcut has something to talk to. Assigned once,
    /// when the representable makes its view.
    @State private var previewOwner: PreviewPanelOwner?
```

Add a helper beside `reveal(_:)`:

```swift
    private func preview(_ path: String?) {
        previewOwner?.toggle(DuplicatePreview.target(selection: path, in: dvm.groups))
    }
```

- [ ] **Step 3: Put the host in the hierarchy and add the shortcut**

Extend the existing `.overlay` on the `List` — the one that already holds the Return button — so it carries all three:

```swift
        .overlay {
            // Zero-size and invisible: a button still owns its shortcut, and
            // the rows already carry the visible affordances in their context
            // menus. A context menu needs a right-click, which Full Keyboard
            // Access without VoiceOver cannot produce.
            ZStack {
                Button("") { reveal(selection) }
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(selection == nil)
                Button("") { preview(selection) }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(selection == nil)
                PreviewPanelHost { previewOwner = $0 }
                    .frame(width: 0, height: 0)
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
```

- [ ] **Step 4: Give it a visible affordance**

In `row(path:stays:)`, extend both the context menu and the accessibility actions:

```swift
        .contextMenu {
            Button(DupStr.quickLook) { preview(path) }
            Button(DupStr.reveal) { reveal(path) }
        }
        // The same actions where VoiceOver can reach them, since the menu
        // above needs a right-click.
        .accessibilityActions {
            Button(DupStr.quickLook) { preview(path) }
            Button(DupStr.reveal) { reveal(path) }
        }
```

Note both of these act on `path` — the row's own file — not on `selection`. Right-clicking a row that is not selected must preview that row.

- [ ] **Step 5: Run the guards and the suite**

Run: `swift build && swift test`
Expected: builds clean, 0 failures. `NamedControlsTests` tolerates the two `Button("")` forms because they are the established shortcut device and the file already carries one; if it flags them, add the accessibility label the guard asks for rather than weakening the guard.

- [ ] **Step 6: Commit**

```bash
git add Sources/Modules/Duplicates/UI/DuplicatesView.swift \
        Sources/Modules/Duplicates/UI/DuplicatesStrings.swift
git commit -m "feat(duplicates): Space looks at the selected copy

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: The two buttons on the page

**Files:**
- Modify: `Sources/Modules/Duplicates/UI/DuplicatesStrings.swift`
- Modify: `Sources/Modules/Duplicates/UI/DuplicatesSettingsPage.swift`

- [ ] **Step 1: Add the strings**

In `Sources/Modules/Duplicates/UI/DuplicatesStrings.swift`, beside `basketExtras`:

```swift
    /// Not "Select all", which invites exactly the reading this module
    /// refuses. A control that lies about its effect on files is the failure
    /// this page is most exposed to.
    static var basketAllExtras: String { L("All extras to basket", [.ru: "Все лишние — к удалению", .es: "Todos los sobrantes a la cesta", .fr: "Tous les surplus au panier", .de: "Alle Überzähligen in den Korb", .ja: "余分をすべてバスケットへ", .zh: "所有多余的放入收集篮", .pt: "Todos os excedentes para a cesta"]) }
    static var clearBasket: String { L("Clear", [.ru: "Очистить", .es: "Vaciar", .fr: "Vider", .de: "Leeren", .ja: "クリア", .zh: "清空", .pt: "Limpar"]) }
```

- [ ] **Step 2: Add "all extras" to the toolbar**

In `toolbar(_:)`, inside the `else` branch, after the search button's closing `}` and before the closing `}` of the `else`:

```swift
                if !dvm.groups.isEmpty {
                    Button(DupStr.basketAllExtras) { dvm.basketAllExtras() }
                        .controlSize(.small)
                        .fixedSize()
                }
```

It appears only when there is something to act on: a button that does nothing is a button somebody presses twice before reading the screen.

- [ ] **Step 3: Add the clear beside Move to Trash**

In `basketRow`, between the `Spacer()` and the trash button:

```swift
            Button(DupStr.clearBasket) { dvm.clearBasket() }
                .controlSize(.small)
```

It is quiet next to a prominent destructive button, which is the right weight: clearing is the safe one, and the eye should still land on the one that deletes.

- [ ] **Step 4: Run the guards and the suite**

Run: `swift build && swift test --filter NamedControlsTests && swift test`
Expected: builds clean, PASS, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/Modules/Duplicates/UI/DuplicatesSettingsPage.swift \
        Sources/Modules/Duplicates/UI/DuplicatesStrings.swift
git commit -m "feat(duplicates): the two buttons, saying what they do

'All extras to basket', never 'Select all' — the second invites exactly the
reading this module refuses, and one copy of everything always stays.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Use it on a real folder

**Files:** none changed if it passes.

The harness rule applies with force here: a scan lands in the module's own store and the page reopens on it at every launch. Point it at a temporary folder and clean up.

- [ ] **Step 1: Build a folder with real duplicates**

```bash
mkdir -p "$TMPDIR/dup-test/nested"
for i in 1 2 3; do mkfile 2m "$TMPDIR/dup-test/big$i.bin" 2>/dev/null || \
  dd if=/dev/urandom of="$TMPDIR/dup-test/big$i.bin" bs=1m count=2; done
cp "$TMPDIR/dup-test/big1.bin" "$TMPDIR/dup-test/nested/copy-of-big1.bin"
cp "$TMPDIR/dup-test/big2.bin" "$TMPDIR/dup-test/nested/copy-of-big2.bin"
ls -la "$TMPDIR/dup-test" "$TMPDIR/dup-test/nested"
```

Use a real image or PDF for at least one pair — Quick Look on random bytes shows a generic icon and proves nothing about the panel.

- [ ] **Step 2: Install and scan**

```bash
pkill -f 'MacOS/HelmApp'; bash Scripts/package-app.sh
rm -rf /Applications/Helm.app
ditto "$TMPDIR/helm-package/Helm.app" /Applications/Helm.app
codesign --verify --deep --strict /Applications/Helm.app
xattr -dr com.apple.quarantine /Applications/Helm.app && open /Applications/Helm.app
```

Settings → Duplicates → choose `$TMPDIR/dup-test` → Search.

- [ ] **Step 3: Check the button**

Press "All extras to basket". Expected: the basket count equals the number of extras, and **every group still shows one row badged "stays" with its checkbox absent**. If any group has all rows ticked, stop — the rule was reimplemented somewhere.

- [ ] **Step 4: Check the clear**

Press Clear. Expected: the basket empties, the bar goes away, no file moves. Check the Trash is empty.

- [ ] **Step 5: Check Space**

Click a row, press Space. Expected: the Quick Look panel opens on that file. Press Space again: it closes. Arrow to another row with the panel open: it follows.

**If the panel does not appear at all**, this is the risk the spec names: an accessory app's settings window may not give the panel key focus. Fall back to opening the preview as a sheet rather than shipping a Space key that sometimes does nothing, and say so in the changelog.

- [ ] **Step 6: Check the right-click path**

Right-click a row that is *not* selected. Expected: the menu's Quick Look previews **that** row, not the selected one.

- [ ] **Step 7: Leave nothing behind**

```bash
rm -rf "$TMPDIR/dup-test"
```

Then, in the app, use Duplicates' own "Choose another folder" so the module does not reopen on a folder that no longer exists. Confirm what is stored:

```bash
ls ~/Library/Application\ Support/Helm/
defaults read com.helm.app | grep -i duplicat
```

Expected: nothing naming the temporary folder. Twice now the app has been handed back with somebody's test tree in it — check before saying this is done.

- [ ] **Step 8: Check the harness rule**

Run: `grep -r HELM_DEBUG Sources/`
Expected: no output.

- [ ] **Step 9: Record it**

Add to `CHANGELOG.md` under `## [Unreleased] — 0.8.0` → `### Added`, and to `Sources/HelmApp/ChangelogData.swift`.

```bash
git add CHANGELOG.md Sources/HelmApp/ChangelogData.swift
git commit -m "docs: the two buttons and Quick Look, in both changelogs

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```
