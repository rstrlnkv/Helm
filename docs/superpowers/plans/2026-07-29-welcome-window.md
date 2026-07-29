# Welcome Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A window shown once per installation that introduces Helm and each of its nine modules, with Back / Next / Skip.

**Architecture:** Every rule worth a test lives in `HelmUI` (which has a test target); `HelmApp` keeps only the `NSWindow` and the wiring. The steps are built from `ModuleMetadata` that the descriptors already carry in eight languages, so no module description is written a second time. `PermissionAudit` is deferred until the window closes, because both want the first launch.

**Tech Stack:** Swift 6, SwiftUI, AppKit (`NSWindow`), XCTest.

**Spec:** `docs/superpowers/specs/2026-07-29-0.8.0-features-design.md` § 1.

---

## File structure

| File | Responsibility |
|---|---|
| `Sources/HelmUI/Welcome/WelcomeFlow.swift` | Where the user is; what Back/Next do there. No AppKit, no SwiftUI. |
| `Sources/HelmUI/Welcome/WelcomeGate.swift` | Whether this installation has seen the tour. |
| `Sources/HelmUI/Welcome/WelcomeStep.swift` | One step's content, and building the list from `[ModuleMetadata]`. |
| `Sources/HelmUI/Welcome/WelcomeStrings.swift` | The chrome, in eight languages. |
| `Sources/HelmUI/Welcome/WelcomeView.swift` | The SwiftUI body. Takes steps, owns a `WelcomeFlow`, reports "closed". |
| `Sources/HelmApp/WelcomeWindow.swift` | The `NSWindow`, the revision write, the deferred audit. |
| `Tests/HelmUITests/WelcomeFlowTests.swift` | Step bounds and button states. |
| `Tests/HelmUITests/WelcomeGateTests.swift` | Shown once, and again only after a bump. |
| `Tests/HelmUITests/WelcomeStepsTests.swift` | One step per module; nothing empty in any language. |

`WelcomeSteps.build` takes `[ModuleMetadata]` rather than reaching for `ModuleRegistry`, because `ModuleRegistry` lives in `HelmApp` and `HelmApp` has no test target. That is the whole reason for the signature; do not "simplify" it back.

---

### Task 1: `WelcomeFlow` — where the user is

**Files:**
- Create: `Sources/HelmUI/Welcome/WelcomeFlow.swift`
- Test: `Tests/HelmUITests/WelcomeFlowTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/HelmUITests/WelcomeFlowTests.swift`:

```swift
import XCTest
@testable import HelmUI

/// The tour's position and what the buttons may do there. Deliberately knows
/// nothing about windows: a flow that could close itself could not be asked
/// what it would do without one.
final class WelcomeFlowTests: XCTestCase {
    func testItStartsAtTheBeginningAndCannotGoBack() {
        let flow = WelcomeFlow(stepCount: 10)
        XCTAssertEqual(flow.step, 0)
        XCTAssertFalse(flow.canGoBack)
        XCTAssertFalse(flow.isLastStep)
    }

    func testNextAdvancesAndBackReturns() {
        var flow = WelcomeFlow(stepCount: 3)
        flow.next()
        XCTAssertEqual(flow.step, 1)
        XCTAssertTrue(flow.canGoBack)
        flow.back()
        XCTAssertEqual(flow.step, 0)
        XCTAssertFalse(flow.canGoBack)
    }

    func testTheLastStepSaysSoAndNextGoesNoFurther() {
        var flow = WelcomeFlow(stepCount: 2)
        flow.next()
        XCTAssertTrue(flow.isLastStep)
        flow.next()
        XCTAssertEqual(flow.step, 1, "next() past the end must not run off the list")
    }

    func testBackAtTheStartDoesNothing() {
        var flow = WelcomeFlow(stepCount: 3)
        flow.back()
        XCTAssertEqual(flow.step, 0)
    }

    /// A tour of nothing is a window with no content and no way out but Skip.
    /// It cannot happen with the real registry, and the type answers for it
    /// anyway rather than trapping on an empty array.
    func testAnEmptyTourIsItsOwnLastStep() {
        let flow = WelcomeFlow(stepCount: 0)
        XCTAssertTrue(flow.isLastStep)
        XCTAssertFalse(flow.canGoBack)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `swift test --filter WelcomeFlowTests`
Expected: FAIL — `cannot find 'WelcomeFlow' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/HelmUI/Welcome/WelcomeFlow.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// Where the tour is and what its buttons may do.
///
/// It cannot close the window: closing is the window's business, and a flow
/// that could do it could not be asked what it would do without one. `next()`
/// at the end is therefore a no-op rather than a dismissal — the view reads
/// `isLastStep` and calls the window's own close.
public struct WelcomeFlow: Equatable, Sendable {
    public let stepCount: Int
    public private(set) var step: Int = 0

