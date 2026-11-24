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
    private let actions: WelcomeActions
    private let onClose: () -> Void
    @State private var flow: WelcomeFlow
    @State private var revealed = false
    /// One switch, wearing two hats: launch-at-login on the intro, that
    /// module's enablement on a module step. Re-seeded in `.onAppear`, which
    /// `.id(step.id)` re-runs on each step, so it never carries a stale value.
    @State private var switchOn = false
    /// Moves VoiceOver to the new step's content when the step changes, or a
    /// reader walking the tour from the keyboard stays on Next while the words
    /// behind it change unannounced.
    @AccessibilityFocusState private var focus: String?

    public init(steps: [WelcomeStep],
                actions: WelcomeActions = WelcomeActions(),
                onClose: @escaping () -> Void) {
        self.steps = steps
        self.actions = actions
        self.onClose = onClose
        _flow = State(initialValue: WelcomeFlow(stepCount: steps.count))
    }

    private var step: WelcomeStep? {
        steps.indices.contains(flow.step) ? steps[flow.step] : nil
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let step {
                VStack(spacing: HelmSpace.s6) {
                    stepContent(step)
                        .accessibilityFocused($focus, equals: step.id)
                    switchSection(step)
                }
                .frame(maxWidth: 420)
                .padding(.horizontal, HelmSpace.s7)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Identity by step so the transition runs, the reveal
                // animation replays, and the switch below re-seeds from the
                // real state; the tokens decide the transition's shape, never
                // an inline curve.
                .id(step.id)
                .transition(.opacity)
                .onAppear { switchOn = currentSwitchValue(step) }
                .onChange(of: flow.step) { _, newStep in
                    if newStep != 0 { revealed = false }
                    if steps.indices.contains(newStep) { focus = steps[newStep].id }
                }
            }

            Divider()

            HStack {
                Button(WelcomeStr.skip) { onClose() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text(WelcomeStr.stepPosition(flow.step + 1, steps.count))
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.faint)
                Spacer()
                Button(HelmWord.back) { flow.back() }
                    .disabled(!flow.canGoBack)
                Button(flow.isLastStep ? HelmWord.done : HelmWord.next) {
                    if flow.isLastStep { onClose() } else { flow.next() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(HelmSpace.s6)
        }
        .animation(HelmMotion.interface, value: flow.step)
        .frame(width: 560, height: 420)
    }

    /// The mark/icon, title and body — one thing for VoiceOver to read, so the
    /// switch below (its own control, its own name) stays a second, separate
    /// stop rather than being folded into the same combined utterance.
    @ViewBuilder
    private func stepContent(_ step: WelcomeStep) -> some View {
        VStack(spacing: HelmSpace.s6) {
            if step.moduleSymbols.isEmpty {
                Image(systemName: step.sfSymbol)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(HelmText.quiet)
                    .accessibilityHidden(true)
            } else {
                // The mark and the title/body stand still; only the
                // icon row moves — one thing moves, the rest doesn't.
                VStack(spacing: HelmSpace.s6) {
                    HelmAppMark(size: 72)
                    // The app's parts, arriving one after another — the
                    // first screen answers "what is this made of" before
                    // a word is read. Icons are decorative here; the step
                    // text carries the meaning, and the row is hidden
                    // from accessibility as a whole.
                    HStack(spacing: HelmSpace.s5) {
                        ForEach(Array(step.moduleSymbols.enumerated()), id: \.offset) { index, symbol in
                            Image(systemName: symbol)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(HelmText.quiet)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color.primary.opacity(0.06)))
                                .scaleEffect(revealed ? 1 : 0.4)
                                .opacity(revealed ? 1 : 0)
                                // Under Reduce Motion the icons still arrive;
                                // only the stagger and the scale go.
                                .animation(HelmMotion.reduceMotion ? nil
                                           : HelmMotion.emphasis.delay(Double(index) * 0.06),
                                           value: revealed)
                        }
                    }
                    .accessibilityHidden(true)
                }
                .onAppear { revealed = true }
            }
            Text(step.title)
                .font(HelmText.plateTitle)
                .multilineTextAlignment(.center)
            Text(step.body)
                .font(HelmText.rowTitle)
                .foregroundStyle(HelmText.quiet)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        // The step is one thing to read, not four stops.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(step.title). \(step.body)")
    }

    /// A module step keeps or drops that module; the intro asks the one
    /// app-level question worth asking here, launch at login. Both write
    /// straight through to the same store the setting reads elsewhere — this
    /// view holds no module or login-item state of its own.
    @ViewBuilder
    private func switchSection(_ step: WelcomeStep) -> some View {
        if let moduleID = step.moduleID {
            VStack(spacing: 6) {
                Toggle(WelcomeStr.useThisModule, isOn: $switchOn)
                    .toggleStyle(.switch)
                    .onChange(of: switchOn) { _, on in actions.setModuleEnabled(moduleID, on) }
                Text(WelcomeStr.switchHint)
                    .helmQuietDetail()
                // A module with something ready to hand over says so here, in
                // its own words, and the button goes straight to it, so the tour
                // sets something up rather than only describing. Only while the
                // module is on: a page for a module just switched off is a door
                // to a dark room.
                if let offer = step.offer, switchOn {
                    Button(offer) { actions.openModule(moduleID) }
                        .controlSize(.small)
                }
            }
        } else {
            Toggle(HelmWord.openHelmAtLogin, isOn: $switchOn)
                .toggleStyle(.switch)
                .onChange(of: switchOn) { _, on in
                    let settled = actions.setLaunchAtLogin(on)
                    if settled != on { switchOn = settled }
                }
        }
    }

    private func currentSwitchValue(_ step: WelcomeStep) -> Bool {
        if let moduleID = step.moduleID { return actions.isModuleEnabled(moduleID) }
        return actions.isLaunchAtLogin()
    }
}
