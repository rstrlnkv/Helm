import AppKit
import SwiftUI
import HelmUI
import Module_Homebrew_Engine

/// **The Health tab: a verdict, the findings behind it, and the configuration.**
///
/// One page, not a list and an inspector: `brew doctor`'s paragraphs of prose
/// and `brew config`'s document are not the shape of a hundred packages.
///
/// **Read top to bottom, and nothing needs choosing first.**
///
/// 1. **The verdict** (`HealthVerdict`): what `brew doctor`'s reading comes to,
///    in one line, and how many findings. `HealthScreen.of` reads it off the
///    unfiltered answer, so a word typed into the search field cannot say the
///    Mac is clean.
/// 2. **One card of findings**, each a row that opens in place through
///    `helmAccordion` on `HelmMotion.disclosure`. The only finding is always
///    open, with no control to close it.
/// 3. **The configuration**, in a card of its own, closed, with the one
///    action on it — «Copy for a bug report» — in its header.
///
/// **One button per state.** A closed finding that Helm may fix carries Run in
/// its header; an open one carries it in the body, beside the command it runs.
/// Never both, so a press is never one of two controls for one act.
///
/// `DoctorFix.judge` decided whether a fix is `.runnable` before this page saw
/// it, `FixAsk` decides which question comes before the act
/// (`HomebrewSettingsPage.fixQuestion`), and the engine judges again at the
/// press. Brew's own words are drawn verbatim and selectable.
///
/// No inspector, no selection, no "Available to install"
/// (Architecture/Homebrew.md § The Health tab).
struct HomebrewHealthPage: View {
    @ObservedObject var hb: HomebrewViewModel
    @Environment(\.helmTraits) private var traits

    /// The plate of a reading that examined nothing. No signal token means
    /// "nothing is known", so this is the one plate that is not one of them;
    /// `HelmBadge.neutralTint` is hierarchical and would change the plate.
    private static let unexaminedTint = Color.gray

    /// The findings the person has opened, by `DoctorIssue.id`. The view's own
    /// state: a page left and returned to starts closed.
    @State private var openFindings: Set<String> = []
    @State private var configurationOpen = false

    /// One slot for the disclosure chevron, in every row, so a finding that has
    /// no control still lines its title up with the ones that do.
    static let chevronSlot: CGFloat = HelmSpace.s5
    /// Where a row's body starts: under its title, past the chevron.
    static let bodyInset: CGFloat = HelmSpace.s5 + chevronSlot + HelmSpace.s3

