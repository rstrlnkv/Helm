// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import HelmUI

/// **Running an assertion in a language, and putting the app back afterwards.**
///
/// The suite runs in whatever language this Mac is set to, so a bare assertion
/// about a string checks one of eight — and this machine's is Russian, which is how
/// a mutation planted in an English value once passed a whole suite (CLAUDE.md §
/// What not to do, and what breaks if you do). The answer is a loop over
/// `AppLanguage.allCases` with `override` set and restored, and it was hand-written
/// in every file that needed it: three identical private copies in the VPN pages
/// alone, each with its own `let previous` and its own `defer`.
///
/// The `defer` is the part worth having in one place. A body that throws or
/// fails an assertion mid-loop leaves the whole process in the last language it
/// was set to otherwise, and the next test file to read a string is then reading
/// a language nobody chose — a failure that reports itself as somebody else's
/// broken assertion three files away.
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
/// A separate entry point rather than an `async` version of `each`: the reason
/// `only` exists — a claim that is about *that* language rather than about all
/// of them — is unchanged, and so is the `defer`. A body that fails or throws
/// mid-way would otherwise leave the whole process in a language nobody chose,
/// which is the failure that reports itself three files away.
///
/// **It runs on the caller's own actor**, which is what `isolated (any Actor)?
/// = #isolation` buys. Every body that needs this mounts a view, so it is
/// `@MainActor`, and a helper that took a `@Sendable` or `sending` closure
/// would be asking to hop off the actor the page has to be laid out on —
/// neither compiles, and the second only stopped compiling after the first was
/// tried.
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
