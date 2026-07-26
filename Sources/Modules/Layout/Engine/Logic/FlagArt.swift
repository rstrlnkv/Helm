import Foundation

/// What a flag is made of, for the flags Helm draws itself.
///
/// The first version of this was a list of colours plus "vertical?", and that
/// model is why Sweden shipped as Ukraine: a blue band over a yellow one is a
/// true statement about both flags and a description of neither. Two layouts
/// on the same Mac drew the same badge, which is the one thing an indicator
/// must never do.
///
/// So the model carries the *construction*, not the colours. Five primitives
/// cover everything in the table; anything needing a sixth is not drawn at all.
public enum FlagArt: Hashable, Sendable {
    /// Bands in proportion. Weights are whole numbers because the proportions
    /// are — Spain is 1:2:1, not "three thirds", which is what it was drawn as.
    case bands(colors: [String], weights: [Int], vertical: Bool)
    /// The Nordic cross, offset towards the hoist. `border` is the second
    /// outline Norway and Iceland carry.
    case nordic(field: String, cross: String, border: String?)
    /// Switzerland: arms that stop short of the edge.
    case swissCross(field: String, cross: String)
    /// Japan: one disc, centred.
    case disc(field: String, disc: String)
    /// Czechia: two bands with a triangle driven in from the hoist.
    case hoistTriangle(top: String, bottom: String, triangle: String)

    /// Equal bands, which most of the table is.
    public static func bands(_ colors: [String], vertical: Bool) -> FlagArt {
        .bands(colors: colors, weights: Array(repeating: 1, count: colors.count), vertical: vertical)
    }

    /// The flag for a region, or nil when Helm will not draw it.
    ///
    /// Three rules decide membership, in this order:
    ///
    /// 1. **Nothing invented, nothing dropped.** A flag with a crest, a canton,
    ///    a star or lettering is not in here — Brazil, Greece, Korea, Portugal,
    ///    the United Kingdom. Drawing the Union Jack means dropping the
    ///    counterchange of the saltire, which at fifteen pixels is half a pixel
    ///    and at any size is a different flag.
    /// 2. **No collisions.** The badge exists to tell one user's layouts apart.
    ///    Mexico without its eagle is Italy exactly; Slovakia and Slovenia
    ///    without their crests are Russia; Serbia's civil flag is Russia's,
    ///    mirrored, and a Serbian keyboard usually sits next to a Russian one.
    ///    All of those take letters instead, including the ones that would have
    ///    been honest drawings.
    /// 3. **Two device pixels of the smallest feature**, at the smallest badge
    ///    size on a Retina screen. A US stripe is 1/13 of the height — 1.38 px,
    ///    which renders as moiré, and the stars are absent besides.
    ///
    /// Between them these rules send both of the most common layouts, US and
    /// GB, to letters. That is the correct answer rather than a shortfall:
    /// macOS itself shows "A" for a US layout, not a flag.
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
        // Nordic crosses
        case "SE": return .nordic(field: "005293", cross: "FECB00", border: nil)
        case "DK": return .nordic(field: "C8102E", cross: "FFFFFF", border: nil)
        case "FI": return .nordic(field: "FFFFFF", cross: "003580", border: nil)
        case "NO": return .nordic(field: "BA0C2F", cross: "00205B", border: "FFFFFF")
        case "IS": return .nordic(field: "02529C", cross: "DC1E35", border: "FFFFFF")
        // One of a kind
        case "CH": return .swissCross(field: "D52B1E", cross: "FFFFFF")
        case "JP": return .disc(field: "FFFFFF", disc: "BC002D")
        case "CZ": return .hoistTriangle(top: "FFFFFF", bottom: "D7141A", triangle: "11457E")
        default: return nil
        }
    }

    /// Every region the table draws. The order is the table's.
    public static let drawnRegions = [
        "RU", "DE", "NL", "UA", "PL", "AT", "HU", "EE", "LT", "BG", "AM",
        "ES", "LV", "TH",
        "FR", "IT", "BE", "IE", "RO",
        "SE", "DK", "FI", "NO", "IS",
        "CH", "JP", "CZ",
    ]
}
