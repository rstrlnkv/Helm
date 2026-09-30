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
import Module_Homebrew_Engine

enum HbStr {
    static var moduleName: String { L("Homebrew") }
    static var summary: String { L("Manage Homebrew packages") }

    static var notInstalledTitle: String { L("Homebrew isn’t installed") }
    /// What the page says before the press. **It names no number of password
    /// prompts**: the sentence that used to say «once» was untrue on a Mac
    /// without Apple's tools, and whether Apple's own installer asks for a
    /// password on the macOS a person runs was not measured. Interpolated with
    /// Apple's own name for the tools, so the table lives here (`appleTools`).
    /// **The Spanish value carries a word joiner (`\u{2060}`) after each slash of
    /// `/opt/homebrew`**: the typesetter may break a line after a slash, and at
    /// the page's column it did, leaving `/opt/` at the end of one line and
    /// `homebrew.` alone on the next (`ThePathInTheInstallSentenceStaysWholeTests`);
    /// a joiner after the second slash alone only moved the break to the first.
    /// The mark draws nothing. The sentence is not selectable — `HelmEmptyState`
    /// draws its message without `textSelection` — so no path is copied out of
    /// it and the mark is never carried anywhere.
    static func notInstalledBody(language: AppLanguage = AppLanguage.current) -> String {
        let tools = appleTools(language: language)
        return L("Helm downloads Homebrew’s own installer and runs it. If the \(tools) are not installed yet, macOS installs them first, in a window of its own, and Helm carries on when they are ready. macOS asks for an administrator password to create /opt/homebrew.",
                 [.ru: "Helm скачает официальный установщик Homebrew и запустит его. Если \(tools) ещё не установлены, macOS сначала установит их в своём окне, а Helm продолжит, когда они будут готовы. Чтобы создать /opt/homebrew, macOS запросит пароль администратора.",
                  .es: "Helm descarga el instalador oficial de Homebrew y lo ejecuta. Si las \(tools) aún no están instaladas, macOS las instala primero en su propia ventana y Helm continúa cuando están listas. macOS solicita una contraseña de administración para crear /\u{2060}opt/\u{2060}homebrew.",
                  .fr: "Helm télécharge le programme d’installation officiel de Homebrew et l’exécute. Si les \(tools) ne sont pas encore installés, macOS les installe d’abord dans sa propre fenêtre, puis Helm continue dès qu’ils sont prêts. macOS demande un mot de passe d’administrateur pour créer /opt/homebrew.",
                  .de: "Helm lädt Homebrews eigenes Installationsprogramm und führt es aus. Sind die \(tools) noch nicht installiert, installiert macOS sie zuerst in einem eigenen Fenster, und Helm macht weiter, sobald sie bereit sind. Zum Anlegen von /opt/homebrew fragt macOS nach einem Adminpasswort.",
                  .ja: "Helm が Homebrew 公式のインストーラをダウンロードして実行します。\(tools)がまだインストールされていない場合は、まず macOS が専用のウインドウでインストールし、準備ができたら Helm が続行します。/opt/homebrew を作るため、macOS が管理者パスワードを求めます。",
                  .zh: "Helm 会下载 Homebrew 官方安装脚本并运行。若尚未安装\(tools)，macOS 会先在自己的窗口中安装，完成后 Helm 会自动继续。为创建 /opt/homebrew，macOS 会要求输入管理员密码。",
                  .pt: "O Helm baixa o instalador oficial do Homebrew e o executa. Se as \(tools) ainda não estiverem instaladas, o macOS as instala primeiro em uma janela própria, e o Helm continua quando estiverem prontas. O macOS pede uma senha de administrador para criar /opt/homebrew."],
                 language: language)
    }

    /// **Apple's own name for what it installs**, lifted out of the sentence its
    /// installer alert draws (`ALERT_INFORMATIVE_STRING` in `Localizable.loctable`
    /// of `Install Command Line Developer Tools.app`) and never translated by
    /// this app: the person sees Apple's window naming the tools this way, and
    /// a second name for the same thing here reads as a second thing — spelled
    /// exactly as Apple spells it, Russian's no-break space before its last word
    /// included. Without
    /// the article, because the article agrees with the sentence the phrase sits
    /// in and the sentences here add their own. `zh.lproj` and `pt.lproj` stand
    /// for Apple's `zh_CN` and `pt_BR` (Simplified script, Brazilian wording —
    /// `TheToolsAreNamedAsAppleNamesThemTests` reads Apple's bundle and holds
    /// the eight to it).
    static func appleTools(language: AppLanguage = AppLanguage.current) -> String {
        L("command line developer tools", language: language)
    }
    static var installBrew: String { L("Install Homebrew") }

    static var segInstalled: String { L("Installed") }
    static var segUpdates: String { L("Updates") }
    /// What `brew doctor` found. Not "Doctor" — that is Homebrew's own name for
    /// the subcommand and names a tool rather than a question; the segment
    /// beside three lists of packages is about the state of the machine.
    static var segHealth: String { L("Health") }

