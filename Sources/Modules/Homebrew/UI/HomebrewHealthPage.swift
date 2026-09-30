import AppKit
import SwiftUI
import HelmUI
import Module_Homebrew_Engine

/// **The Health tab: a verdict, the findings behind it, and the configuration.**
///
/// It was a striped list with an inspector beside it, built for a hundred
/// packages, and the two things it held — one to three paragraphs of prose from
/// `brew doctor` and a document from `brew config` — are not that shape: a
/// title cut to one line at 286 pt with its meaning one click away, a stripe
/// under nothing, and «Nothing to fix.» drawn as the quietest row of a table.
/// The owner chose this direction from three drawn ones, 2026-09-29 («Берем вот
/// этот вариант»).
///
/// **Read top to bottom, and nothing needs choosing first.**
///
/// 1. **The verdict** (`HealthVerdict`): what `brew doctor`'s reading comes to,
///    in one line, and how many findings. `HealthScreen.of` reads it off the
///    unfiltered answer, so a word typed into the search field cannot say the
///    Mac is clean.
/// 2. **One card of findings**, each a row that opens in place through
///    `helmAccordion` on `HelmMotion.disclosure`. The only finding is open
///    always and has no control to close it: a card with one row that hides
///    its one paragraph asks a click for nothing.
/// 3. **The configuration**, in a card of its own, closed, with the one
///    action on it — «Copy for a bug report» — in its header.
///
/// **One button per state.** A closed finding that Helm may fix carries Run in
/// its header; an open one carries it in the body, beside the command it runs.
/// Never both, so a press is never one of two controls for one act.
///
/// **What did not move.** The gate is the same: `DoctorFix.judge` decided
/// whether a fix is `.runnable` before this page saw it, `FixAsk` decides
/// whether a question comes before the act (`HomebrewSettingsPage.runLabel`,
/// `fixQuestion`), the engine judges again at the press and names its refusal,
/// and brew's own words are drawn verbatim and selectable. Only where they are
/// drawn changed.
///
/// **No inspector, no selection, no "Available to install".** Findings open in
/// place, so nothing is selected on this tab and `HomebrewViewModel` keeps no
/// selection for it; a search for a package is not a question about this Mac's
/// health, so the section that draws its answer is not drawn here and the
/// field only filters.
struct HomebrewHealthPage: View {
    @ObservedObject var hb: HomebrewViewModel

    /// The findings the person has opened, by `DoctorIssue.id`. The view's own
    /// state and not the view model's: it is a fact about what this page has
    /// drawn open, and a page that is left and returned to starts closed.
    @State private var openFindings: Set<String> = []
    @State private var configurationOpen = false

    /// One slot for the disclosure chevron, in every row, so a finding that has
    /// no control still lines its title up with the ones that do.
    static let chevronSlot: CGFloat = 12
    /// Where a row's body starts: under its title, past the chevron.
    static let bodyInset: CGFloat = HelmSpace.s5 + chevronSlot + HelmSpace.s3

    var body: some View {
        let screen = HealthScreen.of(hb.doctor, config: hb.configGroups,
                                     needle: ListFilter.needle(hb.query))
        ScrollView {
            VStack(alignment: .leading, spacing: HelmSpace.s6) {
                verdict(screen.verdict)
                if screen.noMatches {
                    // Under the verdict and not instead of it: the Mac has
                    // findings and the field is hiding them, which is a
                    // different fact from having none. **On the column's own
                    // edge, with no padding of its own** — the one the
                    // verdict's plate and both cards stand on. It was inset by
                    // a card's padding under nothing that had one, a fourth
                    // left edge on the page (`TheVerdictHoldsItsPlaceOnThePageTests`).
                    Text(HbStr.noMatches)
                        .foregroundStyle(HelmText.quiet)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if !screen.findings.isEmpty {
                    findingsCard(screen.findings)
                }
                if !screen.configuration.isEmpty {
                    ConfigurationCard(hb: hb, groups: screen.configuration, open: configurationOpen) {
                        withAnimation(HelmMotion.disclosure) { configurationOpen.toggle() }
                    }
                }
            }
            .padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s6)
            .helmSettingsColumn()
        }
    }

    // MARK: - The verdict

    /// The sentence each verdict says, apart from the views that draw it — the
    /// same reason `HomebrewSettingsPage.severityWord` is out where a test can
    /// reach it: which reading says which sentence is a decision, and a `body`
    /// is not somewhere a test can look.
    static func verdictTitle(_ verdict: HealthVerdict) -> String {
        switch verdict {
        case .checking: return HbStr.examiningThisMac
        case .clean: return HbStr.nothingToFix
        case .unexaminable: return HbStr.couldNotExamine
        case let .findings(count): return HbStr.findingsCount(count)
        }
    }

