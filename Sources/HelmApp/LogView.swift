// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI
import HelmRuntime
import HelmUI
import HelmAppStrings

/// The log, while it is being written — a card for each launch of the app.
///
/// Not a diagnostics dashboard: it invents no figure and computes nothing it
/// cannot say how. It shows the lines the app already writes — the same `write`,
/// the same format, the same truth — so that watching Helm misbehave does not
/// mean leaving it, finding `~/Library/Logs/Helm` and reading what already
/// happened.
///
/// **Folded, never edited.** A launch is a card (`LogSessions`), the burst of
/// lines a launch writes while it switches its modules on is one fold, and a line
/// written again and again in a row is one row with a count. None is dropped
/// from the presentation, the footer's counts or «Copy log», which hands back
/// the lines expanded, in the file's own format (`LogPresentation.lines`). Which
/// launches are drawn is Architecture/DiagnosticsLog.md § The log pane.
///
/// Shown on every build, because this is also where the log is switched on:
/// one place for one subject.
///
/// The controls are the window's, not the page's: they live in the header row
/// of the card (`headerContent`, drawn by `helmCardHeader`), and the writing
/// switch is one line in the «More actions» menu.
struct LogView: View {
    /// Set by the settings window, where the page's header is the card's row
    /// (`helmCardHeader`) instead of one in this stack.
    @Environment(\.helmHeaderInCard) private var inCard

    /// The Settings page's tabs, when the page is shown as one of them. They
    /// take the bar's one switcher slot, and the level filter that stands there
    /// when none are handed becomes the first action, before the module filter.
    /// Nil leaves the bar as it is.
    var settingsTabs: HelmHeaderContent?

    /// Polled rather than subscribed. A log has no interesting event to observe
    /// — it has a tail — and one timer that exists while the page is on screen
    /// is cheaper to reason about than a stream that has to be finished.
    @State private var entries: [LogEntry] = []
    /// A file can appear and go without this process doing it — a rollover, a
    /// person emptying the folder — so it is re-read on the same tick the lines
    /// are, never remembered from the first read.
    @State private var hasStoredLog = false
    @State private var minimumLevel: LogLevel = .info
    @State private var chosen: Set<String> = []
    @State private var query = ""
    @State private var following = true
    /// Where the reader is, by the line (`LogReaderPlace`).
    @State private var place = LogReaderPlace()
    /// How many times `drawnAtOpen` is doubled (`drawn(rowsBefore:)`). Raised
    /// only by `LogReaderPlace.drawEarlier`, through `earlierAfterAsk`, never
    /// lowered; a filter changing does not clear it.
    @State private var earlier = 0
    /// The launches whose start-up fold is open, by the id of their first line.
    @State private var openStartups: Set<LogEntry.ID> = []
    @State private var tick: RepeatingTick?
    @State private var loggingOn = LogPolicy.isEnabled(
        isDev: AppBuild.isDev,
        override: AppSettings.loggingOverride)

    /// Read once per body: the split, the filters and the folds are one pass
    /// over at most a thousand lines, and every part of the page below — the
    /// cards, the header row's Copy, the footer, the Follow key — must see the
    /// same one.
    private var presented: LogPresentation {
        LogPresentation.build(entries, minimumLevel: minimumLevel, categories: chosen, query: query)
    }

    var body: some View {
        let page = presented
        VStack(spacing: 0) {
            // A band, not a scroll edge, so `HelmPageHeader` directly. This
            // page is a scroll view and a footer stacked, and nothing ever
            // scrolls under the band: a material there would blur nothing,
            // and the rule would be a hairline between a header and a card.
            //
            // `bleeds: true` like every other full-width page: without it the
            // header caps at `HelmLayout.settingsColumn` and centres, out of
            // line with the rows.
            //
            // In the settings window the header is the card's row
            // (`helmCardHeader`), and this row is not drawn at all.
            if !inCard {
                HelmPageHeader(symbol: "text.alignleft", tint: ModuleTint.hostColour,
                               title: AppStr.logPane,
                               bleeds: true, standsOnStillContent: true)
            }
            lines(page)
            Divider()
            footer(page)
        }
        // The same fact as `standsOnStillContent:` above, for the card's row:
        // `helmPageBar` is applied to the outer stack, with the scroll view
        // several levels inside it, so the scroll trigger can never fire here.
        // The card's row is drawn at the pane's root, a view away, so it hears
        // through a preference.
        .helmPageStandsOnStillContent()
        .helmPageBar(title: AppStr.settingsPane)
        // Declared unconditionally: this page's shape never changes.
        .helmHeaderContent(headerContent(page))
        .onAppear {
            refresh()
            // One second: the log is read, not animated.
            let made = RepeatingTick(interval: 1) { refresh() }
            tick = made
            made.set(active: true)
        }
        .onDisappear {
            tick?.set(active: false)
            tick = nil
        }
    }

