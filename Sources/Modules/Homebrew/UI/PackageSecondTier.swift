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
            factTiles
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

    /// The narrowest a fact tile may be drawn, which is also what decides how
    /// many go across.
    ///
    /// **Derived from the narrowest inspector this module ever draws, not
    /// chosen.** Measured 2026-09-15 at `HomebrewSplit`'s own threshold, where
    /// the master compresses and the inspector is squeezed hardest: 244 pt of
    /// content. That is the narrow end of the whole span this has to cover — the
    /// wide end is `HelmLayout.readingColumn`, since nothing in the inspector
    /// grows past it any more.
    ///
    /// **And the arithmetic is the framework's, not the obvious one.** A
    /// `LazyVGrid` of adaptive columns fits `floor(available / (minimum +
    /// spacing))` of them rather than solving for the gaps it will actually
    /// draw: measured at that 244 pt, a minimum of 118 with an 8 pt gap drew
    /// **one** column — a 243 pt tile holding `3.6.4`, which is the complaint
    /// this change exists to answer — where 2 × 118 + 8 ≤ 244 says two. So the
    /// minimum solves the framework's inequality instead: 244 / 2 − 8 = 114,
    /// which draws two there and three at the reading column.
    ///
    /// **What it does not buy is a label on one line at that narrow end, and
    /// that is the trade taken deliberately.** At the faces these draw in on
    /// macOS 27 — `.caption2` for the label, `.subheadline` for the value — the
    /// widest Latin label is the French «Comment il est arrivé» at 105.2 pt and
    /// the widest value the French «comme dépendance» at 106.3, which with this
    /// tile's own 8 pt each side want 121.2 and 122.3. So those two wrap in a
    /// 114 pt tile and nowhere else, since every wider measure gives the column
    /// 142 pt or more; one wrapped line at the narrowest inspector is the
    /// cheaper of the two prices. The Japanese label is wider still (137.7 pt)
    /// and is not a case to size for at all: Japanese breaks between characters,
    /// so it wraps happily at any width a Latin label survives.
    private static let tileMinimum: CGFloat = 114

    /// The tile grid: label over value, as the approved artboard draws them.
    /// (No path: the drawing is the owner's scratch, untracked, so naming a file
    /// here is a citation no checkout can follow.)
    ///
    /// A `LazyVGrid` rather than a fixed pair of `HStack`s, because the number
    /// of tiles is four, three, two, one or none depending on what brew
    /// answered, and a hand-built row of two has to know which case it is in.
    /// `PackageFacts` is the one that decides.
    ///
    /// **Adaptive, not two flexible columns.** Two flexible columns divide
    /// whatever they are given, so the tiles were a function of the window
    /// rather than of what is in them: measured 2026-09-15 at the pane the app
    /// draws, a tile holding `2.11.4` came out 308 pt wide — six characters in a
    /// box a third of the window. Adaptive sizes the *columns* instead and fits
    /// as many as the measure holds: three across at `HelmLayout.readingColumn`,
    /// fewer as the inspector narrows, one when there is only room for one.
    @ViewBuilder
    private var factTiles: some View {
        let tiles = PackageFacts.of(info, size: size)
        if !tiles.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.tileMinimum),
                                         spacing: HelmSpace.s4)],
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
        // Collapsed to nothing rather than drawn empty, the way `factTiles`
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
            VStack(alignment: .leading, spacing: HelmSpace.s2) {
                if let reason = info.deprecationReason {
                    // Three sentences, and the third only when Homebrew named a
                    // replacement: "nothing was offered instead" is worth saying
                    // and "use nothing instead" is not. Composed out of whole
                    // sentences rather than clauses, so no language has to bend
                    // one into a frame another language chose.
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
                .padding(HelmSpace.s4)
                .background(RoundedRectangle(cornerRadius: HelmRadius.ctl, style: .continuous)
                    .fill(HelmSurface.wellFill))
        }
    }
}
