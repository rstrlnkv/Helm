// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmContract

public struct WelcomeStep: Equatable, Identifiable, Sendable {
    public let id: String
    public let sfSymbol: String
    public let title: String
    public let body: String
    /// Every module's symbol, in registry order — only ever non-empty on the
    /// intro step, which is a showcase rather than a single-symbol step.
    public let moduleSymbols: [String]

    public init(id: String, sfSymbol: String, title: String, body: String,
                moduleSymbols: [String] = []) {
        self.id = id
        self.sfSymbol = sfSymbol
        self.title = title
        self.body = body
        self.moduleSymbols = moduleSymbols
    }
}

/// The tour, built from what the modules already say about themselves.
public enum WelcomeSteps {
    /// Takes metadata rather than reaching for `ModuleRegistry`, which lives in
    /// `HelmApp` — an executable target with no tests. This signature is why
    /// the tour can be asserted at all; do not "simplify" it back.
    public static func build(from modules: [ModuleMetadata]) -> [WelcomeStep] {
        let intro = WelcomeStep(id: "intro", sfSymbol: "sparkles",
                                title: WelcomeStr.introTitle, body: WelcomeStr.introBody,
                                moduleSymbols: modules.map(\.sfSymbol))
        return [intro] + modules.map {
            WelcomeStep(id: $0.id.rawValue, sfSymbol: $0.sfSymbol,
                        title: $0.name, body: $0.summary)
        }
    }
}
