import SwiftUI

/// A titled group of rows on a page that is not a grouped `Form`: `HelmSectionTitle`, then one `helmCard` holding
/// the rows with a hairline between each two. The rows are the content's direct children — a plain `Toggle`, a
/// `HelmSettingRow`, a `HelmSettingsNote`, any view that is one row.
///
/// The gaps are the grouped form's own (`HelmLayout.groupedHeaderGap`, `groupedHeaderOutset`), so a page built
/// on this and a page that is still a `Form` keep one rhythm.
///
/// **A `LabeledContent` inside draws like a form row**, label at the top leading edge and the control at the
/// trailing one: laying that out is the form's job, not the control's, so outside a `Form` the section does it
/// (`RowLabeledContent`). A `Picker` does not get the same by itself: put it in a `HelmSettingRow` with
/// `labelsHidden()`.
public struct HelmSettingsSection<Content: View>: View {
    private let title: String?
    private let content: Content

    public init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: HelmLayout.groupedHeaderGap) {
            if let title {
                HelmSectionTitle(title).padding(.leading, HelmLayout.groupedHeaderOutset)
            }
            VStack(alignment: .leading, spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(rows) { row in
                        if row.id != rows.first?.id {
                            Rectangle().fill(HelmSurface.hairline).frame(height: 1)
                        }
                        row
                            .padding(.horizontal, HelmSpace.s5)
                            .padding(.vertical, HelmSpace.s4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .helmCard(padding: 0)
            .labeledContentStyle(RowLabeledContent())
            .toggleStyle(HelmToggleStyle(switchSize: .mini))
        }
    }
}

public extension View {
    /// A `.menu` `Picker` outside a grouped `Form`, borderless: the value and a bare chevron, 16 pt tall, the
    /// chevron's ink ending 7.5 pt inside the frame. The Form draws a 24 pt control with a round chevron well;
    /// that well has no public spelling, so this is an approximation, not the system's own. For a picker inside
    /// `HelmSettingsSection`, which cannot do it itself: a style set on the section does not reach a `Picker`
    /// (`.menuStyle(.borderlessButton)` and a custom `MenuStyle` do nothing on one), so each picker asks.
    func helmSectionMenu() -> some View {
        buttonStyle(.borderless)
    }
}

/// A quiet line inside a section: `HelmText.rowDetail` in `HelmText.quiet`, wrapping.
public struct HelmSettingsNote: View {
    private let text: String
    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .font(HelmText.rowDetail)
            .foregroundStyle(HelmText.quiet)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// `LabeledContent` laid out like a `Form` row: the label top-leading in `HelmText.rowTitle`, the content at
/// the trailing edge.
private struct RowLabeledContent: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: HelmSpace.s5) {
            configuration.label.font(HelmText.rowTitle)
            Spacer(minLength: HelmSpace.s5)
            configuration.content
        }
    }
}
