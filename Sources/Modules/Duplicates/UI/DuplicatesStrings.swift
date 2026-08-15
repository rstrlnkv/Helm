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
import Module_Duplicates_Engine

/// Every user-visible string in the duplicate finder, in eight languages.
enum DupStr {
    static var chooseFolder: String { L("Choose folder") }
    static var chooseAnother: String { L("Choose another folder") }
    static var search: String { L("Search now") }
    static var searchAgain: String { L("Search again") }
    static var startHint: String { L("Pick a folder and Helm will read what is in it, comparing content rather than names.") }
    static var needsAccess: String { L("Without Full Disk Access Helm cannot read every folder, and a short list of duplicates looks exactly like a folder that has none.") }
    static var stop: String { L("Stop scan") }
    /// "Basket" appears nowhere on screen in any language — the bar above these
    /// controls is headed "To remove". Disk dropped the metaphor for the same
    /// reason; these are the last four that kept it.
    static var basketContents: String { L("Show what is marked for removal") }
    /// `HelmBasket` in HelmUI: Disk draws the same bar and had the same two
    /// lines assembled inside its view. Fixing it here and copying the fix
    /// there is what this pass exists to undo.
    static func basketLine(_ count: Int, _ size: String) -> String {
        HelmBasket.line(count: count, size: size)
    }
    static func basketItem(_ name: String, _ size: String) -> String {
        HelmBasket.item(name: name, size: size)
    }
    static var moveToTrash: String { L("Move to Trash") }
    static var systemItem: String { L("System") }
    static var reveal: String { L("Show in Finder") }
    static var quickLook: String { L("Quick Look") }
    /// What happened, not what people hope happened: the copies went to the
    /// Trash, which is on the same volume, so nothing is freed until the Trash
    /// is emptied. Word for word `DiskStrings.movedToTrash` — four modules say
    /// this sentence now and they must say it the same way.
    static func movedToTrash(_ size: String) -> String {
        L("Moved to the Trash — \(size)", [.ru: "Перемещено в Корзину — \(size)", .es: "Trasladado a la papelera — \(size)", .fr: "Placé dans la corbeille — \(size)", .de: "In den Papierkorb gelegt — \(size)", .ja: "ゴミ箱に入れました — \(size)", .zh: "已移到废纸篓 — \(size)", .pt: "Movido para o Lixo — \(size)"])
    }
    static func confirmTrash(_ count: Int, _ size: String) -> String {
        // The size stays — how much is going is worth knowing — but the promise
        // that it will be freed does not: the Trash is on the same volume.
        HelmConfirm.trash(Plural.files(count, language: AppLanguage.current.rawValue), size)
    }
    static var moduleName: String { L("Duplicates") }
    static var summary: String { L("Files that exist more than once") }
    /// Takes the language, as `none` below does and for the same reason:
    /// `busyLine` chooses between this and `progressLine`, and a choice checked
    /// only in the suite's own language is checked in one language eight times.
    static func searching(language: AppLanguage = AppLanguage.current) -> String {
        L("Reading files…", language: language)
    }
    /// The one sentence a busy screen draws: the tick when there is one, the
    /// plain «reading» when there is not — true of a search and of a removal's
    /// verification alike, since both are files being read in full.
    ///
    /// A function rather than an expression inside the page, because the page's
    /// branch was exercised by nothing: no fake could emit a progress event, so
    /// the `progressLine` half had never been reached by any test.
    static func busyLine(_ progress: DuplicateProgress?,
                         language: AppLanguage = AppLanguage.current) -> String {
        guard let progress, progress.candidates > 0 else {
            return searching(language: language)
        }
        return progressLine(progress.hashed, progress.candidates, language: language)
    }
    /// The button beside a running removal. Not `stop` — that key says «Stop
    /// scan», and this press must not read as one about the search.
    static var stopRemoval: String { L("Stop removal") }
    /// The named outcome of a stopped removal. What did move before the stop is
    /// the banner's to say; this sentence owns the other half — that from the
    /// stop on, nothing else went.
    static func removalStopped(language: AppLanguage = AppLanguage.current) -> String {
        L("Removal stopped — nothing more was moved.", language: language)
    }
    /// The named outcome of a stopped search — drawn as the start screen's
    /// message, because a cancelled search lands on the start phase and the
    /// screen otherwise reads as if nothing had happened. It covers the engine
    /// giving up as well as the person pressing Stop: either way the folder
    /// was not read to the end, which is the half the person acts on.
    static func searchStopped(language: AppLanguage = AppLanguage.current) -> String {
        L("Search stopped — the folder was not read to the end.", language: language)
    }
    /// Both counts go through `Count` — the candidate total runs over every
    /// large file under the folder, which is six digits on a real library.
    /// `BigCountsReadGroupedTests` holds this line and `found` below.
    static func progressLine(_ done: Int, _ total: Int,
                             language: AppLanguage = AppLanguage.current) -> String {
        let (a, b) = (Count(done, language: language), Count(total, language: language))
        return L("\(a) of \(b) checks done", [.ru: "Проверок сделано: \(a) из \(b)", .es: "\(a) de \(b) comprobaciones hechas", .fr: "\(a) vérifications sur \(b)", .de: "\(a) von \(b) Prüfungen erledigt", .ja: "\(b) 件中 \(a) 件を確認済み", .zh: "已完成 \(a) / \(b) 项检查", .pt: "\(a) de \(b) verificações feitas"], language: language)
    }
    /// Takes the language, as `found` above does and for the same reason: the
    /// suite runs in this machine's language, so a sentence that reads
    /// `AppLanguage.current` is checked in one language eight times. This one is
    /// compared against its two neighbours below, and a comparison where only
    /// one side moves is a check that cannot fail — measured: with the refusal
    /// folded back into this sentence, every language still read Russian here.
    static func none(language: AppLanguage = AppLanguage.current) -> String {
        L("No duplicates here. Every large file under this folder is one of a kind.", language: language)
    }
    /// The message over an empty result, one per reason there is no list.
    ///
    /// **The message, not a note under «No duplicates here».** A headline with a
    /// footnote invites the reader to trust the headline, and that headline is
    /// exactly the claim a walk that was refused cannot back — the same choice
    /// `LfStr.emptyMessage` records, and the same repair.
    ///
    /// Exhaustive over the enum, with no `default`: a fourth reason would
    /// otherwise be drawn as the all-clear, which is the defect the type exists
    /// for.
    static func emptyMessage(_ nothing: DuplicatesEmpty.Reason,
                             language: AppLanguage = AppLanguage.current) -> String {
        switch nothing {
        case .nothingFound: return none(language: language)
        case .notEverythingRead(let count): return couldNotRead(count, language: language)
        case .librariesNotOpened: return librariesNotOpened(language: language)
        }
    }
    static func couldNotRead(_ n: Int, language: AppLanguage = AppLanguage.current) -> String {
        let items = Plural.items(n, language: language.rawValue)
        return L("Helm could not read \(items), so the answer is incomplete.",
                 [.ru: "Helm не смог прочитать \(items), поэтому ответ неполный.",
                  .es: "Helm no pudo leer \(items), por lo que la respuesta está incompleta.",
                  .fr: "Helm n’a pas pu lire \(items), la réponse est donc incomplète.",
                  .de: "Helm konnte \(items) nicht lesen, die Antwort ist daher unvollständig.",
                  .ja: "Helm は\(items)を読み取れなかったため、この結果は完全ではありません。",
                  .zh: "Helm 无法读取\(items)，因此这不是完整的结果。",
                  .pt: "O Helm não conseguiu ler \(items), portanto a resposta está incompleta."],
                 language: language)
    }
    /// No count, on purpose: the walk cannot see a library macOS already knows
    /// as a package, so any figure it quoted would be short — and a number that
    /// is known to be wrong is worse than the sentence without one.
    static func librariesNotOpened(language: AppLanguage = AppLanguage.current) -> String {
        L("Photo and music libraries were not opened, so what is inside them was not compared.", language: language)
    }
    static var floorNote: String { L("Files from 1 MB. Hard links are one file and are never offered.") }
    /// The size of the extra copies, not a promise about free space.
    /// `DuplicateGroup.wasted` sums the allocated size of every copy after the
    /// first — and an APFS clone, which is what Finder's Duplicate makes, shares
    /// its blocks with the original: measured here, a file and its clone each
    /// report 20 MB while the pair occupies 20 MB. So for clones the figure is
    /// exactly double what deleting returns, and the copies go to the Trash on
    /// the same volume anyway. Say what was measured.
    /// Now that `wasted` counts what the disk actually gives back — clones
    /// share their blocks, so a cloned copy returns nothing — the figure can
    /// say so. It still names the Trash: the copies land there first, and the
    /// space arrives when it is emptied, which is the rule Disk already keeps.
    /// Takes the language, as `Quoted` and `HelmConfirm.trash` do:
    /// `TheHonestTotalIsDrawnAtEveryWidthTests` has to ask it about German from
    /// a suite running in English.
    /// Built from `onceEmptied` below rather than spelling the tail again —
    /// `VPNStr.secretNeedsAPress`'s construction: the total line and the group
    /// headers say the same sentence because it is the same sentence, not
    /// because somebody keeps two tables in step.
    static func found(_ groups: Int, _ wasted: String,
                      language: AppLanguage = AppLanguage.current) -> String {
        let n = Count(groups, language: language)
        let tail = onceEmptied(wasted, language: language)
        return L("Groups: \(n) · \(tail)", [.ru: "Групп: \(n) · \(tail)", .es: "Grupos: \(n) · \(tail)", .fr: "Groupes : \(n) · \(tail)", .de: "Gruppen: \(n) · \(tail)", .ja: "\(n) グループ・\(tail)", .zh: "\(n) 组 · \(tail)", .pt: "Grupos: \(n) · \(tail)"], language: language)
    }
    /// «\(size) once the Trash is emptied» — the tail of `found` above, on its
    /// own for the group headers: each group says what removing its extras
    /// returns, through the same words as the page's total, and
    /// `TheGroupHeaderSaysWhatItIsWorthTests` holds that `found` still contains
    /// this sentence per language — two spellings of one tail is how
    /// `movedToTrash` drifted.
    static func onceEmptied(_ size: String,
                            language: AppLanguage = AppLanguage.current) -> String {
        L("\(size) once the Trash is emptied", [.ru: "\(size) после очистки Корзины", .es: "\(size) al vaciar la papelera", .fr: "\(size) après avoir vidé la corbeille", .de: "\(size) nach dem Leeren des Papierkorbs", .ja: "ゴミ箱を空にすると \(size)", .zh: "清倒废纸篓后 \(size)", .pt: "\(size) ao esvaziar o Lixo"], language: language)
    }
    static var keep: String { L("stays") }
    /// The badge on a row whose survivor the person chose. Two words in a pill,
    /// beside «stays» rather than instead of it — which of the two a group shows
    /// is the whole difference the badge exists to draw.
    static var yourChoice: String { L("your choice") }
    /// The row's own way in, on the icon at its left, in its context menu and in
    /// its accessibility actions — one name for one act, three places.
    static var keepThisCopy: String { L("Keep this copy") }
    /// And the way back, in the header of a group that has been chosen.
    static var restoreRecommendation: String { L("Restore the recommendation") }

