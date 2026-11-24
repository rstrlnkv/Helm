import SwiftUI
import HelmUI
import Module_Homebrew_Engine

/// **The package view's second tier: what `brew info` added, under the tier the
/// lists already drew.**
///
/// Nothing here reads the page or the view model: the whole input is one
/// `PackageInfo` and the size beside it, which arrives on its own
/// (`SizeReading`, spent in `PackageFacts`).
///
/// **Every block is drawn only when its fact is present.** An absent fact is an
/// absent block rather than one with a dash in it — the reason `PackageInfo`
/// carries optionals rather than empty strings. Nothing here is drawn while
/// `HomebrewViewModel.info` is nil.
struct PackageSecondTier: View {
    let info: PackageInfo
    /// What is known about the disk this package occupies: nothing, a walk that
    /// is out now, or a figure.
    let size: SizeReading

    /// The same stack the first tier's blocks sit in, with the same step: a nested
    /// stack with a different number would move every block on the screen.
    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s5) {
            facts
            origin
            notes
            if !info.dependencies.isEmpty {
                // `HelmWrappingRow`, not an `HStack`, which would compress a
                // long list of names onto one line.
                HelmSettingsSection(HbStr.dependsOn) {
                    HelmWrappingRow(spacing: HelmSpace.s2, lineSpacing: HelmSpace.s2,
                                    alignment: .leading) {
                        ForEach(info.dependencies, id: \.self) { HelmBadge($0) }
                    }
                }
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
    /// Rows, not tiles: tiles need a measured minimum to decide how many go
    /// across and read as controls; a row per fact holds at every width.
    ///
    /// **The label recedes and the value does not.** The value may wrap, and
    /// keeps to the trailing edge when it does.
    @ViewBuilder
    private var facts: some View {
        let rows = PackageFacts.of(info, size: size)
        if !rows.isEmpty {
            HelmSettingsSection {
                ForEach(rows, id: \.label) { row in
                    HStack(alignment: .firstTextBaseline, spacing: HelmSpace.s5) {
                        Text(row.label).foregroundStyle(HelmText.quiet)
                        Spacer(minLength: 0)
                        Text(row.value)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// Where the package comes from: its own site, and the tap it is served
    /// from.
    ///
    /// **The link is drawn as a link only for a scheme a browser answers.** The
    /// value comes from the network, and `Link` hands any scheme to the system
    /// opener. Another homepage is shown as text.
    @ViewBuilder
    private var origin: some View {
        // **An empty stack is still a child,** and the parent's spacing is
        // paid around it; so the block is absent rather than empty.
        // `BrewInfoParser` maps a blank value to nil, so presence is all there
        // is to ask. Either half is enough to draw the line.
        if info.homepage != nil || info.tap != nil {
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
                            .helmQuietDetail()
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
    /// The deprecation goes through `HelmBanner`, the one signal-tinted
    /// statement; the other two are quiet, facts about the package rather than
    /// warnings, so the warning stands out.
    @ViewBuilder
    private var notes: some View {
        // Absent rather than empty, as in `origin`. `installedOnRequest` is
        // read as a value: nil is a cask, and only `false` has something to say.
        if info.deprecationReason != nil || info.installedOnRequest == false
            || !info.siblings.isEmpty {
            VStack(alignment: .leading, spacing: HelmSpace.s4) {
                if let reason = info.deprecationReason {
                    // Whole sentences, not clauses, so no language bends one
                    // into another's frame; the third only with a replacement.
                    let said = HbStr.deprecated + " " + HbStr.deprecationReason(reason)
                    HelmBanner(info.replacement.map { said + " " + HbStr.useInstead($0) } ?? said)
                }
                let quiet = quietNotes
                if !quiet.isEmpty {
                    HelmSettingsSection {
                        ForEach(quiet, id: \.self) { text in
                            Text(text)
                                .foregroundStyle(HelmText.quiet)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
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

    /// What brew prints after an install: paths to edit, a service to start.
    ///
    /// Monospaced, kept whole and selectable: the tool's own text, usually a
    /// path or a command somebody has to copy. A card, not a well: it is to be
    /// read, not typed into.
    private func caveatsBlock(_ caveats: String) -> some View {
        HelmSettingsSection(HbStr.packageNotes) {
            Text(caveats)
                .font(HelmText.code)
                .foregroundStyle(HelmText.quiet)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
