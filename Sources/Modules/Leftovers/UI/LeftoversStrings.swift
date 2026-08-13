// The file-wide line-length exemption is gone: every table here is wrapped, and
// what must never be split — the English key — is still one line each.

import HelmRuntime
import HelmUI
import Module_Leftovers_Engine

enum LfStr {
    // Named after the macOS pane that covers the same ground, so the mapping
    // is obvious: System Settings → General → Login Items & Extensions.
    static var moduleName: String { L("Login Items & Extensions") }

    /// What the sidebar calls it. macOS carries the same pair: the pane is
    /// "Login Items & Extensions" and a list of panes says "Login Items" —
    /// these are its own words for the short form, language by language.
    static var moduleNameShort: String { L("Login Items") }
    static var summary: String { L("Startup items, extensions, and what removed apps left behind") }
    static var filterAll: String { L("All") }
    static var filterLeftovers: String { L("Leftovers") }
    static var statusInUse: String { L("In use") }
    static var statusProtected: String { L("System") }
    static var statusOrphaned: String { L("Leftover") }
    /// The badge on a row whose plist would not be read. Not «Unknown», which
    /// this app already uses for a VPN whose state it has not been told — one
    /// English key means one thing, and what this one says is that the file
    /// itself could not be read.
    static var statusUnreadable: String { L("Unreadable") }
    /// The badge on a row whose *file* was read and whose verdict still could not be
    /// reached: the program it points at is somewhere this process may not look, or
    /// the tool that lists what macOS has loaded did not answer. Not
    /// «Unreadable» — that word is about this file, and this file was fine.
    static var statusUndetermined: String { L("Not checked") }
    static var scan: String { L("Scan") }
    static var scanning: String { L("Scanning…") }
    static var rescan: String { L("Scan again") }
    /// Under the invitation on the first screen, so it is read once and then not
    /// again — and it was three lines of it in German, Spanish and French. What it
    /// has to say is what is in the list, and what may leave it.
    static var intro: String { L("Launch agents, settings files, plug-ins and system extensions. Only leftovers can go to the Trash.") }
    static var notScannedYet: String { L("Scan to see what apps left behind.") }
    /// The one sentence on this screen a person must not miss, and it says why
    /// rather than telling them how to behave: nothing is pre-ticked *because
    /// macOS loads every one of these*.
    static var reviewNote: String { L("Nothing is selected for you: macOS loads every item in this list.") }
    static var removalNeedsAccess: String { L("Without Full Disk Access some files cannot be moved.") }
    static var manageExtensions: String { L("Manage…") }
    /// The switch on a row, both ways round. Functions rather than properties
    /// because `confirmDeleteInUse` names this control inside a sentence, and an
    /// inline table can only be read back in the other seven languages if the
    /// language can be named — and because a pair should read as one.
    static func disable(language: AppLanguage = AppLanguage.current) -> String {
        L("Turn off", language: language)
    }

    static func enable(language: AppLanguage = AppLanguage.current) -> String {
        L("Turn on", language: language)
    }
    static var statusDisabled: String { L("Disabled") }
    /// The menu that narrows the list, drawn beside a filter glyph — so
    /// «Filter» is what it is, and «Show» was a verb borrowed for a noun's job.
    ///
    /// It moved because a *button* elsewhere needed the word: the panel's
    /// permissions notice opens the list of them, and «Show» is what that
    /// button says. One English key means one thing, and these two are not the
    /// same thing — this one is imperfective in Russian («Показывать: всё»),
    /// the button perfective («Показать»), and a shared key would have put the
    /// wrong aspect on one of them in every Slavic language.
    static var filter: String { L("Filter") }
    static var cancelAction: String { L("Cancel") }
    /// **The row's menu names the same act as the bar's button**, plus the
    /// ellipsis that says a question follows. It said «Delete…», over a dialog
    /// titled «Delete X?» whose own destructive button said «Move to Trash», with
    /// a report afterwards saying «Moved to the Trash»: three names for one act,
    /// and the wrong one was on the control a person reads last.
    /// `OneActHasOneNameTests` holds it to `removeSelected` plus an ellipsis in
    /// all eight, because the English being right is how this hid in the other
    /// seven.
    static var deleteItem: String { L("Move to Trash…") }
    /// The question the row asks before deleting — or nil for a row it deletes
    /// without asking.
    ///
    /// **One argument, and it is the item**, for the reason
    /// `LeftoverActions.available` records: a second parameter carrying the reason
    /// beside the item it is about buys nothing except the ability to disagree
    /// with it. The reason is a pure function of the item, so it is asked here.
    ///
    /// Exhaustive over `AskFirst` for the reason `kindName` records: the one
    /// question this module had said «It is loaded now», and it was drawn for
    /// every row that is not a leftover — including, once `.unreadable` existed, a
    /// file whose contents Helm never got to see.
    static func confirmDelete(_ item: StaleItem,
                              language: AppLanguage = AppLanguage.current) -> String? {
        switch LeftoverActions.askBeforeDeleting(item) {
        case .loadedNow: return confirmDeleteInUse(item.identifier, language: language)
        case .cannotBeRead: return confirmDeleteUnreadable(item.identifier, language: language)
        case .cannotBeChecked: return confirmDeleteUnchecked(item.identifier, language: language)
        case nil: return nil
        }
    }
    /// The file read fine; what Helm could not do is check whether anything still
    /// uses it — the program it points at sits where this process may not look, or
    /// macOS's own list of what is loaded did not come. So the sentence says that,
    /// rather than blaming the file the way `confirmDeleteUnreadable` does.
    static func confirmDeleteUnchecked(_ name: String,
                                       language: AppLanguage = AppLanguage.current) -> String {
        L("Move \(name) to the Trash? Helm could not check whether anything still uses it.",
          [.ru: "Переместить \(name) в Корзину? Helm не смог проверить, использует ли его что-нибудь.",
           .es: "¿Trasladar \(name) a la papelera? Helm no pudo comprobar si algo lo sigue usando.",
           .fr: "Placer \(name) dans la corbeille\u{00A0}? Helm n’a pas pu vérifier si quelque chose l’utilise encore.",
           .de: "\(name) in den Papierkorb legen? Helm konnte nicht prüfen, ob es noch verwendet wird.",
           .ja: "\(name) をゴミ箱に入れますか？何かがまだ使用しているか、Helm は確認できませんでした。",
           .zh: "将 \(name) 移到废纸篓？Helm 无法确认是否还有程序在使用它。",
           .pt: "Mover \(name) para o Lixo? O Helm não conseguiu verificar se algo ainda o usa."],
          language: language)
    }

