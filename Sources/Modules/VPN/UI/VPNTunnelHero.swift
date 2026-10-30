// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI
import HelmUI
import Module_VPN_Engine

/// **What the hero draws, as one value.**
///
/// Separate from the view because every rule worth guarding here is a rule
/// about *content* — which tiles exist, what each says, which sentence the
/// verdict is — and none of it can be read back off a rendering: an
/// `NSHostingView`'s accessibility tree is empty outside a real client, and
/// SwiftUI draws its own type rather than through `NSTextField`.
struct VPNTunnelStrip {

    /// What stands in the row above the readings — the offer, the run that is
    /// already going, or the sentence that stands where neither belongs.
    ///
    /// One value, because the three are exclusive and a set of optionals can be
    /// several at once or none: a button drawn beside its own spinner is a
    /// second twenty seconds of somebody's traffic one press away, and a button
    /// drawn beside the sentence explaining why there is no button is worse.
    enum Action: Equatable {
        case offer(String)
        case running(String)
        /// A tunnel that is not carrying the default route. The sentence, not a
        /// disabled button: nothing about *this* card can enable it, and a
        /// control that never becomes pressable is a control that has to be
        /// explained anyway.
        case notOffered(String)
    }

    /// Which reading a tile holds — the identity `ForEach` needs.
    enum Reading: String { case uptime, down, up, speed }

    struct Tile: Identifiable {
        var id: Reading { kind }
        let kind: Reading
        let label: String
        let value: String
        /// The line under the figure. **Not optional, and that is the row's
        /// shape**: a column with nothing under its figure leaves the figures
        /// of the others over a gap.
        let note: String
    }

    /// **The one dash in the strip, and it is the exception that proves the
    /// rule.** An absent reading is an absent tile everywhere else, because a
    /// dash there is a measurement of nothing; the speed tile stands empty
    /// because its emptiness is actionable — there is no passive way to read a
    /// link's throughput, and the button under it is the whole point.
    static let noReading = "—"

    /// **The hero's second line, as one value of three cases.**
    ///
    /// Not an optional string: «no country» is two different states and they
    /// must not be drawn the same. The traffic is in the tunnel and nobody has
    /// been told where it comes out — that is worth a sentence — against the
    /// traffic not being in the tunnel at all, where there is no exit country
    /// to be about and a line saying one is unknown would be answering a
    /// question nobody asked.
    enum Place: Equatable {
        /// The country, already named in Helm's own language.
        case named(String)
        /// In the tunnel; the exit has not answered.
        case unknown
        /// Nothing to say — the traffic is beside the tunnel, or the routing
        /// reading itself failed.
        case none
    }

    let tiles: [Tile]
    /// **What the tunnel carries around itself, or nil when it carries nothing.**
    ///
    /// The verdict says the traffic goes through the tunnel, and a tunnel can
    /// still declare ranges outside itself: with `17.0.0.0/8`, Apple's whole
    /// network, iCloud, the App Store and iMessage leave with the real address
    /// (`VPNExcludedRoutes`).
    let exclusions: String?
    /// **The verdict alone, with no place in it.** `place` is the other half, on
    /// a line of its own, so this has to stay a sentence that is true without
    /// the country rather than one with a dangling dash.
    let verdict: String
    let place: Place
    let action: Action
    /// **How long the arc under a running measurement is drawn against.**
    ///
    /// This link's own last run (`VPNSpeedReading.took`), so from the second
    /// measurement onwards the arc is a fact about the link in front of the
    /// reader; `NetworkQualitySpeed.typicalRun` stands before that.
    ///
    /// Here rather than in the view for the reason this whole type exists: a
    /// number the page draws is content.
    ///
    /// Still a **length**, never a stage — the engine knows only whether a run
    /// is in flight (`VPNEngine.measuringSpeed` is a name or nothing) — so the
    /// arc goes on claiming the clock rather than the work.
    let expectedWait: TimeInterval