    /// Why this group's first copy is the one that stays.
    ///
    /// **This replaces a tooltip that was wrong in eight languages.** «The copy
    /// that was there first» was drawn on every group's badge whatever had
    /// actually decided it — and once the policy existed it was not even the
    /// usual case. The English key was the error, so it was deleted from all
    /// eight files rather than translated again (CLAUDE.md § A changelog entry
    /// that names a control).
    ///
    /// Exhaustive, with no `default`: a rung added to `KeepReason` is a build
    /// error here, not a header that quietly says the wrong one of the four.
    static func keptBecause(_ grounds: KeepGrounds,
                            language: AppLanguage = AppLanguage.current) -> String {
        switch grounds {
        // Not «by place», which is the policy's name: what the person sees is a
        // folder, and the tier is the thing being explained rather than a word
        // to reuse.
        case .rung(.place): return L("kept: by folder", language: language)
        case .rung(.date): return L("kept: arrived first", language: language)
        // Said as the fact it is. «By depth» is the rule's word for it and means
        // nothing on a screen; the shorter path is what somebody can look at.
        case .rung(.depth): return L("kept: the shorter path", language: language)
        // A coin toss, and it has to look like one: two copies alike in every
        // way the rule can see were separated by the alphabet. «By name» sold
        // that tie-break as a criterion; «first alphabetically» says the coin
        // it actually is.
        case .rung(.name): return L("kept: first alphabetically", language: language)
        case .byHand: return L("kept: your choice", language: language)
        }
    }
    /// One key used to label two different actions: a group button meaning
    /// "mark this group's extras" and a row checkbox meaning "mark this copy".
    /// One English key means one thing.
    static var markRow: String { L("Mark for removal") }
    static var markGroupExtras: String { L("Mark the extra copies") }
    /// Not "Select all", which invites exactly the reading this module
    /// refuses. A control that lies about its effect on files is the failure
    /// this page is most exposed to.
    static var basketAllExtras: String { L("Mark every extra copy") }
    /// **Not «Clear selection».** That key is Leftovers' and the Uninstaller's,
    /// where a checkbox is a selection; here a copy is *marked* for removal, and
    /// the module says «Mark…» everywhere else. Sharing the selection key gave it
    /// «Снять выбор» in Russian against three «Отметить…» buttons — its own key
    /// pairs it with them and reads «Снять отметки». One English key, one meaning.
    static var clearBasket: String { L("Clear the marks") }

