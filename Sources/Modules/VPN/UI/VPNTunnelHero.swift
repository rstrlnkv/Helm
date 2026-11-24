// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI
import HelmUI
import Module_VPN_Engine

/// **What the hero draws, as one value.**
///
/// Separate from the view because every rule worth guarding here is about
/// *content*, and none of it can be read back off a rendering: an
/// `NSHostingView`'s accessibility tree is empty outside a real client.
struct VPNTunnelStrip {

    /// What stands in the row above the readings — the offer, the run that is
    /// already going, or the sentence that stands where neither belongs.
    ///
    /// One value, because the three are exclusive: a button beside its own
    /// spinner is a second run of somebody's traffic one press away.
    enum Action: Equatable {
        case offer(String)
        case running(String)
        /// A tunnel that is not carrying the default route. A sentence, not a
        /// disabled button: nothing about *this* card can enable it.
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

    /// **The one dash in the strip.** An absent reading is an absent tile
    /// everywhere else; the speed tile stands empty because its emptiness is
    /// actionable: the button under it is the only way to get a figure.
    static let noReading = "—"

    /// **The hero's second line, as one value of three cases.**
    ///
    /// Not an optional string: «no country» is two states. The traffic is in
    /// the tunnel and the exit has not answered (worth a sentence), or the
    /// traffic is not in the tunnel at all (nothing to say).
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
    /// This link's own last run (`VPNSpeedReading.took`), or
    /// `NetworkQualitySpeed.typicalRun` before there is one. A length, never a
    /// stage: the engine knows only whether a run is in flight.
    let expectedWait: TimeInterval

    /// **Whether a run is in flight for the tunnel this strip is about.**
    ///
    /// Read off `action` rather than stored beside it, so the two cannot
    /// disagree. The speed card wears the measuring slot while this is true
    /// (`helmMeasuringSlot`); the figure already there drops a rank rather
    /// than disappearing.
    var isMeasuring: Bool {
        if case .running = action { true } else { false }
    }

    /// **`measuring` defaults to the state's own answer, not to false.**
    ///
    /// The state carries the engine's answer; the parameter is the page putting
    /// the press in front of it until the work queue answers
    /// (`VPNViewModel.measuring`).
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
            // Named out of `Locale` in Helm's own language, never the exit
            // service's spelling; a code that is not a region is `unknown`.
            place = countryCode.flatMap(VPNStr.country).map(Place.named) ?? .unknown
        case .besideTunnel:
            verdict = VPNStr.trafficBesideTunnel
            place = .none
        case .unknown:
            verdict = VPNStr.trafficUnknown
            place = .none
        }

        // **The offer belongs to the tunnel holding the default route, and to
        // no other.** The engine refuses by the same predicate
        // (`VPNExitVerdict.carriesTheDefaultRoute`).
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
    /// The note opens with the unit, because this column's value is two
    /// numbers. The age follows exactly when `VPNTunnelFacts.speedShowsItsAge`
    /// says so. Not `speedIsStale`: a reading stamped ahead of this page's
    /// clock is stale, and its age would read as a time still to come.
    private static func speedTile(_ facts: VPNTunnelFacts, now: Date) -> Tile {
        guard let speed = facts.speed else {
            // **The unit alone**, so this column stays one line like its
            // neighbours.
            return Tile(kind: .speed, label: VPNStr.tileSpeed, value: noReading,
                        note: VPNStr.speedNote(nil))
        }
        return Tile(kind: .speed, label: VPNStr.tileSpeed,
                    // `Count`, not `Fractional`: the figure is whole megabits
                    // and wants digit grouping, which `Fractional` turns off.
                    // Each arrow sits against its own digits with one space
                    // between the pair, so `helmMetricFigure` does not shrink
                    // the figure at the narrowest pane.
                    value: "\(Count(speed.down))↓ \(Count(speed.up))↑",
                    // `.short`, never `.abbreviated`: that style prints «-1 мин»
                    // in Russian, a signed delta rather than an age.
                    // `HelmDates.AgeStyle` has two cases so it cannot be asked for.
                    note: VPNStr.speedNote(facts.speedShowsItsAge
                        ? HelmDates.age(speed.at, to: now, style: .short) : nil))
    }
}

