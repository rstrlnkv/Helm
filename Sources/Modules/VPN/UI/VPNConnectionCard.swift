// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI
import HelmRuntime
import HelmUI
import Module_VPN_Engine

/// One configuration, with two doors: the applications that raise it, and how
/// loudly it speaks.
///
/// **Its own view because a popover needs somewhere to live**: `.popover` is
/// presented from `@State`, and a card built by a function would keep «which
/// card is open» on the page.
///
/// **The two doors are one height by construction** (`doorHeight`).
struct VPNConnectionCard: View {
    let connection: VPNConnection
    /// Who raises this tunnel, already capped (`VPNTenants`).
    let strip: VPNTenants.Strip
    /// The timing of each application in the strip, for the popover's rows.
    let timings: [String: VPNAppRule.Timing]
    /// Which of those rules will not fire, and why — the engine's own verdicts
    /// (`VPNEngine.StatePayload.ruleRefusals`); a trusted rule is absent.
    let refusals: [String: VPNRuleTrust.Verdict]
    /// Whether this tunnel is up **and** Helm's own doing.
    let heldByHelm: Bool
    /// What this configuration announces, resolved through `VPNNoticeBook`, so
    /// a card with no entry of its own shows what it inherits.
    let notice: VPNNotice
    let dropNotice: VPNNotice
    let spin: Bool
    /// The colour the ring turns for this configuration, per direction,
    /// resolved through the book the same way.
    let tintUp: String
    let tintDown: String
    /// What macOS last said about banners. **Not a `Bool`**: «nobody has asked
    /// this launch» and «asked and refused» are different states, and only the
    /// second is worth a sentence (`VPNNotice.permissionMissing`).
    let bannerAuthorization: NoticeAuthorization?
    /// Where else a rule under this card could point.
    let elsewhere: [String]

    let connect: () -> Void
    let disconnect: () -> Void
    let addApp: () -> Void
    let setTiming: (String, VPNAppRule.Timing) -> Void
    let move: (String, String) -> Void
    let remove: (String) -> Void
    // `@MainActor @Sendable` on these three only: they go straight to
    // `Binding(get:set:)`, whose `set` is `@isolated(any) @Sendable`, and an
    // ordinary function value converted to it warns.
    let setNotice: @MainActor @Sendable (VPNNotice) -> Void
    let setDropNotice: @MainActor @Sendable (VPNNotice) -> Void
    let setSpin: @MainActor @Sendable (Bool) -> Void
    let setTint: (VPNAutomation.Kind, String) -> Void

    @Environment(\.helmTraits) private var traits
    @State private var showingRules = false
    @State private var showingNotices = false

    /// An application's icon, in a door and in a row of the rules popover.
    private static let appIcon: CGFloat = 22
    /// The verb button's circle.
    private static let verbCircle: CGFloat = 28
    /// One height for both doors' labels: the app icon's, the tallest thing
    /// either holds.
    private static let doorHeight = appIcon
    /// The least an application's name is given in the rules popover.
    private static let nameMinimum: CGFloat = 100
    /// The row menu's width in the rules popover.
    private static let menuWidth: CGFloat = 18
    /// The least a mode or timing pop-up takes (`HelmPickerWidth`).
    private static let pickerMinimum: CGFloat = 150
    /// **The picture beside one question**, at the proportion every notice
    /// preview is drawn at (104 : 66), so it does not take the question's room.
    static let noticeThumbnail = CGSize(width: 104, height: 66)

