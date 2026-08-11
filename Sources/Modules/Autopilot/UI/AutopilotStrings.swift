// swiftlint:disable line_length
//
// Every line this rule flags in this file is one localized string — the English
// that is also the key, and that eight `.strings` files answer. Splitting one
// across source lines buys nothing and risks the key. `.swiftlint.yml` already
// says these lines "are correct at that length"; the exemption is here so the
// 320-character warning can go on meaning what that comment claims it means —
// a notice about runaway *code* — instead of firing 61 times on the one case
// it excuses.

import HelmUI
import Module_Autopilot_Engine

/// Every user-visible string in the autopilot module, in eight languages.
///
/// The module is named for what it does rather than what it is made of: a
/// folder holds rules, and the module keeps the folder on course without hands
/// on it — the instrument Helm is named after, one step further along. "Rules"
/// named the mechanism, and left the sidebar with an entry that could have
/// belonged to any part of the app.
enum ApStr {
    static var moduleName: String { L("Autopilot") }
    static var summary: String { L("Folders that keep themselves in order") }
    static var startHint: String { L("Point Helm at a folder and give it rules. A file that arrives is checked against them in order and the first match wins — and every watched folder is checked again once an hour, so age rules come round.") }
    static var needsAccess: String { L("Without Full Disk Access a protected folder reads as empty: no rule matches, and that looks exactly like a folder with nothing to do.") }

    // MARK: - Folders

    static var addFolder: String { L("Add folder…") }
    static var removeFolder: String { L("Stop watching") }
    static var runNow: String { L("Run now") }
    static var noRules: String { L("No rules yet") }
    static var depth: String { L("Include subfolders") }

    // MARK: - Rules

    static var newRule: String { L("New rule") }
    static var untitledRule: String { L("Untitled rule") }
    static var ruleName: String { L("Name") }
    static var matchAll: String { L("all of") }
    static var matchAny: String { L("any of") }
    static var whenLabel: String { L("When") }
    static var thenLabel: String { L("Then") }
    static var addCondition: String { L("Add condition") }
    static var firstMatchNote: String { L("Rules run top to bottom and the first match wins — a file gets one action, not several.") }

    // MARK: - Dry run

    static var dryRun: String { L("What would happen") }
    static var dryRunNote: String { L("A rule is a decision made once and carried out from then on, so it is shown before it is switched on.") }
    static var nothingWouldHappen: String { L("Nothing in this folder matches yet.") }
    static var enableRule: String { L("Turn the rule on") }
    static func swept(_ acted: Int, _ examined: Int) -> String { L("Acted on \(acted) of \(examined)", [.ru: "Обработано \(acted) из \(examined)", .es: "Se actuó sobre \(acted) de \(examined)", .fr: "\(acted) sur \(examined) traités", .de: "\(acted) von \(examined) bearbeitet", .ja: "\(examined) 件中 \(acted) 件を処理", .zh: "处理了 \(examined) 个中的 \(acted) 个", .pt: "Agiu sobre \(acted) de \(examined)"]) }

    // MARK: - Fields

    static var fieldName: String { L("Full name") }
    /// The name with the extension taken off. Sits next to "Full name" rather
    /// than replacing it: a rule written against the full name is somebody's
    /// working rule, and changing what it means would break it in silence.
    static var fieldBaseName: String { L("Name without extension") }
    static var fieldExtension: String { L("Extension") }
    static var fieldKind: String { L("Kind") }
    static var fieldSize: String { L("Size") }
    static var fieldDateAdded: String { L("Date added") }
    static var fieldDateModified: String { L("Date modified") }
    static var fieldSource: String { L("Downloaded from") }
    static var fieldTag: String { L("Tag") }

    static var comparisonIs: String { L("is") }
    static var comparisonContains: String { L("contains") }
    static var comparisonBegins: String { L("begins with") }
    static var comparisonEnds: String { L("ends with") }
    static var comparisonLarger: String { L("larger than") }
    static var comparisonSmaller: String { L("smaller than") }
    static var comparisonOlder: String { L("older than") }
    static var comparisonNewer: String { L("newer than") }
    static var unitMegabytes: String { L("MB") }
    /// The word, agreeing with the number in the field beside it. The
    /// argument for a bare plural was that the label names a field rather than
    /// counting anything — but the field holds a number, so it counts, and the
    /// row opened on "1 дней".
    ///
    /// Both of these stand after «старше» or «новее», which govern the
    /// genitive, so the agreement is `DayUnit`'s rather than `Plural`'s: the
    /// count's own «1 день» / «2 дня» is the wrong case in this position.
    static func unitDays(for count: Double) -> String {
        DayUnit.wordAfterComparison(count, language: AppLanguage.current.rawValue)
    }

