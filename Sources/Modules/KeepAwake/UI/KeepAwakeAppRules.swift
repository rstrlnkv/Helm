import SwiftUI
import HelmUI
import Module_KeepAwake_Engine

/// The list of «keep the Mac awake while this app runs» rules, and the three
/// things that edit it.
///
/// An extension rather than a view of its own: `HelmSettingsSection` lays out
/// its content's subviews as the card's rows. Wrapping these in a stack would
/// make them one row; `Group`, `ForEach` and a view of its own are flattened by
/// its `Group(subviews:)`, so the extension is where the source lives, not what
/// holds the rows apart.
extension KeepAwakeSettingsPage {
    // MARK: - App picker

    /// Rows handed to the section one by one, not wrapped in a `VStack`: the
    /// section draws the padding and the hairline between rows, and a wrapper
    /// would be one row with neither.
    /// - Parameter explained: whether the empty state may say what an app rule is.
    ///   Not while the banner is up: unreadable rules read as no rules, and «No
    ///   apps chosen» under a banner saying the apps could not be read would
    ///   contradict it. The button stays: the banner tells them to press it.
    @ViewBuilder
    func appRules(explained: Bool) -> some View {
        if appTriggers.isEmpty {
            // A sentence that says what an app rule is and why anybody would
            // want one.
            HelmEmptyState(symbol: "plus.app",
                           tint: KeepAwakeDescriptor.tint.colour,
                           title: explained ? KAStr.noAppsYet : nil,
                           message: explained ? KAStr.noAppsYetNote : nil) {
                Button(HelmWord.addApp) { pickApp() }
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
                    .helmSectionMenu()
                } remove: {
                    appTriggers.remove(at: index)
                    saveTriggers()
                }
        }
        // Under a list, never under the empty state, whose prominent button
        // already carries this action.
        if !appTriggers.isEmpty {
            // The card's last row, not a button sitting in one: a line of the
            // list it adds to, in the accent, which is also how macOS's own
            // lists offer «add».
            Button {
                pickApp()
            } label: {
                // Not a `Label`: its own spacing would put this title left of the
                // app names above it. Both numbers are `HelmAppRuleGeometry`'s.
                HStack(spacing: HelmAppRuleGeometry.iconGap) {
                    Image(systemName: "plus")
                        .frame(width: HelmAppRuleGeometry.iconSide,
                               height: HelmAppRuleGeometry.iconSide)
                    Text(HelmWord.addApp)
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
