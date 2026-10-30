import SwiftUI
import HelmUI
import Module_Homebrew_Engine

/// **What pressing Run on a `brew doctor` fix has to ask first.**
///
/// The allowlist behind a runnable fix holds two commands (`DoctorFix.Allowed`)
/// and they are not the same kind of act. `brew cleanup` throws away cached
/// downloads, every one of which comes back from the network; `brew uninstall
/// <name>` unlinks a package and removes its cellar directory, and there is
/// nothing to put back: it is the same irreversible deletion the Uninstall
/// button performs, which raises a confirmation naming the package.
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

extension HomebrewSettingsPage {
    /// What the console says beside «Failed», when the engine knew more than an
    /// exit code.
    ///
    /// **A `switch` over every reason, with no `default:`.** This was an `if`
    /// against one reason, so a second one — a `brew doctor` fix the engine
    /// judged again and would not run — drew a bare «Failed» with nothing
    /// saying why, which is a refusal reaching the page as an empty fact.
    /// `.stopped` is nil because `HomebrewConsole.statusPill` draws its own pill for it: the
    /// person asked for that end, and it is not a failure to explain.
    ///
    /// Takes the whole state, not the reason alone, because `installerFailed`
    /// names the installer's exit code and the code is on the state.
    static func failureNote(_ op: OpState, language: AppLanguage = AppLanguage.current) -> String? {
        guard let reason = op.reason else { return nil }
        switch reason {
        case .brewMissing: return HbStr.brewGone(language: language)
        case .stopped: return nil
        case .fixRefused: return HbStr.fixNotRunnable(language: language)
        case .toolsNotInstalled: return HbStr.toolsNotInstalled(language: language)
        case .authorizationDeclined: return HbStr.authorizationDeclined(language: language)
        case .prefixNotPrepared: return HbStr.prefixNotPrepared(language: language)
        case .installerFailed: return HbStr.installerFailed(code: op.exitCode, language: language)
        }
    }

    /// The running pill's words: what is waited for while the operation waits,
    /// the operation's name otherwise — the engine's label as the engine wrote
    /// it (`upgrade wget`, in English in every language), except for the
    /// install of Homebrew itself, which `HbStr.operationName` words in the
    /// person's language.
    static func pillTitle(for op: OpState, language: AppLanguage = AppLanguage.current) -> String {
        op.waiting == nil ? HbStr.operationName(op.label, language: language)
                          : HbStr.waitingForTools(language: language)
    }

    /// Stop's title while the operation is the wait for Apple's tools: the
    /// press ends the waiting and leaves Apple's window to finish.
    static func stopTitle(for op: OpState) -> String {
        op.waiting == .commandLineTools ? HbStr.stopWaiting : HbStr.stop
    }

    /// The title of the question a press on Run raises, and the sentence under
    /// it — apart from the view that draws them: which act is asked about in
    /// which words is a decision a test can hold.
    ///
    /// nil is «this fix raises no question», which is `FixAsk.runsOnThePress`
    /// and never reaches `pendingFix` — `askToRunFix` sends that one straight
    /// to the engine. It is nil rather than an empty string so that the one
    /// caller cannot draw a dialog with no title if that ever stops being true.
    static func fixQuestion(_ fix: DoctorFix) -> String? {
        switch FixAsk.of(fix.argv) {
        case .runsOnThePress: return nil
        // The same words the Uninstall button's own dialog uses, naming the
        // same thing: it is the same act, reached by a different control.
        case let .uninstalls(name): return HbStr.confirmUninstall(name)
        // Nothing to name but the command, and naming nothing is how a dialog
        // becomes a reflex.
        case .unrecognised: return HbStr.confirmRunTheFix(Self.commandLine(fix))
        }
    }

    /// **What the Run button says: whether a question comes before the act.**
    ///
    /// The ellipsis is the Mac's own mark for a control that opens something
    /// rather than doing it, and `FixAsk` is what knows which of the two this
    /// press is — so the mark is read off the same answer that decides whether
    /// the dialog is raised, and cannot claim a question that never comes.
    /// `brew cleanup` runs on the press and keeps the bare word.
    static func runLabel(_ fix: DoctorFix) -> String {
        switch FixAsk.of(fix.argv) {
        case .runsOnThePress: return HbStr.runTheFix
        case .uninstalls, .unrecognised: return HbStr.runTheFixAsking
        }
    }

    /// The second sentence, and only where there is one to say: a heading over
    /// a reassurance nobody checked is `stillNeededBy`'s own lesson.
    static func fixQuestionNote(_ fix: DoctorFix) -> String? {
        switch FixAsk.of(fix.argv) {
        case .uninstalls: return HbStr.uninstallIsPermanent
        case .runsOnThePress, .unrecognised: return nil
        }
    }

    /// The command as a person would type it, which is what the well shows and
    /// what a question about an unnamed command has to name. Spelled once here
    /// rather than at the two places that draw it.
    static func commandLine(_ fix: DoctorFix) -> String {
        (["brew"] + fix.argv).joined(separator: " ")
    }

    /// The word on a finding's badge — **and nil for a caution, which has no
    /// badge.** A caution is what nearly every finding is, and a pill saying so
    /// on each row said the same word on all of them; only the severity that
    /// stands out is worded. No `default:` on either switch: a third severity
    /// has to be a build error here, where the decision is made.
    static func severityWord(_ severity: DoctorSeverity) -> String? {
        switch severity {
        case .caution: return nil
        case .danger: return HbStr.severityDanger
        }
    }

    /// The badge's ink, nil exactly where `severityWord` is: a finding with no
    /// badge has no tint to draw.
    static func severityTint(_ severity: DoctorSeverity, increased: Bool) -> Color? {
        switch severity {
        case .caution: return nil
        case .danger: return HelmSignal.danger(increased: increased)
        }
    }
}
