import AppKit
import HelmUI

/// What the command line asks of one showcase launch. The showcase stores nothing: the board, the
/// appearance and the presentation are arguments and die with the process.
struct ShowcaseOptions {
    enum Board: String, CaseIterable {
        case buttons, capsules, toggles, rows, sections, hotkeys, notices, header, toolbar, surfaces, pickers, lists, panel
        case motion, palette, ladders, present, welcome
    }

    /// Light and dark are `NSApp.appearance`; the contrast pair adds the kit's accessibility value
    /// (`main.swift`), because the appearance alone does not reach `\.helmTraits` (`HelmTraits.swift`).
    enum Appearance: String, CaseIterable {
        case light, dark
        case lightContrast = "light-contrast", darkContrast = "dark-contrast"

        var name: NSAppearance.Name {
            switch self {
            case .light: .aqua
            case .dark: .darkAqua
            case .lightContrast: .accessibilityHighContrastAqua
            case .darkContrast: .accessibilityHighContrastDarkAqua
            }
        }
        var increasedContrast: Bool { self == .lightContrast || self == .darkContrast }
    }

    /// What the present board opens on launch, one per launch.
    enum Presentation: String, CaseIterable { case sheet, popover, alert, dialog }

    struct Refusal: Error { let message: String }

    private(set) var board = Board.buttons
    private(set) var appearance: Appearance?
    private(set) var presentation: Presentation?
    private(set) var language: AppLanguage?

    static var usage: String {
        func names<T: CaseIterable & RawRepresentable>(_: T.Type) -> String where T.RawValue == String {
            T.allCases.map(\.rawValue).joined(separator: "|")
        }
        return """
        usage: HelmShowcase [--board \(names(Board.self))] [--appearance \(names(Appearance.self))]
                            [--present \(names(Presentation.self))] [--language \(names(AppLanguage.self))]
                            [-reduceTransparency 1]
        """
    }

    init(arguments: [String]) throws {
        var rest = arguments.dropFirst()
        var boardGiven = false
        func value<T: RawRepresentable>(of flag: String, as _: T.Type) throws -> T where T.RawValue == String {
            guard let word = rest.popFirst(), let parsed = T(rawValue: word) else {
                throw Refusal(message: "\(flag) needs one of its values")
            }
            return parsed
        }
        while let flag = rest.popFirst() {
            switch flag {
            case "--board": board = try value(of: flag, as: Board.self); boardGiven = true
            case "--appearance": appearance = try value(of: flag, as: Appearance.self)
            case "--present": presentation = try value(of: flag, as: Presentation.self)
            case "--language": language = try value(of: flag, as: AppLanguage.self)
            // The argument domain has already answered: `HelmAccessibility.system` reads it in this process, with no
            // Mac setting changed.
            case "-reduceTransparency":
                guard rest.popFirst() != nil else { throw Refusal(message: "\(flag) needs a value") }
            default: throw Refusal(message: "unknown argument \(flag)")
            }
        }
        if presentation != nil {
            if !boardGiven { board = .present }
            guard board == .present else { throw Refusal(message: "--present belongs to --board present") }
        }
    }
}