    static func confirmDeleteUnreadable(_ name: String,
                                        language: AppLanguage = AppLanguage.current) -> String {
        L("Move \(name) to the Trash? Helm could not read this file, so it cannot tell what installed it.",
          [.ru: "Переместить \(name) в Корзину? Helm не смог прочитать этот файл и не знает, что его установило.",
           .es: "¿Trasladar \(name) a la papelera? Helm no pudo leer este archivo, así que no sabe qué lo instaló.",
           .fr: "Placer \(name) dans la corbeille\u{00A0}? Helm n’a pas pu lire ce fichier et ne sait donc pas ce qui l’a installé.",
           .de: "\(name) in den Papierkorb legen? Helm konnte diese Datei nicht lesen und weiß daher nicht, was sie installiert hat.",
           .ja: "\(name) をゴミ箱に入れますか？Helm はこのファイルを読み取れず、何がインストールしたか判断できません。",
           .zh: "将 \(name) 移到废纸篓？Helm 无法读取此文件，因此无法判断是什么安装了它。",
           .pt: "Mover \(name) para o Lixo? O Helm não conseguiu ler este arquivo, portanto não sabe o que o instalou."],
          language: language)
    }

    /// **The clause about the switch is the load-bearing half.** «It is loaded
    /// now» warns about the lesser fact: `LeftoversEngine.trash` moves paths and
    /// nothing else, so the job goes on running after its file is in the Trash —
    /// until the next login, or until the app puts the file back. What stops it is
    /// the switch on this same row: `ActiveExtensions.setDisabled` sends `launchctl
    /// disable` **and** `bootout`.
    ///
    /// It **asks** that control for its word rather than spelling it again
    /// (`VPNStr.secretNeedsAPress` is the same construction), so renaming the
    /// button carries the sentence with it in all eight instead of leaving it
    /// behind — the 0.9.0 defect CLAUDE.md records. `Quoted` puts it in each
    /// language's own marks.
    static func confirmDeleteInUse(_ name: String,
                                   language: AppLanguage = AppLanguage.current) -> String {
        let off = Quoted(disable(language: language), language: language)
        return L("Move \(name) to the Trash? It is loaded now, and the app that installed it may put it back. \(off) stops it now; moving the file does not.",
                 [.ru: "Переместить \(name) в Корзину? Этот файл сейчас загружен, и приложение, которое его установило, может создать его заново. \(off) остановит его сейчас, а перемещение файла\u{00A0}— нет.",
                  .es: "¿Trasladar \(name) a la papelera? Está cargado ahora y la app que lo instaló podría volver a crearlo. \(off) lo detiene ahora; mover el archivo no.",
                  .fr: "Placer \(name) dans la corbeille\u{00A0}? Il est chargé, et l’app qui l’a installé peut le recréer. \(off) l’arrête maintenant\u{00A0}; déplacer le fichier, non.",
                  .de: "\(name) in den Papierkorb legen? Es ist gerade geladen, und die App, die es installiert hat, kann es neu anlegen. \(off) stoppt es jetzt; die Datei zu verschieben nicht.",
                  .ja: "\(name) をゴミ箱に入れますか？現在読み込まれており、インストールしたアプリが再作成する場合があります。今すぐ止めるには \(off) を押してください。ファイルを移動しても止まりません。",
                  .zh: "将 \(name) 移到废纸篓？它当前已加载，安装它的应用可能会重新创建。\(off) 会立即停止它；移动文件不会。",
                  .pt: "Mover \(name) para o Lixo? Está carregado agora, e o app que o instalou pode recriá-lo. \(off) o interrompe agora; mover o arquivo não."],
                 language: language)
    }
    /// Why there is no delete button on this row, in the person's terms. Two
    /// sentences, because the two states ask different things of them: one is a
    /// password somebody has, the other is nothing anybody can do.
    ///
    /// Exhaustive over the reason for the same cause `kindName` records — a
    /// `default` here is how one of the two sentences would come to be drawn for
    /// both, which is the defect this pair exists to end.
    static func noDelete(_ reason: NoDelete) -> String {
        switch reason {
        case .needsAdministrator: return needsAdmin
        case .protectedByMacOS: return L("Protected by macOS")
        }
    }