    // MARK: - The header row's controls

    /// The three levels by id. One declaration, so the header row's segments, the
    /// level menu's items and the filter they set cannot disagree.
    private static var levelTabs: [(id: String, level: LogLevel, title: String, symbol: String)] {
        [("all", .info, AppStr.logLevelAll, "list.bullet"),
         ("warn", .warn, AppStr.logLevelWarnings, "exclamationmark.triangle"),
         ("error", .error, AppStr.logLevelErrors, "xmark.octagon")]
    }

    /// The level in force, as one of the three.
    private var levelInForce: (id: String, level: LogLevel, title: String, symbol: String) {
        Self.levelTabs.first { $0.level == minimumLevel } ?? Self.levelTabs[0]
    }

    /// **What the page asks of the header row**, in one place:
    /// `levelHeaderContent` as it stands when no tabs were handed; with
    /// `settingsTabs`, those tabs and the level as the first action.
    private func headerContent(_ page: LogPresentation) -> HelmHeaderContent {
        var content = levelHeaderContent(page)
        guard let settingsTabs else { return content }
        content.tabs = settingsTabs.tabs
        content.selectedTab = settingsTabs.selectedTab
        content.actions.insert(levelAction, at: 0)
        return content
    }

    /// The level filter as an action: its title is the level in force, its
    /// items are the three levels, the same words the tabs say.
    private var levelAction: HelmHeaderAction {
        HelmHeaderAction(
            id: "level",
            title: levelInForce.title,
            symbol: "list.bullet",
            menu: Self.levelTabs.map { tab in
                HelmHeaderMenuItem(id: tab.id, title: tab.title,
                                    isOn: tab.level == minimumLevel) { minimumLevel = tab.level }
            })
    }

    /// The level as the tabs, then the actions — module filter, Follow,
    /// Copy and the «More actions» menu — and the search.
    ///
    /// Follow is a toggle with a face: its state is its glyph (an open eye when
    /// following, a slashed one when not) and never a tint, because a state
    /// carried by colour alone is not read by everyone. Its word is in the
    /// tooltip and the accessibility label, and what it is doing is the
    /// accessibility value.
    private func levelHeaderContent(_ page: LogPresentation) -> HelmHeaderContent {
        HelmHeaderContent(
            tabs: Self.levelTabs.map { HelmHeaderTab(id: $0.id, title: $0.title, symbol: $0.symbol) },
            selectedTab: Binding(
                get: { levelInForce.id },
                set: { id in minimumLevel = Self.levelTabs.first { $0.id == id }?.level ?? .info }),
            actions: [
                // Built from what has arrived, so it names the modules that
                // spoke rather than every one that exists. A line with no module
                // (an unreadable one) has no entry of its own here: it is not
                // something to filter *to*.
                HelmHeaderAction(id: "modules",
                                  title: chosen.isEmpty ? AppStr.logAllModules
                                                        : AppStr.logSomeModules(chosen.count),
                                  symbol: "line.3.horizontal.decrease",
                                  menu: [HelmHeaderMenuItem(id: "all", title: AppStr.logAllModules,
                                                             isOn: chosen.isEmpty) { chosen = [] }]
                                    + LogFilter.categories(in: entries).filter { !$0.isEmpty }.map { category in
                                        HelmHeaderMenuItem(id: category, title: category,
                                                            isOn: chosen.contains(category)) {
                                            chosen.formSymmetricDifference([category])
                                        }
                                    }),
                HelmHeaderAction(id: "follow", title: AppStr.logFollow,
                                  symbol: "eye", isOn: following,
                                  face: HelmHeaderToggleFace(offSymbol: "eye.slash",
                                                              onValue: AppStr.logFollowing,
                                                              offValue: AppStr.logNotFollowing)) {
                    following.toggle()
                },
                HelmHeaderAction(id: "copy", title: AppStr.copyLog, symbol: "doc.on.doc",
                                  isEnabled: !page.lines.isEmpty) {
                    NSPasteboard.general.clearContents()
                    // The lines in the file's own format: a second format here
                    // would drop the level, the date or the source site.
                    NSPasteboard.general.setString(LogLine.lines(page.lines), forType: .string)
                },
                // Whether anything is written to the file at all, and what ends
                // up in it. Dev builds always log — the file is the evidence a
                // build is triaged on — so the switch is theirs to read, not to
                // change.
                HelmHeaderAction(id: "more", title: HelmA11y.moreActions, symbol: "ellipsis", menu: [
                    HelmHeaderMenuItem(id: "write", title: AppStr.writeLog, isOn: loggingOn,
                                        isEnabled: !AppBuild.isDev) {
                        let on = !loggingOn
                        loggingOn = on
                        AppSettings.loggingOverride = on
                        HelmLog.shared.setEnabled(on)
                    },
                    HelmHeaderMenuItem(id: "reveal", title: HelmWord.showInFinder, isOn: false) {
                        HelmReveal.inFinder(HelmLog.fileURL.path)
                    },
                    HelmHeaderMenuItem(id: "clear", title: HelmWord.clear, isOn: false,
                                        // The file, not the page: with logging
                                        // off the tail is empty and the log on
                                        // disk is what a person wants gone.
                                        isEnabled: !entries.isEmpty || hasStoredLog) {
                        // Both: Clear means the log, not the window onto it.
                        HelmLog.shared.clear()
                        HelmLog.shared.clearTail()
                        entries = []
                        hasStoredLog = false
                    },
                ]),
            ],
            search: HelmHeaderQuery(prompt: AppStr.logSearch, text: $query))
    }