    public init(stepCount: Int) {
        self.stepCount = max(0, stepCount)
    }

    public var canGoBack: Bool { step > 0 }
    /// True for an empty tour as well, so a window with no steps still offers
    /// a way out that is not only Skip.
    public var isLastStep: Bool { step >= stepCount - 1 }

    public mutating func next() {
        guard !isLastStep else { return }
        step += 1
    }

    public mutating func back() {
        guard canGoBack else { return }
        step -= 1
    }
}
```

- [ ] **Step 4: Run it and watch it pass**

Run: `swift test --filter WelcomeFlowTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/HelmUI/Welcome/WelcomeFlow.swift Tests/HelmUITests/WelcomeFlowTests.swift
git commit -m "feat(welcome): where the tour is, and what its buttons may do

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: `WelcomeGate` — shown once

**Files:**
- Create: `Sources/HelmUI/Welcome/WelcomeGate.swift`
- Test: `Tests/HelmUITests/WelcomeGateTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/HelmUITests/WelcomeGateTests.swift`:

```swift
import XCTest
@testable import HelmUI

/// A revision rather than a flag. A `Bool` makes "show the new tour once" and
/// "the flag got cleared by accident" the same state, and somebody has to
/// remember to clear it; a number that only moves when the tour is worth
/// showing again cannot be cleared by accident.
final class WelcomeGateTests: XCTestCase {
    func testAnInstallationThatHasSeenNothingIsShownTheTour() {
        XCTAssertTrue(WelcomeGate.shouldShow(seenRevision: 0))
    }

    func testAnInstallationThatHasSeenThisRevisionIsNotShownItAgain() {
        XCTAssertFalse(WelcomeGate.shouldShow(seenRevision: WelcomeGate.revision))
    }

    func testAFutureRevisionIsShownAgain() {
        XCTAssertTrue(WelcomeGate.shouldShow(seenRevision: WelcomeGate.revision - 1))
    }

    /// Someone who ran a later build and went back must not be shown a tour
    /// they have already seen a newer version of.
    func testARevisionFromTheFutureIsNotShown() {
        XCTAssertFalse(WelcomeGate.shouldShow(seenRevision: WelcomeGate.revision + 5))
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `swift test --filter WelcomeGateTests`
Expected: FAIL — `cannot find 'WelcomeGate' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/HelmUI/Welcome/WelcomeGate.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// Whether this installation has seen the tour.
///
/// A revision, not a flag. Nobody holds this key at 0.8.0, so a fresh install
/// and an upgrade both answer yes exactly once — which is the intent: people
/// upgrading have had Autopilot and Duplicates arrive without ever being told
/// what they are. A later tour bumps `revision` deliberately, or does not run.
public enum WelcomeGate {
    /// The key in the app's own namespace. Read and written in one place.
    public static let storeKey = "welcomeSeenRevision"
    public static let revision = 1