    /// Says what the act is, which is moving a file to the Trash — «to delete»
    /// was the third name for it on this page.
    static var needsAdmin: String { L("Only an administrator can move this") }
    static var nothingFound: String { L("No leftovers found.") }
    /// The message over the empty list, one per reason there is no list.
    ///
    /// Over the enum and exhaustive, for the reason `kindName` records: a
    /// `default` here would draw a sentence about a clean Mac for a fourth state
    /// nobody had looked at, which is how «No leftovers found» came to be shown
    /// with rows in the model in the first place.
    static func emptyMessage(_ nothing: LeftoversEmpty.Reason) -> String {
        switch nothing {
        case .notScanned: return notScannedYet
        case .nothingFound: return nothingFound
        // A claim about the filter, not about the Mac — and the filter menu is on
        // screen above this line, which is what makes it worth its own sentence.
        case .hiddenByFilter: return L("Everything found is hidden by the filter.")
        }
    }
    /// Asked before the batch, because this button is the one that acts on the
    /// most load-bearing files in the app — launch agents and login items —
    /// and it was the only multi-file removal in Helm that did not ask.
    /// One question, and nothing after it. It used to promise "It will free
    /// 4 KB" — of files that move to a folder on the same volume, where they
    /// stay until the Trash is emptied. Disk's `confirmTrash` is the shape: the
    /// size sits inside the question as what is going, not as what is gained.
    static func confirmSelected(_ count: Int, _ size: String) -> String {
        HelmConfirm.trash(Plural.items(count, language: AppLanguage.current.rawValue), size)
    }
    static var removeSelected: String { L("Move to Trash") }
    static var selectAll: String { L("Select all") }
    static var deselectAll: String { L("Clear selection") }
    /// **A badge is a mark, not a predicate.** «Runs at login» measured 137 pt of
    /// pill in German, and against the fourteen real launch-agent labels on this
    /// Mac ten of the fourteen then truncated — seven of fourteen in Russian. What
    /// the row is for is its name; this is the qualifier beside it.
    static var runsAtLogin: String { L("At login") }
    /// The one line under a row's name: where the file is, and what is wrong with
    /// it if anything is.
    ///
    /// **One line, because the list had three heights.** The path and the missing
    /// target were two rows of their own — 44 pt with a path, 59 pt with both, 32 pt
    /// for a system extension — and two of those are the same row wearing a fact it
    /// happens to carry. One line, and the row draws it as two `Text`s side by side:
    /// which of the two gives way when the width runs out is the whole point, and a
    /// single joined string can only ever surrender its own end.
    ///
    /// Nil for a system extension, and that is not an omission: the scan gives one
    /// its identifier as its path (`LeftoversScanner.systemExtensions`), so the
    /// line would be the name again a step quieter.
    /// **The dot is language-shaped too**, and this was the one join in the module
    /// that did not know it: `selectedLine` twenty lines down sets `・` for
    /// Japanese, as does every other join in the app, and this one handed all eight
    /// languages a Latin middle dot.
    ///
    /// **The separator belongs to the reason.** Left on the path it is the first
    /// thing a truncation eats, and a middle dot with nothing after it is the same
    /// defect one character shorter.
    struct Detail: Equatable, Sendable {
        /// Where the file is: the half that gives way, and is cut in the middle,
        /// because both its ends carry meaning.
        let path: String
        /// What is wrong with it, separator and all — or nil where nothing is.
        /// Drawn whole: it is the strongest evidence a login item is dead.
        let reason: String?
    }

