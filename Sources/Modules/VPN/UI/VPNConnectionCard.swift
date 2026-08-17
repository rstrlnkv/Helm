// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI
import HelmRuntime
import HelmUI
import Module_VPN_Engine

/// One configuration, with two doors: the applications that raise it, and how
/// loudly it speaks.
///
/// **Its own view because a popover needs somewhere to live.** The page draws
/// these in a grid and a `.popover` is presented from `@State`; a card built by
/// a function on the page would have had to keep «which card is open» on the
/// page, which is a second thing to keep in step with the card that is asking.
///
/// **The two doors are one height by construction.** `doorHeight` is on the
/// container, not on the content, so a door holding four icons and a door
/// holding one glyph cannot come out different sizes — which is exactly what
/// they did when each was sized by what was inside it.
struct VPNConnectionCard: View {
    let connection: VPNConnection
    /// Who raises this tunnel, already capped (`VPNTenants`).
    let strip: VPNTenants.Strip
    /// The timing of each application in the strip, for the popover's rows.
    let timings: [String: VPNAppRule.Timing]
    /// Whether this tunnel is up **and** Helm's own doing.
    let heldByHelm: Bool
    /// What this configuration announces, resolved through `VPNNoticeBook` —
    /// so a card with no entry of its own shows what it inherits.
    let notice: VPNNotice
    let dropNotice: VPNNotice
    let spin: Bool
    /// The colour the ring turns for this configuration, per direction —
    /// resolved through the book like everything else here, so a card nobody has
    /// given a colour shows the one it inherits.
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
    let setNotice: (VPNNotice) -> Void
    let setDropNotice: (VPNNotice) -> Void
    let setSpin: (Bool) -> Void
    let setTint: (VPNAutomation.Kind, String) -> Void

    @State private var showingRules = false
    @State private var showingNotices = false