    // MARK: - What an extra copy is

    /// The label in front of the policy popup. Half a sentence, and the popup
    /// finishes it — a question with a title and a control under it takes four
    /// lines to say what one line says here.
    static var extraCopyIs: String { L("An extra copy is") }

    /// One policy, as the popup says it — the second half of the sentence above.
    ///
    /// Exhaustive over `KeepPolicy` with no `default`: a third belief would
    /// otherwise draw as an empty row in the popup that decides what Helm offers
    /// to delete.
    static func policyName(_ policy: KeepPolicy,
                           language: AppLanguage = AppLanguage.current) -> String {
        switch policy {
        case .byPlace: return theOneInTransit(language: language)
        case .byDate: return L("the one that arrived later", language: language)
        }
    }

    /// «the one in “Downloads” or “Desktop”», with the folders named the way
    /// this Mac names them.
    ///
    /// **macOS spells its own folders**, and it is not a translation Helm gets
    /// to make: Finder says «Загрузки»,「デスクトップ」and, in Portuguese, `Mesa`
    /// — a ninth translation of a name the system already has is how one folder
    /// comes to have two names on one screen. The paths come from
    /// `TransitFolders.named`, so the sentence cannot describe a tier the rule
    /// no longer has.
    ///
    /// Quoted, because they are names: the alternative is declining them, and
    /// «в Загрузки» is what interpolating a nominative folder name into a
    /// Russian preposition produces. `Quoted` is the house's marks per language,
    /// French's unbreakable spaces and all.
    ///
    /// Interpolated, so the table is inline — the lookup happens after the names
    /// are already in the string.
    private static func theOneInTransit(language: AppLanguage) -> String {
        let folders = TransitFolders.named.map { path in
            SystemFolderNames.display(path: path, home: NSHomeDirectory(),
                                      language: language.rawValue)
                ?? (path as NSString).lastPathComponent
        }
        // A Mac that cannot say where its own Downloads folder is answers the
        // English word, which is what the path's last component would have said.
        let (downloads, desktop) = (folders.first ?? "Downloads",
                                    folders.dropFirst().first ?? "Desktop")
        let (dl, dk) = (Quoted(downloads, language: language), Quoted(desktop, language: language))
        return L("the one in \(dl) or \(dk)", [.ru: "та, что в папке \(dl) или \(dk)", .es: "la que está en \(dl) o \(dk)", .fr: "celle dans \(dl) ou \(dk)", .de: "die in \(dl) oder \(dk)", .ja: "\(dl)または\(dk)にあるもの", .zh: "位于\(dl)或\(dk)中的那份", .pt: "a que está em \(dl) ou \(dk)"], language: language)
    }

