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
        HStack(spacing: 8) {
            // The label is real and hidden, not absent: `.labelsHidden()`
            // keeps the row reading as a sentence while VoiceOver still has
            // something to announce before the value.
            Picker(ApStr.a11yField, selection: fieldBinding) {
                ForEach(Field.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: HelmPickerWidth.fitting(Field.allCases.map(\.label), minimum: 150))

            detail

            Spacer(minLength: 4)
            Button(action: remove) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .accessibilityLabel(ApStr.delete)
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
            Picker(ApStr.a11yComparison, selection: Binding(
                get: { comparison },
                set: { condition = .name($0, value) })) {
                    Text(ApStr.comparisonIs).tag(TextComparison.is)
                    Text(ApStr.comparisonContains).tag(TextComparison.contains)
                    Text(ApStr.comparisonBegins).tag(TextComparison.beginsWith)
                    Text(ApStr.comparisonEnds).tag(TextComparison.endsWith)
                }
                .labelsHidden()
                .frame(width: HelmPickerWidth.fitting(
                    [ApStr.comparisonIs, ApStr.comparisonContains,
                     ApStr.comparisonBegins, ApStr.comparisonEnds], minimum: 140))
            TextField("", text: Binding(get: { value },
                                        set: { condition = .name(comparison, $0) }))
                .accessibilityLabel(ApStr.a11yValue)

        case let .baseName(comparison, value):
            // The same four comparisons: the field differs, the question does
            // not, and two shapes for one question is how a screen teaches
            // somebody that they are different when they are not.
            Picker(ApStr.a11yComparison, selection: Binding(
                get: { comparison },
                set: { condition = .baseName($0, value) })) {
                    Text(ApStr.comparisonIs).tag(TextComparison.is)
                    Text(ApStr.comparisonContains).tag(TextComparison.contains)
                    Text(ApStr.comparisonBegins).tag(TextComparison.beginsWith)
                    Text(ApStr.comparisonEnds).tag(TextComparison.endsWith)
                }
                .labelsHidden()
                .frame(width: HelmPickerWidth.fitting(
                    [ApStr.comparisonIs, ApStr.comparisonContains,
                     ApStr.comparisonBegins, ApStr.comparisonEnds], minimum: 140))
            TextField("", text: Binding(get: { value },
                                        set: { condition = .baseName(comparison, $0) }))
                .accessibilityLabel(ApStr.a11yValue)

        case let .fileExtension(list):
            // Typed as a list because that is how it reads: "pdf, png, zip".
            TextField("pdf, png", text: Binding(
                get: { list.joined(separator: ", ") },
                set: { condition = .fileExtension(typed: $0) }))
                .accessibilityLabel(ApStr.a11yExtensions)

        case let .kind(kind):
            Picker(ApStr.a11yField, selection: Binding(get: { kind }, set: { condition = .kind($0) })) {
                ForEach(FileKind.allCases, id: \.self) { Text(ApStr.kindName($0)).tag($0) }
            }
            .labelsHidden()
            .frame(width: HelmPickerWidth.fitting(FileKind.allCases.map(ApStr.kindName), minimum: 160))

        case let .size(comparison, megabytes):
            Picker(ApStr.a11yComparison, selection: Binding(
                get: { comparison },
                set: { condition = .size($0, megabytes: megabytes) })) {
                    Text(ApStr.comparisonLarger).tag(SizeComparison.largerThan)
                    Text(ApStr.comparisonSmaller).tag(SizeComparison.smallerThan)
                }
                .labelsHidden()
                .frame(width: HelmPickerWidth.fitting(
                    [ApStr.comparisonLarger, ApStr.comparisonSmaller], minimum: 140))
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
    private func dateDetail(_ comparison: DateComparison, _ days: Double,
                            _ rebuild: @escaping (DateComparison, Double) -> Void) -> some View {
        Picker(ApStr.a11yComparison, selection: Binding(get: { comparison },
                                                        set: { rebuild($0, days) })) {
            Text(ApStr.comparisonOlder).tag(DateComparison.olderThan)
            Text(ApStr.comparisonNewer).tag(DateComparison.newerThan)
        }
        .labelsHidden()
        .frame(width: HelmPickerWidth.fitting(
            [ApStr.comparisonOlder, ApStr.comparisonNewer], minimum: 140))
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
                // A field that empties itself while being retyped must not
                // become a rule that matches every file: an unparseable value
                // leaves the last good one in place.
                // Finite and bounded. `Double.init` accepts `1e999`, which is
                // `+∞`: `JSONEncoder` then refuses the whole rule list and the
                // engine's setter discarded every folder without a word, while
                // `Int(∞)` in a formatter is a trap rather than an error.
                if let parsed = Double(text.replacingOccurrences(of: ",", with: ".")),
                   RuleCondition.accepts(parsed) {
                    set(parsed)
                }
            }))
        .frame(width: 70)
        .multilineTextAlignment(.trailing)
        // The unit is a separate Text beside the field, so read aloud the
        // number had no unit at all: "30" for days and "10" for megabytes.
        .accessibilityLabel(name)
    }
}
