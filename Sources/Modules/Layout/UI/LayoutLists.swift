import HelmRuntime
import HelmUI
import SwiftUI
import Module_Layout_Engine

/// The two lists that grow: words the module must never touch, and apps it must
/// leave alone or act in.
///
/// A view, not a window: `LayoutListsWindow` puts it up, and everything here can be
/// mounted on a render bench and measured. It owns its state and writes to the store;
/// the page listens for those writes through `NamespacedStore.changed(_:is:)`, so each
/// mirror of a setting re-reads only on its own key.
struct LayoutLists: View {
    private let store: NamespacedStore
    private let announce: () -> Void
    /// The keyboard's way out, which the window cannot give: `HostWindow` supplies no
    /// Escape handling, Helm builds no `NSMenu` so ⌘W is bound to nothing, and macOS's
    /// default Full Keyboard Access leaves window chrome out of the Tab order.
    private let close: () -> Void

    @State private var exceptions: [String]
    @State private var newException = ""
    @State private var appRules: [String: Bool]
    @State private var appLayouts: [String: String]

    /// The apps Helm refuses before any rule is read — terminals and password managers.
    /// Drawn as ordinary rows so the refusal is visible and can be overruled.
    private let builtInBlocked: [String]

    init(store: NamespacedStore, builtInBlocked: [String],
         close: @escaping () -> Void, announce: @escaping () -> Void) {
        self.store = store
        self.builtInBlocked = builtInBlocked
        self.close = close
        self.announce = announce
        _exceptions = State(initialValue: store.stringArray(LayoutKey.exceptions))
        _appRules = State(initialValue: store.boolTable(LayoutKey.appRules))
        _appLayouts = State(initialValue: store.stringTable(LayoutKey.appLayouts))
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                wordsSection
                appsSection
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button(LyStr.listsDone) { close() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, HelmLayout.formInset)
            .padding(.vertical, HelmSpace.s5)
        }
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
                    Text(word).font(LayoutLook.typed)
                    Spacer(minLength: HelmSpace.s4)
                    // Without the word: the row is combined below, so the `Text` beside
                    // this supplies it. `HelmAppRuleRow` spells both; its row is not combined.
                    HelmRemoveButton(label: HelmA11y.remove) { remove(word) }
                }
                // One element per word, so the word and its button read as a pair.
                .accessibilityElement(children: .combine)
            }
            HStack(spacing: HelmSpace.s4) {
                // `prompt:` rather than a title: inside a `Form` a title is drawn as a
                // label beside the field.
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
            HelmSettingsNote(LyStr.exceptionsHint)
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
            // The built-in refusals are drawn as rows, only the ones this Mac has, so the
            // person can see which app is the reason their typing is not fixed there.
            // Read once for the section: every row offers the same layouts, and each
            // read is a system call.
            let layoutSources = InputSourceInfo.all()
            ForEach(AppInfo.sortedByName(AppScope.listed(rules: appRules,
                                                         layouts: appLayouts,
                                                         builtIn: builtInBlocked)),
                    id: \.self) { bundleID in
                appRow(bundleID, layoutSources: layoutSources)
            }
            Button { pickApps() } label: { Label(LyStr.addApp, systemImage: "plus") }
        } header: {
            HelmSectionTitle(LyStr.apps)
        } footer: {
            HelmSettingsNote(LyStr.appsWhy)
        }
    }

    private func appRow(_ bundleID: String, layoutSources: [InputSourceInfo]) -> some View {
        HelmAppRuleRow(bundleID: bundleID) {
            // Named after the app: "Off, pop-up button" says nothing in a list of five.
            Picker(AppInfo.resolve(bundleID).name, selection: ruleBinding(bundleID)) {
                Text(LyStr.ruleOff).tag(false)
                Text(LyStr.ruleOn).tag(true)
            }
            .labelsHidden()
            .fixedSize()
            // Two independent things about one application: whether Helm rewrites the
            // words here, and which layout is typed in here. Neither gates the other.
            Picker(LyStr.appLayout, selection: layoutBinding(bundleID)) {
                Text(LyStr.layoutUnchanged).tag("")
                ForEach(layoutSources, id: \.id) { source in
                    Text(source.name).tag(source.id)
                }
            }
            .labelsHidden()
            .fixedSize()
            // The app's name, as both neighbours carry it.
            .accessibilityLabel("\(LyStr.appLayout), \(AppInfo.resolve(bundleID).name)")
        } remove: {
            appRules.removeValue(forKey: bundleID)
            appLayouts.removeValue(forKey: bundleID)
            write(appRules, LayoutKey.appRules)
            write(appLayouts, LayoutKey.appLayouts)
        }
    }

    private func ruleBinding(_ bundleID: String) -> Binding<Bool> {
        Binding(get: { appRules[bundleID] ?? false },
                set: { appRules[bundleID] = $0; write(appRules, LayoutKey.appRules) })
    }

    /// The empty string is «don't change»: choosing it removes the binding rather than
    /// storing a value nothing reads.
    private func layoutBinding(_ bundleID: String) -> Binding<String> {
        Binding(get: { appLayouts[bundleID] ?? "" },
                set: { chosen in
                    if chosen.isEmpty { appLayouts.removeValue(forKey: bundleID) }
                    else { appLayouts[bundleID] = chosen }
                    write(appLayouts, LayoutKey.appLayouts)
                })
    }

    private func pickApps() {
        // Defaults to «don't fix»: adding an app here names a place the module keeps out of.
        for bundleID in AppPicker.choose() where appRules[bundleID] == nil {
            appRules[bundleID] = false
        }
        write(appRules, LayoutKey.appRules)
    }

    // MARK: - Plumbing

    private func write(_ value: Any, _ key: String) {
        store.set(value, for: key)
        // The store is the one line to the engine, and it has to be told to re-read.
        announce()
    }
}