    public static func shouldShow(seenRevision: Int) -> Bool {
        seenRevision < revision
    }
}
```

- [ ] **Step 4: Run it and watch it pass**

Run: `swift test --filter WelcomeGateTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/HelmUI/Welcome/WelcomeGate.swift Tests/HelmUITests/WelcomeGateTests.swift
git commit -m "feat(welcome): a revision decides whether the tour has been seen

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: The chrome strings

**Files:**
- Create: `Sources/HelmUI/Welcome/WelcomeStrings.swift`

No test of its own — Task 4's test asserts that nothing is empty in any language, which is what there is to get wrong here.

- [ ] **Step 1: Write the strings**

Create `Sources/HelmUI/Welcome/WelcomeStrings.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// The tour's own words. Every module's name and summary comes from that
/// module's descriptor — a second copy here is nine descriptions that go stale
/// on the first rename.
///
/// **The English and the table are named, not inlined.** Every other string
/// table in Helm spells both into one `L(…)` call, which is fine when the only
/// reader is the screen. These are also read by a test that walks all eight
/// languages looking for a hole, and it cannot do that through an accessor that
/// has already resolved `AppLanguage.current`.
public enum WelcomeStr {
    public static let windowTitleEnglish = "Welcome to Helm"
    public static let windowTitleTable: [AppLanguage: String] = [.ru: "Добро пожаловать в Helm", .es: "Te damos la bienvenida a Helm", .fr: "Bienvenue dans Helm", .de: "Willkommen bei Helm", .ja: "Helm へようこそ", .zh: "欢迎使用 Helm", .pt: "Boas-vindas ao Helm"]
    public static var windowTitle: String { L(windowTitleEnglish, windowTitleTable) }

    public static let introTitleEnglish = "Tools for your Mac"
    public static let introTitleTable: [AppLanguage: String] = [.ru: "Инструменты для вашего Mac", .es: "Herramientas para tu Mac", .fr: "Des outils pour votre Mac", .de: "Werkzeuge für deinen Mac", .ja: "Mac のための道具", .zh: "给你的 Mac 的一套工具", .pt: "Ferramentas para o seu Mac"]
    public static var introTitle: String { L(introTitleEnglish, introTitleTable) }

    public static let introBodyEnglish = "Helm lives in the menu bar and is made of modules. Each one does a single job, and you can switch off the ones you do not want."
    public static let introBodyTable: [AppLanguage: String] = [.ru: "Helm живёт в строке меню и состоит из модулей. Каждый делает одно дело, и ненужные можно выключить.", .es: "Helm vive en la barra de menús y está hecho de módulos. Cada uno hace una sola cosa, y puedes desactivar los que no quieras.", .fr: "Helm vit dans la barre des menus et se compose de modules. Chacun fait une seule chose, et vous pouvez désactiver ceux dont vous ne voulez pas.", .de: "Helm sitzt in der Menüleiste und besteht aus Modulen. Jedes erledigt eine Sache, und was du nicht brauchst, schaltest du ab.", .ja: "Helm はメニューバーに常駐し、モジュールでできています。それぞれが一つの仕事をし、要らないものはオフにできます。", .zh: "Helm 常驻菜单栏，由若干模块组成。每个模块只做一件事，不需要的可以关掉。", .pt: "O Helm fica na barra de menus e é feito de módulos. Cada um faz uma única coisa, e você pode desligar os que não quiser."]
    public static var introBody: String { L(introBodyEnglish, introBodyTable) }

    public static let backEnglish = "Back"
    public static let backTable: [AppLanguage: String] = [.ru: "Назад", .es: "Atrás", .fr: "Précédent", .de: "Zurück", .ja: "戻る", .zh: "上一步", .pt: "Voltar"]
    public static var back: String { L(backEnglish, backTable) }

    public static let nextEnglish = "Next"
    public static let nextTable: [AppLanguage: String] = [.ru: "Далее", .es: "Siguiente", .fr: "Suivant", .de: "Weiter", .ja: "次へ", .zh: "下一步", .pt: "Avançar"]
    public static var next: String { L(nextEnglish, nextTable) }

    public static let skipEnglish = "Skip"
    public static let skipTable: [AppLanguage: String] = [.ru: "Пропустить", .es: "Omitir", .fr: "Ignorer", .de: "Überspringen", .ja: "スキップ", .zh: "跳过", .pt: "Pular"]
    public static var skip: String { L(skipEnglish, skipTable) }

    public static let doneEnglish = "Done"
    public static let doneTable: [AppLanguage: String] = [.ru: "Готово", .es: "Listo", .fr: "Terminé", .de: "Fertig", .ja: "完了", .zh: "完成", .pt: "Concluir"]
    public static var done: String { L(doneEnglish, doneTable) }
    /// Read aloud in place of "3 of 10", which VoiceOver otherwise renders as
    /// two bare numbers with no idea what they count.
    public static func stepPosition(_ step: Int, _ total: Int) -> String {
        L("Step \(step) of \(total)", [.ru: "Шаг \(step) из \(total)", .es: "Paso \(step) de \(total)", .fr: "Étape \(step) sur \(total)", .de: "Schritt \(step) von \(total)", .ja: "\(total) 中 \(step) ステップ目", .zh: "第 \(step) 步，共 \(total) 步", .pt: "Passo \(step) de \(total)"])
    }
}
```

