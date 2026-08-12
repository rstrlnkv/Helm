// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI
import HelmRuntime
import HelmUI
import Module_VPN_Engine

/// The per-app automation half of the VPN settings page: the list of rules, what
/// each row says when it cannot fire, and the picker that writes one.
///
/// Its own file because the page reached the length limit, and this is where it
/// divides: everything above is about the connections this Mac has, and
/// everything here is about the rules a person wrote over them. The properties it
/// reads stay on the page — one `@State` of the rules, seeded and written back in
/// one place — so this is an extension rather than a view of its own.
extension VPNSettingsPage {

    /// By the name the row draws, not by the key it is stored under — the same
    /// order the Finder would give the apps themselves.
    private var sortedBundleIDs: [String] {
        AppInfo.sortedByName(rules.keys)
    }

    @ViewBuilder
    /// Read by the page's form, one file over.
    var appRulesEditor: some View {
        if rules.isEmpty {
            // One block, not two grey paragraphs at two sizes stacked in a
            // card — `.callout` over `.caption`, which read as a paragraph that
            // had lost its heading. The scope note below stays where it is: it
            // is for the person who *has* rules, and that is the one this
            // branch is not about.
            HelmEmptyState(symbol: "app.badge.checkmark",
                           tint: VPNDescriptor.tint.colour,
                           message: VPNStr.perAppHint) { EmptyView() }
        }
        // No `Divider()` between them. A grouped `Form` draws its own
        // separators, and each direct child of a `Section` is a **row** — so an
        // explicit divider became a row of its own, with a row's padding, and
        // the list came out with a 40 pt empty band between every pair of
        // apps. Keep Awake's list of the same shape has never had one.
        ForEach(sortedBundleIDs, id: \.self) { bundleID in
            appRuleRow(bundleID)
        }
        Button {
            pickApp()
        } label: {
            // A row of the list it adds to, in the accent — the shape Keep
            // Awake settled on and the one v3 draws. As a bordered `Label` it
            // was a chip sitting in a column of plain rows, its fill starting
            // 1 pt left of the copy above it and its title 36 pt right of it.
            // The 22 pt box is the app icon's column, so the two agree by
            // construction rather than by coincidence.
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .frame(width: 22, height: 22)
                Text(VPNStr.addApp)
            }
            .foregroundStyle(Color.accentColor)
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        // What the tunnel actually covers is the section's **footer** now, drawn
        // by the form itself — it is the one thing on this page somebody can be
        // wrong about in a way that matters, and it belongs under the group it
        // qualifies rather than in it.
    }