    /// The width both mode pop-ups take, in one language.
    ///
    /// **`fittingSymbolled`, because the items carry a glyph** (`VPNNoticeGlyph`)
    /// and plain arithmetic is a symbol column short.
    ///
    /// Language-taking, so a test can measure all eight.
    static func modeWidth(language: AppLanguage = AppLanguage.current) -> CGFloat {
        HelmPickerWidth.fittingSymbolled(
            VPNNotice.allCases.map { VPNStr.noticeOption($0, language: language) },
            minimum: pickerMinimum)
    }
    /// **The timing pop-up's own width, and the popover's from it.**
    /// `HelmPickerWidth` answers what the labels need, so no language
    /// truncates; the popover holds a row of them with `nameMinimum` left for
    /// the application's name. Both popovers are one width: two widths would
    /// read as two unrelated windows.
    private static var timingWidth: CGFloat {
        HelmPickerWidth.fitting(VPNAppRule.Timing.allCases.map { VPNStr.ruleTiming($0) },
                                minimum: pickerMinimum)
    }
    private static var popoverWidth: CGFloat {
        // padding · icon · gap · name · gap · pop-up · gap · menu
        HelmSpace.s5 * 2 + appIcon + HelmSpace.s4 + nameMinimum + HelmSpace.s4 + timingWidth
            + HelmSpace.s4 + menuWidth
    }
    /// The tallest the rules popover grows before it scrolls.
    private static let rulesCeiling: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s4) {
            header
            state
            Divider()
            doors
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .helmCard(padding: HelmSpace.s5)
    }

    // MARK: - What the card says without being opened

    /// **`isConnected`, not `isUp`**: `isUp` includes `.connecting`, and a
    /// green mark three seconds into a handshake says the Mac is protected
    /// while it is not (`VPNStatus.isConnected`).
    static func lit(_ connection: VPNConnection) -> Bool { connection.status.isConnected }

    private var header: some View {
        HStack(spacing: HelmSpace.s4) {
            HelmStatusDot(active: Self.lit(connection))
            Text(connection.name).font(HelmText.sectionHeading)
                .lineLimit(1)
                .help(connection.name)
            Spacer(minLength: HelmSpace.s2)
            verb
        }
    }

    private var verb: some View {
        let action = VPNCardAction.of(connection.status)
        let word = VPNStr.cardWord(action.word)
        return Button {
            switch action.verb {
            case .connect: connect()
            case .disconnect: disconnect()
            }
        } label: {
            Image(systemName: VPNCardGlyph.of(action))
                .font(HelmText.sectionHeading)
                .foregroundStyle(Self.lit(connection)
                                 ? HelmSignal.success(increased: traits.increasedContrast) : HelmText.quiet)
                .frame(width: Self.verbCircle, height: Self.verbCircle)
                .background(Circle().fill(HelmSurface.onPanelFill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!action.enabled)
        .help(word)
        .accessibilityLabel("\(word), \(connection.name)")
    }

    private var state: some View {
        HStack(spacing: HelmSpace.s3) {
            if let kind = prettyKind(connection.kind) { HelmBadge(kind).fixedSize() }
            Text(heldByHelm ? VPNStr.groupHeldByRules : VPNStr.status(connection.status))
                .helmQuietDetail()
                .lineLimit(1)
        }
    }

    // MARK: - The two doors

    private var doors: some View {
        HStack(spacing: HelmSpace.s4) {
            rulesDoor
            Spacer(minLength: HelmSpace.s4)
            noticesDoor
        }
    }

    /// The left door wears the tenants, so the card answers «who raises this»
    /// closed.
    private var rulesDoor: some View {
        Button { showingRules = true } label: {
            HStack(spacing: HelmSpace.s3) {
                if strip.total == 0 {
                    Image(systemName: "app.badge.checkmark").font(HelmText.rowDetail)
                        .foregroundStyle(HelmText.faint)
                    Text(VPNStr.noRulesYet).font(HelmText.rowDetail)
                        .foregroundStyle(HelmText.faint)
                } else {
                    ForEach(strip.shown, id: \.self) { bundleID in
                        Image(nsImage: AppInfo.resolve(bundleID).icon)
                            .resizable().frame(width: Self.appIcon, height: Self.appIcon)
                            .accessibilityHidden(true)
                    }
                    if strip.overflow > 0 {
                        Text("+\(strip.overflow)").helmQuietDetail()
                            .frame(width: Self.appIcon, height: Self.appIcon)
                            .background(Circle().fill(HelmSurface.onPanelFill))
                    }
                }
                chevron
            }
            .frame(minHeight: Self.doorHeight)
        }
        .helmChosen(showingRules)
        .help(VPNStr.rulesFor(connection.name))
        .accessibilityLabel(VPNStr.rulesFor(connection.name))
        .popover(isPresented: $showingRules, arrowEdge: .bottom) { rulesPopover }
    }

    /// The right door wears the mode it is set to, so the card says how loudly
    /// it speaks without being opened either.
    private var noticesDoor: some View {
        Button { showingNotices = true } label: {
            HStack(spacing: HelmSpace.s3) {
                Image(systemName: VPNNoticeGlyph.of(notice)).font(HelmText.rowDetail)
                chevron
            }
            .foregroundStyle(HelmText.quiet)
            .frame(minHeight: Self.doorHeight)
        }
        .helmChosen(showingNotices)
        .help(VPNStr.noticesFor(connection.name))
        .accessibilityLabel(VPNStr.noticesFor(connection.name))
        .popover(isPresented: $showingNotices, arrowEdge: .bottom) { noticesPopover }
    }

    private var chevron: some View {
        Image(systemName: "chevron.down")
            .font(HelmText.smallPrint.weight(.semibold))
            .foregroundStyle(HelmText.separator)
            .accessibilityHidden(true)
    }

    // MARK: - The rules popover

    /// Not `private`: a popover is a window macOS orders in, so the bench
    /// cannot photograph one through the door and mounts this same view
    /// directly.
    var rulesPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            popoverTitle(VPNStr.rulesFor(connection.name))
            // **Every rule, not the four the door wears**: «and 7 more» behind
            // a door somebody just opened is the door refusing to open.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(strip.all.enumerated()), id: \.offset) { index, bundleID in
                        if index > 0 { Divider() }
                        ruleRow(bundleID)
                    }
                }
            }
            .frame(maxHeight: Self.rulesCeiling)
            .fixedSize(horizontal: false, vertical: strip.all.count < 6)
            Divider()
            Button(action: addApp) {
                HStack(spacing: HelmSpace.s4) {
                    Image(systemName: "plus").frame(width: Self.appIcon, height: Self.appIcon)
                    Text(VPNStr.addApp)
                    Spacer(minLength: HelmSpace.s4)
                }
                .foregroundStyle(Color.accentColor)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, HelmSpace.s5).padding(.vertical, HelmSpace.s3)
        }
        .frame(width: Self.popoverWidth, alignment: .leading)
    }

    private func ruleRow(_ bundleID: String) -> some View {
        let info = AppInfo.resolve(bundleID)
        let timing = timings[bundleID] ?? .launchAndQuit
        let note = refusals[bundleID].flatMap { VPNStr.ruleWillNotFire($0) }
        return VStack(alignment: .leading, spacing: HelmSpace.s2) {
            HStack(spacing: HelmSpace.s4) {
                Image(nsImage: info.icon).resizable().frame(width: Self.appIcon, height: Self.appIcon)
                    .accessibilityHidden(true)
                Text(info.name).font(HelmText.rowTitle).lineLimit(1)
                Spacer(minLength: HelmSpace.s4)
                Picker("\(info.name) — \(VPNStr.rulePickerWhen)", selection: Binding(
                    get: { timing },
                    set: { setTiming(bundleID, $0) })) {
                    ForEach(VPNAppRule.Timing.allCases, id: \.self) { option in
                        Text(VPNStr.ruleTiming(option)).tag(option)
                    }
                }
                .labelsHidden()
                // Trailing, because a macOS pop-up hugs its title inside the width it
                // is given.
                .frame(width: Self.timingWidth, alignment: .trailing)
                rowMenu(bundleID, appName: info.name)
            }
            // Under the whole row, indented past the icon: the name column is the
            // narrowest thing in it, and a sentence there wraps to a word a line.
            if let note {
                // The kit's banner voice (`HelmBanner`, compact): the mark carries the
                // signal, the words carry the meaning in `quiet`.
                HStack(alignment: .firstTextBaseline, spacing: HelmSpace.s3) {
                    Image(systemName: "exclamationmark.triangle.fill").font(HelmText.rowDetail)
                        .foregroundStyle(HelmSignal.warning(increased: traits.increasedContrast))
                        .accessibilityHidden(true)
                    HelmSettingsNote(note)
                }
                .padding(.leading, Self.appIcon + HelmSpace.s4)
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, HelmSpace.s5)
        .padding(.vertical, HelmSpace.s3)
        // One rule for VoiceOver: the name, then why it will not fire. The pop-up and
        // the menu keep their own labels, reached inside the row.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(note.map { "\(info.name), \($0)" } ?? info.name)
    }

    /// Move and remove, named with the application it acts on.
    private func rowMenu(_ bundleID: String, appName: String) -> some View {
        HelmRowMenu(subject: appName) {
            if !elsewhere.isEmpty {
                Menu(VPNStr.moveRule) {
                    ForEach(elsewhere, id: \.self) { name in
                        Button(name) { move(bundleID, name) }
                    }
                }
            }
            Button(VPNStr.removeRule, role: .destructive) { remove(bundleID) }
        }
    }

    // MARK: - The notices popover

    /// **Two questions, two pictures, one right edge.** Each picture shows the
    /// mode its question is *set to*; the other modes are words in the pop-up.
    private var noticesPopover: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s5) {
            popoverTitle(VPNStr.noticesFor(connection.name))
                .padding(.horizontal, -HelmSpace.s5)
            noticeChoice(VPNStr.noticeRuleLabel, selection: notice, set: setNotice)
            noticeChoice(VPNStr.noticeDropLabel, selection: dropNotice, set: setDropNotice)

            // **Once for the popover, for both questions**, so the same
            // sentence never stands twice (`permissionMissing`).
            if VPNNotice.permissionMissing(among: [notice, dropNotice],
                                           authorization: bannerAuthorization) {
                HelmPermissionNote(text: VPNStr.noticeDenied,
                                   openSettings: PermissionCheck.openNotificationSettings)
            }
            Divider()
            // `HelmSettingRow`: a label on the left and its control flush
            // right, the rhythm of every settings card.
            HelmSettingRow(VPNStr.spinLabel) {
                Toggle("", isOn: Binding(get: { spin }, set: setSpin))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel(VPNStr.spinLabel)
            }
            // **The two colours, under the switch that gives them meaning.**
            // Disabled rather than removed while the ring is off, so the
            // popover's height does not change with an unrelated setting.
            HelmSettingRow(VPNStr.spinConnected) {
                HelmPaletteSwatches(VPNStr.spinConnected, selection: tintUp) {
                    setTint(.connected, $0)
                }
                .disabled(!spin)
            }
            HelmSettingRow(VPNStr.spinDisconnected) {
                HelmPaletteSwatches(VPNStr.spinDisconnected, selection: tintDown) {
                    setTint(.disconnected, $0)
                }
                .disabled(!spin)
            }
            // This card's ring off and its notice silent is a rule that fires
            // with no sign at all.
            if !spin, notice == .silent {
                Text(VPNStr.spinSilentWarning)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmSignal.warning(increased: traits.increasedContrast))
                    .fixedSize(horizontal: false, vertical: true)
            }
            // A step below `HelmText.rowDetail`: this note is under the whole
            // popover and must not compete with any label in it.
            Text(VPNStr.onlyThisConnection)
                .font(HelmText.smallPrint).foregroundStyle(HelmText.quiet)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(HelmSpace.s5)
        .frame(width: Self.popoverWidth, alignment: .leading)
    }

    /// One question: the picture of the mode it is set to, its label, its pop-up.
    private func noticeChoice(_ title: String, selection: VPNNotice,
                              set: @escaping @MainActor @Sendable (VPNNotice) -> Void)
    -> some View {
        HStack(alignment: .center, spacing: HelmSpace.s5) {
            NoticePreview.of(selection)
                .frame(width: Self.noticeThumbnail.width, height: Self.noticeThumbnail.height)
                .helmPreviewEdge()
                .accessibilityHidden(true)   // the pop-up beside it says the mode
            VStack(alignment: .trailing, spacing: HelmSpace.s3) {
                Text(title).font(HelmText.rowTitle)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Picker(title, selection: Binding(get: { selection }, set: set)) {
                    ForEach(VPNNotice.allCases, id: \.self) { mode in
                        Label(VPNStr.noticeOption(mode),
                              systemImage: VPNNoticeGlyph.of(mode)).tag(mode)
                    }
                }
                .labelsHidden()
                // **A named width, not `fixedSize`**: a pop-up sizes to its
                // widest item anyway; the frame gives the number a name. Trailing,
                // because a pop-up hugs its title inside its width.
                .frame(width: Self.modeWidth(), alignment: .trailing)
                .accessibilityLabel(title)
            }
        }
    }

    private func popoverTitle(_ text: String) -> some View {
        HStack {
            Text(text).font(HelmText.sectionHeading).lineLimit(1)
            Spacer(minLength: HelmSpace.s4)
        }
        .padding(.horizontal, HelmSpace.s5)
        .padding(.top, HelmSpace.s5)
        .padding(.bottom, HelmSpace.s3)
    }

    private func prettyKind(_ raw: String?) -> String? {
        guard let raw else { return nil }
        for k in ["L2TP", "IKEv2", "IPSec", "WireGuard", "PPTP"] where raw.contains(k) { return k }
        return raw.split(separator: ":").first.map(String.init)
    }
}