    static func detail(for item: StaleItem,
                       language: AppLanguage = AppLanguage.current) -> Detail? {
        guard item.kind != .systemExtension else { return nil }
        guard let target = item.missingTarget else { return Detail(path: item.path, reason: nil) }
        // Written as the one difference rather than as eight rows of which seven
        // are identical: only Japanese changes the mark.
        let dot = language == .ja ? "・" : " · "
        return Detail(path: item.path,
                      reason: "\(dot)\(missingTarget(target, language: language))")
    }
    static func missingTarget(_ path: String,
                              language: AppLanguage = AppLanguage.current) -> String {
        L("Points at a missing file: \(path)",
          [.ru: "Ссылается на отсутствующий файл: \(path)",
           .es: "Apunta a un archivo inexistente: \(path)",
           .fr: "Pointe vers un fichier absent\u{00A0}: \(path)",
           .de: "Verweist auf eine fehlende Datei: \(path)",
           .ja: "存在しないファイルを参照: \(path)",
           .zh: "指向缺失的文件：\(path)",
           .pt: "Aponta para um arquivo ausente: \(path)"], language: language)
    }
    /// The bar under the list, about the selection and nothing else. It used to
    /// pair the number of rows found with the size of the selection, and a
    /// middle dot made the two look like one measurement: "1 item · 0 B" over a
    /// visible row saying 4 KB.
    static func selectedLine(_ n: Int, _ size: String,
                             language: AppLanguage = AppLanguage.current) -> String {
        let items = Plural.items(n, language: language.rawValue)
        return L("Selected: \(items) · \(size)",
                 [.ru: "Выбрано: \(items) · \(size)",
                  .es: "Seleccionado: \(items) · \(size)",
                  .fr: "Sélection\u{00A0}: \(items) · \(size)",
                  .de: "Ausgewählt: \(items) · \(size)",
                  .ja: "選択：\(items)・\(size)",
                  .zh: "已选择：\(items) · \(size)",
                  .pt: "Selecionado: \(items) · \(size)"], language: language)
    }

    /// What the scan turned up, beside the control that filters it.
    static func foundLine(_ n: Int, language: AppLanguage = AppLanguage.current) -> String {
        let items = Plural.items(n, language: language.rawValue)
        return L("Found: \(items)",
                 [.ru: "Найдено: \(items)", .es: "Encontrado: \(items)",
                  .fr: "Trouvé\u{00A0}: \(items)", .de: "Gefunden: \(items)",
                  .ja: "検出：\(items)", .zh: "找到：\(items)",
                  .pt: "Encontrado: \(items)"], language: language)
    }
    /// Where the files went, not what the disk gained: the Trash is a folder on
    /// the same volume, so nothing is free until it is emptied. The same
    /// sentence Disk settled on, in Finder's own words for the act (`AL13`) in
    /// the past tense — one phrasing across the app, not a second one here.
    ///
    /// **The count as well as the size.** The person ticked a number of rows and
    /// `LeftoversViewModel.removedCount` is in hand where this is built, so a
    /// report that measured the batch without counting it was leaving out the
    /// half they had chosen. Russian keeps the em dash with the word before it;
    /// Japanese and Chinese use their own colon and their own dot, which is what
    /// `selectedLine` two functions up already does.
    static func movedToTrash(_ count: Int, _ size: String,
                             language: AppLanguage = AppLanguage.current) -> String {
        let items = Plural.items(count, language: language.rawValue)
        return L("Moved to the Trash: \(items) — \(size)",
                 [.ru: "Перемещено в Корзину: \(items)\u{00A0}— \(size)",
                  .es: "Trasladado a la papelera: \(items) — \(size)",
                  .fr: "Placé dans la corbeille\u{00A0}: \(items) — \(size)",
                  .de: "In den Papierkorb gelegt: \(items) — \(size)",
                  .ja: "ゴミ箱に入れました：\(items)・\(size)",
                  .zh: "已移到废纸篓：\(items) · \(size)",
                  .pt: "Movido para o Lixo: \(items) — \(size)"], language: language)
    }
    /// **The kind, not its `rawValue`.** This took a `String` and ended in a
    /// `default` that answered "Plug-ins" — so a sixth `StaleKind` would have
    /// been drawn under the wrong heading, silently, and the `default` is
    /// exactly the shape CLAUDE.md keeps out of the engines for the same reason:
    /// it makes an unhandled case look like an answer. Over the enum the switch
    /// is exhaustive and a new case is a build error.
    static func kindName(_ kind: StaleKind) -> String {
        switch kind {
        case .launchAgent: return L("Launch agents")
        case .launchDaemon: return L("Launch daemons")
        case .preference: return L("Settings files")
        case .systemExtension: return L("System extensions")
        case .plugin: return L("Plug-ins")
        }
    }
}
