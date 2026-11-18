import Foundation
import HelmUI

enum DisplayCornersStr {
    static var name: String { L(.displayCornersName) }
    static var summary: String { L(.displayCornersSummary) }
    static var roundBuiltInCorners: String { L(.roundBuiltInCorners) }
    static var roundExternalCorners: String { L(.roundExternalCorners) }
    static var roundExternalCornersNote: String { L(.roundExternalCornersNote) }
    static var calibration: String { L(.calibration) }
    static var calibrationNote: String { L(.calibrationNote) }
    /// The colour button's name and tooltip, and the colour panel's title.
    static var calibrationColour: String { L(.calibrationColour) }
    static var cornerRadius: String { L(.cornerRadius) }
    static var radiusFine: String { L(.radiusFine) }
    static var radiusFineNote: String { L(.radiusFineNote) }

    /// «14 pt»: a whole number, in the app's language, with its unit's own spelling. Built on every ask, never held:
    /// a formatter held keeps the language the app started in.
    static func points(_ value: Int) -> String {
        L(.pointsValue(value.formatted(.number.locale(AppLanguage.current.locale))))
    }

    /// «14.5 px»: one decimal. A preset is points × scale and is not rounded, so «24.38» shows as «24.4».
    static func pixels(_ value: Double) -> String {
        L(.pixelsValue(value.formatted(.number.precision(.fractionLength(1)).locale(AppLanguage.current.locale))))
    }
}
