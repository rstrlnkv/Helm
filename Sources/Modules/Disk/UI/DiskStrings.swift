// swiftlint:disable line_length
//
// Every line this rule flags in this file is one localized string — the English
// that is also the key, and that eight `.strings` files answer. Splitting one
// across source lines buys nothing and risks the key. `.swiftlint.yml` already
// says these lines "are correct at that length"; the exemption is here so the
// 320-character warning can go on meaning what that comment claims it means —
// a notice about runaway *code* — instead of firing 61 times on the one case
// it excuses.

import Foundation
import HelmRuntime
import HelmUI
import Module_Disk_Engine

enum DkStr {
    /// The display name only — the module id stays `disk`, or every stored
    /// setting keyed to it would be orphaned.
    static var moduleName: String { L("Disk") }
    static var summary: String { L("What is taking up space") }
    static var scanFolder: String { L("Scan a folder…") }
    static var scanning: String { L("Scanning") }
    static var stop: String { L("Stop scan") }
    static var cancel: String { L("Cancel") }
    /// Leaves the scan on screen and goes back to the picker — and forgets the
    /// saved one, which is the only way out of a scan that should not have been
    /// there. Without it the app opened on whatever it measured last, for ever.
    static var chooseAnother: String { L("Choose another…") }
    static var scanAgain: String { L("Scan again") }
    static var free: String { L("free") }
    static var moveToTrash: String { L("Move to Trash") }
    /// "Basket" was the only place the English UI used the word: no visible
    /// label says it — the bar itself is headed "To remove".
    static var basketContents: String { L("Show what is marked for removal") }
    /// `HelmBasket` in HelmUI — the same bar Duplicates draws, and both had
    /// these two lines built inside the view with a Latin middle dot and an
    /// ASCII colon whatever the language.
    static func basketLine(_ count: Int, _ size: String) -> String {
        HelmBasket.line(count: count, size: size)
    }
    static func basketItem(_ name: String, _ size: String) -> String {
        HelmBasket.item(name: name, size: size)
    }
    /// The name of the action, not of the gesture: "Add" has no object, and a
    /// screen reader says it once per row down a list of two hundred.
    static var markForRemoval: String { L("Mark for removal") }
    /// What the same button does when the item is already marked — which is
    /// what it was announcing as "Add".
    static var unmarkForRemoval: String { L("Unmark for removal") }
    /// One button, two meanings. Kept here rather than at the two call sites so
    /// the pair cannot drift apart — they already had, in the direction where
    /// the label described neither state.
    static func basketAction(basketed: Bool) -> String {
        basketed ? unmarkForRemoval : markForRemoval
    }
    static var systemItem: String { L("System") }
    static var emptyFolder: String { L("Nothing in this folder.") }
    static var noAccess: String { L("No access") }
    static var scanNeedsAccess: String { L("Without Full Disk Access some folders scan as empty.") }
    static var startHint: String { L("Pick a volume, or scan any folder.") }
    /// The start screen's silence. Its opening is Leftovers' `rescanLost` word for
    /// word, because it is literally the same nil coming back from
    /// `TransportClient.request` — two phrasings of one machine fact is a defect
    /// this codebase keeps catching. What follows differs because what is under it
    /// differs: there, a list from the previous scan; here, a picker that may be
    /// missing a disk somebody is looking for.
    static var volumeListLost: String { L("Helm got no answer, so this may not be every volume.") }
    static func scannedIn(_ files: Int, _ seconds: String) -> String { L("\(files) files in \(seconds) s", [.ru: "Файлов: \(files) за \(seconds) с", .es: "\(files) archivos en \(seconds) s", .fr: "\(files) fichiers en \(seconds) s", .de: "\(files) Dateien in \(seconds) s", .ja: "\(files) ファイル / \(seconds) 秒", .zh: "\(files) 个文件，\(seconds) 秒", .pt: "\(files) arquivos em \(seconds) s"]) }
    /// Where the files went, not what the disk gained: the Trash is a folder on
    /// the same volume, so nothing is free until it is emptied. Same wording as
    /// the button that started it (Finder's `AL13`), in the past tense.
    static func movedToTrash(_ size: String) -> String { L("Moved to the Trash — \(size)", [.ru: "Перемещено в Корзину — \(size)", .es: "Trasladado a la papelera — \(size)", .fr: "Placé dans la corbeille — \(size)", .de: "In den Papierkorb gelegt — \(size)", .ja: "ゴミ箱に入れました — \(size)", .zh: "已移到废纸篓 — \(size)", .pt: "Movido para o Lixo — \(size)"]) }
    /// Takes the plan, not a count and a size the caller worked out for itself.
    ///
    /// The page had both to hand — `basket.count` and `basketBytes` — and they
    /// describe the basket, which for a cache row is one entry standing for the
    /// contents of a folder. Passing the question along is the same repair
    /// `VPNStr.secretNeedsAPress` made by construction: the sentence cannot name
    /// something other than what the button does, because it is handed nothing
    /// else to name.
    static func confirmTrash(_ question: DiskRemovalPlan.Question) -> String {
        HelmConfirm.trash(Plural.items(question.count, language: AppLanguage.current.rawValue),
                          Bytes(question.bytes))
    }
    static func measured(_ ago: String) -> String { L("Measured \(ago)", [.ru: "Измерено \(ago)", .es: "Medido \(ago)", .fr: "Mesuré \(ago)", .de: "Gemessen \(ago)", .ja: "計測 \(ago)", .zh: "测量于 \(ago)", .pt: "Medido \(ago)"]) }
    /// The third thing the ring can be showing, beside a fresh measurement and a
    /// memory of one: a walk that was stopped.
    ///
    /// One word, and deliberately without the file count its siblings carry.
    /// Measured against the widest existing statement at `.caption`, "Остановлено
    /// — файлов: 263144" is 161 pt against a 122 pt budget — and the width the
    /// `showsScanStatement` threshold was measured for is that budget, so at
    /// windows just above it the line would arrive truncated. A warning with an
    /// ellipsis in it is a poor warning; the count moved to the hint, which has no
    /// width to answer to. `StoppedStatementWidthTests` holds the budget.
    static var stopped: String { L("Stopped") }
    /// Why that line matters, and how far the walk got. `TreeBuilder` charges a
    /// directory as its files are found, so every folder in a stopped tree shows a
    /// floor and not a total — which is the number somebody would be deciding to
    /// delete on. Interpolated, so it keeps an inline table: the lookup would
    /// otherwise be asked for a key with the count already in it.
    static func stoppedHint(_ files: Int) -> String { L("The walk was stopped after \(files) files, so a folder may hold more than it shows.", [.ru: "Обход прерван, измерено файлов: \(files). Папка может содержать больше, чем показано.", .es: "El recorrido se detuvo tras \(files) archivos, así que una carpeta puede contener más de lo que muestra.", .fr: "L’analyse a été arrêtée après \(files) fichiers : un dossier peut contenir plus que ce qu’il affiche.", .de: "Der Durchlauf wurde nach \(files) Dateien gestoppt, daher kann ein Ordner mehr enthalten als angezeigt.", .ja: "\(files) ファイルで走査を停止したため、フォルダの実際の容量は表示より大きい場合があります。", .zh: "扫描在 \(files) 个文件后停止，文件夹的实际大小可能大于显示值。", .pt: "A varredura parou após \(files) arquivos, então uma pasta pode conter mais do que mostra."]) }
    static var advice: String { L("Recommendations") }
    static var adviceHint: String { L("What could be deleted") }
    static var adviceKindCache: String { L("Cache — apps rebuild it") }
    static var adviceKindOldDownload: String { L("Old download") }
    /// What the attribute actually says. The scanner reads `ATTR_CMN_MODTIME`,
    /// which is when the file was last *written*; the row used to claim
    /// "Untouched for months", which is a statement about use. A Parallels
    /// image opened every morning and a film watched monthly are both written
    /// to by nobody, and both were listed as untouched. Nothing macOS hands a
    /// bulk directory read reports use, so the row says the date instead —
    /// which is also the reason it was previously missing.
    static func notModifiedSince(_ date: String) -> String { L("Not modified since \(date)", [.ru: "Не изменялся с \(date)", .es: "Sin modificar desde el \(date)", .fr: "Non modifié depuis le \(date)", .de: "Nicht geändert seit \(date)", .ja: "\(date) 以降変更なし", .zh: "自 \(date) 起未修改", .pt: "Sem modificações desde \(date)"]) }
    /// The same claim with no date to hang it on: advice restored from a scan
    /// an earlier build cached, which carried the verdict and not the date.
    static var notModifiedInMonths: String { L("Not modified in months") }
    /// Why a row is in the Advice list — and, for the size-and-age verdict, the
    /// date it was reached from. Here rather than in the view because it is a
    /// decision with three branches and one of them turns on whether there is a
    /// date at all, which is exactly the kind of thing a test should be able to
    /// ask about without rendering anything.
    static func adviceReason(_ advice: DiskAdvice) -> String {
        switch advice.kind {
        // A folder, whose own mtime says when something was last added to it
        // and nothing about what is inside. No date to offer, so no date.
        case .cache: adviceKindCache
        // Both file verdicts are dates — thirty days for a download, half a year
        // for a large file — and the download row offered the category word as
        // its whole evidence against a request to bin an 8 GB installer. Each
        // keeps its own fallback beside it, for advice cached by a build that
        // did not carry the date.
        case .oldDownload: dated(advice.modified) ?? adviceKindOldDownload
        case .largeOld: dated(advice.modified) ?? notModifiedInMonths
        }
    }