    /// Composed with the number rather than glued to it: a bare word after a
    /// numeral gives «1 дней» and «22 дней» in Russian, and "1 days" in English.
    static func days(_ count: Double) -> String {
        DayUnit.afterComparison(count, language: AppLanguage.current.rawValue)
    }

    static func kindName(_ kind: FileKind) -> String {
        switch kind {
        case .image: L("Image")
        case .document: L("Document")
        case .archive: L("Archive")
        case .video: L("Video")
        case .audio: L("Audio")
        case .folder: L("Folder")
        case .other: L("Other")
        }
    }

    // MARK: - Actions

    static var actionMove: String { L("Move to folder") }
    static var actionSort: String { L("Sort into subfolder") }
    static var actionRename: String { L("Rename") }
    static var actionTag: String { L("Add tag") }
    static var actionTrash: String { L("Move to Trash") }
    static var schemeKind: String { L("by kind") }
    static var schemeMonth: String { L("by month") }
    static var patternHint: String { L("{name}, {date} and {counter} are replaced. The extension is always the file’s own.") }
    static var chooseDestination: String { L("Choose…") }

    // MARK: - Common

    static var cancel: String { L("Cancel") }
    static var done: String { L("Done") }
    static var edit: String { L("Edit") }
    static var delete: String { L("Delete") }

    // MARK: - Names for controls that carry none on screen

    /// A rule reads as a sentence — "name contains report, move to Documents" —
    /// and the screen builds it out of pickers and fields whose meaning comes
    /// entirely from their position in the row. Sighted, that works; read aloud
    /// it was "pop up button, pop up button, text field" and a rule could not be
    /// built at all. These are the names those controls always had and never
    /// said. Kept short, because VoiceOver reads the name before every value.
    static var a11yField: String { L("What to check") }
    static var a11yComparison: String { L("How to compare") }
    static var a11yValue: String { L("Value to match") }
    static var a11yExtensions: String { L("Extensions, separated by commas") }
    static var a11yDays: String { L("Number of days") }
    static var a11yMegabytes: String { L("Size in megabytes") }
    static var a11yHost: String { L("Site the file came from") }
    static var a11yTagValue: String { L("Tag name") }
    static var a11yAction: String { L("What to do") }
    static var a11yScheme: String { L("Renaming scheme") }
    static var a11yPattern: String { L("Name pattern") }
    static var a11yMatch: String { L("Which conditions must match") }

    // MARK: - What it did

    static var historyTitle: String { L("Last 30 days") }
    static var historyEmpty: String { L("Autopilot has not done anything yet.") }
    static var historyClear: String { L("Clear") }
    /// Refusals and failures counted together: both mean a file the rule meant
    /// to act on is still sitting where it was.
    static func historyProblems(_ count: Int) -> String {
        // Written as label-then-count on purpose. "2 не прошло" needs "прошли"
        // for two through four in Russian, and the same trap waits in every
        // language that agrees a verb with a numeral; a colon makes the number
        // a count rather than a subject and the agreement question disappears.
        L("not completed: \(count)", [.ru: "не выполнено: \(count)", .es: "sin completar: \(count)", .fr: "non effectuées : \(count)", .de: "nicht ausgeführt: \(count)", .ja: "未実行: \(count)", .zh: "未完成：\(count)", .pt: "não concluídas: \(count)"])
    }

    /// The verb for one row. Past tense, because the row is a record of
    /// something that already happened — the rule editor's list says "Move",
    /// this says "moved", and the difference is the whole point of the section.
    static func historyVerb(_ kind: ActionRecord.Kind) -> String {
        switch kind {
        case .moved: L("moved to")
        case .renamed: L("renamed to")
        // German said "Tag" — the word for *day*, which this module also prints
        // in the same column ("älter als 30 Tage"), so the record of a tagged
        // file read as a record of a date. French said "Étiquette", a
        // capitalised noun among five lowercase past participles. Both are past
        // participles now, which is what every other language here already had.
        case .tagged: L("tagged")
        case .trashed: L("moved to Trash")
        case .refused: L("refused")
        case .failed: L("failed")
        }
    }
}