    var body: some View {
        let screen = HealthScreen.of(hb.doctor, config: hb.configGroups,
                                     needle: ListFilter.needle(hb.query))
        ScrollView {
            VStack(alignment: .leading, spacing: HelmSpace.s6) {
                verdict(screen.verdict)
                if screen.noMatches {
                    // Under the verdict, not instead of it: the field hides
                    // findings the Mac has. On the column's own edge, the one
                    // the plate and both cards stand on.
                    Text(HbStr.noMatches)
                        .foregroundStyle(HelmText.quiet)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if !screen.findings.isEmpty, case let .findings(total) = screen.verdict {
                    findingsCard(screen.findings, total: total)
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

    /// The sentence each verdict says, apart from the views that draw it: which
    /// reading says which sentence is a decision.
    private static func verdictTitle(_ verdict: HealthVerdict) -> String {
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
        // **Top-aligned, at a fixed step from the top,** so the title's first
        // line stands at one place in every reading however many lines follow.
        HStack(alignment: .top, spacing: HelmSpace.s5) {
            switch verdict {
            case .checking:
                // **Waiting moves**: a still sentence over the slowest query
                // reads as a page that has stopped. Beside the title's first line.
                ProgressView().controlSize(.small)
                    .padding(.top, HelmSpace.s2)
                    .frame(width: Self.plate, height: Self.plate, alignment: .top)
            case .clean:
                HelmSignalPlate(symbol: "checkmark", tint: HelmSignal.success(increased: traits.increasedContrast), size: Self.plate)
            case .unexaminable:
                HelmSignalPlate(symbol: "questionmark", tint: Self.unexaminedTint, size: Self.plate)
            case .findings:
                HelmSignalPlate(symbol: "exclamationmark.triangle.fill", tint: HelmSignal.warning(increased: traits.increasedContrast),
                                size: Self.plate)
            }
            VStack(alignment: .leading, spacing: HelmSpace.s2) {
                Text(Self.verdictTitle(verdict))
                    .font(HelmText.plateTitle)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = Self.verdictDetail(verdict) {
                    HelmSettingsNote(detail)
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

    /// The plate's size; the wait's spinner gets a slot of the same size, so
    /// the text column starts at one place across in every reading.
    private static let plate: CGFloat = 44

    // MARK: - The findings

    /// `total` is the verdict's own count of findings and not what the filter
    /// leaves: a word that narrows three findings to one must not make that
    /// one uncloseable.
    private func findingsCard(_ findings: [DoctorIssue], total: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(findings.enumerated()), id: \.element.id) { index, issue in
                if index > 0 { Divider().padding(.leading, Self.bodyInset) }
                // **The only finding is open, and stays open.**
                FindingRow(hb: hb, issue: issue,
                           open: total == 1 || openFindings.contains(issue.id),
                           toggle: total > 1 ? {
                               withAnimation(HelmMotion.disclosure) {
                                   openFindings.formSymmetricDifference([issue.id])
                               }
                           } : nil)
            }
        }
        .helmCard(padding: 0)
    }
}

// MARK: - One finding

/// The disclosure chevron both cards draw: quiet, in the one `chevronSlot`, and
/// hidden from VoiceOver. Where a row has a button, the button says the state
/// (`HelmA11y.expanded`).
private struct DisclosureChevron: View {
    let open: Bool

    var body: some View {
        Image(systemName: open ? "chevron.down" : "chevron.right")
            .helmQuietDetail()
            .frame(width: HomebrewHealthPage.chevronSlot)
            .accessibilityHidden(true)
    }
}

/// A row of the findings card: the title, and under it — when open — brew's own
/// words and the fix.
private struct FindingRow: View {
    @ObservedObject var hb: HomebrewViewModel
    @Environment(\.helmTraits) private var traits
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
                // Brew's own words, verbatim (`DoctorParser.body`).
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
            // Only `Error:` earns a word; a caution, nearly every finding, has
            // none (`severityBadge`).
            if let (word, tint) = HomebrewSettingsPage.severityBadge(issue.severity, increased: traits.increasedContrast) {
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
            DisclosureChevron(open: open)
                // Nothing to open: the slot stays, the mark does not.
                .opacity(toggle == nil ? 0 : 1)
            Text(issue.title)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - The fix

/// The pasteboard write both Copy buttons make.
private func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

/// The one Run button, in the closed row's header and in the open row's body —
/// the same builder, so the two cannot disagree about what pressing it does.
///
/// `role: .destructive` draws it red; `askToRunFix` asks before every fix runs,
/// and the label's ellipsis says so.
///
/// **It names what it will run in the tooltip and to VoiceOver**, because on a
/// closed row the command is out of sight.
private struct HealthRunButton: View {
    @ObservedObject var hb: HomebrewViewModel
    let fix: DoctorFix

    var body: some View {
        let command = HomebrewSettingsPage.commandLine(fix)
        Button(HbStr.runTheFixAsking, role: .destructive) { Task { await hb.askToRunFix(fix) } }
        .disabled(hb.running)
        .help(command)
        .accessibilityHint(command)
    }
}

/// The command, whose label says whose reading it is, and whatever this app
/// may do with it.
///
/// **No control here attributes the command to Homebrew** (`HbStr.helmReadsThisAs`);
/// `HbStr.brewNamedNoCommand` is drawn for both kinds of fix, because the
/// provenance is a fact about the command.
///
/// The copy is a pasteboard write from the view: nothing leaves this process.
/// Inside a clipped, animated block the ink is a literal primary with an
/// opacity, never a hierarchical style (`HelmAccordion`).
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
                    .font(HelmText.code)
                    .textSelection(.enabled)
                    .padding(.horizontal, HelmSpace.s4).padding(.vertical, HelmSpace.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // `ctl`, not `card`: a one-line field well.
                    .background(RoundedRectangle(cornerRadius: HelmRadius.ctl, style: .continuous)
                        .fill(HelmSurface.wellFill))
                Button(HbStr.copyTheFix) { copyToPasteboard(command) }
                if fix.kind == .runnable {
                    // A wider step than the row's: a press meant for Copy
                    // must not land on Run.
                    HealthRunButton(hb: hb, fix: fix)
                        .padding(.leading, HelmSpace.s5 - HelmSpace.s3)
                }
            }
            HelmSettingsNote(HbStr.brewNamedNoCommand)
            if fix.kind == .copyOnly {
                HelmSettingsNote(HbStr.helmDoesNotRunThis)
            }
        }
    }
}

// MARK: - The configuration

/// What `brew config` says, in one card: closed it is a line that names this
/// Homebrew and this Mac, with the one action; open it is the document.
///
/// **«Copy for a bug report» copies `BrewConfig.text`, what brew printed,**
/// not the regrouped reading drawn. Drawn only when there is a document.
///
/// The key as Homebrew spells it; the value monospaced (versions, paths,
/// hashes are compared character by character) and selectable.
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
                        // key: Homebrew adds keys between releases.
                        Grid(alignment: .leadingFirstTextBaseline,
                             horizontalSpacing: HelmSpace.s5, verticalSpacing: HelmSpace.s3) {
                            ForEach(group.lines) { line in
                                GridRow {
                                    Text(line.key)
                                        .helmQuietDetail()
                                    Text(line.value)
                                        .font(HelmText.code)
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
                    DisclosureChevron(open: open)
                    VStack(alignment: .leading, spacing: HelmSpace.s1) {
                        Text(HbStr.headingConfiguration)
                        if let summary = ConfigSummary.of(hb.config?.lines ?? []) {
                            Text(summary)
                                .helmQuietDetail()
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
                Button(HbStr.copyForABugReport) { copyToPasteboard(text) }
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
