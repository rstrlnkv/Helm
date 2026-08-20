// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import AppKit
import HelmUI

/// **The 40 pt sentence at the top of a module page, as something a check can
/// ask about.**
///
/// Two modules draw one — Keep Awake's state and the VPN's verdict — and each
/// has a check that its lines are centred where they wrap. Both need the same
/// three facts, and neither is about the module: which column the words get,
/// how tall a run of ink has to be before it is a line of the figure rather
/// than the caption under it, and what «drawn about one axis» is measured as.
/// Spelled in both test targets they are the shape CLAUDE.md calls a name
/// spelled twice across a target boundary — one side changes it and nothing is
/// an error anywhere.
@MainActor
public enum HeroFigure {

    /// The column a hero's words really get: the settings column less the inset
    /// a grouped `Form` gives a section **header**, which is where both pages
    /// mount their hero (`HelmLayout.groupedHeaderOutset` carries the other half
    /// of that ruling). 30 pt a side, so 60.
    public static let column: CGFloat = HelmLayout.settingsColumn - 60

    /// The same, at the narrowest a person can reach: an 860 pt window with the
    /// sidebar dragged to its 320 pt maximum.
    public static let narrowest: CGFloat = 539 - 60

    /// Both, in the order a sweep reports them — the width most people see
    /// first, and then the one the layout has to survive.
    public static let widths: [CGFloat] = [column, narrowest]

    /// **A run of ink this tall is a line of the figure**, and the first run
    /// under it is the caption. Measured across both heroes in all eight
    /// languages: 40 pt type inks 29 to 36.5 rows, 13 pt type 10 to 15.
    ///
    /// A band typed in points cannot do this job — the figure is one line in
    /// English and three in Spanish at the narrowest width, so any fixed band is
    /// either short of the last line or long enough to sweep the caption in with
    /// it, and a caption is centred on its own whatever the figure does.
    private static let ink: CGFloat = 20

    /// Deep enough for three lines of 40 pt type and the caption under them,
    /// which is the tallest any hero draws. A **bound on the scan**, not the
    /// discriminator: it keeps a 1.1-million-pixel read off the rows where the
    /// verbs are, and `ink` above is what decides where the figure ends.
    private static let deepest = 200

    /// The lines of the figure `view` draws at its top, and nothing under them.
    ///
    /// **Clamped to the drawing, and it has to be.** A hosting view takes its
    /// content's height, not the window's: the Keep Awake hero settles at 145 pt
    /// and the VPN's empty state at less, so a band of 200 runs off the bottom
    /// of both — and `RenderedLines` refuses a band past the end of the image
    /// rather than reading a short one, which is right, because «the band found
    /// nothing» and «the band was not there» must not be the same answer.
    public static func lines(of view: NSView) -> [RenderedLines.Line]? {
        // A `ClosedRange` cannot be empty, so the floor is a guard against
        // `0...(-1)`, which traps rather than answering nil.
        let depth = min(deepest, Int(view.bounds.height))
        guard depth > 0, let lines = RenderedLines.read(view, points: 0...depth) else { return nil }
        return Array(lines.prefix { $0.bottom - $0.top >= ink })
    }

    /// How far apart the lines are drawn — the whole of what «centred» means
    /// here, since every one of them is centred in the same column or none is.
    public static func spread(_ lines: [RenderedLines.Line]) -> CGFloat {
        let centres = lines.map(\.centre)
        return (centres.max() ?? 0) - (centres.min() ?? 0)
    }

    /// The centres themselves, for the sentence a failure prints.
    public static func centres(_ lines: [RenderedLines.Line]) -> String {
        lines.map { String(format: "%.1f", $0.centre) }.joined(separator: ", ")
    }
}
