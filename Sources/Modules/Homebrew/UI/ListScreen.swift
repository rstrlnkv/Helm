import Foundation

/// **What happened to the query behind one of this module's lists.**
///
/// The three package lists each had a `Bool` — `loadedInstalled`,
/// `loadedOutdated`, and nothing at all for the search — and a `Bool` can only
/// answer two of the three things that happen to a `brew` call. It said
/// "loaded" and "not loaded yet", and a refusal is neither: `brew list` that
/// could not be put leaves the flag down for ever, so the page drew the waiting
/// spinner and «Reading the package list…» over a question that will never be
/// answered, with no timeout anywhere in the UI to end it.
///
/// This is `DoctorReading`'s shape applied to the other three lists, for the
/// rule that type carries and `refreshDoctor`'s own doc comment states: "no
/// issues" and "the question could not be put" are the same empty array and
/// must never be one sentence on screen. Состояние honoured it; Установленные,
/// Обновления and Поиск did not.
enum ListReading: Equatable {
    /// Nobody has asked yet. The search pane's ordinary state — a query is
    /// typed and Return has not been pressed — and the frame or two the other
    /// two lists spend between mounting and their first ask.
    case notAsked
    /// A query is out and nothing has come back.
    case waiting
    /// **There is an answer to draw**, and the list beside this reading is it.
    ///
    /// A refusal landing on top of a list that already has rows leaves this
    /// reading where it is, which is the module's own rule for the three
    /// package lists ("no `?? []` on any list reply" — a hung `brew` cut off at
    /// the runner's deadline must not replace a real list with an empty one).
    /// The kept answer is still the newest thing there is to draw, so the page
    /// draws it and the log names the outcome.
    case answered
    /// **The question could not be put, and there is no earlier answer behind
    /// it.** Not an empty list: an unread one. A separate case from `answered`
    /// for exactly the reason `DoctorReading.refused` is separate from an
    /// `.examined([])` — the sentence a person reads is the one they decide
    /// whether to trust the app on.
    case unanswerable
}

/// **What a list pane puts on screen — four drawings, and three of them are
/// what this exists for.**
///
/// `SearchDisplay` and `HealthScreen` are the shape this follows, for the
/// reason those files give: which sentence stands over which state is the whole
/// of the decision, and a `body` is nowhere a test can reach.
///
/// Waiting *moves*; the two answers do not, and they are not the same sentence.
/// Drawn as one — which is what a single `empty:` string and a `Bool` amounted
/// to — «Нет установленных пакетов.» stands over a Mac with fifty-three
/// packages on it whose `brew list` refused, and «Ничего не найдено.» stands
/// over the nine seconds a `brew search` takes.
enum ListScreen: Equatable {
    /// There are rows. What the reading says is beside the point: rows on
    /// screen are an answer somebody got.
    case rows
    /// Something is on its way. The one drawing with a spinner in it.
    case waiting
    /// The query answered, and answered nothing.
    case nothing
    /// The query could not be put. Its own sentence, and nothing moving —
    /// there is nothing to wait for.
    case unanswerable

    static func of(isEmpty: Bool, reading: ListReading) -> ListScreen {
        guard isEmpty else { return .rows }
        switch reading {
        case .notAsked, .waiting: return .waiting
        case .answered: return .nothing
        case .unanswerable: return .unanswerable
        }
    }
}

/// **What pressing Run on a `brew doctor` fix has to ask first.**
///
/// The allowlist behind a runnable fix holds two commands (`DoctorFix.Allowed`)
/// and they are not the same kind of act. `brew cleanup` throws away cached
/// downloads, every one of which comes back from the network; `brew uninstall
/// <name>` unlinks a package and removes its cellar directory, and there is
/// nothing to put back — it is the same irreversible deletion the Uninstall
/// button performs, which has raised a confirmation naming the package since
/// the day somebody noticed it removed an application on a single click.
/// Measured 2026-09-16 on the shipping page: «Выполнить» sat 6 pt from
/// «Скопировать», at the same weight, with no role and no question, and the
/// command behind it was `brew uninstall periphery`.
///
/// **The unrecognised command asks too.** `DoctorFix.judge` is what decides
/// whether a command may run at all and it is argument-exact, so nothing
/// outside the two entries reaches this today. That is a fact about today's
/// allowlist and not a property of this type: a third entry added without
/// reading this file gets a question rather than a press, which is the safe
/// direction for a fix this app is about to run on somebody's machine.
enum FixAsk: Equatable {
    /// Nothing is destroyed that cannot be had again. The press runs it.
    case runsOnThePress
    /// A package leaves this Mac for good. The question names it, with the
    /// words the Uninstall button's own dialog uses.
    case uninstalls(name: String)
    /// Something this build has no sentence for. The question names the
    /// command itself, because naming nothing is how a dialog becomes a
    /// reflex.
    case unrecognised

    static func of(_ argv: [String]) -> FixAsk {
        if argv == ["cleanup"] { return .runsOnThePress }
        if argv.count == 2, argv[0] == "uninstall" { return .uninstalls(name: argv[1]) }
        return .unrecognised
    }
}
