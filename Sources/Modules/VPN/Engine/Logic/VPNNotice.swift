// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmRuntime

/// How loudly the module says that a rule fired.
///
/// Whether the ring turns is a separate switch on each card, off by default
/// (`VPNSettings.automationSpin`): that is feedback that the app did something,
/// not a notification, and with it off the quietest mode leaves no way to tell
/// an automation from a tunnel that simply changed, which the card says
/// (`spinSilentWarning`).
public enum VPNNotice: String, CaseIterable, Codable, Sendable {
    case silent, menuBar, system

    public var showsMenuBarName: Bool { self == .menuBar }
    public var postsBanner: Bool { self == .system }

    /// What actually happens, given whether macOS let us post banners.
    ///
    /// A refused banner becomes the label, never silence: the person chose to
    /// be told loudly, and the one outcome the app must not produce is quietly
    /// not telling them. The settings row says the same thing in words.
    public func effective(bannerAuthorized: Bool) -> VPNNotice {
        self == .system && !bannerAuthorized ? .menuBar : self
    }

    /// Which of the two stored settings a firing answers to — the one rule the
    /// store reads, and the view model through the store, so nobody decides this
    /// twice.
    ///
    /// **A teardown Helm performed is announced no more quietly than a fall.**
    /// The two settings pull apart exactly where it matters: with `notice = silent` and
    /// `dropNotice = system` the person has said «tell me loudly when I lose a
    /// tunnel, quietly when a rule does as it was told» — and a tunnel taken down
    /// because a mapped app quit is a loss of protection wearing the quiet label.
    /// A quit can also be provoked by anything running as this user
    /// (`VPNRuleTrust`).
    ///
    /// Exhaustive on purpose — no `default`: a fourth kind of firing must be a
    /// build error here rather than something that silently inherits the rules'
    /// volume.
    public static func mode(for kind: VPNAutomation.Kind,
                            rules: VPNNotice, drop: VPNNotice) -> VPNNotice {
        switch kind {
        case .connected: return rules
        case .dropped: return drop
        case .disconnected: return louder(rules, drop)
        }
    }

    /// Silence, then the label, then the banner. Ordered by what a person is
    /// likelier to notice rather than by the case order, which is the same thing
    /// here and would not stay so if a mode were added.
    private var loudness: Int {
        switch self {
        case .silent: return 0
        case .menuBar: return 1
        case .system: return 2
        }
    }

    private static func louder(_ one: VPNNotice, _ other: VPNNotice) -> VPNNotice {
        one.loudness >= other.loudness ? one : other
    }

    /// Whether a card of these choices has to say that macOS is refusing them.
    ///
    /// **Asked of the card, not of a row.** The notice card decides two events,
    /// and asked per row the banner chosen for both would draw one sentence twice.
    ///
    /// `nil` is not a refusal: it means nobody has asked macOS this launch,
    /// which is what the page holds until its `.task` has run.
    public static func permissionMissing(among modes: [VPNNotice],
                                         authorization: NoticeAuthorization?) -> Bool {
        authorization == .denied && modes.contains { $0.postsBanner }
    }
}