    /// **Whether a run is in flight for the tunnel this strip is about.**
    ///
    /// Read off `action` rather than stored beside it, so the two cannot
    /// disagree: `.running` *is* the state, and a second field meaning the same
    /// thing is a field somebody has to remember to set. The speed card wears
    /// the measuring slot while this is true (`helmMeasuringSlot`) — the figure
    /// already there drops a rank rather than disappearing, because it is still
    /// the only reading the person has.
    var isMeasuring: Bool {
        if case .running = action { true } else { false }
    }

    /// **`measuring` defaults to the state's own answer, not to false.**
    ///
    /// The state already carries whether a run is in flight — it is the engine's
    /// fact — and the parameter is the page putting the press in front of it
    /// until the engine's work queue answers (`VPNViewModel.measuring`). Defaulted to `false` the two would disagree
    /// by construction.
    init(_ state: VPNTunnelState, now: Date = Date(), measuring: Bool? = nil) {
        let measuring = measuring ?? state.measuring
        let facts = VPNTunnelFacts(since: state.since, bytesIn: state.bytesIn,
                                   bytesOut: state.bytesOut, speed: state.speed, now: now)
        var tiles: [Tile] = []
        // Each of the three is drawn only if it was actually read. Nil here is
        // never zero: nobody saw the tunnel come up, or the kernel had no
        // counters for its interface.
        if let uptime = facts.uptime {
            tiles.append(Tile(kind: .uptime, label: VPNStr.tileUptime,
                              value: HelmDates.span(uptime),
                              note: VPNStr.tunnelAndInterface(state.name, state.interface)))
        }
        if let bytesIn = facts.bytesIn {
            tiles.append(Tile(kind: .down, label: VPNStr.tileDown,
                              value: Bytes(Int(clamping: bytesIn)), note: VPNStr.bytesSince))
        }
        if let bytesOut = facts.bytesOut {
            tiles.append(Tile(kind: .up, label: VPNStr.tileUp,
                              value: Bytes(Int(clamping: bytesOut)), note: VPNStr.bytesSince))
        }
        tiles.append(Self.speedTile(facts, now: now))
        self.tiles = tiles
        expectedWait = facts.speed?.took ?? NetworkQualitySpeed.typicalRun
        exclusions = VPNStr.excluded(state.excluded)

        switch state.exit {
        case .throughTunnel(let countryCode):
            verdict = VPNStr.trafficThroughTunnel
            // The place is named out of `Locale` in Helm's own language — never
            // the exit service's own spelling of it — and a code that is not a
            // region, or none at all, is `unknown` rather than a line that
            // trails off.
            place = countryCode.flatMap(VPNStr.country).map(Place.named) ?? .unknown
        case .besideTunnel:
            verdict = VPNStr.trafficBesideTunnel
            place = .none
        case .unknown:
            verdict = VPNStr.trafficUnknown
            place = .none
        }

        // **The offer belongs to the tunnel holding the default route, and to
        // no other.** One predicate, read here and by the engine that refuses
        // the same call (`VPNExitVerdict.carriesTheDefaultRoute`), and a rule
        // spelled twice is a rule two targets can disagree about.
        if measuring {
            action = .running(VPNStr.measuring)
        } else if state.exit.carriesTheDefaultRoute {
            // «Measure again» rather than «Measure speed» once a figure sits in
            // the tile: the press replaces a stale number, it does not produce
            // the first one.
            action = .offer(facts.speed == nil ? VPNStr.measureSpeed : VPNStr.measureAgain)
        } else {
            action = .notOffered(VPNStr.speedIsTheRoutedTunnels)
        }
    }