    /// One prompt for all three tabs, including Состояние, where the same
    /// field also filters `brew doctor` findings and `brew config` groups
    /// rather than packages alone — left as one key deliberately for now
    /// rather than guessed at three ways: the owner has not been asked
    /// whether the Health tab's own prompt should say so, and a wrong guess
    /// here is faithfully translated into all seven other languages.
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
    /// What the removal takes with it. Drawn only when the Cellar named
    /// something: an empty line under a question is a reassurance nobody
    /// checked, and a refused query answers with nothing to say.
    static var stillNeededBy: String { L("Other installed packages still need it:") }
    static var cancel: String { L("Cancel") }
    static var uninstall: String { L("Uninstall") }
    /// **The Uninstall button, as opposed to the dialog's own Uninstall.**
    ///
    /// The ellipsis is the Mac's convention and it carries a fact: pressing
    /// this does not remove anything, it asks. The dialog's confirming button
    /// does the removing and keeps the bare word. One key means one thing, so
    /// the two are two keys — and a translation cannot put the mark on the
    /// wrong one of them.
    static var uninstallAsking: String { L("Uninstall…") }
    static var upgrade: String { L("Upgrade") }
    static var upgradeAll: String { L("Upgrade all") }

    static var cask: String { L("cask") }

    static var upToDate: String { L("Everything is up to date.") }
    static var noneInstalled: String { L("No packages installed.") }
    static var noResults: String { L("No results.") }
    /// **The header over what a filtered query and an automatic `brew
    /// search` found that this Mac does not already have.** Drawn under
    /// whichever package list the tab already shows — Установленные or
    /// Обновления, and not Состояние: a search for a package is not a question
    /// about this Mac's health — never as a list of its own: the Search tab it
    /// used to sit under was removed 2026-09-24, the owner's decision.
    static var availableToInstall: String { L("Available to install") }
    /// The list itself has rows, and the query hides every one of them —
    /// distinct from `noResults`, which is `brew search` answering that
    /// nothing exists at all. `HbStr.noneInstalled`/`upToDate`/`nothingToFix`
    /// stay separate keys for the reason each already carries: this is a
    /// fourth fact and not a fourth spelling of one of them.
    static var noMatches: String { L("Nothing in this list matches.") }

    /// **The three refusals, one per list — and each is a separate key from the
    /// empty answer above it.**
    ///
    /// `couldNotExamine` is the shape, and these are the same sentence about
    /// the other three questions: Homebrew did not answer, and the app says
    /// what it therefore does not know rather than what it wishes were true.
    /// Drawn where «No packages installed.» and «No results.» used to stand
    /// over a query that refused — which is the module's own rule, written in
    /// `refreshDoctor`'s doc comment and honoured in one segment of four: "no
    /// issues" and "the question could not be put" are the same empty list and
    /// must never be one sentence on screen.
    ///
    /// Three keys and not one, because one key means one thing: what is not
    /// known differs, and several of the eight languages inflect the three
    /// differently.
    static var couldNotList: String {
        L("Homebrew did not answer, so nothing is known about the installed packages right now.")
    }
    static var couldNotCheckForUpdates: String {
        L("Homebrew did not answer, so nothing is known about updates right now.")
    }
    static var couldNotSearch: String {
        L("Homebrew did not answer, so the search could not be carried out right now.")
    }

    static var done: String { L("Done") }
    static var failed: String { L("Failed") }
    static var clear: String { L("Clear") }
    /// Ends the running operation — the only way out of a brew that will not
    /// finish. "Stop"/"Stopped" are the app's existing pair; Keep Awake and
    /// Disk already draw them with the same meaning.
    static var stop: String { L("Stop") }
    static var stopped: String { L("Stopped") }
    /// Beside Stop, for the operation that is waiting on Apple's window: it
    /// ends the *waiting* and leaves Apple's installer alone, which a bare
    /// «Stop» would promise to end.
    static var stopWaiting: String { L("Stop waiting") }
    /// The neutral word for a password dialog answered no. Not «Stopped»: the
    /// person did not stop anything, they declined one question.
    static var cancelled: String { L("Cancelled") }
    /// What the pill says while an operation runs. The engine's label is a log
    /// line naming the brew run without `brew` — `upgrade wget`, `uninstall
    /// periphery`, and `upgrade all` for the run that upgrades everything,
    /// which is `brew upgrade` and not a label of its arguments — the same
    /// English in every language, except for the install of Homebrew itself,
    /// which is not a brew run and which the engine names in English
    /// (`HomebrewEngine.installBrewLabel`): that one is worded here, or the pill
    /// changes from a translated sentence to a lowercase English one the moment
    /// Apple's tools arrive.
    static func operationName(_ label: String, language: AppLanguage = AppLanguage.current) -> String {
        label == HomebrewEngine.installBrewLabel ? L("Installing Homebrew", language: language) : label
    }
    /// The pill while the operation waits for Apple's installer.
    static func waitingForTools(language: AppLanguage = AppLanguage.current) -> String {
        let tools = appleTools(language: language)
        return L("Waiting for the \(tools)",
                 [.ru: "Ждём \(tools)",
                  .es: "Esperando las \(tools)",
                  .fr: "En attente des \(tools)",
                  .de: "Warten auf die \(tools)",
                  .ja: "\(tools)を待機中",
                  .zh: "正在等待\(tools)",
                  .pt: "Aguardando as \(tools)"],
                 language: language)
    }