    /// The day, not the minute: these judgements are measured in months, and
    /// "19:00" is noise on a file nobody has touched since March. nil where
    /// there is no date to say anything about.
    private static func dated(_ modified: TimeInterval?) -> String? {
        modified.map { notModifiedSince(HelmDates.day(Date(timeIntervalSince1970: $0))) }
    }
    static var otherItems: String { L("Smaller items") }
    static var ringMap: String { L("Disk map") }
    static var openFolder: String { L("Look inside") }
    static func ringShare(_ name: String, _ size: String, _ percent: Int) -> String { L("\(name), \(size), \(percent)% of this folder", [.ru: "\(name), \(size), \(percent) % этой папки", .es: "\(name), \(size), \(percent) % de esta carpeta", .fr: "\(name), \(size), \(percent) % de ce dossier", .de: "\(name), \(size), \(percent) % dieses Ordners", .ja: "\(name)、\(size)、このフォルダの \(percent)%", .zh: "\(name)，\(size)，占此文件夹 \(percent)%", .pt: "\(name), \(size), \(percent)% desta pasta"]) }
    static var back: String { L("Back") }
    static func liveCount(_ files: Int) -> String { L("\(files) files", [.ru: "Файлов: \(files)", .es: "\(files) archivos", .fr: "\(files) fichiers", .de: "\(files) Dateien", .ja: "\(files) ファイル", .zh: "\(files) 个文件", .pt: "\(files) arquivos"]) }
}
