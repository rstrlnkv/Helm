// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import HelmUI

/// **Running an assertion in a language, and putting the app back afterwards.**
///
/// The suite runs in whatever language this Mac is set to, so a bare assertion
/// about a string checks one of eight, and a defect in an English value passes
/// on a Mac set to Russian (Architecture/TestsAndMeasurement.md § Shared test plumbing).
///
/// The `defer` is the part worth having in one place: a body that throws or
/// fails mid-loop would otherwise leave the process in a language nobody chose,
/// and the failure would report itself as somebody else's assertion three files
/// away.
///
/// The rule a new test follows: an assertion about what a visible string says
/// takes its language from `each` or `only`. `AppLanguage.current` is read only
/// where the subject is that a call with no language answers in the app's
/// language, or inside a body that has already set `override`. Older tests that
/// set `override` by hand may move here.
public extension AppLanguage {

    /// The body, once per language, with `override` set to it.
    static func each(_ body: (AppLanguage) -> Void) {
        let previous = override
        defer { override = previous }
        for language in allCases {
            override = language
            body(language)
        }
    }

    /// The body in one language named outright, for a claim that is about that
    /// language rather than about all of them — a system spelling, a wrap.
    static func only(_ language: AppLanguage, _ body: () -> Void) {
        let previous = override
        defer { override = previous }
        override = language
        body()
    }
}

/// The asynchronous half of `only`, for a claim about one language whose body
/// has to mount and settle a page.
///
/// It runs on the caller's own actor (`isolated (any Actor)? = #isolation`):
/// every body that needs this mounts a view on the main actor, and a
/// `@Sendable` or `sending` closure would ask to hop off it; neither compiles.
public extension AppLanguage {
    static func only(_ language: AppLanguage,
                     isolation: isolated (any Actor)? = #isolation,
                     _ body: () async -> Void) async {
        let previous = override
        defer { override = previous }
        override = language
        await body()
    }
}