    /// The console line at the start of the wait — what a person needs to know
    /// while a window of Apple's is either in front of them or behind this one.
    /// Its last sentence holds only while the wait does: a press on «Stop
    /// waiting» ends it, and `toolsWaitStoppedConsole` is the line that says so.
    /// **Apple's «Install» is `install` above, quoted**: it is the same word in
    /// all eight languages (`TheToolsAreNamedAsAppleNamesThemTests` holds both
    /// to Apple's bundle), so it is interpolated and never typed into a sentence.
    static func toolsWaitingConsole(language: AppLanguage = AppLanguage.current) -> String {
        let tools = appleTools(language: language)
        let button = Quoted(L("Install", language: language), language: language)
        return L("Homebrew needs the \(tools). macOS is showing its own installer window for them. Choose \(button) there. The window may be behind this one. Helm carries on by itself once they are installed.",
                 [.ru: "Homebrew нужны \(tools). macOS показывает своё окно установки. Выберите в нём \(button). Окно может оказаться за этим окном. Helm продолжит сам, когда они будут установлены.",
                  .es: "Homebrew necesita las \(tools). macOS muestra su propia ventana de instalación. Elige \(button) en ella. La ventana puede estar detrás de esta. Helm continuará solo cuando estén instaladas.",
                  .fr: "Homebrew a besoin des \(tools). macOS affiche sa propre fenêtre d’installation. Choisissez \(button) dans cette fenêtre. Elle peut se trouver derrière celle-ci. Helm continuera seul une fois les outils installés.",
                  .de: "Homebrew benötigt die \(tools). macOS zeigt dafür ein eigenes Installationsfenster. Wähle darin \(button). Das Fenster kann hinter diesem liegen. Helm macht selbstständig weiter, sobald sie installiert sind.",
                  .ja: "Homebrew には\(tools)が必要です。macOS が専用のインストールウインドウを表示します。そこで\(button)を選択してください。ウインドウはこのウインドウの後ろにある場合があります。インストールが終わると、Helm が自動で続行します。",
                  .zh: "Homebrew 需要\(tools)。macOS 会显示自己的安装窗口。请在其中选取\(button)。该窗口可能在此窗口后面。安装完成后，Helm 会自动继续。",
                  .pt: "O Homebrew precisa das \(tools). O macOS mostra a própria janela de instalação. Escolha \(button) nela. A janela pode estar atrás desta. O Helm continua sozinho quando elas estiverem instaladas."],
                 language: language)
    }

    /// The console line when the person pressed «Stop waiting»: Helm no longer
    /// watches for the tools and will not go on by itself. **It says nothing of
    /// Apple's window.** It used to say macOS carries on with the installation
    /// in its own window, and that was a claim Helm had no reading for: the line
    /// is chosen by the step `waiting → stopped` alone, and the same step is
    /// reached over a window Helm never saw running and over one it had just
    /// read closed without the tools. What follows is the person's press on the button the
    /// page shows again — **it names the button by the same string the button
    /// is drawn with** (`installBrew`), quoted, so a rename cannot leave this
    /// sentence behind. It says nothing of the tools' name: the languages
    /// disagree on the case that name would need after a verb.
    static func toolsWaitStoppedConsole(language: AppLanguage = AppLanguage.current) -> String {
        let button = Quoted(L("Install Homebrew", language: language), language: language)
        return L("Helm stopped waiting and will not go on by itself. To continue, choose \(button) again.",
                 [.ru: "Helm перестал ждать и сам не продолжит. Чтобы продолжить, снова выберите \(button).",
                  .es: "Helm dejó de esperar y no continuará por sí solo. Para continuar, elige \(button) de nuevo.",
                  .fr: "Helm a cessé d’attendre et ne continuera pas seul. Pour continuer, choisissez à nouveau \(button).",
                  .de: "Helm wartet nicht mehr und macht nicht von selbst weiter. Wähle zum Fortfahren erneut \(button).",
                  .ja: "Helm は待機をやめました。自動では続行しません。続けるには、もう一度\(button)を選択してください。",
                  .zh: "Helm 已停止等待，不会自动继续。要继续，请再次选取\(button)。",
                  .pt: "O Helm parou de esperar e não continuará sozinho. Para continuar, escolha \(button) novamente."],
                 language: language)
    }

    /// The console line at the end of the wait, when the tools are there and
    /// the password dialog is next.
    static func toolsArrivedConsole(language: AppLanguage = AppLanguage.current) -> String {
        let tools = appleTools(language: language)
        return L("The \(tools) are installed. Continuing with Homebrew.",
                 [.ru: "Установлены \(tools). Продолжаем установку Homebrew.",
                  .es: "Las \(tools) están instaladas. Continuando con Homebrew.",
                  .fr: "Les \(tools) sont installés. Suite de l’installation de Homebrew.",
                  .de: "Die \(tools) sind installiert. Homebrew wird weiter installiert.",
                  .ja: "\(tools)がインストールされました。Homebrew のインストールを続けます。",
                  .zh: "已安装\(tools)。继续安装 Homebrew。",
                  .pt: "As \(tools) estão instaladas. Continuando com o Homebrew."],
                 language: language)
    }