/// **The top of the VPN page: what the tunnel carrying your traffic is doing.**
///
/// Only the page knows which tunnel the traffic actually leaves through, so
/// this reads one tunnel rather than being drawn on every card. The shape is
/// `KeepAwakeHero`'s.
///
/// **No card of its own.** It rides on the first section's header
/// (`VPNSettingsPage.heroAndTitle`), drawn out to the cards' column by
/// `-groupedHeaderOutset`: a hero inside a card would be a card above the
/// cards.
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
    /// two of them instead of snapping; without it the section title under the
    /// hero jumps whenever the content changes height.
    @State private var bodyHeight: CGFloat?
    /// What is **drawn**, as against what has arrived. Seeded from the incoming
    /// value, so a page opened on a live tunnel shows it rather than playing
    /// the empty state swapping into it.
    @State private var shown: [VPNTunnelState]
    /// **When this page saw a run begin, or nil because it did not.**
    ///
    /// The engine says only *whether* a measurement is in flight, so the clock
    /// is the only progress there is, and only a page that watched the run
    /// start may read it. Seeded `nil`, not `Date()`: a page opened *into* a
    /// run would draw an old run as a fresh one. `HelmExpectedWait` answers
    /// `nil` with the indeterminate spinner.
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
        // Resolved here rather than in `init`: the page holds the selection and
        // the engine rewrites the list under it.
        let switcher = VPNTunnelSwitcher(shown, selected: selected)
        return Group {
            if let chosen = switcher.chosen {
                live(switcher, chosen).transition(.opacity)
            } else {
                empty.transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The measurement alone, not `helmAccordion`: this block never
        // collapses, it only needs an animating frame for the cross-fade's clip.
        .helmMeasuredHeight($bodyHeight)
        .frame(height: bodyHeight, alignment: .top)
        .clipped()
        // Where the value **lands**, not where it was set
        // (Architecture/DesignSystem.md § Motion).
        .onChange(of: tunnels) { _, arrived in
            withAnimation(HelmMotion.disclosure) { shown = arrived }
        }
        // **The stamp is taken where the run begins, and only there.** Not in
        // `init`, which runs on every engine rebuild and would restart the
        // clock. Not in `measure`'s closure: a press is not a start, the engine
        // may refuse it. Nil → a name is a run beginning; a name → nil is it
        // ending, and the stamp goes with it.
        //
        // No `withAnimation`: the handover between the two indicators is a cut
        // on purpose, because they say different things.
        .onChange(of: measuring) { was, running in
            measureStarted = running == nil ? nil : (was == nil ? Date() : measureStarted)
        }
    }

    // MARK: - With a tunnel up

    /// **The shape `KeepAwakeHero` draws**: the verdict in the 40 pt slot, the
    /// country and the exclusions as the caption, and the segments and the
    /// measure button as the capsule row. No glyph: the state is carried by
    /// words.
    private func live(_ switcher: VPNTunnelSwitcher,
                      _ chosen: VPNTunnelState) -> some View {
        let strip = VPNTunnelStrip(chosen, now: now, measuring: measuring == chosen.name)
        return VStack(spacing: HelmSpace.s6) {
            // The figure block is `KeepAwakeHero`'s, spacing and all: two
            // heroes of one shape must not be two rhythms.
            VStack(spacing: HelmSpace.s4) {
                headline(strip)
                verbs(switcher, strip, chosen)
                    .padding(.top, HelmSpace.s6)
            }
            // **The words are inset like a heading; the surface is not.** The
            // block sits in the cards' column (`VPNSettingsPage.heroAndTitle`),
            // and the words go back in by `HelmLayout.groupedHeaderOutset`. A
            // negative padding on the readings alone would draw nothing:
            // `.clipped()` at the root takes it back.
            .padding(.horizontal, HelmLayout.groupedHeaderOutset)
            readings(strip)
        }
        .frame(maxWidth: .infinity)
    }

    /// The verdict at the size a page's own state is set in, and one caption
    /// under it: the country and the exclusions on one line, joined by
    /// `VPNStr.note`'s dot.
    ///
    /// **No glyph beside the verdict.** It would carry colour and nothing else,
    /// and push the sentence off the caption's axis.
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

    /// **The verbs, as capsules in a centred row**, the shape `KeepAwakeHero`
    /// gives its presets. A tunnel not carrying the traffic has no button; its
    /// sentence goes under the row, because a paragraph among capsules is not a
    /// capsule.
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
                        // wait is**: about the wait, not the measurement, which
                        // reports nothing until it is over. Same slot as the
                        // spinner, so the row does not move.
                        HelmExpectedWait(started: measureStarted,
                                         expected: strip.expectedWait)
                        Text(word)
                            .helmQuietDetail()
                    }
                    .frame(height: Self.verbHeight)
                case .notOffered:
                    EmptyView()
                }
            }
            .helmCapsuleButtons()
            if case .notOffered(let sentence) = strip.action {
                Text(sentence)
                    .helmQuietDetail()
                    .helmHeroSentence()
            }
        }
    }

    /// **The readings as four cards**, on the kit's card surface
    /// (`helmCard`), so the page has one card system.
    private func readings(_ strip: VPNTunnelStrip) -> some View {
        // The gap the connections grid uses between its own cards, so the two
        // rows are one rhythm rather than two.
        HStack(alignment: .top, spacing: HelmSpace.s5) {
            // **Only the speed card, and only while its own run is going**: the
            // slot says a newer figure is on its way. `false` is inert
            // (`HelmMeasuringSlot`).
            ForEach(strip.tiles) { tile in
                column(tile).helmMeasuringSlot(strip.isMeasuring && tile.kind == .speed)
            }
        }
        // The row takes the height of its tallest card and no more.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }

    /// One reading, as its own card.
    ///
    /// `maxWidth: .infinity` makes the four equal in width. `maxHeight:
    /// .infinity` makes them equal in height: a long configuration name wraps
    /// one note, and under the row's `.fixedSize(vertical:)` the other three
    /// take that height, with `alignment: .top` keeping every word in place.
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
                // Wrapping rather than truncating: a cut note loses the
                // interface out of «incy · utun8».
                .fixedSize(horizontal: false, vertical: true)
        }
        // «Скорость, 343, incy · utun8» as one VoiceOver stop, the way
        // `HelmMetricStrip` reads its two.
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .helmCard(padding: HelmSpace.s5)
    }

    // MARK: - With nothing up

    /// **The idle state, in the same slot and size as `KeepAwakeHero`'s.** No
    /// mark: nothing is wrong with a Mac that has no tunnel up.
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
        // The same inset as the live state's words.
        .padding(.horizontal, HelmLayout.groupedHeaderOutset)
    }
}
