import AppKit
import HelmUI
import Module_Autopilot_Engine
import SwiftUI

/// One condition, editable.
///
/// The field picker rebuilds the condition rather than editing a shared value,
/// because the three parts are not independent: changing "name" to "size"
/// changes which comparisons exist and what the value means. Rebuilding is what
/// keeps "size begins with 4 MB" from being a state this screen can hold.
struct ConditionRow: View {
    @Binding var condition: RuleCondition
    let remove: () -> Void

    var body: some View {
        HStack(spacing: HelmSpace.s4) {
            // The label is real and hidden, not absent: `.labelsHidden()`
            // keeps the row reading as a sentence while VoiceOver still has
            // something to announce before the value.
            Picker(ApStr.a11yField, selection: fieldBinding) {
                ForEach(Field.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: HelmPickerWidth.fitting(Field.allCases.map(\.label), minimum: AutopilotLayout.fieldPicker),
                   alignment: .leading)

            detail

            Spacer(minLength: HelmSpace.s2)
            HelmRemoveButton(label: "\(ApStr.delete), \(field.label)", target: 20, action: remove)
        }
    }

    // MARK: - The field

    enum Field: String, CaseIterable {
        case name, baseName, fileExtension, kind, size, dateAdded, dateModified, source, tag

        var label: String {
            switch self {
            case .name: ApStr.fieldName
            case .baseName: ApStr.fieldBaseName
            case .fileExtension: ApStr.fieldExtension
            case .kind: ApStr.fieldKind
            case .size: ApStr.fieldSize
            case .dateAdded: ApStr.fieldDateAdded
            case .dateModified: ApStr.fieldDateModified
            case .source: ApStr.fieldSource
            case .tag: ApStr.fieldTag
            }
        }

        /// A condition of this field with values that mean something: switching
        /// field must not produce a rule that matches everything while someone
        /// is still typing.
        var blank: RuleCondition {
            switch self {
            case .name: .name(.contains, "")
            case .baseName: .baseName(.contains, "")
            case .fileExtension: .fileExtension([])
            case .kind: .kind(.image)
            case .size: .size(.largerThan, megabytes: 10)
            case .dateAdded: .dateAdded(.olderThan, days: 30)
            case .dateModified: .dateModified(.olderThan, days: 30)
            case .source: .downloadedFrom("")
            case .tag: .tag("")
            }
        }
    }

    private var field: Field {
        switch condition {
        case .name: .name
        case .baseName: .baseName
        case .fileExtension: .fileExtension
        case .kind: .kind
        case .size: .size
        case .dateAdded: .dateAdded
        case .dateModified: .dateModified
        case .downloadedFrom: .source
        case .tag: .tag
        }
    }

    private var fieldBinding: Binding<Field> {
        Binding(get: { field }, set: { condition = $0.blank })
    }

    // MARK: - The rest of the row

    @ViewBuilder private var detail: some View {
        switch condition {
        case let .name(comparison, value):
            textDetail(comparison, value) { condition = .name($0, $1) }

        case let .baseName(comparison, value):
            // The same four comparisons as the full name: one question gets one
            // shape, or the screen teaches that the two differ.
            textDetail(comparison, value) { condition = .baseName($0, $1) }

        case let .fileExtension(list):
            // Typed as a list because that is how it reads: "pdf, png, zip".
            TextField("pdf, png", text: Binding(
                get: { list.joined(separator: ", ") },
                set: { condition = .fileExtension(typed: $0) }))
                .accessibilityLabel(ApStr.a11yExtensions)

        case let .kind(kind):
            Picker(ApStr.a11yValue, selection: Binding(get: { kind }, set: { condition = .kind($0) })) {
                ForEach(FileKind.allCases, id: \.self) { Text(ApStr.kindName($0)).tag($0) }
            }
            .labelsHidden()
            .frame(width: HelmPickerWidth.fitting(FileKind.allCases.map(ApStr.kindName), minimum: AutopilotLayout.kindPicker))

        case let .size(comparison, megabytes):
            ShortPicker(name: ApStr.a11yComparison, selected: comparison,
                        options: [(.largerThan, ApStr.comparisonLarger),
                                  (.smallerThan, ApStr.comparisonSmaller)]) {
                condition = .size($0, megabytes: megabytes)
            }
            numberField(megabytes, ApStr.a11yMegabytes) { condition = .size(comparison, megabytes: $0) }
            Text(ApStr.unitMegabytes).font(HelmText.rowTitle).foregroundStyle(HelmText.quiet)

        case let .dateAdded(comparison, days):
            dateDetail(comparison, days) { condition = .dateAdded($0, days: $1) }

        case let .dateModified(comparison, days):
            dateDetail(comparison, days) { condition = .dateModified($0, days: $1) }

        case let .downloadedFrom(host):
            Text(ApStr.comparisonContains).font(HelmText.rowTitle).foregroundStyle(HelmText.quiet)
            TextField("example.com", text: Binding(get: { host },
                                                   set: { condition = .downloadedFrom($0) }))
                .accessibilityLabel(ApStr.a11yHost)

        case let .tag(tag):
            Text(ApStr.comparisonIs).font(HelmText.rowTitle).foregroundStyle(HelmText.quiet)
            TextField("", text: Binding(get: { tag }, set: { condition = .tag($0) }))
                .accessibilityLabel(ApStr.a11yTagValue)
        }
    }

    @ViewBuilder
    private func textDetail(_ comparison: TextComparison, _ value: String,
                            _ rebuild: @escaping (TextComparison, String) -> Void) -> some View {
        ShortPicker(name: ApStr.a11yComparison, selected: comparison,
                    options: [(.is, ApStr.comparisonIs), (.contains, ApStr.comparisonContains),
                              (.beginsWith, ApStr.comparisonBegins),
                              (.endsWith, ApStr.comparisonEnds)]) { rebuild($0, value) }
        TextField("", text: Binding(get: { value }, set: { rebuild(comparison, $0) }))
            .accessibilityLabel(ApStr.a11yValue)
    }

    @ViewBuilder
    private func dateDetail(_ comparison: DateComparison, _ days: Double,
                            _ rebuild: @escaping (DateComparison, Double) -> Void) -> some View {
        ShortPicker(name: ApStr.a11yComparison, selected: comparison,
                    options: [(.olderThan, ApStr.comparisonOlder),
                              (.newerThan, ApStr.comparisonNewer)]) { rebuild($0, days) }
        numberField(days, ApStr.a11yDays) { rebuild(comparison, $0) }
        Text(ApStr.unitDays(for: days)).font(HelmText.rowTitle).foregroundStyle(HelmText.quiet)
    }

    /// Typed rather than stepped: 30 days and 500 MB are both a number someone
    /// knows, and a stepper to reach either is a stepper nobody finishes.
    private func numberField(_ value: Double, _ name: String,
                             _ set: @escaping (Double) -> Void) -> some View {
        TextField("", text: Binding(
            get: { RuleSummary.number(value) },
            set: { text in
                // An unparseable value leaves the last good one, so a field
                // emptied while retyped never becomes a rule that matches every
                // file. Finite and bounded too: `Double.init` reads `1e999` as
                // `+∞`, which `JSONEncoder` refuses with the whole rule list and
                // `Int(∞)` in a formatter traps on.
                if let parsed = Double(text.replacingOccurrences(of: ",", with: ".")),
                   RuleCondition.accepts(parsed) {
                    set(parsed)
                }
            }))
        .frame(width: AutopilotLayout.numberField)
        .multilineTextAlignment(.trailing)
        // The unit is a separate Text beside the field, so the label carries it:
        // "30" alone would not say days or megabytes.
        .accessibilityLabel(name)
    }
}