    /// Why an install of Homebrew ended without Homebrew, one sentence per
    /// reason the engine names — beside «Failed», or beside «Cancelled» for the
    /// password.
    static func toolsNotInstalled(language: AppLanguage = AppLanguage.current) -> String {
        let tools = appleTools(language: language)
        return L("The \(tools) were not installed, so Homebrew was not installed either.",
                 [.ru: "Homebrew не установлен, потому что не установлены \(tools).",
                  .es: "Las \(tools) no se instalaron, así que Homebrew tampoco se instaló.",
                  .fr: "Les \(tools) n’ont pas été installés, donc Homebrew ne l’a pas été non plus.",
                  .de: "Die \(tools) wurden nicht installiert, daher wurde auch Homebrew nicht installiert.",
                  .ja: "\(tools)がインストールされなかったため、Homebrew もインストールされませんでした。",
                  .zh: "未安装\(tools)，因此 Homebrew 也没有安装。",
                  .pt: "As \(tools) não foram instaladas, então o Homebrew também não foi instalado."],
                 language: language)
    }
    static func authorizationDeclined(language: AppLanguage = AppLanguage.current) -> String {
        L("Administrator authorization was cancelled, so Homebrew was not installed.", language: language)
    }
    static func prefixNotPrepared(language: AppLanguage = AppLanguage.current) -> String {
        L("macOS could not prepare /opt/homebrew, so Homebrew was not installed.", language: language)
    }
    /// The one note that carries a number: the installer's own exit code, which
    /// is what somebody looking for the cause searches for. nil when the state
    /// has none — the engine always sets one for this reason.
    static func installerFailed(code: Int?, language: AppLanguage = AppLanguage.current) -> String {
        let code = code.map(String.init) ?? "?"
        return L("Homebrew’s installer stopped with exit code \(code). Its last lines are in the console.",
                 [.ru: "Установщик Homebrew завершился с кодом \(code). Последние строки его вывода остались в консоли.",
                  .es: "El instalador de Homebrew terminó con el código \(code). Sus últimas líneas están en la consola.",
                  .fr: "Le programme d’installation de Homebrew s’est terminé avec le code \(code). Ses dernières lignes sont dans la console.",
                  .de: "Das Homebrew-Installationsprogramm wurde mit dem Code \(code) beendet. Die letzten Zeilen stehen in der Konsole.",
                  .ja: "Homebrew のインストーラがコード \(code) で終了しました。最後の出力はコンソールに残っています。",
                  .zh: "Homebrew 安装脚本以退出码 \(code) 结束。最后几行输出保留在控制台中。",
                  .pt: "O instalador do Homebrew terminou com o código \(code). As últimas linhas estão no console."],
                 language: language)
    }
    /// Why the operation failed before it could start: brew vanished between
    /// the page's status and the press — its own uninstaller in a terminal.
    static func brewGone(language: AppLanguage = AppLanguage.current) -> String {
        L("Homebrew is no longer installed.", language: language)
    }

