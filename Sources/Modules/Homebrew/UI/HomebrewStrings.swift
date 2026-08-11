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

enum HbStr {
    static var moduleName: String { L("Homebrew") }
    static var summary: String { L("Manage Homebrew packages") }

    static var notInstalledTitle: String { L("Homebrew isn’t installed") }
    static var notInstalledBody: String { L("Helm downloads Homebrew’s own installer and runs it. macOS asks for an administrator password once, to create /opt/homebrew.") }
    static var installBrew: String { L("Install Homebrew") }

    static var segInstalled: String { L("Installed") }
    static var segUpdates: String { L("Updates") }
    static var segSearch: String { L("Search") }

    static var searchPlaceholder: String { L("Search packages") }
    static var install: String { L("Install") }
    static func confirmUninstall(_ name: String) -> String { L("Uninstall \(name)?", [.ru: "Удалить \(name)?", .es: "¿Desinstalar \(name)?", .fr: "Désinstaller \(name) ?", .de: "\(name) deinstallieren?", .ja: "\(name) をアンインストールしますか？", .zh: "卸载 \(name)？", .pt: "Desinstalar \(name)?"]) }
    /// The only irreversible deletion in the app, and it had the mildest
    /// confirmation: a bare "Uninstall ada-url?" beside five screens that spell
    /// out "Move to Trash" for deletions the Finder can undo. `brew uninstall`
    /// unlinks and removes the cellar directory, and there is nothing to put
    /// back. The word for the Trash is macOS's own in each language, so this
    /// reads against the Finder rather than past it.
    static var uninstallIsPermanent: String {
        L("Homebrew removes it right away. It does not go to the Trash, and this cannot be undone.")
    }
    static var cancel: String { L("Cancel") }
    static var uninstall: String { L("Uninstall") }
    static var upgrade: String { L("Upgrade") }
    static var upgradeAll: String { L("Upgrade all") }

    static var cask: String { L("cask") }

    static var upToDate: String { L("Everything is up to date.") }
    static var noneInstalled: String { L("No packages installed.") }
    static var noResults: String { L("No results.") }
    static var typeToSearch: String { L("Type a name and press Return.") }

    static var done: String { L("Done") }
    static var failed: String { L("Failed") }
    static var clear: String { L("Clear") }
    /// Not "Actualizar lista" / "Atualizar lista": the Updates screen shows the
    /// toolbar's refresh and a per-row Upgrade button at the same time, and in
    /// Spanish and Portuguese both said *Actualizar* / *Atualizar* — one verb
    /// for reloading a list and for replacing software on the machine. French,
    /// German, Chinese, Japanese and Russian all separate the two already.
    /// `Recargar` / `Recarregar` is what macOS itself uses for reloading (Safari
    /// and WebKit, es/pt.lproj).
    static var refreshList: String { L("Refresh list") }
    /// While the first list is still out. "0 packages · 0 updates · 0 casks"
    /// is a statement of fact about a machine nobody has looked at yet, and it
    /// is shown for the whole second after every install.
    static var packagesLoading: String { L("Reading the package list…") }
    /// The three lists each spent their wait as a bare spinner on an otherwise
    /// empty page — `HelmBusyState`'s own comment calls that one of the three
    /// shapes it exists to end, and `OrphansView` has said what it is doing all
    /// along. `brew outdated` and `brew search` both go to the network, so this
    /// is the longest wait in the module and the one with least to look at.
    static var checkingForUpdates: String { L("Checking for updates…") }
    static var searching: String { L("Searching…") }
    /// Counted as labels rather than as sentences: one outdated package read as
    /// "1 updates" in five of the eight languages, and a strip of three figures
    /// is the one place where a label carries the meaning as well as a noun does.
    /// The Russian line used to read "Пакетов: 52 · обновлений: 0 · cask: 1" —
    /// a bare Latin term with nothing for it to count, and a capital letter at
    /// the start of the line that the other two segments did not get. "cask"
    /// stays: it is Homebrew's own word for the thing, and translating it would
    /// name something Homebrew does not. It now has a noun in front of it.
    static func packagesStatus(_ total: Int, _ outdated: Int, _ casks: Int) -> String { L("Packages: \(total) · Updates: \(outdated) · Casks: \(casks)", [.ru: "Пакетов: \(total) · Обновлений: \(outdated) · Пакетов cask: \(casks)", .es: "Paquetes: \(total) · actualizaciones: \(outdated) · casks: \(casks)", .fr: "Paquets : \(total) · mises à jour : \(outdated) · casks : \(casks)", .de: "Pakete: \(total) · Updates: \(outdated) · Casks: \(casks)", .ja: "パッケージ \(total)・更新 \(outdated)・cask \(casks)", .zh: "软件包 \(total) · 更新 \(outdated) · cask \(casks)", .pt: "Pacotes: \(total) · atualizações: \(outdated) · casks: \(casks)"]) }

    /// Shown instead of the Upgrade button. Not "cannot be upgraded": it is
    /// held on purpose, by the person reading this, and unpinning is a
    /// deliberate act in Terminal rather than something to offer in a row.
    static var pinned: String {
        L("Pinned")
    }
}
