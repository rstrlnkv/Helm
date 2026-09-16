import SwiftUI
import HelmUI
import Module_Homebrew_Engine

/// **The package view's second tier: what `brew info` added, under the tier the
/// lists already drew.**
///
/// Its own file rather than five more members on `HomebrewSettingsPage`, which
/// was already the longest view in the module and went past the house's file
/// length with them in it. Nothing here reads the page or the view model: the
/// whole input is one `PackageInfo` and the figure beside it, which is why it
/// can stand alone at all.
/// `packageDetail` stays the one builder of what a package draws, and this is
/// one of the things it draws.
///
/// **Every block is drawn only when its fact is present.** A package that is not
/// installed has no install date and no "how it got here"; a cask records
/// neither a licence nor who asked for it; most packages are not deprecated,
/// have no sibling version lines and print no caveats. An absent fact is an
/// absent block rather than one with a dash in it — the whole reason
/// `PackageInfo` carries optionals rather than empty strings.
///
/// And nothing here can be reached while `HomebrewViewModel.info` is nil, which
/// is the rule the tier exists under: a selection with no answer yet, or one
/// whose answer was refused, draws the first tier and nothing false.
///
/// **The size is the one input that is not part of `info`**, and it is a
/// parameter of its own because it arrives on its own: `brew info` carries no
/// size in either direction, so the figure is a walk of the package's Cellar
/// directory that lands after this tier has already been drawn once.
///
/// It is also the one input with three states rather than two. While that walk
/// is out for the package on screen, the tile is there and says the figure is
/// being counted; when it answers, the figure replaces the word in the tile that
/// is already there; when there was nothing to measure — a cask, a keg that
/// would not open, a package that is not installed — there is no tile at all,
/// the same as every other absent fact here. `SizeReading` is what carries the
/// difference, and `PackageFacts` is where it is spent.
struct PackageSecondTier: View {
    let info: PackageInfo
    /// What is known about the disk this package occupies: nothing, a walk that
    /// is out now, or a figure.
    let size: SizeReading

