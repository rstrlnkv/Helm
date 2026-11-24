import SwiftUI
import HelmUI
import Module_Homebrew_Engine

/// **What pressing Run on a `brew doctor` fix has to ask first.**
///
/// The allowlist holds one command (`DoctorFix.Allowed`), `brew uninstall
/// <name>`: the same irreversible deletion the Uninstall button asks about.
///
/// **The unrecognised command asks too.** Nothing reaches it with today's
/// allowlist; a second entry added later gets a question rather than a press.
enum FixAsk: Equatable {
    /// A package leaves this Mac for good. The question names it, with the
    /// words the Uninstall button's own dialog uses.
    case uninstalls(name: String)
    /// Something this build has no sentence for. The question names the
    /// command itself.
    case unrecognised

    static func of(_ argv: [String]) -> FixAsk {
        if argv.count == 2, argv[0] == "uninstall" { return .uninstalls(name: argv[1]) }
        return .unrecognised
    }
}

extension HomebrewSettingsPage {
    /// What the console says beside «Failed», when the engine knew more than an
    /// exit code.
    ///
    /// **A `switch` over every reason, with no `default:`,** so a new reason
    /// cannot reach the page as a bare «Failed». `.stopped` is nil:
    /// `HomebrewConsole.statusPill` draws its own pill for an end the person
    /// asked for.
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
        case .unsupportedAccount: return HbStr.unsupportedAccountName(language: language)
        }
    }

    /// The running pill's words: what is waited for while the operation waits,
    /// the operation's name otherwise (`HbStr.operationName`).
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
    /// it — apart from the view, so a test can hold the words.
    static func fixQuestion(_ fix: DoctorFix) -> String {
        switch FixAsk.of(fix.argv) {
        // The Uninstall button's own words: it is the same act.
        case let .uninstalls(name): return HbStr.confirmUninstall(name)
        // Nothing to name but the command.
        case .unrecognised: return HbStr.confirmRunTheFix(Self.commandLine(fix))
        }
    }

    /// What both uninstall dialogs say under the title. The second sentence
    /// only when there is something to say; a refusal says it was one rather
    /// than reassure.
    static func uninstallNote(dependents: DependentsReading) -> String {
        switch dependents {
        case .notAsked, .read([]): return HbStr.uninstallIsPermanent
        case .read(let names):
            return HbStr.uninstallIsPermanent + "\n\n" + HbStr.stillNeededBy + "\n"
                + names.joined(separator: ", ")
        case .unread: return HbStr.uninstallIsPermanent + "\n\n" + HbStr.dependentsUnread
        }
    }

    /// The sentence under a fix's question, where there is one.
    static func fixQuestionNote(_ fix: DoctorFix, dependents: DependentsReading) -> String? {
        switch FixAsk.of(fix.argv) {
        case .uninstalls: return uninstallNote(dependents: dependents)
        case .unrecognised: return nil
        }
    }

    /// The command as a person would type it, which is what the well shows and
    /// what a question about an unnamed command has to name.
    static func commandLine(_ fix: DoctorFix) -> String {
        (["brew"] + fix.argv).joined(separator: " ")
    }

    /// The word on a finding's badge and its ink — **and nil for a caution,**
    /// which nearly every finding is. No `default:`: a third severity is a
    /// build error here.
    static func severityBadge(_ severity: DoctorSeverity, increased: Bool) -> (word: String, tint: Color)? {
        switch severity {
        case .caution: return nil
        case .danger: return (HbStr.severityDanger, HelmSignal.danger(increased: increased))
        }
    }
}
