// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmRuntime
import HelmUI

/// What the Log page says in words.
///
/// **Two kinds.** A string with no number in it is a catalog word in
/// `Localizable.xcstrings`. A counted one is a template there, the number a `%@`,
/// the way `logSomeModules` and `logCount` do, with the noun's form chosen
/// by the key: one key per form (`Plural.form` says which: errors and warnings
/// have three forms in Russian, the other counts two; Japanese and Chinese
/// write the same in all). Nothing
/// here splices a word into a sentence: a noun inflected by a number is written
/// out whole per language, because one form spliced into eight grammars is right
/// in roughly one of them.
extension AppStr {

    /// The search field's prompt. Named for what it searches, like «Search
    /// apps» and «Search packages» on the pages beside it.
    public static var logSearch: String { L(.logSearch) }

    /// What Follow says it is doing, as its accessibility value: its glyph is
    /// an open or a slashed eye, and a glyph is not a word VoiceOver can read.
    public static var logFollowing: String { L(.logFollowing) }
    public static var logNotFollowing: String { L(.logNotFollowing) }

    /// The heading of the card at the head of the tail, whose launch began
    /// before anything the page holds — it has no start line to name a version
    /// by. Only that card: a run with no start line that comes *after* another
    /// card began later, and says its time alone (`LogCardTitle`).
    public static var logEarlierLaunch: String { L(.logEarlierLaunch) }

    /// The last fragment of the footer: what the page does not show is not gone.
    /// Said only when the tail is full (`LogView.olderLinesExist`), because a
    /// short log shows everything the file holds.
    public static var logOlderInFile: String { L(.logOlderInFile) }

    /// The start-up burst, folded: what a launch says while it switches its
    /// modules on, and how much of it there is.
    public static func logStartup(_ n: Int) -> String {
        let count = Count(n)
        return Plural.form(n, language: AppLanguage.current.rawValue) == .one
            ? L(.logStartupOne(count)) : L(.logStartupMany(count))
    }

    /// How many lines of a launch were errors — lines, not distinct messages:
    /// a fault written a thousand times is a thousand.
    public static func logErrorCount(_ n: Int) -> String {
        let count = Count(n)
        switch Plural.form(n, language: AppLanguage.current.rawValue) {
        case .one: return L(.logErrorCountOne(count))
        case .few: return L(.logErrorCountFew(count))
        case .many: return L(.logErrorCountMany(count))
        }
    }

    public static func logWarningCount(_ n: Int) -> String {
        let count = Count(n)
        switch Plural.form(n, language: AppLanguage.current.rawValue) {
        case .one: return L(.logWarningCountOne(count))
        case .few: return L(.logWarningCountFew(count))
        case .many: return L(.logWarningCountMany(count))
        }
    }

    /// On the ×N badge of a folded run: when the last of the repeats was
    /// written, which the folded rows no longer show.
    public static func logRepeatedUntil(_ time: String) -> String {
        L(.logRepeatedUntil(time))
    }

    /// The same sentence for a run that crossed midnight, where what follows is
    /// a day and a minute and not a time: French and Spanish put an article
    /// before a date («jusqu’au», «hasta el») that a time does not take
    /// («jusqu’à 09:00», «hasta 09:00»). Nothing is spliced into the other
    /// sentence — each is whole in every language.
    public static func logRepeatedUntilDay(_ day: String) -> String {
        L(.logRepeatedUntilDay(day))
    }

    /// The footer's launches count — of those in the tail, how many the filters
    /// leave. The noun follows the total, the number the sentence is about.
    public static func logLaunches(_ shown: Int, _ total: Int) -> String {
        let (a, b) = (Count(shown), Count(total))
        return Plural.form(total, language: AppLanguage.current.rawValue) == .one
            ? L(.logLaunchesOne(a, b)) : L(.logLaunchesMany(a, b))
    }

    /// Where the tail begins — its oldest line, day and minute. Lower case: it
    /// is a fragment of the footer's line, after a «·».
    public static func logSince(_ when: String) -> String {
        L(.logSince(when))
    }
}
