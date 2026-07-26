import Foundation

/// What a flag is made of, for the flags Helm draws itself.
///
/// The first version of this was a list of colours plus "vertical?", and that
/// model is why Sweden shipped as Ukraine: a blue band over a yellow one is a
/// true statement about both flags and a description of neither. Two layouts
/// on the same Mac drew the same badge, which is the one thing an indicator
/// must never do. So the model carries the *construction*, not the colours.
///
/// Every region the layout table can produce is drawn — the first cut sent
/// half of them to letters on strictness grounds, and the first thing noticed
/// in use was that the most common layout of all had no flag. At badge size a
/// flag is a recognition mark, not a rendering of cloth: the US canton has no
/// stars and seven stripes stand for thirteen, an eagle or a crest becomes a
/// plain emblem shape, and the Union Jack loses the counterchange of its
/// saltire. Each simplification keeps the silhouette that makes the flag
/// recognisable at fifteen pixels and drops only what was never going to
/// survive the trip.
public enum FlagArt: Hashable, Sendable {
    /// A small mark drawn over a field — the crest, star or leaf reduced to
    /// the one shape that still reads at badge size. Positions and sizes are
    /// fractions of the canvas, so the same emblem scales with the badge.
    public struct Emblem: Hashable, Sendable {
        public enum Shape: Hashable, Sendable {
            case disc, star5, star6, cross, shield, vstripe
        }
        public let shape: Shape
        public let hex: String
        /// Centre, as fractions of width and height from the top-left.
        public let x: Double
        public let y: Double
        /// Diameter, as a fraction of the flag's height.
        public let size: Double

        public init(_ shape: Shape, _ hex: String,
                    x: Double = 0.5, y: Double = 0.5, size: Double = 0.4) {
            self.shape = shape
            self.hex = hex
            self.x = x
            self.y = y
            self.size = size
        }
    }

    /// Bands in proportion. Weights are whole numbers because the proportions
    /// are — Spain is 1:2:1, not "three thirds", which is what it was drawn as.
    case bands(colors: [String], weights: [Int], vertical: Bool)
    /// Bands with an emblem over them: Canada's leaf, Mexico's eagle, the
    /// Slavic crests — each reduced to a shape, because the shape is what
    /// tells three white-blue-red tricolours apart at fifteen pixels.
    case bandsEmblem(colors: [String], weights: [Int], vertical: Bool, emblem: Emblem)
    /// The Nordic cross, offset towards the hoist. `border` is the second
    /// outline Norway and Iceland carry.
    case nordic(field: String, cross: String, border: String?)
    /// Switzerland: arms that stop short of the edge.
    case swissCross(field: String, cross: String)
    /// Georgia: a cross that runs to the edges (the four small crosses are
    /// below badge size and are not drawn).
    case centeredCross(field: String, cross: String)
    /// Japan, Kazakhstan, North Macedonia: one disc, centred.
    case disc(field: String, disc: String)
    /// Czechia: two bands with a triangle driven in from the hoist.
    case hoistTriangle(top: String, bottom: String, triangle: String)
    /// The United States, Greece, Taiwan: stripes with a canton. Stripes are
    /// listed top to bottom; the canton covers the upper hoist quarter. Seven
    /// stripes stand in for the US's thirteen — thirteen are 1.4 px each at
    /// the smallest size and render as moiré.
    case stripesCanton(stripes: [String], canton: String, emblem: Emblem?)
    /// The Union Jack, without the counterchange of the saltire — half a
    /// pixel at badge size.
    case unionJack(field: String)
    /// Australia: a blue field with the Jack in the canton. The stars are
    /// below badge size.
    case jackCanton(field: String)
    /// Türkiye: crescent and star.
    case crescentStar(field: String, mark: String)
    /// China and Vietnam: one star — at the hoist for China (the four small
    /// ones are below badge size), centred for Vietnam.
    case star(field: String, star: String, atHoist: Bool)
    /// South Korea: the taegeuk disc, red over blue (the trigrams are below
    /// badge size).
    case taegeuk(field: String)
    /// Brazil: rhombus on a field, disc on the rhombus.
    case rhombusDisc(field: String, rhombus: String, disc: String)

