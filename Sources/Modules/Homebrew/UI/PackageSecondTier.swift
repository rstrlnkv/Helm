import SwiftUI
import HelmUI
import Module_Homebrew_Engine

/// **The package view's second tier: what `brew info` added, under the tier the
/// lists already drew.**
///
/// Its own file rather than five more members on `HomebrewSettingsPage`, which
/// was already the longest view in the module and went past the house's file
/// length with them in it. Nothing here reads the page or the view model: the
/// whole input is one `PackageInfo`, which is why it can stand alone at all.
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
/// Size is deliberately not here. It is a directory walk that belongs to a later
/// phase, and a tile that says it is working something out for a phase that has
/// not landed is a promise this code cannot keep.
struct PackageSecondTier: View {
    let info: PackageInfo

    /// The same stack the first tier's blocks sit in, with the same step: this
    /// used to be a `@ViewBuilder` member of the page, spaced by the page's own
    /// `VStack`, and a nested stack with a different number would have moved
    /// every block on the screen.
    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s5) {
            factTiles
            origin
            notes
            if !info.dependencies.isEmpty {
                chips(HbStr.dependsOn, info.dependencies)
            }
            if let caveats = info.caveats, !caveats.isEmpty {
                caveatsBlock(caveats)
            }
        }
    }

    /// The tile grid: two columns of label over value, as the prototype draws
    /// them (`design/Main.dc.html`).
    ///
    /// A `LazyVGrid` of flexible columns rather than a fixed pair of `HStack`s,
    /// because the number of tiles is three, two, one or none depending on what
    /// brew answered, and a hand-built row of two has to know which case it is
    /// in. `PackageFacts` is the one that decides.
    @ViewBuilder
    private var factTiles: some View {
        let tiles = PackageFacts.of(info)
        if !tiles.isEmpty {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: HelmSpace.s4),
                                GridItem(.flexible(), spacing: HelmSpace.s4)],
                      alignment: .leading, spacing: HelmSpace.s4) {
                ForEach(tiles, id: \.label) { tile in
                    VStack(alignment: .leading, spacing: HelmSpace.s1) {
                        Text(tile.label).font(.caption2).foregroundStyle(HelmText.faint)
                        Text(tile.value).font(HelmText.rowDetail)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, HelmSpace.s4).padding(.vertical, HelmSpace.s3)
                    .background(RoundedRectangle(cornerRadius: HelmRadius.ctl, style: .continuous)
                        .fill(HelmSurface.wellFill))
                }
            }
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
        HStack(spacing: HelmSpace.s5) {
            if let homepage = info.homepage, !homepage.isEmpty {
                if let url = URL(string: homepage),
                   let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
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
            if let tap = info.tap, !tap.isEmpty {
                Text(tap).font(HelmText.rowDetail).foregroundStyle(HelmText.faint).lineLimit(1)
            }
            Spacer(minLength: 0)
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
        VStack(alignment: .leading, spacing: HelmSpace.s2) {
            if let reason = info.deprecationReason {
                // Three sentences, and the third only when Homebrew named a
                // replacement: "nothing was offered instead" is worth saying and
                // "use nothing instead" is not. Composed out of whole sentences
                // rather than clauses, so no language has to bend one into a
                // frame another language chose.
                let said = HbStr.deprecated + " " + HbStr.deprecationReason(reason)
                HelmBanner(info.replacement.map { said + " " + HbStr.useInstead($0) } ?? said)
            }
            if info.installedOnRequest == false {
                quietNote(HbStr.cameAsDependency)
            }
            if !info.siblings.isEmpty {
                quietNote(HbStr.otherVersionLines(info.siblings.joined(separator: ", ")))
            }
        }
    }

    /// A fact about the package in a field of its own, at the same radius and
    /// the same fill the tiles use — so the tier reads as one surface rather
    /// than as a grid and then some loose sentences.
    private func quietNote(_ text: String) -> some View {
        Text(text)
            .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, HelmSpace.s4).padding(.vertical, HelmSpace.s3)
            .background(RoundedRectangle(cornerRadius: HelmRadius.ctl, style: .continuous)
                .fill(HelmSurface.wellFill))
    }

    /// A heading and a wrapping row of pills — the dependencies.
    ///
    /// `HelmWrappingRow`, not an `HStack`: an `HStack` places every child on one
    /// line by construction and compresses them when the line is too narrow, and
    /// `node` answers with eight names in a column that is 260 pt at its
    /// narrowest.
    private func chips(_ heading: String, _ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: HelmSpace.s2) {
            Text(heading).font(.caption2).foregroundStyle(HelmText.faint)
            HelmWrappingRow(spacing: HelmSpace.s2, lineSpacing: HelmSpace.s2,
                            alignment: .leading) {
                ForEach(names, id: \.self) { HelmBadge($0) }
            }
        }
    }

    /// What brew prints after an install: paths to edit, a service to start.
    ///
    /// Monospaced and kept whole, because it is the tool's own text and usually
    /// carries a path or a command somebody has to copy — re-flowing it would
    /// change what it says, and `textSelection` is what makes copying possible
    /// at all. Its own well, at the tiles' radius.
    private func caveatsBlock(_ caveats: String) -> some View {
        VStack(alignment: .leading, spacing: HelmSpace.s2) {
            Text(HbStr.packageNotes).font(.caption2).foregroundStyle(HelmText.faint)
            Text(caveats)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(HelmText.quiet)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(HelmSpace.s4)
                .background(RoundedRectangle(cornerRadius: HelmRadius.ctl, style: .continuous)
                    .fill(HelmSurface.wellFill))
        }
    }
}