    /// The second line, and only where there is something to say: a Mac nobody
    /// could examine says nothing about itself, and a wait says what it waits
    /// for and no more.
    static func verdictDetail(_ verdict: HealthVerdict) -> String? {
        switch verdict {
        case .checking, .unexaminable: return nil
        case .clean: return HbStr.healthCleanNote
        case .findings: return HbStr.healthVerdictFrame
        }
    }

    private func verdict(_ verdict: HealthVerdict) -> some View {
        // **Top-aligned, and the text column has a fixed step from the top.**
        // The row used to centre its text on the plate, so the title stood
        // wherever the number of lines put it: a wait with one line lower
        // than the answer that replaced it with two, and a refusal that wraps
        // higher again — the title jumping at the moment it was being read.
        // Now its first line begins at the same place in every reading, whatever
        // is under it (`TheVerdictHoldsItsPlaceOnThePageTests`).
        HStack(alignment: .top, spacing: HelmSpace.s5) {
            switch verdict {
            case .checking:
                // **Waiting moves**: the reading is `brew doctor`, the slowest
                // query in the module, and a still sentence over it reads as a
                // page that has stopped (`TheHealthWaitMovesTests`).
                // Beside the title's first line, which is where the title now
                // stands: centred in the slot it would sit under it.
                ProgressView().controlSize(.small)
                    .padding(.top, HelmSpace.s2)
                    .frame(width: Self.plate, height: Self.plate, alignment: .top)
            case .clean:
                HelmSignalPlate(symbol: "checkmark", tint: HelmSignal.success, size: Self.plate)
            case .unexaminable:
                HelmSignalPlate(symbol: "questionmark", tint: .gray, size: Self.plate)
            case .findings:
                HelmSignalPlate(symbol: "exclamationmark.triangle.fill", tint: HelmSignal.warning,
                                size: Self.plate)
            }
            VStack(alignment: .leading, spacing: HelmSpace.s2) {
                Text(Self.verdictTitle(verdict))
                    .font(.system(size: 16, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = Self.verdictDetail(verdict) {
                    Text(detail)
                        .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, HelmSpace.s1)
            Spacer(minLength: 0)
        }
        // One thing to VoiceOver and the page's first landmark: the verdict is
        // the heading the findings under it answer to.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// The plate's own size, named once. The wait's spinner is drawn in a slot
    /// of the same size, so the text column starts at one place across in every
    /// reading; that the title also stands at one *height* is the top
    /// alignment above.
    private static let plate: CGFloat = 44

    // MARK: - The findings

    private func findingsCard(_ findings: [DoctorIssue]) -> some View {
        // The count that decides "the only finding" is the reading's own and
        // not what the filter leaves: a word that narrows three findings to
        // one must not make that one uncloseable.
        let total = hb.issues.count
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(findings.enumerated()), id: \.element.id) { index, issue in
                if index > 0 { Divider().padding(.leading, Self.bodyInset) }
                FindingRow(hb: hb, issue: issue,
                           open: HealthScreen.isOpen(issue, of: total, opened: openFindings),
                           toggle: HealthScreen.canToggle(total: total) ? {
                               withAnimation(HelmMotion.disclosure) {
                                   if openFindings.contains(issue.id) {
                                       openFindings.remove(issue.id)
                                   } else {
                                       openFindings.insert(issue.id)
                                   }
                               }
                           } : nil)
            }
        }
        .helmCard(padding: 0)
    }
}

// MARK: - One finding

/// A row of the findings card: the title, and under it — when open — brew's own
/// words and the fix.
private struct FindingRow: View {
    @ObservedObject var hb: HomebrewViewModel
    let issue: DoctorIssue
    let open: Bool
    /// nil is «always open»: the only finding has no control to close it.
    let toggle: (() -> Void)?
    @State private var height: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(HelmSpace.s5)
            VStack(alignment: .leading, spacing: HelmSpace.s5) {
                // Brew's own words, kept as brew wrote them — the parser keeps
                // body lines verbatim on purpose (`DoctorParser.body`), and a
                // body line naming a path is somebody's path.
                Text(issue.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let fix = issue.fix { HealthFixBlock(hb: hb, fix: fix) }
            }
            .padding(.leading, HomebrewHealthPage.bodyInset)
            .padding([.trailing, .bottom], HelmSpace.s5)
            .helmAccordion(open: open, height: $height)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: HelmSpace.s3) {
            if let toggle {
                Button(action: toggle) { title }
                    .buttonStyle(.plain)
                    // A custom row has no disclosure triangle for the system to
                    // say its state from, so it is said here.
                    .accessibilityValue(HelmA11y.expanded(open))
            } else {
                title
            }
            // The word, and only where there is one: a caution is what nearly
            // every finding is, and a badge on every row said the same word on
            // all of them, so `severityWord` has none for it. `Problem` is
            // `Error:` in brew's own text and is the one that should stand out.
            if let word = HomebrewSettingsPage.severityWord(issue.severity),
               let tint = HomebrewSettingsPage.severityTint(issue.severity) {
                HelmBadge(word, tint: tint)
            }
            // **The closed row's one button.** Open, it is in the body beside
            // the command (`HealthFixBlock`), and never in both.
            if !open, let fix = issue.fix, fix.kind == .runnable {
                HealthRunButton(hb: hb, fix: fix)
            }
        }
    }

    private var title: some View {
        HStack(alignment: .firstTextBaseline, spacing: HelmSpace.s3) {
            Image(systemName: open ? "chevron.down" : "chevron.right")
                .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                .frame(width: HomebrewHealthPage.chevronSlot)
                // Nothing to open: the slot stays, the mark does not.
                .opacity(toggle == nil ? 0 : 1)
                .accessibilityHidden(true)
            Text(issue.title)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - The fix

/// The one Run button, in the closed row's header and in the open row's body —
/// the same builder, so the two cannot disagree about what pressing it does.
///
/// **The destructive one, drawn and behaved as the destructive one it is.**
/// `role: .destructive` is what makes it behave in a menu or a dialog and
/// draws nothing on this macOS, so `helmDestructive` carries what a person can
/// see (`TheDestructiveControlIsMarkedInInkTests`); `askToRunFix` is what makes
/// it *behave* differently, and `FixAsk` decides which of the two commands on
/// the allowlist that means — `brew cleanup` still runs on the press, because a
/// cached download comes back.
///
/// **It names what it will run in the tooltip and to VoiceOver**, because a
/// closed row shows the button at the far edge from its title and the command
/// is out of sight; the dialog that follows (`fixQuestion`) still names the package.
private struct HealthRunButton: View {
    @ObservedObject var hb: HomebrewViewModel
    let fix: DoctorFix

    var body: some View {
        let command = HomebrewSettingsPage.commandLine(fix)
        Button(role: .destructive) { hb.askToRunFix(fix) } label: {
            Text(HomebrewSettingsPage.runLabel(fix)).helmDestructive()
        }
        .disabled(hb.running)
        .help(command)
        .accessibilityHint(command)
    }
}

/// The command, whose label says whose reading it is, and whatever this app
/// may do with it.
///
/// **No control here attributes the command to Homebrew.** Measured on this
/// Mac (Homebrew 7.0.1, 2026-09-15): `brew doctor` printed 1,194 bytes and not
/// one `brew …` command line, so `uninstall <name>` is Helm's reading of a
/// heading brew printed and not a line brew wrote — `HbStr.helmReadsThisAs` and
/// `HbStr.brewNamedNoCommand` are the two places that say so, and the second is
/// drawn for both kinds of fix, because the provenance is a fact about the
/// command rather than about the button beside it.
///
/// The copy is a pasteboard write from the view, the way `LogView` already
/// does it: there is no engine command for it, because nothing leaves this
/// process. Inside a clipped, animated block the ink is a literal primary with
/// an opacity (`HelmText.quiet` is one), never a hierarchical style
/// (`HelmAccordion`'s own note on why).
private struct HealthFixBlock: View {
    @ObservedObject var hb: HomebrewViewModel
    let fix: DoctorFix

    var body: some View {
        let command = HomebrewSettingsPage.commandLine(fix)
        VStack(alignment: .leading, spacing: HelmSpace.s3) {
            // Whose reading this is, as the heading of what follows.
            HelmSectionTitle(HbStr.helmReadsThisAs)
            HStack(spacing: HelmSpace.s3) {
                Text(command)
                    // A text *style* rather than a frozen 11 pt: `.subheadline`
                    // is the same 11 at the default setting and follows the
                    // system text size from there, which a literal cannot.
                    .font(.system(.subheadline, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, HelmSpace.s4).padding(.vertical, HelmSpace.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // `ctl` and not `card`: this is one line of text, a small
                    // field well, and the design system gives those the
                    // control corner.
                    .background(RoundedRectangle(cornerRadius: HelmRadius.ctl, style: .continuous)
                        .fill(HelmSurface.wellFill))
                Button(HbStr.copyTheFix) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                }
                if fix.kind == .runnable {
                    // The step before it is `HelmSpace.s5` where the row's own
                    // is `s3`: a press meant for Copy that lands on this one is
                    // not a press anybody can take back.
                    HealthRunButton(hb: hb, fix: fix)
                        .padding(.leading, HelmSpace.s5 - HelmSpace.s3)
                }
            }
            Text(HbStr.brewNamedNoCommand).font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                .fixedSize(horizontal: false, vertical: true)
            if fix.kind == .copyOnly {
                Text(HbStr.helmDoesNotRunThis).font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - The configuration

/// What `brew config` says, in one card: closed it is a line that names this
/// Homebrew and this Mac, with the one action; open it is the document.
///
/// **«Copy for a bug report» copies the document and not what is drawn.**
/// `BrewConfig.text` is what brew printed, byte for byte; the groups below are
/// a reading regrouped under headings this app invented, and a bug report asks
/// for the first. Drawn only when there is a document — a button that copies an
/// empty string is a button that silently does nothing.
///
/// The key is drawn as Homebrew spells it and the value in a monospaced face:
/// many of the values are a version, a path or a hash, which is what a
/// reader compares character by character rather than reads as a word. The
/// value is selectable, because a person who is not copying the whole document
/// is copying exactly one of these.
private struct ConfigurationCard: View {
    @ObservedObject var hb: HomebrewViewModel
    let groups: [ConfigGroup]
    let open: Bool
    let toggle: () -> Void
    @State private var height: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(HelmSpace.s5)
            VStack(alignment: .leading, spacing: HelmSpace.s5) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: HelmSpace.s3) {
                        // A header to VoiceOver as well as to the eye: the
                        // title carries the trait itself (`HelmSectionTitle`).
                        HelmSectionTitle(HbStr.configSectionName(group.section))
                        // A `Grid`, so the key column is as wide as the widest
                        // key and not a number written down here: Homebrew adds
                        // keys between releases, so the column has to be able
                        // to grow.
                        Grid(alignment: .leadingFirstTextBaseline,
                             horizontalSpacing: HelmSpace.s5, verticalSpacing: HelmSpace.s3) {
                            ForEach(group.lines) { line in
                                GridRow {
                                    Text(line.key)
                                        .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                                    Text(line.value)
                                        // The one spelling this module gives a
                                        // monospaced face, the shape the rest of
                                        // the tree uses.
                                        .font(.system(.subheadline, design: .monospaced))
                                        .textSelection(.enabled)
                                        .gridColumnAlignment(.leading)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, HomebrewHealthPage.bodyInset)
            .padding([.trailing, .bottom], HelmSpace.s5)
            .helmAccordion(open: open, height: $height)
        }
        .helmCard(padding: 0)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: HelmSpace.s3) {
            Button(action: toggle) {
                HStack(alignment: .center, spacing: HelmSpace.s3) {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                        .frame(width: HomebrewHealthPage.chevronSlot)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: HelmSpace.s1) {
                        Text(HbStr.headingConfiguration)
                        if let summary = ConfigSummary.of(hb.config?.lines ?? []) {
                            Text(summary)
                                .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: HelmSpace.s5)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(HelmA11y.expanded(open))
            if let text = hb.config?.text {
                Button(HbStr.copyForABugReport) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
        }
    }
}

/// The one line the closed configuration card says: this Homebrew, this macOS,
/// this prefix — the three facts a bug report opens with, read off `brew
/// config`'s own lines and spelled with its own values. «Homebrew» and «macOS»
/// are names and never translated, so this holds no string of the app's.
/// A fact `brew config` did not print is left out and not guessed; nil when it
/// printed none of the three.
enum ConfigSummary {
    static func of(_ lines: [ConfigLine]) -> String? {
        func value(_ key: String) -> String? {
            lines.first { $0.key == key }?.value
        }
        let parts = [value("HOMEBREW_VERSION").map { "Homebrew \($0)" },
                     value("macOS").map { "macOS \($0)" },
                     value("HOMEBREW_PREFIX")]
        let present = parts.compactMap { $0 }
        return present.isEmpty ? nil : present.joined(separator: " · ")
    }
}