    /// The fourth column: a figure once one has been asked for, and before that
    /// a dash over the unit alone.
    ///
    /// The note always opens with the unit, because this column's value is two
    /// numbers and cannot carry one the way a byte figure does — and what
    /// follows the unit is the one thing worth qualifying it with. The age is
    /// there exactly when `VPNTunnelFacts.speedShowsItsAge` says there is one
    /// to draw; a fresh reading keeps the unit alone. Written the other way
    /// round (an age under every reading) the property would be a promise with
    /// nothing keeping it.
    ///
    /// **`speedShowsItsAge`, not `speedIsStale`, and the two came apart here.**
    /// This line read the staleness — «may the figure stand as live» — as «show
    /// the age», so a reading stamped ahead of this page's clock, which is
    /// stale for that very reason, drew «Мбит/с · через 5 мин.»: a time still
    /// to come under a figure taken in the past.
    private static func speedTile(_ facts: VPNTunnelFacts, now: Date) -> Tile {
        guard let speed = facts.speed else {
            // **The unit alone.** A price tag under the figure would wrap this
            // column to two lines while its three neighbours take one, and the
            // duration it quoted was never measured.
            return Tile(kind: .speed, label: VPNStr.tileSpeed, value: noReading,
                        note: VPNStr.speedNote(nil))
        }
        return Tile(kind: .speed, label: VPNStr.tileSpeed,
                    // `Count`, not `Decimal`: the figure is a whole number of
                    // megabits and wants the language's digit grouping;
                    // `Decimal(speed.down)` binds to `Foundation.Decimal.init(_: Int)`
                    // and draws «10000» for a 10 Gbit link.
                    //
                    // **Each arrow sits against its own digits, and there is one
                    // space between the pair**: the narrower string is what keeps
                    // `helmMetricFigure` from shrinking the figure at the
                    // narrowest pane. An arrow is the unit of the number beside
                    // it, not a word of its own.
                    value: "\(Count(speed.down))↓ \(Count(speed.up))↑",
                    // `.short`, and **never `.abbreviated`** however well its
                    // name suits a 116 pt column: that style prints «-1 мин» in
                    // Russian and «-1 min» in French — a signed delta rather
                    // than an age, under a figure that is already two signed
                    // readings. `HelmDates.AgeStyle` has two cases so the third
                    // cannot be asked for here.
                    note: VPNStr.speedNote(facts.speedShowsItsAge
                        ? HelmDates.age(speed.at, to: now, style: .short) : nil))
    }
}

/// **The top of the VPN page: what the tunnel carrying your traffic is doing.**
///
/// The one thing this page can say that a card cannot. A card knows its own
/// configuration is connected; only the page knows which tunnel the traffic is
/// actually leaving through, how long it has been that way, and what it has
/// carried — so this reads one tunnel rather than being drawn four times over.
///
/// **First on the page.** The two things a person opens it to find out — is my
/// traffic really in the tunnel, and where does it come out — belong above the
/// settings, in the type size of a headline. The shape is `KeepAwakeHero`'s.
///
/// **No card of its own.** It rides on the first section's header
/// (`VPNSettingsPage.heroAndTitle`), drawn out to the cards' column by
/// `-groupedHeaderOutset` — a hero inside a card would be a card above the
/// cards.
///
/// The four readings are cards of the kit (`readings`), side by side.
struct VPNTunnelHero: View {
    private let tunnels: [VPNTunnelState]
    @Binding private var selected: String?
    private let now: Date
    /// The name of the tunnel a run is in flight for, or nil. A name rather
    /// than a flag, so a spinner turns over the tunnel being measured and not
    /// over whichever one the switcher happens to be showing.
    private let measuring: String?
    private let measure: (String) -> Void

    /// Natural height of whatever the block is showing, so it can ramp between
    /// two of them instead of snapping.
    ///
    /// **Without it the section title under the hero jumps** whenever the
    /// content changes height — the exit country arriving, the uptime becoming
    /// known, a segment pressed — and two of those happen with nobody touching
    /// anything. `KeepAwakeHero` ramps the same way.
    @State private var bodyHeight: CGFloat?
    /// What is **drawn**, as against what has arrived. Seeded from the incoming
    /// value rather than from a constant: a page opened on a live tunnel must
    /// show it, not play the empty state swapping into it (`KeepAwakeHero` says
    /// why an optional falling back to the property is a check that cannot
    /// fail).
    @State private var shown: [VPNTunnelState]
    /// **When this page saw a run begin, or nil because it did not.**
    ///
    /// The engine says *whether* a measurement is in flight and nothing else —
    /// no stage, no fraction, no byte count (`VPNEngine.measuringSpeed` is a
    /// name or nothing). So the only fact anybody has about how far along a run
    /// is, is the clock, and the only page entitled to read that clock is one
    /// that watched the run start. Seeded `nil` rather than `Date()`, which is
    /// the same law the `shown` property above obeys from the other end: a page
    /// opened *into* a run never saw it begin, and a stamp taken at `init` would
    /// be a twenty-second-old run drawn as a fresh one. `HelmExpectedWait`
    /// answers `nil` with the indeterminate spinner this page has always drawn.
    @State private var measureStarted: Date?

