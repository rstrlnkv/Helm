import HelmUI
import SwiftUI

// MARK: - Sections

/// One cell of the hotkey board with a recorder of its own, so a press in one cell records in that cell alone.
private struct HotkeyCell<Content: View>: View {
    @StateObject private var recorder: HelmHotkeyRecorder
    private let content: (HelmHotkeyRecorder) -> Content

    init(label: String?, content: @escaping (HelmHotkeyRecorder) -> Content) {
        _recorder = StateObject(wrappedValue: HelmHotkeyRecorder.unsaved(label: label))
        self.content = content
    }

    var body: some View { content(recorder) }
}

/// `HelmHotkeyRow` over `HelmHotkeyRecorder.unsaved`: a recorder over a store in memory, one per cell, so a
/// press keeps nothing. The recording face comes from a press (`HelmReadout press`); no key is typed at it.
/// Hover and pressed are on the row "set" alone: Set is the same in every row, Clear is off in the row
/// with nothing assigned.
private struct HotkeyRows: View {
    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s6) {
            Matrix(rows: [
                row("set", [.rest, .disabled], label: "⌃⌥K") { HelmHotkeyRow(Sample.title, recorder: $0, taken: false) },
                row("none", [.rest, .disabled], label: nil) { HelmHotkeyRow(Sample.title, recorder: $0, taken: false) },
                row("taken", [.rest, .disabled], label: "⌃⌥K") {
                    HelmHotkeyRow(Sample.russian, recorder: $0, taken: true)
                },
                row("taken, exact note", [.rest, .disabled], label: "⌃⌥K") {
                    HelmHotkeyRow(Sample.title, recorder: $0, taken: true, note: Sample.russianNote)
                },
            ], columns: [.rest, .disabled], cellWidth: 560)
            Matrix(rows: [
                row("set", [.hover, .pressed], label: "⌃⌥K") { HelmHotkeyRow(Sample.title, recorder: $0, taken: false) },
            ], columns: [.hover, .pressed], cellWidth: 560)
        }
    }

    private func row(_ name: String, _ states: [ShowcaseState], label: String?,
                     _ make: @escaping (HelmHotkeyRecorder) -> some View) -> ShowcaseRow {
        ShowcaseRow(name, states: states) { _ in HotkeyCell(label: label, content: make) }
    }
}

struct SectionsBoard: View {
    var body: some View {
        Board(name: "Settings sections", caption: """
            Sections, rows and their notes take no pointer state, so there is one look of each. The \
            explainer's open popover comes from a press (HelmReadout press), not from this board. The \
            system's segmented control and menu cannot be forced to hover or press. The last row is disabled as a \
            row, and its switch carries no label of its own (labels hidden).
            """) {
            VStack(alignment: .leading, spacing: HelmSpace.s6) {
                HelmSettingsSection(Sample.title) {
                    Toggle(Sample.short, isOn: .constant(true))
                    HelmSettingRow(Sample.title) {
                        Picker(Sample.title, selection: .constant(1)) {
                            Text(verbatim: "A").tag(1)
                            Text(verbatim: "B").tag(2)
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                    }
                    HelmSettingRow(Sample.title) {
                        Picker(Sample.title, selection: .constant(1)) {
                            Text(verbatim: "A").tag(1)
                            Text(verbatim: "B").tag(2)
                        }
                        .labelsHidden().fixedSize().helmSectionMenu()
                    }
                    HelmSettingsNote(Sample.note)
                }
                .frame(width: 560)
                HelmSettingsSection {
                    Toggle(Sample.short, isOn: .constant(false))
                    HelmSettingsNote(Sample.russianNote)
                }
                .frame(width: 560)
                HelmSettingsSection(Sample.russian) {
                    HelmSettingRow(Sample.russian, note: Sample.russianNote, mark: .attention) {
                        Button(Sample.short) {}
                    }
                }
                .frame(width: 560)
                HelmSettingsSection(Sample.title) {
                    HelmSettingRow(Sample.russian, note: Sample.russianNote, explainer: Sample.explainer,
                                   mark: .attention, markSpoken: Sample.note) {
                        Toggle(Sample.title, isOn: .constant(true)).labelsHidden()
                    }
                    HelmSettingRow(Sample.title, note: Sample.note) {
                        Toggle(Sample.title, isOn: .constant(false)).labelsHidden()
                    }
                    .disabled(true)
                }
                .frame(width: 560)
            }
        }
    }
}

// MARK: - Hotkeys

struct HotkeysBoard: View {
    var body: some View {
        Board(name: "Hotkey rows", caption: """
            The row over a recorder in memory, one per cell: a press keeps nothing. Its recording face comes \
            from a press (HelmReadout press); no key is typed at it. The row's button is the kit's, by \
            helmRoot(); hover and pressed are forced, on the row "set" alone (Set is the same in every row, \
            Clear is off in the row with nothing assigned).
            """) {
            HotkeyRows()
        }
    }
}

// MARK: - Notices

struct NoticesBoard: View {
    private static let states: [ShowcaseState] = [.rest, .hover, .pressed, .disabled]

    var body: some View {
        Board(name: "Notices", caption: """
            Banners, the permission note, the empty and the busy state; the removal outcome is on lists. A \
            button inside a notice is the kit's own, so its hover and pressed columns are forced. The \
            permission note takes a closure and reads no permission.
            """) {
            VStack(alignment: .leading, spacing: HelmSpace.s6) {
                Matrix(rows: [
                    ShowcaseRow("banner, its button", states: Self.states) { _ in
                        HelmBanner(Sample.long) { Button(Sample.short) {} }
                    },
                    ShowcaseRow("banner, compact", states: Self.states) { _ in
                        HelmBanner(Sample.russian, compact: true) { Button(Sample.short) {} }
                    },
                    ShowcaseRow("banner, no action", states: [.rest]) { _ in HelmBanner(Sample.russianNote) },
                    ShowcaseRow("permission note", states: Self.states) { _ in
                        HelmPermissionNote(text: Sample.russianNote) {}
                    },
                    ShowcaseRow("empty state's button", states: Self.states) { _ in
                        HelmEmptyState(title: Sample.title) { Button(Sample.short) {} }.frame(height: 80)
                    },
                    ShowcaseRow("busy state's button", states: Self.states) { _ in
                        HelmBusyState(Sample.note) { Button(Sample.cancel) {} }.frame(height: 86)
                    },
                ], columns: Self.states, cellWidth: 270)
                HStack(alignment: .top, spacing: HelmSpace.s6) {
                    HelmEmptyState(symbol: "tray", title: Sample.title, message: Sample.note) {
                        Button(Sample.short) {}
                    }
                    .frame(width: 300, height: 160)
                    HelmEmptyState(title: Sample.russian, message: Sample.russianNote)
                        .frame(width: 300, height: 136)
                    HelmBusyState(Sample.note).frame(width: 200, height: 136)
                }
            }
        }
    }
}