    /// The console's first line after a launch that follows an interrupted
    /// quit: the child survived Helm and kept going with nobody watching — a
    /// brew run that kept changing the Cellar, or the bash wrapper of the
    /// Homebrew installer. **Two sentences, because the two labels are two
    /// kinds of thing.** The marker stores the engine's label and the line is
    /// built from it at the next launch (`HomebrewViewModel.refreshStatus` hands
    /// it over as it was stored). For a brew run the label is the phrase that
    /// names it, without `brew` — English in every language, as it is in the
    /// log — and the sentence quotes it with the language's own marks; that one
    /// is interpolated, so its table lives here. For the install of Homebrew
    /// (`HomebrewEngine.installBrewLabel`), which is not a brew run, the label
    /// is a state's name and not a word of any language, so quoting it inside a
    /// translated sentence put English in the middle of every translation: it has a
    /// whole sentence of its own and a `.lproj` key, with no label in it
    /// (`AnInterruptedInstallIsSaidInThePersonsLanguageTests`).
    static func interruptedAtQuit(_ label: String,
                                  language: AppLanguage = AppLanguage.current) -> String {
        if label == HomebrewEngine.installBrewLabel {
            return L("Helm quit while Homebrew was still being installed. The installation may not have finished.",
                     language: language)
        }
        let q = Quoted(label, language: language)
        return L("Helm quit while \(q) was still running. It may not have finished.",
                 [.ru: "Helm завершил работу, пока выполнялось \(q). Операция могла не завершиться.",
                  .es: "Helm se cerró mientras \(q) seguía en ejecución. Puede que no haya terminado.",
                  .fr: "Helm a quitté pendant que \(q) était encore en cours. L’opération ne s’est peut-être pas terminée.",
                  .de: "Helm wurde beendet, während \(q) noch lief. Der Vorgang ist womöglich nicht abgeschlossen.",
                  .ja: "\(q) の実行中に Helm が終了しました。完了していない可能性があります。",
                  .zh: "Helm 在 \(q) 仍在运行时退出。该操作可能未完成。",
                  .pt: "O Helm foi encerrado enquanto \(q) ainda estava em execução. A operação pode não ter sido concluída."],
                 language: language)
    }
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
    /// **The counts bar when there is nothing to count, and the one sentence on
    /// this page that exists only because two of them disagreed.**
    ///
    /// `statusLine` gated on `loadedInstalled`, which is `installedReading ==
    /// .answered` and therefore false for a refusal as well as for a wait. So
    /// the page drawn over a `brew list` that could not be put said «Homebrew
    /// did not answer, so nothing is known about the installed packages right
    /// now.» in the middle of the master and «Reading the package list…» in the
    /// bar 327 pt below it — measured on a 984 pt pane, 2026-09-16. One screen,
    /// two accounts of one fact, and the quieter of the two is the one that
    /// gets believed.
    ///
    /// Short, and not `couldNotList` a second time: the long sentence is
    /// already on the page and says what is not known. This is the counts bar
    /// saying why it has no counts, which is a different job in the same
    /// screenful — and a bar that stays blank reads as «nothing to report»,
    /// which is the reading the refusal has to displace.
    static var couldNotCount: String { L("Homebrew did not answer.") }
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
    static func packagesStatus(_ total: Int, _ outdated: Int, _ casks: Int) -> String { L("Packages: \(total) · Updates: \(outdated) · Casks: \(casks)", [.ru: "Пакетов: \(total) · Обновлений: \(outdated) · Пакетов cask: \(casks)", .es: "Paquetes: \(total) · actualizaciones: \(outdated) · casks: \(casks)", .fr: "Paquets\u{00A0}: \(total) · mises à jour\u{00A0}: \(outdated) · casks\u{00A0}: \(casks)", .de: "Pakete: \(total) · Updates: \(outdated) · Casks: \(casks)", .ja: "パッケージ \(total)・更新 \(outdated)・cask \(casks)", .zh: "软件包 \(total) · 更新 \(outdated) · cask \(casks)", .pt: "Pacotes: \(total) · atualizações: \(outdated) · casks: \(casks)"]) }

    /// The same line before `brew outdated` has ever answered: the two counts
    /// that have arrived, and silence about the one that has not. A zero there
    /// would be a statement about a question nobody asked —
    /// `AStatusLineDoesNotInventZeroUpdatesTests` holds the pairing.
    static func packagesStatusNoUpdates(_ total: Int, _ casks: Int) -> String { L("Packages: \(total) · Casks: \(casks)", [.ru: "Пакетов: \(total) · Пакетов cask: \(casks)", .es: "Paquetes: \(total) · casks: \(casks)", .fr: "Paquets\u{00A0}: \(total) · casks\u{00A0}: \(casks)", .de: "Pakete: \(total) · Casks: \(casks)", .ja: "パッケージ \(total)・cask \(casks)", .zh: "软件包 \(total) · cask \(casks)", .pt: "Pacotes: \(total) · casks: \(casks)"]) }

    /// Shown instead of the Upgrade button. Not "cannot be upgraded": it is
    /// held on purpose, by the person reading this, and unpinning is a
    /// deliberate act in Terminal rather than something to offer in a row.
    static var pinned: String {
        L("Pinned")
    }

    /// The package view with nothing to describe. Not "on the left": there is
    /// no left below `HomebrewSplit`'s threshold, where the package replaces
    /// the list rather than sitting beside it, and one key serves both layouts.
    /// Japanese and Chinese had gone further than the English and named the
    /// list itself («左のリストから», «请在左侧»), so the sentence was wrong in
    /// two languages more loudly than in the other six.
    static var nothingSelected: String { L("Select a package") }
    /// The narrow screen's way out of a selected package, back to the list.
    ///
    /// The English text is the key, so every back control in the app that
    /// means this word shares one entry in the eight `.strings` files and one
    /// translation each. Which modules those are is not written here: this
    /// comment named two of the four that already existed, and a list or a
    /// count in prose is a thing that goes stale at the next module.
    /// `command grep -rn 'L("Back")' Sources` answers it today.
    static var back: String { L("Back") }
    /// **What a row in the single-column list does when it is pressed** — the
    /// accessibility hint the chevron beside it cannot carry, because a mark
    /// is not an element.
    ///
    /// Its own key rather than `back`'s neighbour in some shared file: the
    /// sentence is about this module's own two-screen shape, and the one other
    /// place in the app with that shape spells its own.
    static var opensItsOwnScreen: String { L("Opens its own screen") }
    /// The accessibility label of the row's update marker, and the word the
    /// package screen spells beside the same symbol — the only carrier of "an
    /// update exists" for a colourblind reader or one using VoiceOver.
    static var updateAvailable: String { L("Update available") }

    // MARK: - The package view's second tier