    // MARK: - What the last press did to the marks

    /// Marks taken off copies that have just become the ones that stay.
    ///
    /// Label-then-count, the shape `ApStr.historyProblems` records: «Снято
    /// отметок: 2» makes the number a count rather than the subject of a verb,
    /// and the agreement question every Slavic and Romance language would
    /// otherwise ask disappears. No noun after the colon for the same reason —
    /// what was unmarked is on the screen the sentence is under.
    static func unmarkedSurvivors(_ count: Int,
                                  language: AppLanguage = AppLanguage.current) -> String {
        L("Unmarked: \(count) — those copies stay now", [.ru: "Снято отметок: \(count) — эти копии теперь остаются", .es: "Desmarcados: \(count) — esas copias ahora se conservan", .fr: "Décochés\u{00A0}: \(count) — ces copies sont désormais conservées", .de: "Markierung entfernt: \(count) – diese Kopien bleiben jetzt", .ja: "選択を解除: \(count) — これらのコピーは残ります", .zh: "已取消勾选：\(count) — 这些副本现在会保留", .pt: "Desmarcados: \(count) — essas cópias agora ficam"], language: language)
    }

    /// Copies «Mark every extra copy» passed over: paths outside what Helm may
    /// remove at all.
    ///
    /// Says what Helm may not do rather than what the file is — «System» is a
    /// label on a row, and this is a sentence about a press. The count carries
    /// its noun through `Plural`, because after the colon it is still a counted
    /// noun in six of the eight languages.
    static func skippedNotRemovable(_ count: Int,
                                    language: AppLanguage = AppLanguage.current) -> String {
        let files = Plural.files(count, language: language.rawValue)
        return L("Skipped: \(files) — Helm may not remove those", [.ru: "Пропущено: \(files) — их нельзя удалить", .es: "Omitidos: \(files) — Helm no puede eliminarlos", .fr: "Ignorés\u{00A0}: \(files) — Helm n’a pas le droit de les supprimer", .de: "Übersprungen: \(files) – die darf Helm nicht entfernen", .ja: "スキップ: \(files) — Helm はこれらを削除できません", .zh: "已跳过：\(files) — Helm 不能移除它们", .pt: "Ignorados: \(files) — o Helm não pode removê-los"], language: language)
    }
    static var cancel: String { L("Cancel") }
    static var close: String { L("Close") }
}