    /// The same stack the first tier's blocks sit in, with the same step: this
    /// used to be a `@ViewBuilder` member of the page, spaced by the page's own
    /// `VStack`, and a nested stack with a different number would have moved
    /// every block on the screen.
    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s5) {
            facts
            origin
            notes
            if !info.dependencies.isEmpty {
                chips(HbStr.dependsOn, info.dependencies)
            }
            if let caveats = info.caveats {
                caveatsBlock(caveats)
            }
        }
    }

    /// **The facts, as the rows of one grouped card: label leading, value
    /// trailing** — the shape macOS itself uses for exactly this, in System
    /// Settings' own «About» and in every grouped `Form`.
    ///
    /// It was a `LazyVGrid` of adaptive tiles, label over value, each in a well
    /// of its own. The grid needed a measured minimum to decide how many went
    /// across (114 pt, solved against the framework's own inequality at the
    /// narrowest inspector), and still gave a French label two lines at that
    /// width; and a column of wells side by side read as a set of controls
    /// rather than as statements about one package. Rows need no such number:
    /// there is one of them per fact at every width, and the only thing the
    /// width decides is whether a long value takes a second line.
    ///
    /// **The label recedes and the value does not**, which is the hierarchy the
    /// tiles already had and the mockup inverted by accident. The person came
    /// for «3.6.4», not for «Installed version».
    ///
    /// The value may wrap and keeps to the trailing edge when it does:
    /// measured 2026-09-15, the widest pair is French at 105.2 pt of label and
    /// 106.3 of value, which with the row's own gaps is a few points more than
    /// the 244 pt inspector at `HomebrewSplit`'s threshold. One wrapped value in
    /// one language at one width is the price, and the same one the tiles paid.
    @ViewBuilder
    private var facts: some View {
        let rows = PackageFacts.of(info, size: size)
        if !rows.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.label) { index, row in
                    if index > 0 {
                        // Inset to the text, the way a grouped `Form` draws
                        // its own: a rule across the card's whole width reads
                        // as the card being cut in two.
                        Divider().padding(.leading, HelmSpace.s5)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: HelmSpace.s5) {
                        Text(row.label).foregroundStyle(HelmText.quiet)
                        Spacer(minLength: 0)
                        Text(row.value)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, HelmSpace.s5).padding(.vertical, HelmSpace.s3)
                }
            }
            .helmCard(padding: 0)
        }
    }

    /// Where the package comes from: its own site, and the tap it is served
    /// from.
    ///
    /// **The link is drawn as a link only for a scheme a browser answers.** The
    /// value is a string out of a document downloaded from the network, and
    /// `Link` hands whatever it is given to the system opener — which answers
    /// every scheme any installed app has registered, not only the two this is
    /// for. A homepage that is neither `http` nor `https` is still shown, as
    /// text.
    @ViewBuilder
    private var origin: some View {
        // Collapsed to nothing rather than drawn empty, the way `facts`
        // above is: a `VStack`'s step is not paid around an absent child, and an
        // `HStack` of nothing is a child. `PackageBlocks` is the one that
        // decides, so a test can read the answer.
        if PackageBlocks.hasOrigin(info) {
            HStack(spacing: HelmSpace.s5) {
                if let homepage = info.homepage {
                    if let url = URL(string: homepage), let scheme = url.scheme?.lowercased(),
                       scheme == "http" || scheme == "https" {
                        Link(destination: url) {
                            Label(homepage, systemImage: "globe")
                        }
                        .font(HelmText.rowDetail)
                        .lineLimit(1).truncationMode(.middle)
                    } else {
                        Label(homepage, systemImage: "globe")
                            .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                if let tap = info.tap {
                    Text(tap).font(HelmText.rowDetail).foregroundStyle(HelmText.faint)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// The notes, each one drawn only when its fact is there.
    ///
    /// The deprecation goes through `HelmBanner`, which is the house's one
    /// signal-tinted statement and measures its ink against its own fill; the
    /// other two are quiet fields, because "it came in as a dependency" and
    /// "there are other version lines" are facts about the package rather than
    /// warnings about it, and three orange fields in a column would leave none
    /// of them reading as the one that matters.
    @ViewBuilder
    private var notes: some View {
        // And the same for this one: most packages are not deprecated, were
        // asked for by name and have no other version lines, which is an empty
        // `VStack` on the commonest screen in the module.
        if PackageBlocks.hasNotes(info) {
            VStack(alignment: .leading, spacing: HelmSpace.s4) {
                if let reason = info.deprecationReason {
                    // Three sentences, and the third only when Homebrew named a
                    // replacement: "nothing was offered instead" is worth saying
                    // and "use nothing instead" is not. Composed out of whole
                    // sentences rather than clauses, so no language has to bend
                    // one into a frame another language chose.
                    let said = HbStr.deprecated + " " + HbStr.deprecationReason(reason)
                    HelmBanner(info.replacement.map { said + " " + HbStr.useInstead($0) } ?? said)
                }
                let quiet = quietNotes
                if !quiet.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(quiet.enumerated()), id: \.offset) { index, text in
                            if index > 0 { Divider().padding(.leading, HelmSpace.s5) }
                            Text(text)
                                .foregroundStyle(HelmText.quiet)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, HelmSpace.s5).padding(.vertical, HelmSpace.s3)
                        }
                    }
                    .helmCard(padding: 0)
                }
            }
        }
    }

    /// The two notes that are facts about the package rather than warnings
    /// about it, in the order they are drawn.
    private var quietNotes: [String] {
        var out: [String] = []
        if info.installedOnRequest == false { out.append(HbStr.cameAsDependency) }
        if !info.siblings.isEmpty {
            out.append(HbStr.otherVersionLines(info.siblings.joined(separator: ", ")))
        }
        return out
    }

    /// A heading and a wrapping row of pills — the dependencies.
    ///
    /// `HelmWrappingRow`, not an `HStack`: an `HStack` places every child on one
    /// line by construction and compresses them when the line is too narrow, and
    /// `node` answers with eight names in a column that is 260 pt at its
    /// narrowest.
    private func chips(_ heading: String, _ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: HelmSpace.s3) {
            HelmSectionTitle(heading)
                .accessibilityAddTraits(.isHeader)
                .padding(.leading, HelmSpace.s5)
            HelmWrappingRow(spacing: HelmSpace.s2, lineSpacing: HelmSpace.s2,
                            alignment: .leading) {
                ForEach(names, id: \.self) { HelmBadge($0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .helmCard(padding: HelmSpace.s5)
        }
    }

    /// What brew prints after an install: paths to edit, a service to start.
    ///
    /// Monospaced and kept whole, because it is the tool's own text and usually
    /// carries a path or a command somebody has to copy — re-flowing it would
    /// change what it says, and `textSelection` is what makes copying possible
    /// at all. In a card of its own under the house's section title, the same
    /// surface as the facts above it rather than a recessed well — it is
    /// something to read, not something to type into.
    private func caveatsBlock(_ caveats: String) -> some View {
        VStack(alignment: .leading, spacing: HelmSpace.s3) {
            HelmSectionTitle(HbStr.packageNotes)
                .accessibilityAddTraits(.isHeader)
                .padding(.leading, HelmSpace.s5)
            Text(caveats)
                // A text *style* rather than a frozen 11 pt: it resolves to the
                // same 11 at the default setting and follows the system text
                // size from there, which a literal size cannot. The one other
                // deliberate monospaced face in the tree
                // (`HelmExplainer`) is spelled the same way.
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(HelmText.quiet)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .helmCard(padding: HelmSpace.s5)
        }
    }
}
