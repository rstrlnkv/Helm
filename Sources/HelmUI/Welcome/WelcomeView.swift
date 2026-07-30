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
    private let isModuleEnabled: (String) -> Bool
    private let setModuleEnabled: (String, Bool) -> Void
    private let isLaunchAtLogin: () -> Bool
    private let setLaunchAtLogin: (Bool) -> Void
    private let onClose: () -> Void
    @State private var flow: WelcomeFlow
    @State private var revealed = false
    /// One switch, wearing two hats depending on the step: launch-at-login on
    /// the intro, that module's enablement on a module step. Seeded in
    /// `.onAppear` from whichever closure the current step calls for, the same
    /// re-seed-per-step pattern `revealed` already uses below — `.id(step.id)`
    /// re-runs `.onAppear` each time the step changes, so this never carries a
    /// stale value from the step before it.
    @State private var switchOn = false

    public init(steps: [WelcomeStep],
                isModuleEnabled: @escaping (String) -> Bool = { _ in true },
                setModuleEnabled: @escaping (String, Bool) -> Void = { _, _ in },
                isLaunchAtLogin: @escaping () -> Bool = { false },
                setLaunchAtLogin: @escaping (Bool) -> Void = { _ in },
                onClose: @escaping () -> Void) {
        self.steps = steps
        self.isModuleEnabled = isModuleEnabled
        self.setModuleEnabled = setModuleEnabled
        self.isLaunchAtLogin = isLaunchAtLogin
        self.setLaunchAtLogin = setLaunchAtLogin
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
                    stepContent(step)
                    switchSection(step)
                }
                .frame(maxWidth: 420)
                .padding(.horizontal, 32)
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
                }
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

    /// The mark/icon, title and body — one thing for VoiceOver to read, so the
    /// switch below (its own control, its own name) stays a second, separate
    /// stop rather than being folded into the same combined utterance.
    @ViewBuilder
    private func stepContent(_ step: WelcomeStep) -> some View {
        VStack(spacing: 16) {
            if step.moduleSymbols.isEmpty {
                Image(systemName: step.sfSymbol)
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(HelmText.quiet)
                    .accessibilityHidden(true)
            } else {
                // The mark and the title/body stand still; only the
                // icon row moves — one thing moves, the rest doesn't.
                VStack(spacing: 20) {
                    HelmAppMark(size: 72)
                    // The app's parts, arriving one after another — the
                    // first screen answers "what is this made of" before
                    // a word is read. Icons are decorative here; the step
                    // text carries the meaning, and the row is hidden
                    // from accessibility as a whole.
                    HStack(spacing: 14) {
                        ForEach(Array(step.moduleSymbols.enumerated()), id: \.offset) { index, symbol in
                            Image(systemName: symbol)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(HelmText.quiet)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color.primary.opacity(0.06)))
                                .scaleEffect(revealed ? 1 : 0.4)
                                .opacity(revealed ? 1 : 0)
                                // Under Reduce Motion the icons still
                                // arrive — the stagger and the scale
                                // that would carry it do not, the
                                // same trade the VPN spin makes.
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
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(step.body)
                .font(.callout)
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
                    .onChange(of: switchOn) { _, on in setModuleEnabled(moduleID, on) }
                Text(WelcomeStr.switchHint)
                    .font(.caption)
                    .foregroundStyle(HelmText.quiet)
            }
        } else {
            Toggle(WelcomeStr.launchAtLogin, isOn: $switchOn)
                .toggleStyle(.switch)
                .onChange(of: switchOn) { _, on in setLaunchAtLogin(on) }
        }
    }

    private func currentSwitchValue(_ step: WelcomeStep) -> Bool {
        if let moduleID = step.moduleID { return isModuleEnabled(moduleID) }
        return isLaunchAtLogin()
    }
}