    /// The version a package is installed at.
    ///
    /// Not `segInstalled`, which is also "Installed" in English: that names the
    /// tab and this names a fact about one package, and one key means one thing
    /// — several languages draw the distinction the English has lost, and a
    /// shared key would have given them one word for both.
    static var tileInstalledVersion: String { L("Installed version") }
    /// The day it was installed. Its value goes through `HelmDates.day`, never a
    /// `DateFormatter` built with no locale.
    static var tileInstalledOn: String { L("Installed on") }
    /// Whether Homebrew installed it because somebody asked for it or because
    /// something else needed it. Drawn only for a formula — a cask's document
    /// records no such fact, and inventing "you asked for it" would be the page
    /// answering a question brew never answered.
    static var tileHowItGotHere: String { L("How it got here") }
    static var installedOnRequest: String { L("you asked for it") }
    static var installedAsDependency: String { L("as a dependency") }
    /// What Homebrew would install now — the only version a package that is not
    /// installed has anywhere in this module.
    static var tileVersion: String { L("Version") }
    /// The heading over the names in a package list. «Package» and not
    /// «Name»: the column is the package, of which the name is the handle, and
    /// «Name» is already Autopilot's word for what a person calls a rule.
    static var columnPackage: String { L("Package") }
    static var tileLicence: String { L("Licence") }
    /// How much disk the installed package occupies. **Walked, not read**:
    /// `brew info --json=v2` carries no size in either direction, so this tile
    /// is the only fact in the tier that arrives after the rest. Its value goes
    /// through `Bytes`, so the unit is the app's own language rather than the
    /// system's.
    static var tileOnDisk: String { L("On disk") }
    /// What the tile above says while the walk is out — and only while it is
    /// out, for the package on screen (`SizeReading`). A state, not a figure:
    /// this is the one thing the tier says about a number nobody has yet, and it
    /// is said only because the walk really is running.
    ///
    /// **Its own key rather than VPN's «Measuring…».** That one is about a link
    /// being driven for twenty seconds and its eight translations are written
    /// for that — Russian «Измеряю…», Japanese 測定中 — where this is a directory
    /// being added up. One key means one thing, and the two would have shared a
    /// word that several of the eight do not share.
    static var countingTheSize: String { L("Counting…") }

    // MARK: - What `brew doctor` found

    /// What the badge on a finding says, for the one severity that has a badge.
    /// `DoctorParser` reads two off brew's own `Warning:` and `Error:` prefixes
    /// and the word is not brew's: `Error` beside a tap's deprecation notice
    /// would call somebody's machine broken over a cask that still works. The
    /// other, a caution, is what nearly every finding is, and a badge saying so
    /// on each row said the same word on all of them — it has no word at all
    /// (`HomebrewSettingsPage.severityWord`).
    static var severityDanger: String { L("Problem") }

    /// While `brew doctor` is out. It is the slowest query in the module and
    /// the one with least to look at, so it says what is being waited on
    /// rather than spinning — the rule `checkingForUpdates` above carries.
    static var examiningThisMac: String { L("Checking this Mac…") }
    /// `brew doctor` ran and named nothing. **The one reading that may be drawn
    /// as a healthy machine**, and it is a separate key from the refusal below
    /// for exactly that reason.
    static var nothingToFix: String { L("Nothing to fix.") }
    /// `brew doctor` could not be asked, answered nothing at all where it
    /// always answers something, or exited non-zero with nothing in its answer
    /// this build could read (`HomebrewEngine.doctor`). Deliberately says
    /// nothing about the machine:
    /// a Mac nobody could examine is not a Mac that is fine, and the sentence a
    /// person decides whether to trust the app on must not claim a reading that
    /// was never taken.
    static var couldNotExamine: String {
        L("Homebrew did not answer, so nothing is known about this Mac right now.")
    }
    /// What the verdict says over a Mac that `brew doctor` examined and found
    /// nothing wrong with, in a second line: whose reading it is. Not brew's
    /// own «Your system is ready to brew.» — that sentence is Homebrew's and
    /// the app says what it did with it — and no more than `nothingToFix`
    /// says: a claim about what was *read*, since the same tab can also be
    /// looking at a Mac nobody could examine (`couldNotExamine`).
    static var healthCleanNote: String {
        L("Homebrew checked this Mac and found nothing to report.")
    }
    /// The count over a Mac with findings, as a label with a number and not as
    /// a sentence, for `packagesStatus`'s reason: a sentence would need its own
    /// plural in each of the eight languages.
    static func findingsCount(_ count: Int) -> String { L("Findings: \(count)", [.ru: "Замечаний: \(count)", .es: "Observaciones: \(count)", .fr: "Remarques\u{00A0}: \(count)", .de: "Befunde: \(count)", .ja: "\(count) 件の項目", .zh: "发现 \(count) 项", .pt: "Observações: \(count)"]) }
    /// Under the count: whose voice this is. `cmd/doctor.rb` prints exactly
    /// this permission before its first warning — «If everything you use
    /// Homebrew for is working fine: please don't worry or file an issue; just
    /// ignore this.» — and `DoctorParser` throws that frame away on purpose, so
    /// this is the one place the tab says it, in the app's words and named as
    /// Homebrew's.
    static var healthVerdictFrame: String {
        L("Homebrew itself says: if everything you use it for works, you can ignore these.")
    }
    // MARK: - The configuration card

