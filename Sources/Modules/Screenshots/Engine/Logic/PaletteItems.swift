import Foundation
import HelmRuntime

/// What a person may take off the editor's palette: the objects of its row, and nothing else. Colours, Undo, Redo, ⋯,
/// Done and ✕ are not here, so no list this type reads or writes can take away the way out or the colours.
///
/// **The raw value is stored data**: a case that retires stays and is never renamed. The glyph tools are not here
/// either: they stand in the ⋯ menu, and there is nowhere to take them from. A case is a name the store may hold; which
/// of them the palette draws is the palette's own list, so a case no object answers to is neither shown nor counted.
public enum PaletteItem: String, CaseIterable, Sendable {
    case pen, highlighter, pencil, eraser, ruler, spotlight

    /// What an item is until a person says otherwise. A tool added later takes this at once, for the person who had
    /// already chosen something as for the one who had not.
    public var shownByDefault: Bool { true }
}

/// Which objects the palette's row shows: the person's explicit picks over each item's default.
///
/// `paletteChoices` holds **only what was picked**, a table from an item's raw value to shown or hidden; with no entry the
/// item's default decides. A list of the hidden ones, or of the shown ones, could not give a tool added later its default
/// for somebody who had already chosen. Read by walking the cases there are and asking the table about each, never by
/// walking the table: a name that is no case, `"colours"` or `"undo"` among them, is never read, and what the table
/// holds beyond the cases is dropped by the next write, so it is bounded by the number of cases. An entry that is no Bool is no pick and costs the
/// others nothing. A stored value that is no table reads as no picks. Not sealed: nothing unattended reads it.
public enum PaletteItems {
    /// The picks, for the items that have one.
    public static func picks(_ store: NamespacedStore) -> [PaletteItem: Bool] {
        let stored = store.object(ScreenshotsSettings.Key.paletteChoices) as? [String: Any] ?? [:]
        var picks: [PaletteItem: Bool] = [:]
        for item in PaletteItem.allCases {
            if let pick = stored[item.rawValue] as? Bool { picks[item] = pick }
        }
        return picks
    }

    /// Whether `item` is on the palette: its pick, or its default.
    public static func isShown(_ item: PaletteItem, in store: NamespacedStore) -> Bool {
        picks(store)[item] ?? item.shownByDefault
    }

    /// The items not taken off, in the order of the cases: every case with no pick against it, so this is a name list, not
    /// what the palette draws, which is the objects `EditorPalette.objects` places in its row. The palette and the settings
    /// page both read this one answer.
    public static func visible(_ store: NamespacedStore) -> [PaletteItem] {
        let picks = picks(store)
        return PaletteItem.allCases.filter { picks[$0] ?? $0.shownByDefault }
    }

    /// Records a pick for `item` and keeps the picks the others had; a name in the table that is no case goes with the write.
    public static func set(_ item: PaletteItem, shown: Bool, in store: NamespacedStore) {
        var table = Dictionary(uniqueKeysWithValues: picks(store).map { ($0.key.rawValue, $0.value) })
        table[item.rawValue] = shown
        store.set(table, for: ScreenshotsSettings.Key.paletteChoices)
    }
}