    init(_ tunnels: [VPNTunnelState], selected: Binding<String?>, now: Date = Date(),
         measuring: String? = nil, measure: @escaping (String) -> Void) {
        self.tunnels = tunnels
        _selected = selected
        self.now = now
        self.measuring = measuring
        self.measure = measure
        _shown = State(initialValue: tunnels)
    }

    var body: some View {
        // Resolved here rather than in `init`, because the choice depends on a
        // binding: the page holds the selection and the engine rewrites the
        // list under it, and a value computed once at construction would be the
        // answer to a question asked before either could move.
        let switcher = VPNTunnelSwitcher(shown, selected: selected)
        return Group {
            if let chosen = switcher.chosen {
                live(switcher, chosen).transition(.opacity)
            } else {
                empty.transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The measurement alone, and **not** `helmAccordion`: this block has no
        // open state and never collapses. What it needs is to be the size of
        // whatever it is showing, so the cross-fade has an animating frame for
        // its clip to be taken from.
        .helmMeasuredHeight($bodyHeight)
        .frame(height: bodyHeight, alignment: .top)
        .clipped()
        // Where the value **lands**, not where it was set: the engine publishes
        // these and a transaction is the only thing that makes them move
        // (ARCHITECTURE.md § Design system). `.animation(_:value:)` on the outside was
        // measured doing nothing for the same shape one module over.
        .onChange(of: tunnels) { _, arrived in
            withAnimation(HelmMotion.disclosure) { shown = arrived }
        }
        // **The stamp is taken where the run begins, and only there.** Not in
        // `init` — that is every rebuild the engine causes, and it causes dozens
        // behind one connect, so the clock would restart under a wait already
        // running. Not inside `measure`'s closure either: a press is not a
        // start, the engine refuses a tunnel that is not carrying the default
        // route, and `VPNViewModel.measuring` puts the press in front of the
        // engine's answer until the engine's work queue answers.
        // Nil → a name is the one transition that is a run beginning; a name →
        // nil is it ending, and the stamp goes with it so the next page opened
        // into a run inherits nothing.
        //
        // No `withAnimation` around it, and that is not an oversight: what this
        // value changes is *which* indicator draws, and the handover between
        // them is a cut on purpose — the two say different things and a
        // cross-fade between them would be the app hedging.
        .onChange(of: measuring) { was, running in
            measureStarted = running == nil ? nil : (was == nil ? Date() : measureStarted)
        }
    }

    // MARK: - With a tunnel up

    /// **The shape `KeepAwakeHero` draws**: the figure there is a *sentence* at
    /// 40 pt light, centred, in `HelmText.quiet`, with a caption under it and a
    /// centred row of capsule verbs under that. No glyph: the state is carried
    /// by words.
    ///
    /// So the verdict takes the 40 pt slot, the country and the exclusions
    /// become the caption, and the segments and the measure button become the
    /// capsule row.
    private func live(_ switcher: VPNTunnelSwitcher,
                      _ chosen: VPNTunnelState) -> some View {
        let strip = VPNTunnelStrip(chosen, now: now, measuring: measuring == chosen.name)
        return VStack(spacing: HelmSpace.s6) {
            // **The figure block is `KeepAwakeHero`'s, spacing and all**: its
            // verdict, caption and row of verbs in one `VStack(spacing: s4)`
            // with `s6` on top of the row. Two heroes of one shape must not be
            // two rhythms.
            VStack(spacing: HelmSpace.s4) {
                headline(strip)
                verbs(switcher, strip, chosen)
                    .padding(.top, HelmSpace.s6)
            }
            // **The words are inset like a heading; the surface is not.**
            //
            // The whole block sits in the cards' own column
            // (`VPNSettingsPage.heroAndTitle` backs it out of the header inset),
            // and the words go back in by the same amount, because a heading
            // belongs level with what the rows below *say* —
            // `HelmLayout.groupedHeaderOutset` carries both halves of that
            // ruling. As a negative padding on the readings alone it would draw
            // nothing: `.clipped()` sits at this view's root for the cross-fade,
            // and a clip takes back whatever a negative padding inside it gives.
            .padding(.horizontal, HelmLayout.groupedHeaderOutset)
            readings(strip)
        }
        .frame(maxWidth: .infinity)
    }

    /// The verdict at the size a page's own state is set in, and one caption
    /// under it.
    ///
    /// **The country and the exclusions are one line, not two**, joined by the
    /// dot this module already punctuates with (`VPNStr.note`): one caption in
    /// the slot `KeepAwakeHero` puts «Ни одно правило не включено» in.
    ///
    /// **No glyph beside the verdict.** A tick or a warning triangle would carry
    /// colour and nothing else, and standing inside the centred row it would push
    /// the sentence off the caption's axis. `KeepAwakeHero` carries its verdict
    /// in words alone at the same rank.
    @ViewBuilder
    private func headline(_ strip: VPNTunnelStrip) -> some View {
        Text(strip.verdict)
            .font(HelmText.heroFont)
            .helmHeroSentence()
        if let caption = caption(strip) {
            Text(caption)
                .font(HelmText.rowTitle)
                .foregroundStyle(HelmText.quiet)
                .helmHeroSentence()
        }
    }

    /// «Финляндия · кроме локальной сети и серверов Apple», or whichever half
    /// of it there is — and nil when there is neither, so the slot is absent
    /// rather than empty.
    private func caption(_ strip: VPNTunnelStrip) -> String? {
        let place: String? = switch strip.place {
        case .named(let country): country
        case .unknown: VPNStr.exitCountryUnknown
        case .none: nil
        }
        let parts = [place, strip.exclusions].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The height of the kit's large capsule (`helmCapsuleButtons`,
    /// `.controlSize(.large)`), so the running slot keeps the row's height across
    /// offer → measuring → done.
    static let verbHeight: CGFloat = 32

    /// **The verbs, as capsules in a centred row** — the shape
    /// `KeepAwakeHero` gives its presets.
    ///
    /// The segments and the measure button share the row because they are the
    /// same kind of thing here: the only two things this block can be told to
    /// do. A tunnel that is not carrying the traffic has no button to offer,
    /// and its sentence goes under the row rather than into it — a paragraph
    /// among capsules is not a capsule.
    @ViewBuilder
    private func verbs(_ switcher: VPNTunnelSwitcher, _ strip: VPNTunnelStrip,
                       _ chosen: VPNTunnelState) -> some View {
        VStack(spacing: HelmSpace.s4) {
            HelmWrappingRow(spacing: HelmSpace.s4, lineSpacing: HelmSpace.s3,
                            alignment: .center) {
                VPNTunnelSwitcherRow(switcher.drawn(beside: strip.action),
                                     selected: $selected)
                switch strip.action {
                case .offer(let word):
                    Button(word) { measure(chosen.name) }
                        // The hero is a `Form` section header, whose bold font a
                        // button would inherit.
                        .font(HelmText.rowTitle)
                        .controlSize(.large)
                case .running(let word):
                    HStack(spacing: HelmSpace.s3) {
                        // **The one thing on this page that says how far in the
                        // wait is** — and it says it about the wait, not about
                        // the measurement, because the measurement reports
                        // nothing until it is over. Same slot as the spinner
                        // it replaces, so the row it stands in does not move;
                        // when the clock runs out it *becomes* that
                        // spinner again rather than filling up and sitting
                        // there. `HelmExpectedWait` carries the argument.
                        HelmExpectedWait(started: measureStarted,
                                         expected: strip.expectedWait)
                        Text(word)
                            .font(HelmText.rowDetail)
                            .foregroundStyle(HelmText.quiet)
                    }
                    .frame(height: Self.verbHeight)
                case .notOffered:
                    EmptyView()
                }
            }
            .helmCapsuleButtons()
            if case .notOffered(let sentence) = strip.action {
                Text(sentence)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmText.quiet)
                    .helmHeroSentence()
            }
        }
    }

    /// **The readings as four cards**, on the kit's card surface. Two card
    /// systems on one page is a defect this house has already paid for twice, so
    /// the fill is the kit's (`helmCard`) and not one of the hero's own.
    private func readings(_ strip: VPNTunnelStrip) -> some View {
        // The gap the connections grid uses between its own cards, so the two
        // rows are one rhythm rather than two.
        HStack(alignment: .top, spacing: HelmSpace.s5) {
            // **Only the speed card, and only while its own run is going.** The
            // slot is the one place on this page that says a newer figure is on
            // its way; drawn on all four it would be saying it about three
            // readings nobody asked for. `false` is inert — full ink, no border,
            // a paused schedule (`HelmMeasuringSlot`).
            ForEach(strip.tiles) { tile in
                column(tile).helmMeasuringSlot(strip.isMeasuring && tile.kind == .speed)
            }
        }
        // The row takes the height of its tallest card and no more. Without it a
        // container taller than the row stretches it, with empty fill under the
        // figures.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }

    /// One reading, as its own card.
    ///
    /// `maxWidth: .infinity` on each is what makes the four equal in width, and
    /// `HelmSpace.s5` is a connection card's own inner padding.
    ///
    /// **`maxHeight: .infinity` is what makes them equal in height.** Notes are
    /// not all one line — a configuration named at length in System Settings
    /// wraps one at any pane. Under the row's `.fixedSize(vertical:)` the
    /// `HStack` still takes the height of its tallest card and no more; this
    /// spends that height on the other three, and `alignment: .top` on the row
    /// keeps every word where it was.
    private func column(_ tile: VPNTunnelStrip.Tile) -> some View {
        VStack(alignment: .leading, spacing: HelmSpace.s3) {
            Text(tile.label)
                .font(HelmText.smallPrint)
                .foregroundStyle(HelmText.quiet)
                .lineLimit(1)
            Text(tile.value)
                .helmMetricFigure()
            Text(tile.note)
                .font(HelmText.smallPrint)
                .foregroundStyle(HelmText.faint)
                // Wrapping rather than truncating: a note that loses its tail
                // loses the interface out of «incy · utun8», and a tunnel named
                // at length in System Settings is an ordinary Mac.
                .fixedSize(horizontal: false, vertical: true)
        }
        // «Скорость, 343, incy · utun8» as one VoiceOver stop, the way
        // `HelmMetricStrip` reads its two. Left apart, the four cards are twelve
        // stops and three of them say the figure before the word naming it.
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .helmCard(padding: HelmSpace.s5)
    }

    // MARK: - With nothing up

    /// **The state `KeepAwakeHero` is drawn around**, and the best argument for
    /// taking its shape whole: «Mac засыпает как обычно» is that page's idle,
    /// set in the same 40 pt as its countdown. «Ни один туннель не поднят» is
    /// this one's, and it sits in the same slot at the same size.
    ///
    /// No mark: nothing is wrong with a Mac that has no tunnel up, and a glyph
    /// beside that sentence would be answering a question nobody asked.
    private var empty: some View {
        VStack(spacing: HelmSpace.s4) {
            Text(VPNStr.noTunnelUp)
                .font(HelmText.heroFont)
                .foregroundStyle(HelmText.quiet)
                .helmHeroSentence()
            Text(VPNStr.noTunnelUpNote)
                .font(HelmText.rowTitle)
                .foregroundStyle(HelmText.quiet)
                .helmHeroSentence()
        }
        .frame(maxWidth: .infinity)
        // The same inset the live state's words take, for the same reason: the
        // block is in the cards' column and its text is not.
        .padding(.horizontal, HelmLayout.groupedHeaderOutset)
    }
}
