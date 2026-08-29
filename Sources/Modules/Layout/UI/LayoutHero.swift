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
            Text(note)
                .font(HelmText.rowDetail)
                .foregroundStyle(HelmText.quiet)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, HelmSpace.s3)

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

    /// The line that never leaves. With time it names the assumption behind the
    /// estimate; with words it says when counting began, which is what «all
    /// time» means to somebody reading it.
    private var note: String {
        guard watching, hasFigure else { return "" }
        if metric == .minutes { return LyStr.estimateNote }
        guard let since = totals.since else { return "" }
        return LyStr.countingSince(HelmDates.day(since))
    }

    // MARK: - The controls

    /// The metric pair, in its own property: written inline it was one
    /// expression the type-checker refused.
    private var metricButtons: some View {
        HStack(spacing: HelmSpace.s1) {
            ForEach(HeroMetric.allCases, id: \.self) { option in
                metricButton(option)
            }
        }
        .padding(HelmSpace.s1)
        .background(RoundedRectangle(cornerRadius: HelmRadius.ctl)
            .strokeBorder(HelmSurface.hairline))
    }

    private func metricButton(_ option: HeroMetric) -> some View {
        let chosen = metric == option
        return Button { metric = option } label: {
            Image(systemName: option.symbol)
                .frame(width: 30, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: HelmRadius.ctl)
            .fill(chosen ? HelmSurface.wellFill : Color.clear))
        .accessibilityLabel(option.name)
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
        .help(option.name)
    }

    private var controls: some View {
        HelmWrappingRow(spacing: HelmSpace.s4, lineSpacing: HelmSpace.s3) {
            // **Two buttons, not a segmented control**, and that is a
            // measurement rather than a preference. A segmented picker draws to
            // its intrinsic width — measured at 52 pt drawn against 52 pt
            // wanted, in all eight languages — so inside a row that proposes
            // `.unspecified` it has no headroom by construction, and
            // `LongStringGeometryRatchetTests` counts a control with none as
            // one a longer label breaks. Widening the frame does not reach it:
            // the control centres inside whatever it is given.
            //
            // The pair still reads as one choice — same capsule, same size, the
            // chosen one filled — and each carries its name, because a glyph
            // with no name is invisible to VoiceOver.
            metricButtons

            // **A menu, not a segment, and that is a measurement.** Drawn as
            // five words the segment came to 347.5 pt in English with no
            // headroom at all, and `LongStringGeometryRatchetTests` counts a
            // control with less than 39 % room as one a longer word breaks —
            // which German and French are. A menu shows the chosen word and
            // costs the width of one, in every language.
            Picker(LyStr.period, selection: $period) {
                ForEach(ConversionPeriod.allCases, id: \.self) { option in
                    Text(LyStr.periodName(option)).tag(option)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
        .disabled(!watching)
        .opacity(watching ? 1 : 0)
    }
}
