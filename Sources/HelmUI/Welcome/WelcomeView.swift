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
