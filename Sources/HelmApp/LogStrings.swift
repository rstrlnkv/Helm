// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmRuntime
import HelmUI

/// What the Log page says in words.
///
/// **Two kinds, and the split is Swift's own.** A string with no number in it is
/// an ordinary lookup on its English text and lives in the eight `.strings`
/// files. A counted one is interpolated, so interpolation runs before the
/// lookup and it could never match a key — those carry an inline table, the way
/// `logSomeModules` and `logCount` do, with the noun's form chosen per language
/// (`Plural.russian` for the three-form one; the others have two, and Japanese
/// and Chinese have none). Nothing here interpolates a word into a sentence: a
/// noun inflected by a number is written out whole per language, because one
/// form spliced into eight grammars is right in roughly one of them.
extension AppStr {

    /// The search field's prompt. Named for what it searches, like «Search
    /// apps» and «Search packages» on the pages beside it.
    static var logSearch: String { L("Search the log") }

    /// What Follow says it is doing, as its accessibility value: its glyph is
    /// an open or a slashed eye, and a glyph is not a word VoiceOver can read.
    static var logFollowing: String { L("Following") }
    static var logNotFollowing: String { L("Not following") }

    /// The heading of the card at the head of the tail, whose launch began
    /// before anything the page holds — it has no start line to name a version
    /// by. Only that card: a run with no start line that comes *after* another
    /// card began later, and says its time alone (`LogCardTitle`).
    static var logEarlierLaunch: String { L("Earlier launch") }

    /// The last fragment of the footer: what the page does not show is not gone.
    /// Said only when the tail is full (`LogView.olderLinesExist`), because a
    /// short log shows everything the file holds.
    static var logOlderInFile: String { L("older lines are in the file") }

    /// The start-up burst, folded: what a launch says while it switches its
    /// modules on, and how much of it there is.
    static func logStartup(_ n: Int) -> String {
        let count = Count(n)
        return L(n == 1 ? "Starting modules · 1 line" : "Starting modules · \(count) lines", [
            .ru: "Старт модулей · строк: \(count)",
            .es: "Inicio de módulos · " + (n == 1 ? "1 línea" : "\(count) líneas"),
            .fr: "Démarrage des modules · " + (n <= 1 ? "\(count) ligne" : "\(count) lignes"),
            .de: "Modulstart · " + (n == 1 ? "1 Zeile" : "\(count) Zeilen"),
            .ja: "モジュールの起動 · \(count) 行",
            .zh: "模块启动 · \(count) 行",
            .pt: "Início dos módulos · " + (n == 1 ? "1 linha" : "\(count) linhas")])
    }

    /// How many lines of a launch were errors — lines, not distinct messages:
    /// a fault written a thousand times is a thousand.
    static func logErrorCount(_ n: Int) -> String {
        let count = Count(n)
        return L(n == 1 ? "1 error" : "\(count) errors", [
            .ru: "\(count) " + Plural.russian(n, "ошибка", "ошибки", "ошибок"),
            .es: n == 1 ? "1 error" : "\(count) errores",
            .fr: "\(count) " + (n <= 1 ? "erreur" : "erreurs"),
            .de: "\(count) Fehler",
            .ja: "エラー \(count) 件",
            .zh: "\(count) 个错误",
            .pt: n == 1 ? "1 erro" : "\(count) erros"])
    }

    static func logWarningCount(_ n: Int) -> String {
        let count = Count(n)
        return L(n == 1 ? "1 warning" : "\(count) warnings", [
            .ru: "\(count) " + Plural.russian(n, "предупреждение", "предупреждения", "предупреждений"),
            .es: n == 1 ? "1 aviso" : "\(count) avisos",
            .fr: "\(count) " + (n <= 1 ? "avertissement" : "avertissements"),
            .de: n == 1 ? "1 Warnung" : "\(count) Warnungen",
            .ja: "警告 \(count) 件",
            .zh: "\(count) 条警告",
            .pt: n == 1 ? "1 aviso" : "\(count) avisos"])
    }

    /// On the ×N badge of a folded run: when the last of the repeats was
    /// written, which the folded rows no longer show.
    static func logRepeatedUntil(_ time: String) -> String {
        L("Repeated until \(time)", [
            .ru: "Повторялась до \(time)",
            .es: "Repetida hasta \(time)",
            .fr: "Répétée jusqu’à \(time)",
            .de: "Wiederholt bis \(time)",
            .ja: "\(time) まで繰り返し",
            .zh: "重复至 \(time)",
            .pt: "Repetida até \(time)"])
    }

    /// The same sentence for a run that crossed midnight, where what follows is
    /// a day and a minute and not a time: French and Spanish put an article
    /// before a date («jusqu’au», «hasta el») that a time does not take
    /// («jusqu’à 09:00», «hasta 09:00»). Nothing is spliced into the other
    /// sentence — each is whole in every language.
    static func logRepeatedUntilDay(_ day: String) -> String {
        L("Repeated until \(day)", [
            .ru: "Повторялась до \(day)",
            .es: "Repetida hasta el \(day)",
            .fr: "Répétée jusqu’au \(day)",
            .de: "Wiederholt bis \(day)",
            .ja: "\(day) まで繰り返し",
            .zh: "重复至 \(day)",
            .pt: "Repetida até \(day)"])
    }

    /// The footer's launches count — of those in the tail, how many the filters
    /// leave. The noun follows the total, the number the sentence is about.
    static func logLaunches(_ shown: Int, _ total: Int) -> String {
        let a = Count(shown), b = Count(total)
        return L(total == 1 ? "\(a) of 1 launch" : "\(a) of \(b) launches", [
            .ru: "Запусков: \(a) из \(b)",
            .es: total == 1 ? "\(a) de 1 inicio" : "\(a) de \(b) inicios",
            .fr: total <= 1 ? "\(a) sur \(b) lancement" : "\(a) sur \(b) lancements",
            .de: total == 1 ? "\(a) von 1 Start" : "\(a) von \(b) Starts",
            .ja: "\(b) 回中 \(a) 回の起動",
            .zh: "\(b) 次启动中的 \(a) 次",
            .pt: total == 1 ? "\(a) de 1 inicialização" : "\(a) de \(b) inicializações"])
    }

    /// Where the tail begins — its oldest line, day and minute. Lower case: it
    /// is a fragment of the footer's line, after a «·».
    static func logSince(_ when: String) -> String {
        L("since \(when)", [
            .ru: "с \(when)", .es: "desde el \(when)", .fr: "depuis le \(when)",
            .de: "seit \(when)", .ja: "\(when) 以降", .zh: "自 \(when) 起",
            .pt: "desde \(when)"])
    }
}
