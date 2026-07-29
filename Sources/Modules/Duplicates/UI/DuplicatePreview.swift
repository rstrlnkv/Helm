// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import AppKit
import QuickLookUI
import Module_Duplicates_Engine

public enum DuplicatePreview {
    /// The file a preview would show, or nil when there is nothing to show.
    ///
    /// The selection is checked against the groups rather than trusted: a copy
    /// that has just been trashed leaves the list while the selection still
    /// names it, and a panel opened onto a file that is gone is an empty frame
    /// with no explanation.
    public static func target(selection: String?, in groups: [DuplicateGroup]) -> URL? {
        guard let selection,
              groups.contains(where: { $0.paths.contains(selection) }) else { return nil }
        return URL(fileURLWithPath: selection)
    }
}