    /// Equal bands, which most of the table is.
    public static func bands(_ colors: [String], vertical: Bool) -> FlagArt {
        .bands(colors: colors, weights: Array(repeating: 1, count: colors.count), vertical: vertical)
    }

    /// The flag for a region, or nil only when the region is unknown.
    public static func flag(region: String?) -> FlagArt? {
        guard let region = region?.uppercased() else { return nil }
        switch region {
        // Horizontal bands, equal
        case "RU": return .bands(["FFFFFF", "0039A6", "D52B1E"], vertical: false)
        case "DE": return .bands(["000000", "DD0000", "FFCE00"], vertical: false)
        case "NL": return .bands(["AE1C28", "FFFFFF", "21468B"], vertical: false)
        case "UA": return .bands(["0057B7", "FFD700"], vertical: false)
        case "PL": return .bands(["FFFFFF", "DC143C"], vertical: false)
        case "AT": return .bands(["ED2939", "FFFFFF", "ED2939"], vertical: false)
        case "HU": return .bands(["CE2939", "FFFFFF", "477050"], vertical: false)
        case "EE": return .bands(["0072CE", "000000", "FFFFFF"], vertical: false)
        case "LT": return .bands(["FDB913", "006A44", "C1272D"], vertical: false)
        case "BG": return .bands(["FFFFFF", "00966E", "D62612"], vertical: false)
        case "AM": return .bands(["D90012", "0033A0", "F2A800"], vertical: false)
        case "IR": return .bands(["239F40", "FFFFFF", "DA0000"], vertical: false)
        // Horizontal bands, unequal
        case "ES": return .bands(colors: ["AA151B", "F1BF00", "AA151B"],
                                 weights: [1, 2, 1], vertical: false)
        case "LV": return .bands(colors: ["9E3039", "FFFFFF", "9E3039"],
                                 weights: [2, 1, 2], vertical: false)
        case "TH": return .bands(colors: ["A51931", "F4F5F8", "2D2A4A", "F4F5F8", "A51931"],
                                 weights: [1, 1, 2, 1, 1], vertical: false)
        // Vertical bands
        case "FR": return .bands(["002395", "FFFFFF", "ED2939"], vertical: true)
        case "IT": return .bands(["008C45", "F4F5F0", "CD212A"], vertical: true)
        case "BE": return .bands(["000000", "FDDA24", "EF3340"], vertical: true)
        case "IE": return .bands(["169B62", "FFFFFF", "FF883E"], vertical: true)
        case "RO": return .bands(["002B7F", "FCD116", "CE1126"], vertical: true)
        // Bands with an emblem
        case "CA": return .bandsEmblem(colors: ["FF0000", "FFFFFF", "FF0000"],
                                       weights: [1, 2, 1], vertical: true,
                                       emblem: Emblem(.disc, "FF0000", size: 0.42))
        case "MX": return .bandsEmblem(colors: ["006847", "FFFFFF", "CE1126"],
                                       weights: [1, 1, 1], vertical: true,
                                       emblem: Emblem(.disc, "6B4A2B", size: 0.32))
        case "PT": return .bandsEmblem(colors: ["046A38", "DA291C"],
                                       weights: [2, 3], vertical: true,
                                       emblem: Emblem(.disc, "FFE900", x: 0.4, size: 0.38))
        case "IL": return .bandsEmblem(colors: ["FFFFFF", "0038B8", "FFFFFF", "0038B8", "FFFFFF"],
                                       weights: [1, 1, 4, 1, 1], vertical: false,
                                       emblem: Emblem(.star6, "0038B8", size: 0.42))
        case "BY": return .bandsEmblem(colors: ["CE1720", "007C30"],
                                       weights: [2, 1], vertical: false,
                                       emblem: Emblem(.vstripe, "FFFFFF", x: 0.07, size: 0.14))
        // Three white-blue-red tricolours and Croatia: told apart by the
        // crest's colour and place, which is what tells them apart in cloth.
        case "SK": return .bandsEmblem(colors: ["FFFFFF", "0B4EA2", "EE1C25"],
                                       weights: [1, 1, 1], vertical: false,
                                       emblem: Emblem(.shield, "EE1C25", x: 0.3, y: 0.55, size: 0.5))
        case "SI": return .bandsEmblem(colors: ["FFFFFF", "005DA4", "ED1C24"],
                                       weights: [1, 1, 1], vertical: false,
                                       emblem: Emblem(.shield, "005DA4", x: 0.3, y: 0.38, size: 0.42))
        case "RS": return .bandsEmblem(colors: ["C6363C", "0C4076", "FFFFFF"],
                                       weights: [1, 1, 1], vertical: false,
                                       emblem: Emblem(.shield, "FFFFFF", x: 0.4, y: 0.5, size: 0.46))
        case "HR": return .bandsEmblem(colors: ["FF0000", "FFFFFF", "171796"],
                                       weights: [1, 1, 1], vertical: false,
                                       emblem: Emblem(.shield, "FF0000", y: 0.5, size: 0.46))
        // Nordic crosses
        case "SE": return .nordic(field: "005293", cross: "FECB00", border: nil)
        case "DK": return .nordic(field: "C8102E", cross: "FFFFFF", border: nil)
        case "FI": return .nordic(field: "FFFFFF", cross: "003580", border: nil)
        case "NO": return .nordic(field: "BA0C2F", cross: "00205B", border: "FFFFFF")
        case "IS": return .nordic(field: "02529C", cross: "DC1E35", border: "FFFFFF")
        // Crosses of their own
        case "CH": return .swissCross(field: "D52B1E", cross: "FFFFFF")
        case "GE": return .centeredCross(field: "FFFFFF", cross: "FF0000")
        // Discs
        case "JP": return .disc(field: "FFFFFF", disc: "BC002D")
        case "KZ": return .disc(field: "00AFCA", disc: "FEC50C")
        case "MK": return .disc(field: "D20000", disc: "FFE600")
        // One of a kind
        case "CZ": return .hoistTriangle(top: "FFFFFF", bottom: "D7141A", triangle: "11457E")
        case "US": return .stripesCanton(stripes: ["B22234", "FFFFFF", "B22234", "FFFFFF",
                                                   "B22234", "FFFFFF", "B22234"],
                                         canton: "3C3B6E", emblem: nil)
        case "GR": return .stripesCanton(stripes: ["0D5EAF", "FFFFFF", "0D5EAF",
                                                   "FFFFFF", "0D5EAF"],
                                         canton: "0D5EAF",
                                         emblem: Emblem(.cross, "FFFFFF"))
        case "TW": return .stripesCanton(stripes: ["FE0000"], canton: "000095",
                                         emblem: Emblem(.disc, "FFFFFF"))
        case "GB": return .unionJack(field: "012169")
        case "AU": return .jackCanton(field: "00247D")
        case "TR": return .crescentStar(field: "E30A17", mark: "FFFFFF")
        case "KR": return .taegeuk(field: "FFFFFF")
        case "BR": return .rhombusDisc(field: "009C3B", rhombus: "FFDF00", disc: "002776")
        case "CN": return .star(field: "EE1C25", star: "FFFF00", atHoist: true)
        case "VN": return .star(field: "DA251D", star: "FFFF00", atHoist: false)
        default: return nil
        }
    }

    /// Every region the table draws. The order is the table's.
    public static let drawnRegions = [
        "RU", "DE", "NL", "UA", "PL", "AT", "HU", "EE", "LT", "BG", "AM", "IR",
        "ES", "LV", "TH",
        "FR", "IT", "BE", "IE", "RO",
        "CA", "MX", "PT", "IL", "BY", "SK", "SI", "RS", "HR",
        "SE", "DK", "FI", "NO", "IS",
        "CH", "GE",
        "JP", "KZ", "MK",
        "CZ", "US", "GR", "TW", "GB", "AU", "TR", "KR", "BR", "CN", "VN",
    ]
}
