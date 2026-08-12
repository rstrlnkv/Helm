import SwiftUI
import HelmUI
import Module_KeepAwake_Engine

/// The list of «keep the Mac awake while this app runs» rules, and the three
/// things that edit it.
///
/// An extension rather than a view of its own, and that is load-bearing: a
/// grouped `Form` groups by what its **direct children** are, so wrapping these
/// rows in anything — even a `Group` — changes the card they are drawn in
/// (ARCHITECTURE.md § Settings window). The rows have to stay siblings of the
/// section's other rows, so what moves is the source and not the hierarchy.
extension KeepAwakeSettingsPage {
    // MARK: - App picker

    /// Rows handed to the `Section` one by one, not wrapped in a `VStack`.
    ///
    /// The wrapper made this the only per-app list in Helm without the system's
    /// row padding and hairlines: measured against the identical list in VPN it
    /// came out 13 pt shorter with no separators at all. The form draws both,
    /// and draws them the way every other section is drawn.
    /// - Parameter explained: whether the empty state may say what an app rule is.
    ///   Not while the banner is up: unreadable rules read as no rules, so «No apps
    ///   chosen» and a paragraph about adding one sat under a banner saying the apps
    ///   could not be read — two sentences contradicting the third about whether
    ///   anything was chosen. The button stays: the banner tells them to press it.
    @ViewBuilder
    func appRules(explained: Bool) -> some View {
        if appTriggers.isEmpty {
            // A sentence, not a shrug. «No apps yet.» said nothing about what
            // an app rule is or why anybody would want one, and the section
            // heading used to carry that job in its tail — re-explaining it on
            // every visit for ever, including to people who already had a list.
            HelmEmptyState(symbol: "plus.app",
                           tint: KeepAwakeDescriptor.tint.colour,
                           title: explained ? KAStr.noAppsYet : nil,
                           message: explained ? KAStr.noAppsYetNote : nil) {
                Button(KAStr.addApp) { pickApp() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
            // One row per app: icon, name, when it applies, and the remove
            // button. The condition is a single menu because the two flags are
            // not independent choices — "display and power" means both.
            ForEach(Array(appTriggers.enumerated()), id: \.element.bundleID) { index, trigger in
                HelmAppRuleRow(bundleID: trigger.bundleID) {
                    Picker(AppInfo.resolve(trigger.bundleID).name,
                           selection: conditionBinding(index)) {
                        ForEach(AppTrigger.Condition.allCases, id: \.self) { condition in
                            Text(KAStr.triggerCondition(condition)).tag(condition)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                } remove: {
                    appTriggers.remove(at: index)
                    saveTriggers()
                }
        }
        // Under a list, never under the empty state: there the one prominent
        // button already carries this action, and two «Add app…» in one card is
        // the app asking the same question twice.
        if !appTriggers.isEmpty {
            // The card's last row, not a button sitting in one: v3 draws it as
            // a line of the list it adds to, in the accent, which is also how
            // macOS's own lists offer «add».
            Button {
                pickApp()
            } label: {
                // The app rows above are a 22 pt icon and a 12 pt gap, and a
                // `Label` uses neither — its own spacing put this title 6.5 pt
                // to the left of every app name it sits under, which on a card
                // of otherwise aligned rows reads as the last row being
                // slightly broken. Spelled out, so the two agree by
                // construction rather than by coincidence.
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .frame(width: 22, height: 22)
                    Text(KAStr.addApp)
                }
                .foregroundStyle(Color.accentColor)
                // The row is one target and one announcement, not a glyph and
                // a word to stop on separately.
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)
        }
    }

    private func conditionBinding(_ index: Int) -> Binding<AppTrigger.Condition> {
        Binding(
            get: { appTriggers.indices.contains(index) ? appTriggers[index].condition : .always },
            set: { newValue in
                guard appTriggers.indices.contains(index) else { return }
                appTriggers[index].set(newValue)
                saveTriggers()
            })
    }

    private func saveTriggers() {
        vm.save(in: store) { $0.setAppTriggers(appTriggers) }
    }

    private func pickApp() {
        var added = false
        for bundleID in AppPicker.choose()
        where !appTriggers.contains(where: { $0.bundleID == bundleID }) {
            appTriggers.append(AppTrigger(bundleID: bundleID))
            added = true
        }
        if added { saveTriggers() }
    }
}