    /// The title of the card holding `brew config`. There is no heading over the
    /// findings any more: the verdict above them is what says what they are.
    static var headingConfiguration: String { L("Configuration") }

    /// The three groups `brew config`'s flat list is drawn in.
    ///
    /// **Ours, so translated — the keys beside them are Homebrew's, so never.**
    /// `brew config` prints a list of `key: value` lines and no heading at all;
    /// `CLT` and `HOMEBREW_PREFIX` are Homebrew's words for those things and a
    /// person looking one up needs the word Homebrew uses, while "Machine" and
    /// "Tools" are this app's reading and belong to whoever is reading it.
    ///
    /// `.brew` answers with the module's own name rather than a second key
    /// spelling «Homebrew» again: it is the same word for the same thing in all
    /// eight languages, and two `.strings` entries with the same key is a file
    /// whose value depends on which one the reader reaches.
    static func configSectionName(_ section: ConfigSection) -> String {
        switch section {
        case .brew: return moduleName
        case .machine: return L("Machine")
        case .tools: return L("Tools")
        }
    }

    /// What the whole of `brew config` is for, put on the pasteboard in one
    /// press. Not «Copy» — the button copies the entire document and not the
    /// group on screen, and a person pressing it is almost always about to
    /// paste it into somebody's issue tracker.
    static var copyForABugReport: String { L("Copy for a bug report") }

    /// The label over the command in its well.
    ///
    /// **Not «Homebrew suggests».** Measured on this Mac (Homebrew 7.0.1,
    /// 2026-09-15): `brew doctor` printed 1,194 bytes and **not one `brew …`
    /// command line** — the deprecated-formulae block prints a heading asking
    /// the person to find replacements and an indented name under it, and
    /// nothing else. `uninstall <name>` is Helm reading that heading
    /// (`DoctorFixCandidate.Heading`), so a label attributing it to Homebrew
    /// would put Helm's own decision in somebody else's mouth — and the one
    /// reader who would act on that attribution is the one who trusted
    /// Homebrew rather than this app.
    static var helmReadsThisAs: String { L("Helm reads this as") }
    /// Said under the well, both when the command may be run and when it may
    /// only be copied: the provenance is a fact about the command, not about
    /// the button beside it.
    static var brewNamedNoCommand: String {
        L("Homebrew named no command here — it said what is wrong and left it at that. The line above is Helm’s own reading of that.")
    }
    /// The button that acts. `runDoctorFix` re-judges it in the engine before
    /// anything runs, so what this button starts is not what the page judged.
    ///
    /// **One word, because the command is beside it.** This was «Run this
    /// command», which names an object the person can already see — and next
    /// to «Copy this command» the two controls were 188 and 175 pt of a 625 pt
    /// column, measured 2026-09-15. The approved drawing this module was built
    /// from draws the verb alone.
    static var runTheFix: String { L("Run") }
    /// Run, when pressing it raises a question first — `uninstallAsking`'s
    /// reason. Not for `brew cleanup`, which runs on the press:
    /// `HomebrewSettingsPage.runLabel` is where the two are told apart.
    static var runTheFixAsking: String { L("Run…") }
    /// The question a press on Run raises when the command is one this build
    /// has no sentence for — `FixAsk.unrecognised`, which nothing on
    /// `DoctorFix.Allowed` reaches today and which a third entry added without
    /// reading that file would. It names the command, because a question that
    /// names nothing is a question people learn to dismiss. Interpolated, so
    /// the table is inline: a `.lproj` key with a command baked into it could
    /// never match.
    static func confirmRunTheFix(_ command: String) -> String { L("Run \(command)?", [.ru: "Выполнить \(command)?", .es: "¿Ejecutar \(command)?", .fr: "Exécuter \(command)\u{00A0}?", .de: "\(command) ausführen?", .ja: "\(command) を実行しますか？", .zh: "执行 \(command)？", .pt: "Executar \(command)?"]) }
    /// The copy affordance beside a command Helm will not run itself. One word,
    /// for the reason above.
    static var copyTheFix: String { L("Copy") }
    /// Why there is no button for this one. It names no control: the word on
    /// the control is a key of its own, and a sentence spelling a label by hand
    /// is a sentence a rename leaves behind in seven translations.
    static var helmDoesNotRunThis: String {
        L("Helm does not run this one. It is here to read and to copy.")
    }
    /// Drawn beside "Failed" when the engine judged the command again at the
    /// press and would not run it — the ordinary cause being the race this
    /// whole design is built around: the package left the Cellar between the
    /// screen being drawn and the button being pressed.
    static func fixNotRunnable(language: AppLanguage = AppLanguage.current) -> String {
        L("Helm checked the command again and would not run it.", language: language)
    }

    /// The heading over the dependency chips.
    static var dependsOn: String { L("Depends on") }
    /// The heading over what `brew info` prints after an install — paths to
    /// edit, a service to start. Homebrew's own word is "caveats", which reads
    /// as a warning in English and is not one.
    static var packageNotes: String { L("Package notes") }

