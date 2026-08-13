// swiftlint:disable line_length
//
// Every line this rule flags in this file is one localized string — the English
// that is also the key, and that eight `.strings` files answer. Splitting one
// across source lines buys nothing and risks the key. `.swiftlint.yml` already
// says these lines "are correct at that length"; the exemption is here so the
// 320-character warning can go on meaning what that comment claims it means —
// a notice about runaway *code* — instead of firing 61 times on the one case
// it excuses.

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
    static var scan: String { L("Scan") }
    static var scanning: String { L("Scanning…") }
    static var rescan: String { L("Scan again") }
    static var intro: String { L("Launch agents, settings files, plug-ins and system extensions on this Mac. Leftovers can be removed; the rest is shown for context.") }
    static var notScannedYet: String { L("Scan to see what apps left behind.") }
    static var reviewNote: String { L("Nothing is selected by default — macOS loads these, so choose deliberately.") }
    static var removalNeedsAccess: String { L("Without Full Disk Access some files cannot be moved.") }
    static var manageExtensions: String { L("Manage…") }
    static var disable: String { L("Turn off") }
    static var enable: String { L("Turn on") }
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
    static var deleteItem: String { L("Delete…") }
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
    static func confirmDelete(_ item: StaleItem) -> String? {
        switch LeftoverActions.askBeforeDeleting(item) {
        case .loadedNow: return confirmDeleteInUse(item.identifier)
        case .cannotBeRead: return confirmDeleteUnreadable(item.identifier)
        case nil: return nil
        }
    }
    static func confirmDeleteUnreadable(_ name: String) -> String { L("Delete \(name)? Helm could not read this file, so it cannot tell what installed it.", [.ru: "Удалить \(name)? Helm не смог прочитать этот файл и не может определить, что его установило.", .es: "¿Eliminar \(name)? Helm no pudo leer este archivo, así que no sabe qué lo instaló.", .fr: "Supprimer \(name) ? Helm n’a pas pu lire ce fichier et ne sait donc pas ce qui l’a installé.", .de: "\(name) löschen? Helm konnte diese Datei nicht lesen und weiß daher nicht, was sie installiert hat.", .ja: "\(name) を削除しますか？Helm はこのファイルを読み取れず、何がインストールしたか判断できません。", .zh: "删除 \(name)？Helm 无法读取此文件，因此无法判断是什么安装了它。", .pt: "Excluir \(name)? O Helm não conseguiu ler este arquivo, portanto não sabe o que o instalou."]) }
    static func confirmDeleteInUse(_ name: String) -> String { L("Delete \(name)? It is loaded now, and the app that installed it may put it back.", [.ru: "Удалить \(name)? Он сейчас загружен, и установившее его приложение может создать его заново.", .es: "¿Eliminar \(name)? Está cargado ahora y la app que lo instaló podría volver a crearlo.", .fr: "Supprimer \(name) ? Il est chargé, et l’app qui l’a installé peut le recréer.", .de: "\(name) löschen? Es ist gerade geladen, und die App, die es installiert hat, kann es neu anlegen.", .ja: "\(name) を削除しますか？現在読み込まれており、インストールしたアプリが再作成する場合があります。", .zh: "删除 \(name)？它当前已加载，安装它的应用可能会重新创建。", .pt: "Excluir \(name)? Está carregado agora, e o app que o instalou pode recriá-lo."]) }
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

    static var needsAdmin: String { L("Needs an administrator to delete") }
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
    static var runsAtLogin: String { L("Runs at login") }
    /// The one line under a row's name: where the file is, and what is wrong with
    /// it if anything is.
    ///
    /// **One line, because the list had three heights.** The path and the missing
    /// target were two `Text`s — 44 pt with a path, 59 pt with both, 32 pt for a
    /// system extension — and two of those are the same row wearing a fact it
    /// happens to carry. Interpolated rather than a key of its own: both halves are
    /// already looked up, and the middle dot is the only new thing in it.
    ///
    /// Nil for a system extension, and that is not an omission: the scan gives one
    /// its identifier as its path (`LeftoversScanner.systemExtensions`), so the
    /// line would be the name again a step quieter.
    static func detailLine(for item: StaleItem) -> String? {
        guard item.kind != .systemExtension else { return nil }
        guard let target = item.missingTarget else { return item.path }
        return "\(item.path) · \(missingTarget(target))"
    }
    static func missingTarget(_ path: String) -> String { L("Points at a missing file: \(path)", [.ru: "Ссылается на отсутствующий файл: \(path)", .es: "Apunta a un archivo inexistente: \(path)", .fr: "Pointe vers un fichier absent : \(path)", .de: "Verweist auf eine fehlende Datei: \(path)", .ja: "存在しないファイルを参照: \(path)", .zh: "指向缺失的文件：\(path)", .pt: "Aponta para um arquivo ausente: \(path)"]) }
    /// The bar under the list, about the selection and nothing else. It used to
    /// pair the number of rows found with the size of the selection, and a
    /// middle dot made the two look like one measurement: "1 item · 0 B" over a
    /// visible row saying 4 KB.
    static func selectedLine(_ n: Int, _ size: String) -> String {
        let items = Plural.items(n, language: AppLanguage.current.rawValue)
        return L("Selected: \(items) · \(size)", [.ru: "Выбрано: \(items) · \(size)", .es: "Seleccionado: \(items) · \(size)", .fr: "Sélection : \(items) · \(size)", .de: "Ausgewählt: \(items) · \(size)", .ja: "選択：\(items)・\(size)", .zh: "已选择：\(items) · \(size)", .pt: "Selecionado: \(items) · \(size)"])
    }

    /// What the scan turned up, beside the control that filters it.
    static func foundLine(_ n: Int) -> String {
        let items = Plural.items(n, language: AppLanguage.current.rawValue)
        return L("Found: \(items)", [.ru: "Найдено: \(items)", .es: "Encontrado: \(items)", .fr: "Trouvé : \(items)", .de: "Gefunden: \(items)", .ja: "検出：\(items)", .zh: "找到：\(items)", .pt: "Encontrado: \(items)"])
    }
    /// Where the files went, not what the disk gained: the Trash is a folder on
    /// the same volume, so nothing is free until it is emptied. The same
    /// sentence Disk settled on, in Finder's own words for the act (`AL13`) in
    /// the past tense — one phrasing across the app, not a second one here.
    static func movedToTrash(_ size: String) -> String { L("Moved to the Trash — \(size)", [.ru: "Перемещено в Корзину — \(size)", .es: "Trasladado a la papelera — \(size)", .fr: "Placé dans la corbeille — \(size)", .de: "In den Papierkorb gelegt — \(size)", .ja: "ゴミ箱に入れました — \(size)", .zh: "已移到废纸篓 — \(size)", .pt: "Movido para o Lixo — \(size)"]) }
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