- [ ] **Step 2: Check it compiles**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/HelmUI/Welcome/WelcomeStrings.swift
git commit -m "feat(welcome): the tour's own words, in eight languages

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: `WelcomeStep` and building the list

**Files:**
- Create: `Sources/HelmUI/Welcome/WelcomeStep.swift`
- Test: `Tests/HelmUITests/WelcomeStepsTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/HelmUITests/WelcomeStepsTests.swift`:

```swift
import XCTest
import HelmContract
@testable import HelmUI

/// The tour is generated from what the descriptors already say. These assert
/// the generation, not the wording: the wording belongs to each module and is
/// tested where it lives.
final class WelcomeStepsTests: XCTestCase {
    private func metadata(_ name: String) -> ModuleMetadata {
        ModuleMetadata(id: ModuleID(rawValue: name.lowercased()), name: name,
                       summary: "what \(name) does", sfSymbol: "circle")
    }

    func testEveryModuleGetsOneStepAfterTheIntro() {
        let steps = WelcomeSteps.build(from: [metadata("Alpha"), metadata("Beta")])
        XCTAssertEqual(steps.count, 3, "an intro step plus one per module")
        XCTAssertEqual(steps[1].title, "Alpha")
        XCTAssertEqual(steps[2].title, "Beta")
    }

    func testTheIntroComesFirstAndIsNotAModule() {
        let steps = WelcomeSteps.build(from: [metadata("Alpha")])
        XCTAssertEqual(steps[0].title, WelcomeStr.introTitle)
        XCTAssertEqual(steps[0].body, WelcomeStr.introBody)
    }

    func testAModuleStepCarriesItsSummaryAndSymbol() {
        let steps = WelcomeSteps.build(from: [metadata("Alpha")])
        XCTAssertEqual(steps[1].body, "what Alpha does")
        XCTAssertEqual(steps[1].sfSymbol, "circle")
    }

    /// The suite runs in this machine's language, so a test that reads
    /// `AppLanguage.current` checks English eight times and calls it coverage.
    /// `L(_:_:language:)` names the language outright, which is the only way to
    /// see a table with a hole in it.
    ///
    /// The tables are spelled out here rather than read off `WelcomeStr`,
    /// because `WelcomeStr`'s accessors resolve `.current` internally — asking
    /// them in a loop over languages asks the same question eight times. Keep
    /// this list in step with `WelcomeStrings.swift`: a string added there and
    /// not here is a string nobody checks.
    func testEveryChromeStringExistsInEveryLanguage() {
        let tables: [(String, String, [AppLanguage: String])] = [
            ("windowTitle", WelcomeStr.windowTitleEnglish, WelcomeStr.windowTitleTable),
            ("introTitle", WelcomeStr.introTitleEnglish, WelcomeStr.introTitleTable),
            ("introBody", WelcomeStr.introBodyEnglish, WelcomeStr.introBodyTable),
            ("back", WelcomeStr.backEnglish, WelcomeStr.backTable),
            ("next", WelcomeStr.nextEnglish, WelcomeStr.nextTable),
            ("skip", WelcomeStr.skipEnglish, WelcomeStr.skipTable),
            ("done", WelcomeStr.doneEnglish, WelcomeStr.doneTable),
        ]
        for (name, english, table) in tables {
            for language in AppLanguage.allCases where language != .en {
                let value = L(english, table, language: language)
                XCTAssertFalse(value.isEmpty, "\(name) is empty in \(language.rawValue)")
                XCTAssertNotEqual(value, english,
                                  "\(name) fell back to English in \(language.rawValue)")
            }
        }
    }

    func testNoStepIsEmpty() {
        let steps = WelcomeSteps.build(from: [metadata("Alpha"), metadata("Beta")])
        for step in steps {
            XCTAssertFalse(step.title.isEmpty)
            XCTAssertFalse(step.body.isEmpty)
            XCTAssertFalse(step.sfSymbol.isEmpty)
        }
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `swift test --filter WelcomeStepsTests`
Expected: FAIL — `cannot find 'WelcomeSteps' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/HelmUI/Welcome/WelcomeStep.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmContract

public struct WelcomeStep: Equatable, Identifiable, Sendable {
    public let id: String
    public let sfSymbol: String
    public let title: String
    public let body: String
}

/// The tour, built from what the modules already say about themselves.
public enum WelcomeSteps {
    /// Takes metadata rather than reaching for `ModuleRegistry`, which lives in
    /// `HelmApp` — an executable target with no tests. This signature is why
    /// the tour can be asserted at all; do not "simplify" it back.
    public static func build(from modules: [ModuleMetadata]) -> [WelcomeStep] {
        let intro = WelcomeStep(id: "intro", sfSymbol: "sparkles",
                                title: WelcomeStr.introTitle, body: WelcomeStr.introBody)
        return [intro] + modules.map {
            WelcomeStep(id: $0.id.rawValue, sfSymbol: $0.sfSymbol,
                        title: $0.name, body: $0.summary)
        }
    }
}
```

- [ ] **Step 4: Run it and watch it pass**

Run: `swift test --filter WelcomeStepsTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/HelmUI/Welcome/WelcomeStep.swift Tests/HelmUITests/WelcomeStepsTests.swift
git commit -m "feat(welcome): the tour is built from what the modules already say

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: The view

**Files:**
- Create: `Sources/HelmUI/Welcome/WelcomeView.swift`

- [ ] **Step 1: Write the view**

Create `Sources/HelmUI/Welcome/WelcomeView.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI

/// The tour. Owns its position and reports only one thing outward: it is done.
///
/// Back is disabled rather than hidden on the first step — a control that
/// vanishes moves the two beside it, and a row of buttons that reflows as you
/// walk through it reads as the window flinching.
public struct WelcomeView: View {
    private let steps: [WelcomeStep]
    private let onClose: () -> Void
    @State private var flow: WelcomeFlow

    public init(steps: [WelcomeStep], onClose: @escaping () -> Void) {
        self.steps = steps
        self.onClose = onClose
        _flow = State(initialValue: WelcomeFlow(stepCount: steps.count))
    }

    private var step: WelcomeStep? {
        steps.indices.contains(flow.step) ? steps[flow.step] : nil
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let step {
                VStack(spacing: 16) {
                    Image(systemName: step.sfSymbol)
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(HelmText.quiet)
                        .accessibilityHidden(true)
                    Text(step.title)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text(step.body)
                        .font(.callout)
                        .foregroundStyle(HelmText.quiet)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 420)
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // The step is one thing to read, not four stops.
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(step.title). \(step.body)")
                // Identity by step so the transition runs; the tokens decide
                // its shape, never an inline curve.
                .id(step.id)
                .transition(.opacity)
            }

            Divider()

            HStack {
                Button(WelcomeStr.skip) { onClose() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text(WelcomeStr.stepPosition(flow.step + 1, steps.count))
                    .font(.caption)
                    .foregroundStyle(HelmText.faint)
                Spacer()
                Button(WelcomeStr.back) { flow.back() }
                    .disabled(!flow.canGoBack)
                Button(flow.isLastStep ? WelcomeStr.done : WelcomeStr.next) {
                    if flow.isLastStep { onClose() } else { flow.next() }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .animation(HelmMotion.interface, value: flow.step)
        .frame(width: 560, height: 420)
    }
}
```