    /// The first sentence of the deprecation note. The reason follows it as a
    /// sentence of its own, so no language has to bend a clause into a frame
    /// another language chose.
    static var deprecated: String { L("Homebrew has deprecated this package.") }
    /// Drawn when `installed_on_request` is false: the person did not ask for
    /// this, and removing it alone is how a dependency comes straight back.
    static var cameAsDependency: String {
        L("It came in as a dependency — you did not ask for it. It is worth removing together with whatever brought it.")
    }

    /// What to use instead, when Homebrew names one. Interpolated, so the table
    /// is inline: interpolation runs before the lookup, and a `.lproj` key with
    /// a package name baked into it could never match.
    static func useInstead(_ name: String) -> String { L("Use \(name) instead.", [.ru: "Вместо него стоит взять \(name).", .es: "En su lugar conviene usar \(name).", .fr: "Il vaut mieux utiliser \(name) à la place.", .de: "Stattdessen sollte \(name) verwendet werden.", .ja: "代わりに \(name) を使ってください。", .zh: "请改用 \(name)。", .pt: "Em vez dele, convém usar \(name)."]) }

    /// A deprecation reason Homebrew spells as a token this build has no
    /// sentence for — a free-text reason a formula wrote by hand, or a token
    /// added upstream since this release. The token itself, said to be
    /// Homebrew's word rather than Helm's, because inventing a translation for
    /// a reason nobody has read is worse than showing the raw one.
    static func brewsOwnReason(_ reason: String) -> String { L("Homebrew’s reason: \(reason)", [.ru: "Причина, которую называет Homebrew: \(reason)", .es: "El motivo que indica Homebrew: \(reason)", .fr: "La raison indiquée par Homebrew\u{00A0}: \(reason)", .de: "Der von Homebrew genannte Grund: \(reason)", .ja: "Homebrew が挙げている理由: \(reason)", .zh: "Homebrew 给出的理由：\(reason)", .pt: "O motivo indicado pelo Homebrew: \(reason)"]) }

    /// The other version lines of the same package sitting in the catalogue —
    /// `openssl@1.1` beside `openssl@3`. A joined list, so the table is inline.
    static func otherVersionLines(_ names: String) -> String { L("Other version lines are here too: \(names)", [.ru: "Рядом есть другие линии: \(names)", .es: "También hay otras líneas de versión: \(names)", .fr: "D’autres lignes de version existent aussi\u{00A0}: \(names)", .de: "Es gibt auch andere Versionslinien: \(names)", .ja: "ほかのバージョン系列もあります: \(names)", .zh: "还有其他版本线：\(names)", .pt: "Também existem outras linhas de versão: \(names)"]) }

    /// Homebrew's deprecation reason as a sentence, or the token itself.
    ///
    /// The tokens are Homebrew's own enumeration, read out of
    /// `/opt/homebrew/Library/Homebrew/deprecate_disable.rb` on 2026-09-15
    /// against Homebrew 7.0.1 — the formula set and the cask set, which share
    /// `unmaintained` and `unreachable` and otherwise do not overlap. A formula
    /// may also deprecate itself with a sentence of its own rather than a token,
    /// and upstream adds tokens between releases: both land on
    /// `brewsOwnReason`, which says whose word it is instead of translating one
    /// nobody has read. `repo_archived` is the one this Mac produces today
    /// (`periphery`).
    static func deprecationReason(_ token: String) -> String {
        reasonSentences[token].map { $0() } ?? brewsOwnReason(token)
    }

    /// A table against Homebrew's table, rather than a `switch`: this is a
    /// lookup and not a decision, and the two hashes read side by side. Each
    /// value is a closure because `L` reads the app's language at the moment it
    /// is called, and the language changes while the app runs — a dictionary of
    /// *strings* would answer in whichever language happened to build it.
    private static let reasonSentences: [String: @Sendable () -> String] = [
        "does_not_build": { L("It does not build.") },
        "no_license": { L("It has no licence.") },
        "repo_archived": { L("Its upstream repository has been archived.") },
        "repo_removed": { L("Its upstream repository has been removed.") },
        "unmaintained": { L("Nobody maintains it upstream any more.") },
        "unreachable": { L("It can no longer be reliably downloaded from upstream.") },
        "unsupported": { L("Upstream does not support it.") },
        "deprecated_upstream": { L("Upstream has deprecated it.") },
        "versioned_formula": { L("It is an older version line rather than the current one.") },
        "checksum_mismatch": { L("It was built from a source file upstream has since replaced, so that repository may have been tampered with.") },
        "discontinued": { L("Upstream has discontinued it.") },
        "moved_to_mas": { L("It is now distributed only through the Mac App Store.") },
        "no_longer_available": { L("It is no longer available upstream.") },
        "no_longer_meets_criteria": { L("It no longer meets Homebrew’s conditions for a cask.") },
        "fails_gatekeeper_check": { L("It does not pass the macOS Gatekeeper check.") },
    ]
}