    // MARK: - The cards

    /// The zero-height end of the list, what Follow scrolls to. Below the last
    /// card and above the page's own bottom padding, so «at the end» is the
    /// padding's height and no more.
    private static let endMarker = "helm.log.end"

    /// What the person chose to see; a change of it is a different page, and the
    /// reader's line is not held across it (`LogReaderPlace.forget`).
    private struct FilterKey: Equatable {
        let level: LogLevel
        let chosen: Set<String>
        let query: String
    }

    /// What the follow rule watches; see the handler in `lines`.
    private struct FollowKey: Equatable {
        let following: Bool
        let first: LogEntry.ID?
        let last: LogEntry.ID?
        let count: Int
    }

    /// The folder this build's log really lives in (`HelmLog.fileURL`), home as `~`.
    private static var logFolder: String {
        (HelmLog.fileURL.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }

    @ViewBuilder private func lines(_ page: LogPresentation) -> some View {
        if page.isEmpty {
            // No symbol: the header already draws this mark, and
            // `HelmEmptyState`'s rule is that a statement is a sentence alone.
            HelmEmptyState(message: entries.isEmpty ? AppStr.logEmpty : AppStr.logNothingMatches,
                           note: entries.isEmpty && !loggingOn && !AppBuild.isDev
                               ? AppStr.logNoteStableAt(Self.logFolder) : nil) {
                if !entries.isEmpty {
                    Button(AppStr.logAllModules) {
                        chosen = []
                        minimumLevel = .info
                        query = ""
                    }
                }
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: HelmSpace.s5) {
                        ForEach(page.drawn(rowsBefore: Self.drawnAtOpen << earlier)) { card in
                            cardView(card)
                        }
                        Color.clear.frame(height: 0).id(Self.endMarker)
                    }
                    .helmPageStrip()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .coordinateSpace(.named(Self.contentSpace))
                }
                .onScrollGeometryChange(for: LogReaderPlace.Metrics.self) { geometry in
                    LogReaderPlace.Metrics(top: geometry.visibleRect.minY,
                                           visibleHeight: geometry.visibleRect.height,
                                           contentHeight: geometry.contentSize.height)
                } action: { _, now in
                    place.scrolled(now)
                }
                // The end is held by the scroll view, not scrolled to once: a
                // lazy card's rows make the page's height an estimate until
                // they are drawn, so a `scrollTo` lands short once they are
                // measured. Anchoring the bottom for size changes too keeps the
                // end under a view that was at it. Set only while Follow is
                // lit; a reader scrolled up is held by the line they read
                // (`LogReaderPlace`). `.alignment` is left alone, so a short
                // log still sits at the top of its pane.
                .defaultScrollAnchor(following ? .bottom : nil, for: .initialOffset)
                .defaultScrollAnchor(following ? .bottom : nil, for: .sizeChanges)
                // One rule for every road: while Follow is lit and what is
                // shown changes, or Follow turns on, the view goes to the end
                // of the newest card. Keyed on the newest line's identity,
                // never the count alone: once `LogTail` is full the count is
                // constant. The oldest identity and the count are in the key
                // because a filter can change what is shown and leave the
                // newest line the same.
                .onChange(of: FilterKey(level: minimumLevel, chosen: chosen, query: query)) { _, _ in
                    place.forget()
                }
                .onChange(of: FollowKey(following: following, first: page.cards.first?.id,
                                        last: page.newestID, count: page.lines.count)) { _, _ in
                    guard following, !page.isEmpty else { return }
                    place.seekTheEnd()
                    proxy.scrollTo(Self.endMarker, anchor: .bottom)
                    // A second time on the next turn, and `place` asks for the end
                    // again after each quiet period until the view is at it (or
                    // gives up after `LogReaderPlace.attempts`): the anchor above
                    // holds the end only for a view that was at it. Whether
                    // Follow is still lit is read inside the hop, because a
                    // person may have turned it off in between.
                    DispatchQueue.main.async {
                        guard following else { return }
                        proxy.scrollTo(Self.endMarker, anchor: .bottom)
                    }
                }
                // The other half: this reader is mounted by the first read
                // that brings a line, so the lines were already here when it
                // appeared and `onChange` has nothing to report for them. The
                // anchor above is what makes the open exact; this is the first
                // landing, which the anchor then corrects as rows are measured.
                .onAppear {
                    place.following = { following }
                    place.scrollToLine = { proxy.scrollTo($0, anchor: UnitPoint(x: 0, y: $1)) }
                    place.scrollToEnd = { proxy.scrollTo(Self.endMarker, anchor: .bottom) }
                    // Read when it is asked, not when it is set: a closure that
                    // held this `onAppear`'s values would answer from them for
                    // ever. The presentation is built once per ask, at rest.
                    place.drawEarlier = {
                        if let next = Self.earlierAfterAsk(earlier, in: presented) { earlier = next }
                    }
                    guard following, !page.isEmpty else { return }
                    place.seekTheEnd()
                    proxy.scrollTo(Self.endMarker, anchor: .bottom)
                }
            }
        }
    }

    /// One launch: what it was and how it went, then its lines.
    ///
    /// The card is the house's card (`helmCard`) with no padding of its own and
    /// clipped to its corners, so a row's wash reaches the card's edge instead
    /// of a rounded corner's.
    ///
    /// The rows are lazy above `lazyAbove` of them, which is why Follow's
    /// landing is held by the scroll view (the anchor in `lines`).
    private func cardView(_ card: LogPresentation.Card) -> some View {
        let burstLines = card.startup.reduce(0) { $0 + $1.repeats }
        let open = Self.startupIsOpen(card.id, opened: openStartups, query: query)
        return VStack(alignment: .leading, spacing: 0) {
            cardHeader(card)
            if burstLines > 0 { startupFold(card, lines: burstLines, open: open) }
            if !card.rows.isEmpty || (open && burstLines > 0) { Divider() }
            if open && burstLines > 0 {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(card.startup) { tracked($0, LogRowView(row: $0).equatable()) }
                }
                .padding(.vertical, HelmSpace.s3)
                if !card.rows.isEmpty { Divider() }
            }
            if !card.rows.isEmpty {
                let rows = ForEach(card.rows) { row in
                    if let heading = row.heading { dayHeader(heading) }
                    tracked(row, LogRowView(row: row).equatable())
                }
                Group {
                    if card.rows.count > Self.lazyAbove {
                        LazyVStack(alignment: .leading, spacing: 0) { rows }
                    } else {
                        VStack(alignment: .leading, spacing: 0) { rows }
                    }
                }
                .padding(.vertical, HelmSpace.s3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .helmCard(padding: 0)
        .clipShape(RoundedRectangle(cornerRadius: HelmRadius.card, style: .continuous))
    }

    /// How many rows a card draws plainly before it draws them lazily. A plain
    /// stack's heights are all measured, so `LogReaderPlace` can hold the reader
    /// to a line; a lazy stack estimates what the view has scrolled past. Lazy
    /// is what makes a thousand rows cheap, so it stays for the card too large
    /// to draw whole. Chosen, not measured; the bound it sets with
    /// `drawnAtOpen` is Architecture/DiagnosticsLog.md § The log pane.
    static let lazyAbove = 400

    /// How many rows the launches before the newest hold, at least, when the
    /// page opens (`LogPresentation.drawn(rowsBefore:)`): a threshold reached or
    /// passed, since launches are added whole. Chosen, not measured: it keeps
    /// the rows laid out at open from growing with the log. Each doubling of it
    /// (`earlier`) is a step of an ask for earlier launches.
    static let drawnAtOpen = 100

    /// What `earlier` becomes when the reader asks for earlier launches: the
    /// nearest count above it at which `page` draws a launch more. Nil when every
    /// launch is drawn already, and then nothing is written, so an ask with
    /// nothing to give does not redraw the page.
    ///
    /// A doubling that adds no launch is stepped over, never written: a page
    /// that drew nothing new would not move, nothing would rest, and nothing
    /// would ask again, leaving a reader at a top that is not the log's. The
    /// loop ends because `drawn(rowsBefore:)` never draws fewer with a larger
    /// figure and draws every launch once the figure passes the page's rows.
    /// `drawnAtOpen << next` stays positive up to 56, and `earlier` is written
    /// only with this function's answers, so it never gets that far.
    static func earlierAfterAsk(_ earlier: Int, in page: LogPresentation) -> Int? {
        let now = page.drawn(rowsBefore: drawnAtOpen << earlier).count
        guard now < page.cards.count else { return nil }
        var next = earlier + 1
        while page.drawn(rowsBefore: drawnAtOpen << next).count == now { next += 1 }
        return next
    }

    /// The content's own coordinates, which the rows report their place in.
    private nonisolated static let contentSpace = "helm.log.content"

    /// A row that tells `place` where it is in the content whenever that
    /// changes, and when it is no longer drawn. A row's place moves only when the
    /// layout does — a scroll does not move it — so this is not a per-frame cost.
    private func tracked(_ row: LogPresentation.Row, _ view: some View) -> some View {
        view
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.contentSpace)) } action: { @MainActor in
                place.rowMoved(row.id, frame: $0)
            }
            .onDisappear { @MainActor in place.rowGone(row.id) }
            .id(row.id)
    }

    /// Whether a launch's start-up fold is drawn open: pressed open, or held open
    /// by a search. A search names lines, and a line inside a shut fold is a hit
    /// nobody can see — so while a word is being searched every fold is open, and
    /// closes again with the word.
    static func startupIsOpen(_ id: LogEntry.ID, opened: Set<LogEntry.ID>, query: String) -> Bool {
        opened.contains(id) || LogSearch.isActive(query)
    }

    /// What a card's header says: a heading, and a quieter detail beside it. A
    /// run that began with its own start line is named by its time, with the
    /// version beside it; the head of the tail, whose start scrolled out of it,
    /// is an *earlier* launch with the time of its first line; any other run
    /// with no start line is named by the time of its first line alone, since
    /// the file records no more (`LogCardTitle`).
    static func headerWords(for session: LogSession) -> (heading: String, detail: String?) {
        let began = HelmDates.dayAndMinute(session.lines[0].date)
        switch session.title {
        case .launch(let version): return (began, version.map { "Helm \($0)" })
        case .earlierLaunch: return (AppStr.logEarlierLaunch, began)
        case .noStartLine: return (began, nil)
        }
    }

    /// The launch's time and version, and its errors and warnings as badges.
    /// Two arrangements: on one line where
    /// the pane has the room, and the badges on a line of their own where a
    /// longer language does not.
    private func cardHeader(_ card: LogPresentation.Card) -> some View {
        let session = card.session
        let title = HStack(alignment: .firstTextBaseline, spacing: HelmSpace.s4) {
            Image(systemName: "power").foregroundStyle(HelmText.quiet).accessibilityHidden(true)
            let words = Self.headerWords(for: session)
            // The launch's name is what the rotor jumps to; the card combines
            // its header into one element, and the trait is set on the text
            // that is the heading as well as on the element.
            Text(words.heading).font(HelmText.sectionHeading)
                .accessibilityAddTraits(.isHeader)
            if let detail = words.detail {
                Text(detail).helmQuietDetail()
            }
        }
        let badges = HStack(spacing: HelmSpace.s3) {
            if card.errors > 0 {
                HelmBadge(AppStr.logErrorCount(card.errors), tint: HelmSignal.danger)
            }
            if card.warnings > 0 {
                HelmBadge(AppStr.logWarningCount(card.warnings), tint: HelmSignal.warning)
            }
        }
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: HelmSpace.s4) {
                title
                Spacer(minLength: HelmSpace.s4)
                badges
            }
            VStack(alignment: .leading, spacing: HelmSpace.s3) {
                title
                badges
            }
        }
        .padding(.horizontal, HelmSpace.s5).padding(.top, HelmSpace.s5).padding(.bottom, HelmSpace.s4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// The start-up burst as one line, opened by a press.
    ///
    /// A swap and not a reveal, on purpose: `helmAccordion` keeps its content
    /// mounted, which here would be dozens of hidden rows per launch drawn for
    /// nobody. The accordion guards an animated removal, and this one is not
    /// animated.
    private func startupFold(_ card: LogPresentation.Card, lines: Int, open: Bool) -> some View {
        Button {
            openStartups.formSymmetricDifference([card.id])
        } label: {
            HStack(spacing: HelmSpace.s4) {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(HelmText.rowDetail.weight(.semibold))
                    .frame(width: HelmLayout.markColumn)
                    .accessibilityHidden(true)
                Text(AppStr.logStartup(lines))
                    .font(HelmText.rowDetail)
                Spacer(minLength: 0)
            }
            .foregroundStyle(HelmText.quiet)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, HelmSpace.s5).padding(.bottom, HelmSpace.s4)
        .accessibilityValue(HelmA11y.expanded(open))
    }

    private func dayHeader(_ text: String) -> some View {
        Text(text)
            .font(HelmText.groupLabel).foregroundStyle(HelmText.quiet)
            .padding(.horizontal, HelmSpace.s5)
            .padding(.top, HelmSpace.s4).padding(.bottom, HelmSpace.s2)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Copy, Clear and the footer

    /// Whether the file can hold lines the page does not: the tail is full, so
    /// the oldest went to make room, and there is a file. A tail that is not full
    /// holds everything the file has, and saying «older lines are in the file» over
    /// it would be a sentence about lines that do not exist.
    static func olderLinesExist(entryCount: Int, storedLog: Bool) -> Bool {
        storedLog && entryCount >= HelmLog.tailLimit
    }

    /// Counts, and where the tail begins: «3 of 12 launches · Showing 17 of the
    /// last 46 lines · since 29.09.2026, 23:41 · older lines are in the file».
    /// Empty for an empty tail.
    static func footerCounts(_ page: LogPresentation, entries: [LogEntry],
                             storedLog: Bool) -> String {
        guard let oldest = entries.first else { return "" }
        var parts = [AppStr.logLaunches(page.cards.count, page.launchCount),
                     AppStr.logShowingLast(page.shown, entries.count),
                     AppStr.logSince(HelmDates.dayAndMinute(oldest.date))]
        if olderLinesExist(entryCount: entries.count, storedLog: storedLog) {
            parts.append(AppStr.logOlderInFile)
        }
        return parts.joined(separator: " · ")
    }

    private func footer(_ page: LogPresentation) -> some View {
        VStack(alignment: .leading, spacing: HelmSpace.s1) {
            let counts = Self.footerCounts(page, entries: entries, storedLog: hasStoredLog)
            if !counts.isEmpty {
                HelmSettingsNote(counts)
            }
            Text(AppStr.logRedactionNote)
                .font(HelmText.rowDetail).foregroundStyle(HelmText.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s4)
    }

    /// Assigns only what changed: a `@State` write re-runs the page's body
    /// whether or not the value differs, and this runs once a second.
    /// `LogEntry`'s `==` is its five parts, not the id, so a tail that says the
    /// same thing is the same tail.
    private func refresh() {
        let read = HelmLog.shared.recentEntries()
        if read != entries { entries = read }
        let stored = HelmLog.anyFileExists()
        if stored != hasStoredLog { hasStoredLog = stored }
    }
}

/// One line, or a run of identical ones — see the row's own doc below.
///
/// Equatable, so a tick that changed one line re-draws one row: a row is its
/// lines, and the same lines are the same row. The day heading rides on the
/// comparison because it depends on the row above, which a filter can change
/// without touching this row's lines.
struct LogRowView: View, Equatable {
    let row: LogPresentation.Row

    nonisolated static func == (a: LogRowView, b: LogRowView) -> Bool {
        a.row.heading == b.row.heading && a.row.repeats == b.row.repeats
            && a.row.first.id == b.row.first.id && a.row.last.id == b.row.last.id
    }

    /// One line, or a run of identical ones. The level is a wash behind the
    /// whole row and a glyph, and its word is the row's accessibility value —
    /// so it is readable without the colour alone: the glyph is the shape that
    /// says it without the colour, and the value says it aloud. The category
    /// word is not tinted: the tint says "bad", and the word says "who".
    ///
    /// No line is cut short: a page whose point is showing exactly what the
    /// file holds does not get to decide which characters matter.
    var body: some View {
        let entry = row.first
        let signal = tint(for: entry.level)
        HStack(alignment: .firstTextBaseline, spacing: HelmSpace.s4) {
            // One literal with two interpolations: `"\(a)" + "\(b)"` is String
            // concatenation and would print each `Text`'s `description`.
            Text("\(Text(HelmDates.logTime(entry.date)).foregroundStyle(HelmText.quiet))\(Text(HelmDates.logMillis(entry.date)).foregroundStyle(HelmText.faint))")
                .helmFigure()
            Image(systemName: glyph(for: entry.level) ?? "circle")
                .foregroundStyle(signal ?? .clear)
                .font(HelmText.rowDetail)
                .frame(width: HelmLayout.markColumn)
                .opacity(signal == nil ? 0 : 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: HelmSpace.s1) {
                if entry.category.isEmpty {
                    // A line this app did not write, or not all of one: whole,
                    // in the face that says it is not ours.
                    Text(entry.message)
                        .font(HelmText.rowDetail.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("\(Text(entry.category).fontWeight(.semibold).foregroundStyle(HelmText.faint))  \(Text(entry.message).foregroundStyle(entry.level == .info ? HelmText.quiet : Color.primary))")
                        .font(HelmText.rowDetail)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let site = entry.site {
                    Text("\(site.file):\(site.line)  \(site.function)")
                        .font(HelmText.rowDetail.monospaced()).foregroundStyle(HelmText.faint)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
            if row.repeats > 1 {
                HelmBadge("×\(Count(row.repeats))", tint: signal ?? HelmBadge.neutralTint)
                    .help(Self.repeatedUntilNote(row))
            }
        }
        .padding(.vertical, HelmSpace.s1)
        .padding(.horizontal, HelmSpace.s5)
        // The wash fills the row and reaches its edges; no coloured bar at the
        // left edge: the fill and the glyph already say it.
        .background {
            if let signal { signal.opacity(HelmSurface.rowWashOpacity) }
        }
        .accessibilityElement(children: .combine)
        // The row's marks of severity are a wash and a glyph, and a combined
        // element has neither. Empty for an ordinary line: see
        // `logLevelWord`.
        .accessibilityValue(AppStr.logLevelWord(entry.level) ?? "")
    }

    /// When the last repeat was written: the time, and the day too when the run
    /// crossed midnight — a time alone would put the last repeat on the first
    /// one's day.
    static func repeatedUntil(_ row: LogPresentation.Row, calendar: Calendar = .current) -> String {
        calendar.isDate(row.first.date, inSameDayAs: row.last.date)
            ? HelmDates.logTime(row.last.date) : HelmDates.dayAndMinute(row.last.date)
    }

    /// The tooltip of the ×N badge: «Repeated until 03:01:40», or — when the run
    /// crossed midnight — «Repeated until 22.09.2026, 03:01», each its own
    /// sentence because the languages that put an article before a date do not
    /// put one before a time.
    static func repeatedUntilNote(_ row: LogPresentation.Row, calendar: Calendar = .current) -> String {
        let until = repeatedUntil(row, calendar: calendar)
        return calendar.isDate(row.first.date, inSameDayAs: row.last.date)
            ? AppStr.logRepeatedUntil(until) : AppStr.logRepeatedUntilDay(until)
    }

    /// Nil for an ordinary line, so an info row gains no layers at all.
    private func tint(for level: LogLevel) -> Color? {
        switch level {
        case .info: return nil
        case .warn: return HelmSignal.warning
        case .error: return HelmSignal.danger
        }
    }

    private func glyph(for level: LogLevel) -> String? {
        switch level {
        case .info: return nil
        case .warn: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}