- [ ] **Step 2: Check the guards are happy**

Run: `swift test --filter NamedControlsTests`
Expected: PASS. That guard scans the source for unnamed controls; every `Button` above carries its label, so it should stay green. If it fails, the failure names the file and line.

- [ ] **Step 3: Build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 4: Commit**

```bash
git add Sources/HelmUI/Welcome/WelcomeView.swift
git commit -m "feat(welcome): the tour on screen, with Back disabled rather than hidden

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: The window, and moving the permission audit

**Files:**
- Create: `Sources/HelmApp/WelcomeWindow.swift`
- Modify: `Sources/HelmApp/AppDelegate.swift` (the two lines calling `PermissionAudit`)

This task has no unit test: it is `NSWindow` wiring in a target with no test target, which is exactly why Tasks 1–4 exist. It is verified live in Task 7.

- [ ] **Step 1: Write the window**

Create `Sources/HelmApp/WelcomeWindow.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import AppKit
import SwiftUI
import HelmRuntime
import HelmUI

/// The tour's window. Shown once per installation, deciding nothing itself:
/// `WelcomeGate` says whether, `WelcomeSteps` says what, and this owns the
/// `NSWindow` and the one write that records it was seen.
@MainActor final class WelcomeWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    /// Run when the window goes away, however it goes away. The permission
    /// audit is deferred into this: both want the first launch, and two things
    /// arriving together is not an introduction.
    private let onClose: () -> Void
    /// Guards against running `onClose` twice — Done calls it, and closing the
    /// window then calls `windowWillClose` as well.
    private var closed = false

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    static func shouldShow(store: NamespacedStore) -> Bool {
        WelcomeGate.shouldShow(seenRevision: store.int(WelcomeGate.storeKey, default: 0))
    }

    func show(steps: [WelcomeStep], store: NamespacedStore) {
        // Written when the window opens, not when it closes: a person who
        // force-quits mid-tour has still been shown it, and showing it again
        // at every launch until they press Done is worse than not showing it.
        store.set(WelcomeGate.revision, for: WelcomeGate.storeKey)

        let view = WelcomeView(steps: steps) { [weak self] in self?.close() }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.title = WelcomeStr.windowTitle
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        self.window = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard !closed else { return }
        closed = true
        NSApp.setActivationPolicy(.accessory)
        window = nil
        onClose()
    }
}
```

- [ ] **Step 2: Defer the audit in `AppDelegate`**

In `Sources/HelmApp/AppDelegate.swift`, find these two lines inside `applicationDidFinishLaunching`:

```swift
        PermissionAudit.host = host
        PermissionAudit.run()
```

Replace them with:

```swift
        PermissionAudit.host = host
        // The audit puts up an alert when macOS is withholding something, and
        // on a first launch that is the same moment the welcome window wants.
        // Two of them arriving together is not an introduction, it is a
        // pile-up — so the audit waits for the window to go away, by Done, by
        // Skip or by the close button.
        if WelcomeWindow.shouldShow(store: AppSettings.store) {
            let welcome = WelcomeWindow { PermissionAudit.run() }
            self.welcomeWindow = welcome
            welcome.show(steps: WelcomeSteps.build(from: ModuleRegistry.all.map(\.moduleMetadata)),
                         store: AppSettings.store)
        } else {
            PermissionAudit.run()
        }