    /// One line per app: which VPN, and when the rule fires. The two switches
    /// this replaces were not independent settings — "neither" is a rule that
    /// does nothing, which the menu can name.
    private func appRuleRow(_ bundleID: String) -> some View {
        let info = AppInfo.resolve(bundleID)
        // A renamed or deleted VPN silently disables its rules; the row said
        // nothing and the picker simply showed blank.
        // `VPNRules.orphaned` is this question, tested, and was answered here
        // by hand — per row, which is also how the second answer gets written.
        let missing = VPNRules.orphaned(rules, against: vm.connections)[bundleID] != nil
        return HelmAppRuleRow(bundleID: bundleID) {
            // Two nameless pop-ups in one row are indistinguishable to
            // VoiceOver; each carries what it chooses.
            Picker("\(info.name) — \(VPNStr.rulePickerVPN)", selection: vpnNameBinding(bundleID)) {
                // The name the rule actually holds, even when the system no
                // longer has it. A `Picker` whose selection matches no tag
                // draws **blank**, so an orphaned rule showed an empty control
                // beside a note explaining that «Old office» is gone — the one
                // row where the page had something to say showed nothing at
                // all. v3 answers this with a «Choose another» button; the
                // picker *is* that button, and it only had to be able to
                // display where it currently points.
                if let held = rules[bundleID]?.vpnName,
                   !vm.connections.contains(where: { $0.name == held }) {
                    Text(VPNStr.missingConnection(held)).tag(held)
                    Divider()
                }
                ForEach(vm.connections.map(\.name), id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .labelsHidden()
            .fixedSize()
            Picker("\(info.name) — \(VPNStr.rulePickerWhen)", selection: timingBinding(bundleID)) {
                ForEach(VPNAppRule.Timing.allCases, id: \.self) { timing in
                    Text(VPNStr.ruleTiming(timing)).tag(timing)
                }
            }
            .labelsHidden()
            .fixedSize()
        } note: {
            if missing, let name = rules[bundleID]?.vpnName {
                ruleWarning(VPNStr.ruleVPNMissing(name))
            } else if let name = rules[bundleID]?.vpnName,
                      vm.secretsBehindAPrompt.contains(name) {
                // **The rule that could not fire, on the row somebody looks at when
                // it stops working.** The secret is in the System keychain and an
                // automatic connect may not open the dialog macOS guards it with,
                // so this rule does nothing at all until one press of Connect fills
                // Helm's own cache — and `scutil` reports the start it could not
                // perform as a success, so nothing else on this page would say it.
                ruleWarning(VPNStr.secretNeedsAPress(name))
            } else if let note = trustNote(bundleID) {
                // A rule bound to no identity, or to an app nobody signed, cannot
                // fire — and a rule that refuses in silence looks exactly like one
                // that works. The same shape as the missing-VPN note above,
                // because it is the same class of news: the row is set up and
                // nothing will happen.
                ruleWarning(note)
            } else if holdingNow(bundleID) {
                // **The one question this list could not answer: is it working
                // right now?** Everything in the row is what was *asked* for —
                // an app, a VPN, a moment — and a rule that has quietly stopped
                // firing looks exactly like one that fires every day. The
                // engine already publishes which tunnels it is holding up
                // itself; the row simply had nothing that read it.
                //
                // Only for tunnels in `autoConnected`, which is Helm's own
                // book: a VPN somebody raised by hand is up, and saying "this
                // rule did that" about it would be the row taking credit for
                // somebody else's click.
                HStack(spacing: 6) {
                    HelmStatusDot(active: true)
                    Text(VPNStr.ruleHoldingNow)
                        .font(HelmText.rowDetail)
                        .foregroundStyle(HelmText.quiet)
                }
                .accessibilityElement(children: .combine)
            }
        } remove: {
            rules.removeValue(forKey: bundleID)
            persist()
        }
    }

    /// The line under a rule that is written down and cannot fire. Two reasons
    /// draw it — the VPN it names is gone, or the app it names cannot be confirmed
    /// — and they had the same eight lines each.
    private func ruleWarning(_ text: String) -> some View {
        HStack(spacing: 6) {
            // The token, not `.orange`: `HelmPermissionNote` draws this exact
            // glyph two rows away at 4.54:1, and the literal measured 2.31:1 in
            // light appearance.
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(HelmSignal.warning)
                .accessibilityHidden(true)   // the text beside it says it
            Text(text)
                .font(HelmText.rowDetail)
                .foregroundStyle(HelmText.quiet)
        }
    }

    /// What is wrong with this rule as *stored*, if anything.
    ///
    /// Asked with `running: nil` on purpose: the page knows what the person wrote
    /// down, not what is running at the instant it draws, and the two verdicts that
    /// depend on the instant are the two `VPNStr.ruleTrustNote` answers nothing
    /// for. The engine asks the same function with the real answer and logs its
    /// refusal there.
    private func trustNote(_ bundleID: String) -> String? {
        guard let rule = rules[bundleID] else { return nil }
        return VPNStr.ruleTrustNote(VPNRuleTrust.judge(rule: rule, running: nil))
    }

    /// Is this rule's tunnel up **and** Helm's doing, right now.
    ///
    /// Both halves. `autoConnected` is the engine's book of what it raised
    /// itself and outlives the tunnel by a refresh or two; the live status is
    /// what `scutil` says. Either one alone would put a green dot under a rule
    /// whose VPN is down.
    private func holdingNow(_ bundleID: String) -> Bool {
        guard let name = rules[bundleID]?.vpnName, vm.autoConnected.contains(name) else {
            return false
        }
        return vm.connections.contains { $0.name == name && $0.status.isConnected }
    }

    private func timingBinding(_ bundleID: String) -> Binding<VPNAppRule.Timing> {
        Binding(
            get: { rules[bundleID]?.timing ?? .launchAndQuit },
            set: { newValue in
                guard var rule = rules[bundleID] else { return }
                rule.set(newValue)
                rules[bundleID] = rule
                persist()
            })
    }

    private func vpnNameBinding(_ bundleID: String) -> Binding<String> {
        Binding(
            get: { rules[bundleID]?.vpnName ?? vm.connections.first?.name ?? "" },
            set: { newValue in
                var rule = rules[bundleID] ?? VPNAppRule(vpnName: newValue)
                rule.vpnName = newValue
                rules[bundleID] = rule
                persist()
            })
    }

    private func persist() {
        VPNSettings(store: store).setRulesJSON(VPNRules.encode(rules))
        vm.send(VPNCommand.reloadRules)
    }

    /// **Where a rule's identity comes from, and the only place it can.** The path
    /// in front of a file dialog is somebody pointing at an app deliberately;
    /// everything downstream has only a bundle identifier, which is a string in a
    /// plist anybody can write. `VPNRules.adopting` decides what that does to the
    /// rules — including for an app that already has one, which is how a rule
    /// written before identities existed is repaired.
    private func pickApp() {
        let picked = AppPicker.chooseApps().map {
            (bundleID: $0.bundleID, identity: CodeIdentity.of(bundleAt: $0.url))
        }
        let updated = VPNRules.adopting(picked, into: rules,
                                        defaultVPN: vm.connections.first?.name ?? "")
        guard updated != rules else { return }
        rules = updated
        persist()
    }
}
