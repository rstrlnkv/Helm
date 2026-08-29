import SwiftUI
import HelmRuntime
import HelmUI
import Module_Layout_Engine

/// Which figure the hero is showing.
///
/// Two glyphs rather than two words: a letter and a clock are things a glyph
/// can be, where «Всё время» is not. Each carries a name — a glyph-only control
/// is invisible to anybody using VoiceOver, and `NamedControlsTests` scans the
/// source for exactly this shape.
enum HeroMetric: String, CaseIterable {
    case words, minutes

    var symbol: String {
        switch self {
        // Measured rather than chosen by meaning: `textformat.abc` paints 176
        // wide at 100 pt — half again wider than anything in `SymbolInk.ratios`
        // — and breaks the column it stands in. These two sit near the mean.
        case .words: "character.cursor.ibeam"
        case .minutes: "clock"
        }
    }

    var name: String {
        switch self {
        case .words: LyStr.showWords
        case .minutes: LyStr.showMinutes
        }
    }
}

/// The page's one figure: what the module has put right, over a period somebody
/// chooses, and what that came to in time.
///
/// Built to the shape the two finished pages of this app already use — Keep
/// Awake's and VPN's — because those are the ones that have been measured and
/// argued over. Centred like Keep Awake's, which is why it takes no
/// `groupedHeaderOutset`: the 10 pt is for a block that draws a surface, and
/// centred text needs none of it.
///
/// **Every state is the same height.** The figure changes, the caption changes,
/// and the line under them changes what it says rather than coming and going —
/// a hero that grows a line when somebody presses a segment moves the whole
/// form under it on an act that was not about the form.
struct LayoutHero: View {

    let totals: ConversionTotals
    let suspended: Bool
    let watching: Bool
    @Binding var period: ConversionPeriod
    @Binding var metric: HeroMetric
    /// Offered only when the grant is missing — the hero carries the verb
    /// rather than repeating itself in a second block below.
    var grant: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            figure
                .font(HelmText.heroFigureFont)
                .tracking(-2)
                // A figure that changes rolls rather than cuts — and the keyed
                // animation is the half that makes the transition an animation
                // rather than an instruction for one.
                .contentTransition(.numericText())
                .animation(HelmMotion.interface, value: figureText)
                .frame(maxWidth: .infinity)

            Text(caption)
                .font(HelmText.rowTitle)
                .foregroundStyle(HelmText.quiet)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, HelmSpace.s4)

            // Always occupied, never inserted: this is what keeps the four
            // states one height. It says the estimate's assumption while the
            // figure is time, and when counting began while it is words.
            // The placeholder is the longest of the two, so the space it
            // holds is the space the real one needs.
            Text(note.isEmpty ? LyStr.estimateNote : note)
                .font(HelmText.rowDetail)
                .foregroundStyle(HelmText.quiet)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, HelmSpace.s3)
                .opacity(note.isEmpty ? 0 : 1)
                .accessibilityHidden(note.isEmpty)

            if watching {
                controls.padding(.top, HelmSpace.s6)
            } else if let grant {
                Button(HelmPermissionNote.grantLabel, action: grant)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, HelmSpace.s6)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    // MARK: - The figure

    private var figures: LedgerFigures { totals.figures(period) }

    private var seconds: TimeInterval {
        TimeSaved.seconds(words: figures.words, characters: figures.characters)
    }

    /// Nothing put right is not «0». A module that has been watching all day and
    /// had nothing to correct is working perfectly, and a zero reads as a fault
    /// — the state no edition of the redesign ever drew.
    private var hasFigure: Bool { figures.words > 0 }

    private var figureText: String {
        guard hasFigure else { return watching ? LyStr.nothingYet : LyStr.heroNotWatching }
        switch metric {
        case .words: return Decimal(Double(figures.words), decimals: 0)
        case .minutes: return HelmDuration.string(seconds)
        }
    }

    @ViewBuilder private var figure: some View {
        if hasFigure, metric == .minutes {
            // «≈» is part of the figure and set smaller: the words are counted
            // and the time is estimated, and they must not look equally certain.
            HStack(alignment: .firstTextBaseline, spacing: HelmSpace.s3) {
                Text(verbatim: "≈")
                    .font(HelmText.rowTitle)
                    .foregroundStyle(HelmText.quiet)
                Text(figureText)
            }
        } else {
            Text(figureText)
                .foregroundStyle(hasFigure ? Color.primary : HelmText.quiet)
        }
    }

    private var caption: String {
        guard watching else { return LyStr.heroNotWatchingWhy }
        guard hasFigure else { return LyStr.nothingYetNote }
        if suspended { return LyStr.suspended }
        return metric == .words
            ? LyStr.wordsIn(period, count: figures.words)
            : LyStr.timeIn(period)
    }

    /// The line that never leaves.
    ///
    /// It says the estimate's assumption while the figure is time, and nothing
    /// while it is words — but it is drawn either way, at `.opacity(0)`, so the
    /// hero does not change height when somebody presses a glyph. An `if` here
    /// takes the form under it with it, on an act that was not about the form.
    ///
    /// It used to say «counted since 29 August» under the words. True, and not
    /// worth a line on the page: a start date is something a person needs once
    /// and never again, and it was standing in the one place the page has for
    /// something worth saying.
    private var note: String {
        guard watching, hasFigure, metric == .minutes else { return "" }
        return LyStr.estimateNote
    }

    // MARK: - The controls

    /// Every choice on this row is a button, the way Keep Awake's hero is: one
    /// `HelmWrappingRow` of `.large` buttons that folds instead of truncating.
    ///
    /// **Buttons rather than a segmented control, and that is a measurement.**
    /// A segmented picker draws to its intrinsic width and centres inside
    /// whatever it is given, so inside a row that proposes `.unspecified` it has
    /// no headroom at all — measured at 347.5 pt for five words in English,
    /// 52 pt for the glyph pair, drawn exactly equal to wanted in all eight
    /// languages. `LongStringGeometryRatchetTests` counts a control with under
    /// 39 % room as one a longer word breaks, which German and French are.
    /// A row of buttons wraps to a second line instead, which is what
    /// `HelmWrappingRow` exists for.
    ///
    /// The chosen one is `.borderedProminent`; the rest are ordinary. That is
    /// the same «this is the one that is on» the panel uses, and it needs no
    /// second colour of its own.
    private var controls: some View {
        HelmWrappingRow {
            ForEach(ConversionPeriod.allCases, id: \.self) { option in
                periodButton(option)
            }
        }
    }

    private func periodButton(_ option: ConversionPeriod) -> some View {
        chooser(chosen: period == option) { period = option } label: {
            Text(LyStr.periodName(option))
        }
    }

    /// One button, filled when it is the one in force.
    ///
    /// `.borderedProminent` and `.bordered` are two types, so the choice is a
    /// branch rather than a value — SwiftUI has no `AnyButtonStyle`, and hiding
    /// that behind an erased wrapper would cost more than the four lines it
    /// saves.
    @ViewBuilder
    private func chooser<Label: View>(chosen: Bool,
                                      action: @escaping () -> Void,
                                      @ViewBuilder label: () -> Label) -> some View {
        if chosen {
            Button(action: action, label: label)
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .accessibilityAddTraits(.isSelected)
        } else {
            Button(action: action, label: label)
                .controlSize(.large)
                .buttonStyle(.bordered)
        }
    }
}
