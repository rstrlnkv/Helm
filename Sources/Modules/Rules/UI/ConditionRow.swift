import AppKit
import HelmRuntime
import HelmUI
import Module_Rules_Engine
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
            Picker("", selection: fieldBinding) {
                ForEach(Field.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: 150)

            detail

            Spacer(minLength: 4)
            Button(action: remove) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .accessibilityLabel(RuStr.delete)
        }
    }

    // MARK: - The field

    enum Field: String, CaseIterable {
        case name, fileExtension, kind, size, dateAdded, dateModified, source, tag

        var label: String {
            switch self {
            case .name: RuStr.fieldName
            case .fileExtension: RuStr.fieldExtension
            case .kind: RuStr.fieldKind
            case .size: RuStr.fieldSize
            case .dateAdded: RuStr.fieldDateAdded
            case .dateModified: RuStr.fieldDateModified
            case .source: RuStr.fieldSource
            case .tag: RuStr.fieldTag
            }
        }

        /// A condition of this field with values that mean something: switching
        /// field must not produce a rule that matches everything while someone
        /// is still typing.
        var blank: RuleCondition {
            switch self {
            case .name: .name(.contains, "")
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
            Picker("", selection: Binding(
                get: { comparison },
                set: { condition = .name($0, value) })) {
                    Text(RuStr.comparisonIs).tag(TextComparison.is)
                    Text(RuStr.comparisonContains).tag(TextComparison.contains)
                    Text(RuStr.comparisonBegins).tag(TextComparison.beginsWith)
                    Text(RuStr.comparisonEnds).tag(TextComparison.endsWith)
                }
                .labelsHidden().frame(width: 140)
            TextField("", text: Binding(get: { value },
                                        set: { condition = .name(comparison, $0) }))

        case let .fileExtension(list):
            // Typed as a list because that is how it reads: "pdf, png, zip".
            TextField("pdf, png", text: Binding(
                get: { list.joined(separator: ", ") },
                set: { text in
                    condition = .fileExtension(text
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                        .filter { !$0.isEmpty })
                }))

        case let .kind(kind):
            Picker("", selection: Binding(get: { kind }, set: { condition = .kind($0) })) {
                ForEach(FileKind.allCases, id: \.self) { Text(RuStr.kindName($0)).tag($0) }
            }
            .labelsHidden().frame(width: 160)

        case let .size(comparison, megabytes):
            Picker("", selection: Binding(
                get: { comparison },
                set: { condition = .size($0, megabytes: megabytes) })) {
                    Text(RuStr.comparisonLarger).tag(SizeComparison.largerThan)
                    Text(RuStr.comparisonSmaller).tag(SizeComparison.smallerThan)
                }
                .labelsHidden().frame(width: 140)
            numberField(megabytes) { condition = .size(comparison, megabytes: $0) }
            Text(RuStr.unitMegabytes).font(.callout).foregroundStyle(HelmText.quiet)

        case let .dateAdded(comparison, days):
            dateDetail(comparison, days) { condition = .dateAdded($0, days: $1) }

        case let .dateModified(comparison, days):
            dateDetail(comparison, days) { condition = .dateModified($0, days: $1) }

        case let .downloadedFrom(host):
            Text(RuStr.comparisonContains).font(.callout).foregroundStyle(HelmText.quiet)
            TextField("example.com", text: Binding(get: { host },
                                                   set: { condition = .downloadedFrom($0) }))

        case let .tag(tag):
            Text(RuStr.comparisonIs).font(.callout).foregroundStyle(HelmText.quiet)
            TextField("", text: Binding(get: { tag }, set: { condition = .tag($0) }))
        }
    }

    @ViewBuilder
    private func dateDetail(_ comparison: DateComparison, _ days: Double,
                            _ rebuild: @escaping (DateComparison, Double) -> Void) -> some View {
        Picker("", selection: Binding(get: { comparison },
                                      set: { rebuild($0, days) })) {
            Text(RuStr.comparisonOlder).tag(DateComparison.olderThan)
            Text(RuStr.comparisonNewer).tag(DateComparison.newerThan)
        }
        .labelsHidden().frame(width: 140)
        numberField(days) { rebuild(comparison, $0) }
        Text(RuStr.unitDays).font(.callout).foregroundStyle(HelmText.quiet)
    }

    /// Typed rather than stepped: 30 days and 500 MB are both a number someone
    /// knows, and a stepper to reach either is a stepper nobody finishes.
    private func numberField(_ value: Double,
                             _ set: @escaping (Double) -> Void) -> some View {
        TextField("", text: Binding(
            get: { value == value.rounded() ? String(Int(value)) : String(value) },
            set: { text in
                // A field that empties itself while being retyped must not
                // become a rule that matches every file: an unparseable value
                // leaves the last good one in place.
                if let parsed = Double(text.replacingOccurrences(of: ",", with: ".")),
                   parsed > 0 {
                    set(parsed)
                }
            }))
        .frame(width: 70)
        .multilineTextAlignment(.trailing)
    }
}
