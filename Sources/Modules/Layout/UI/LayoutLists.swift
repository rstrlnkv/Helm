import HelmRuntime
import HelmUI
import SwiftUI
import Module_Layout_Engine

/// The two lists that grow: words the module must never touch, and apps it must
/// leave alone or act in.
///
/// **A view, not a window.** `LayoutListsWindow` puts it up; everything here can
/// be mounted on a render bench and measured, which the module's own history
/// says matters — the introduction was a `.sheet` until somebody noticed that
/// nothing of the first screen a new user meets was inside the page's layers.
///
/// It owns its state and writes to the store, and the page listens for those
/// writes to keep its counts right. Filtered by key through
/// `NamespacedStore.changed(_:is:)`, which existed and was used by nobody: two
/// mirrors of one setting re-read themselves on *every* write anywhere in Helm
/// before this, which is how the hero and the window header came to disagree.
struct LayoutLists: View {
    private let store: NamespacedStore
    private let announce: () -> Void

    @State private var exceptions: [String]
    @State private var newException = ""
    @State private var appRules: [String: Bool]

    /// The apps Helm refuses before any rule is read — terminals and password
    /// managers. Drawn as ordinary rows so the refusal is visible and the
    /// person can overrule it, which is what this list is for.
    private let builtInBlocked: [String]

    init(store: NamespacedStore, builtInBlocked: [String], announce: @escaping () -> Void) {
        self.store = store
        self.builtInBlocked = builtInBlocked
        self.announce = announce
        _exceptions = State(initialValue: store.stringArray(LayoutKey.exceptions))
        _appRules = State(initialValue: store.boolTable(LayoutKey.appRules))
    }

    var body: some View {
        Form {
            wordsSection
            appsSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Words

    @ViewBuilder private var wordsSection: some View {
        Section {
            if exceptions.isEmpty {
                Text(LyStr.noExceptions)
                    .font(HelmText.rowTitle)
                    .foregroundStyle(HelmText.quiet)
            }
            ForEach(exceptions, id: \.self) { word in
                HStack(spacing: HelmSpace.s5) {
                    Text(word).font(.system(.body, design: .monospaced))
                    Spacer(minLength: HelmSpace.s4)
                    Button { remove(word) } label: {
                        Image(systemName: "xmark").foregroundStyle(HelmText.faint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(HelmA11y.remove), \(word)")
                }
                // One element per word: read apart it was a word and an unnamed
                // button, with nothing saying the two belonged together.
                .accessibilityElement(children: .combine)
            }
            HStack(spacing: HelmSpace.s4) {
                // `prompt:` rather than a title: inside a `Form` a `TextField`'s
                // title is drawn as a label beside the field, not inside it.
                TextField("", text: $newException, prompt: Text(LyStr.exceptionPrompt))
                    .accessibilityLabel(LyStr.exceptionPrompt)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .onSubmit { addTyped() }
                Button(LyStr.addException) { addTyped() }
                    .disabled(newException.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            HelmSectionTitle(LyStr.exceptions)
        } footer: {
            sectionNote(LyStr.exceptionsHint)
        }
    }

    private func addTyped() {
        guard let words = Exceptions.adding(newException, to: exceptions) else { return }
        exceptions = words
        write(exceptions, LayoutKey.exceptions)
        newException = ""
    }

    private func remove(_ word: String) {
        exceptions.removeAll { $0 == word }
        write(exceptions, LayoutKey.exceptions)
    }

    // MARK: - Apps

    @ViewBuilder private var appsSection: some View {
        Section {
            // **The built-in list is drawn, not described.** Seven apps were
            // refused before any rule was consulted and the page said so twice
            // in different words — without naming one of them. Somebody whose
            // typing is not being fixed in Warp had no way to learn that Warp
            // was the reason. Only the ones this Mac has: a row for an app
            // nobody installed is a list of somebody else's software.
            ForEach(AppInfo.sortedByName(Set(appRules.keys).union(builtInBlocked)),
                    id: \.self) { bundleID in
                appRow(bundleID)
            }
            Button { pickApps() } label: { Label(LyStr.addApp, systemImage: "plus") }
        } header: {
            HelmSectionTitle(LyStr.apps)
        } footer: {
            sectionNote(LyStr.appsWhy)
        }
    }

    private func appRow(_ bundleID: String) -> some View {
        HelmAppRuleRow(bundleID: bundleID) {
            // The picker carries the app's name: "Off, pop-up button" answers
            // nothing when there are five of these in a list.
            Picker(AppInfo.resolve(bundleID).name, selection: ruleBinding(bundleID)) {
                Text(LyStr.ruleOff).tag(false)
                Text(LyStr.ruleOn).tag(true)
            }
            .labelsHidden()
            .fixedSize()
        } remove: {
            appRules.removeValue(forKey: bundleID)
            write(appRules, LayoutKey.appRules)
        }
    }

    private func ruleBinding(_ bundleID: String) -> Binding<Bool> {
        Binding(get: { appRules[bundleID] ?? false },
                set: { appRules[bundleID] = $0; write(appRules, LayoutKey.appRules) })
    }

    private func pickApps() {
        // Defaults to «don't fix»: somebody adding an app to this list is
        // naming a place the module should keep out of, which is what the
        // built-in refusals are and what the picker is reached for.
        for bundleID in AppPicker.choose() where appRules[bundleID] == nil {
            appRules[bundleID] = false
        }
        write(appRules, LayoutKey.appRules)
    }

    // MARK: - Plumbing

    private func write(_ value: Any, _ key: String) {
        store.set(value, for: key)
        // The engine owns the behaviour; the store is the one line between
        // them, and it has to be told to re-read.
        announce()
    }

    private func sectionNote(_ text: String) -> some View {
        Text(text)
            .font(HelmText.rowDetail)
            .foregroundStyle(HelmText.quiet)
            .fixedSize(horizontal: false, vertical: true)
    }
}