```

- [ ] **Step 3: Hold the window**

`AppDelegate` must keep a reference or the window is released while it is on screen. Near the top of the class, beside `private var footprintTimer: Timer?`, add:

```swift
    /// Held for as long as it is on screen; dropped in its own close handler.
    private var welcomeWindow: WelcomeWindow?
```

And in the `onClose` closure from Step 2, clear it after the audit runs so the object does not outlive the tour. Change the closure to:

```swift
            let welcome = WelcomeWindow { [weak self] in
                self?.welcomeWindow = nil
                PermissionAudit.run()
            }
```

- [ ] **Step 4: Build and run the suite**

Run: `swift build && swift test`
Expected: builds clean; 1575 + 14 new tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/HelmApp/WelcomeWindow.swift Sources/HelmApp/AppDelegate.swift
git commit -m "feat(welcome): the window, and the audit that now waits for it

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: See it, on a machine that has never seen it

**Files:** none changed if it passes.

The window only ever appears on an installation with no `welcomeSeenRevision`, which this machine will have as soon as it runs once. Everything here is about getting back to that state and leaving it clean.

- [ ] **Step 1: Build and install the signed copy**

```bash
pkill -f 'MacOS/HelmApp'; bash Scripts/package-app.sh
rm -rf /Applications/Helm.app
ditto "$TMPDIR/helm-package/Helm.app" /Applications/Helm.app
codesign --verify --deep --strict /Applications/Helm.app
xattr -dr com.apple.quarantine /Applications/Helm.app
```

Expected: `codesign` prints nothing and exits 0. If it complains about "resource fork, Finder information, or similar detritus", the checkout is under a file provider — see ARCHITECTURE.md § Dev loop.

- [ ] **Step 2: Clear the key and launch**

```bash
defaults delete com.helm.app app.welcomeSeenRevision 2>/dev/null
open /Applications/Helm.app
```

Expected: the welcome window appears, centred, showing "Tools for your Mac".

If the defaults domain name is wrong the delete silently succeeds and nothing changes. Confirm the key exists first with `defaults read com.helm.app | grep -i welcome` after a first run, and use whatever domain that shows.

- [ ] **Step 3: Walk it**

Check, by hand:
- Back is greyed on step 1, not missing.
- Next advances; the counter reads "Step 2 of 10".
- The last step's right-hand button says Done, not Next.
- Return activates the right-hand button; Escape closes the window.
- **The permission alert appears only after the window is gone**, not over it.

- [ ] **Step 4: Confirm it does not come back**

```bash
pkill -f 'MacOS/HelmApp'; open /Applications/Helm.app
```

Expected: no welcome window. The permission audit runs as it always did.

- [ ] **Step 5: Leave nothing behind**

The harness rule: a run that leaves state behind hands the next person a machine that is already half-configured.

```bash
defaults read com.helm.app app.welcomeSeenRevision
```

Expected: `1`. That is the state a real user is in after the tour, so it is the right state to leave. Nothing else was written — the tour does not touch module state.

- [ ] **Step 6: Check the harness rule**

Run: `grep -r HELM_DEBUG Sources/`
Expected: no output.

- [ ] **Step 7: Record it**

Add to `CHANGELOG.md` under `## [Unreleased] — 0.8.0` → `### Added`, and to `Sources/HelmApp/ChangelogData.swift` (localized, user-facing, no fix minutiae). Both, per CLAUDE.md.

```bash
git add CHANGELOG.md Sources/HelmApp/ChangelogData.swift
git commit -m "docs: the tour, in both changelogs

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```