    /// One height for both doors — see the type's own note.
    private static let doorHeight: CGFloat = 30
    /// **The card the three notice labels have to fit**, and the reason it is
    /// named rather than typed at the call site: `TheNoticeLabelsFitTheCardTests`
    /// measures every language's label against it, and a number spelled twice is
    /// a number one side can change alone.
    ///
    /// Derived from the popover rather than typed, because the popover's width is
    /// itself derived (`timingWidth`) — at a typed 88 the three thumbnails ended
    /// 38 pt short of the popover's right edge, which reads as a row that failed
    /// to fill. `HelmChoiceCards` puts 12 pt between them. The height keeps the
    /// proportion the page-wide question was drawn at, 104×66.
    static var noticeThumbnail: CGSize {
        let width = ((popoverWidth - HelmSpace.s5 * 2 - 24) / 3).rounded(.down)
        return CGSize(width: width, height: (width * 66 / 104).rounded())
    }
    /// **The timing pop-up's own width, and the popover's from it.** At a typed
    /// 150 pt the Russian «При запуске и выходе» came out «При запуске и в…» —
    /// which is a control that does not say what it is set to. `HelmPickerWidth`
    /// answers what the labels need; the popover is then wide enough to hold a
    /// row of them, with 100 pt left for the application's name.
    ///
    /// The two popovers are one width: they hold the same kind of thing — a set of
    /// settings about one configuration — and two widths would read as two
    /// unrelated windows.
    private static var timingWidth: CGFloat {
        HelmPickerWidth.fitting(VPNAppRule.Timing.allCases.map { VPNStr.ruleTiming($0) },
                                minimum: 150)
    }
    private static var popoverWidth: CGFloat {
        // padding · icon · gap · name · gap · pop-up · gap · menu
        HelmSpace.s5 * 2 + 22 + HelmSpace.s4 + 100 + 10 + timingWidth + HelmSpace.s4 + 18
    }
    /// The tallest the rules popover grows before it scrolls. Somebody with
    /// eighteen rules on one tunnel gets a list, not a popover taller than the
    /// window it comes out of.
    private static let rulesCeiling: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s4) {
            header
            state
            Divider()
            doors
        }
        .padding(HelmSpace.s5)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: HelmRadius.card, style: .continuous)
            .fill(HelmSurface.wellFill))
    }

    // MARK: - What the card says without being opened

    private var header: some View {
        HStack(spacing: HelmSpace.s4) {
            HelmStatusDot(active: connection.status.isConnected)
            Text(connection.name).font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .help(connection.name)
            Spacer(minLength: 4)
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(connection.status.isConnected
                                 ? HelmSignal.success : HelmText.quiet)
                .frame(width: 28, height: 28)
                .background(Circle().fill(HelmSurface.onPanelFill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!action.enabled)
        .help(word)
        .accessibilityLabel("\(word), \(connection.name)")
    }

    private var state: some View {
        HStack(spacing: 6) {
            if let kind = prettyKind(connection.kind) { HelmBadge(kind).fixedSize() }
            Text(heldByHelm ? VPNStr.groupHeldByRules : VPNStr.status(connection.status))
                .font(HelmText.rowDetail)
                .foregroundStyle(HelmText.quiet)
                .lineLimit(1)
        }
    }

    // MARK: - The two doors

    private var doors: some View {
        HStack(spacing: HelmSpace.s4) {
            rulesDoor
            Spacer(minLength: 8)
            noticesDoor
        }
    }

    /// The left door wears the tenants, so the card answers «who raises this»
    /// closed.
    private var rulesDoor: some View {
        Button { showingRules = true } label: {
            HStack(spacing: 6) {
                if strip.total == 0 {
                    Image(systemName: "app.badge.checkmark").font(.system(size: 11))
                        .foregroundStyle(HelmText.faint)
                    Text(VPNStr.noRulesYet).font(HelmText.rowDetail)
                        .foregroundStyle(HelmText.faint)
                } else {
                    ForEach(strip.shown, id: \.self) { bundleID in
                        Image(nsImage: AppInfo.resolve(bundleID).icon)
                            .resizable().frame(width: 22, height: 22)
                            .accessibilityHidden(true)
                    }
                    if strip.overflow > 0 {
                        Text("+\(strip.overflow)").font(HelmText.rowDetail)
                            .foregroundStyle(HelmText.quiet)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(HelmSurface.onPanelFill))
                    }
                }
                chevron
            }
            .padding(.horizontal, 8)
            .frame(height: Self.doorHeight)
            .background(door(open: showingRules))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(VPNStr.rulesFor(connection.name))
        .accessibilityLabel(VPNStr.rulesFor(connection.name))
        .popover(isPresented: $showingRules, arrowEdge: .bottom) { rulesPopover }
    }

    /// The right door wears the mode it is set to, so the card says how loudly
    /// it speaks without being opened either.
    private var noticesDoor: some View {
        Button { showingNotices = true } label: {
            HStack(spacing: HelmSpace.s3) {
                Image(systemName: VPNNoticeGlyph.of(notice)).font(.system(size: 11))
                chevron
            }
            .foregroundStyle(HelmText.quiet)
            .padding(.horizontal, 8)
            .frame(height: Self.doorHeight)
            .background(door(open: showingNotices))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(VPNStr.noticesFor(connection.name))
        .accessibilityLabel(VPNStr.noticesFor(connection.name))
        .popover(isPresented: $showingNotices, arrowEdge: .bottom) { noticesPopover }
    }

    private var chevron: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(HelmText.separator)
            .accessibilityHidden(true)
    }

    private func door(open: Bool) -> some View {
        RoundedRectangle(cornerRadius: HelmRadius.ctl, style: .continuous)
            .fill(open ? Color.accentColor.opacity(0.18) : HelmSurface.onPanelFill)
    }

    // MARK: - The rules popover

    /// Not `private`, deliberately: a popover is a window macOS orders in, so the
    /// offscreen bench cannot photograph one through the door. A bench that wants
    /// to look at this mounts it directly — the same view the door presents, not a
    /// copy of it, which is the difference between measuring the screen and
    /// measuring a mock-up (ARCHITECTURE.md § VPN).
    var rulesPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            popoverTitle(VPNStr.rulesFor(connection.name))
            // **Every rule, not the four the door wears.** The cap is a width on
            // the closed card; here there is room, and «and 7 more» behind a door
            // somebody just opened is the door refusing to open.
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
                    Image(systemName: "plus").frame(width: 22, height: 22)
                    Text(VPNStr.addApp)
                    Spacer(minLength: 8)
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
        return HStack(spacing: HelmSpace.s4) {
            Image(nsImage: info.icon).resizable().frame(width: 22, height: 22)
                .accessibilityHidden(true)
            Text(info.name).font(HelmText.rowTitle).lineLimit(1)
            Spacer(minLength: 10)
            Picker("\(info.name) — \(VPNStr.rulePickerWhen)", selection: Binding(
                get: { timing },
                set: { setTiming(bundleID, $0) })) {
                ForEach(VPNAppRule.Timing.allCases, id: \.self) { option in
                    Text(VPNStr.ruleTiming(option)).tag(option)
                }
            }
            .labelsHidden()
            // Trailing, because a macOS pop-up hugs its title inside the width it
            // is given — the same reason the page's own two pickers say so.
            .frame(width: Self.timingWidth, alignment: .trailing)
            rowMenu(bundleID, appName: info.name)
        }
        .padding(.horizontal, HelmSpace.s5)
        .padding(.vertical, HelmSpace.s3)
    }

    /// Move and remove. A glyph-faced menu, so it carries its name.
    private func rowMenu(_ bundleID: String, appName: String) -> some View {
        Menu {
            if !elsewhere.isEmpty {
                Menu(VPNStr.moveRule) {
                    ForEach(elsewhere, id: \.self) { name in
                        Button(name) { move(bundleID, name) }
                    }
                }
            }
            Button(VPNStr.removeRule, role: .destructive) { remove(bundleID) }
        } label: {
            Image(systemName: "ellipsis")
                .font(HelmText.rowDetail.weight(.medium))
                .foregroundStyle(HelmText.faint)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("\(HelmA11y.moreActions), \(appName)")
    }

    // MARK: - The notices popover

    /// Mounted directly by a bench, for the reason `rulesPopover` gives.
    var noticesPopover: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s5) {
            popoverTitle(VPNStr.noticesFor(connection.name))
                .padding(.horizontal, -HelmSpace.s5)
            noticeChoice(VPNStr.noticeRuleLabel, selection: notice, set: setNotice)
            noticeChoice(VPNStr.noticeDropLabel, selection: dropNotice, set: setDropNotice)

            // **Once for the popover, and both questions are in it.** A mode
            // macOS refuses looks exactly like one it allows, and each question
            // used to ask the refusal for itself: choosing the banner for both
            // events and then revoking the permission said the same sentence
            // twice, which is the defect `permissionMissing` exists to prevent.
            if VPNNotice.permissionMissing(among: [notice, dropNotice],
                                           authorization: bannerAuthorization) {
                HelmPermissionNote(text: VPNStr.noticeDenied,
                                   openSettings: PermissionCheck.openNotificationSettings)
            }
            Divider()
            Toggle(VPNStr.spinLabel, isOn: Binding(get: { spin }, set: setSpin))
                .toggleStyle(.switch)
                .controlSize(.small)
            // **The two colours, under the switch that makes them mean
            // anything.** Disabled rather than taken away while the ring is
            // off: a row that loses its tallest control makes the popover
            // shorter on a setting that has nothing to do with its height,
            // which is the answer Keep Awake reached for the same pair.
            tint(VPNStr.spinConnected, token: tintUp, kind: .connected)
            tint(VPNStr.spinDisconnected, token: tintDown, kind: .disconnected)
            // The cost of the two quiet settings meeting, said where they meet:
            // this card's ring off and this card's notice silent is a rule that
            // fires with no sign at all.
            if !spin, notice == .silent {
                Text(VPNStr.spinSilentWarning)
                    .font(HelmText.rowDetail)
                    .foregroundStyle(HelmSignal.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(VPNStr.onlyThisConnection)
                .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(HelmSpace.s5)
        .frame(width: Self.popoverWidth, alignment: .leading)
    }

    /// The same picture question the page used to ask once for the whole module,
    /// asked here for one configuration — and it fits: three previews at 88 pt
    /// come to 288 of the popover's 298 of content.
    private func noticeChoice(_ title: String, selection: VPNNotice,
                              set: @escaping (VPNNotice) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                .fixedSize(horizontal: false, vertical: true)
            HelmChoiceCards(selection: Binding(get: { selection }, set: set),
                            items: [
                                .init(id: .silent, label: VPNStr.noticeOption(.silent),
                                      preview: NoticePreview.of(.silent)),
                                .init(id: .menuBar, label: VPNStr.noticeOption(.menuBar),
                                      preview: NoticePreview.of(.menuBar)),
                                .init(id: .system, label: VPNStr.noticeOption(.system),
                                      preview: NoticePreview.of(.system)),
                            ],
                            thumbnail: Self.noticeThumbnail)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(title)
        }
    }

    /// One palette, with its name over it rather than beside it.
    ///
    /// `HelmSettingRow` is what the page drew these in, and a row needs a label
    /// column: at the popover's width «Когда правило подключает VPN» took two
    /// lines of it and the two rows lost their baseline. The label goes above,
    /// which is the shape the two picture questions above already use — so the
    /// popover has one rhythm rather than a form's inside a popover's.
    private func tint(_ title: String, token: String,
                      kind: VPNAutomation.Kind) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
                .fixedSize(horizontal: false, vertical: true)
            HelmPaletteSwatches(title, selection: token) { setTint(kind, $0) }
                .disabled(!spin)
        }
    }

    private func popoverTitle(_ text: String) -> some View {
        HStack {
            Text(text).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 8)
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
