import Foundation

/// The three orders the Apps tab can be read in, each in the one direction
/// that answers a removal question (what is big, what have I not opened), so
/// the menu is a flat list of three with no direction to choose.
public enum AppSortOrder: String, CaseIterable, Sendable {
    /// A to Z. Also what every list is in until a reading arrives.
    case name
    /// Largest first; a size that was measured as nothing goes last.
    case size
    /// Longest ago first; an app with no recorded opening goes before them all,
    /// and one the read never reached goes after them all.
    case dateLastOpened

    /// What a Mac that has never chosen reads as. Not size: the list arrives
    /// before the sizes, and would rebuild itself under the pointer.
    public static let standard = AppSortOrder.name

    /// A stored value, bounded on the way in: any process running as the user
    /// can write the property list, so an unknown spelling reads as the standard
    /// order. A retired case is kept in the enum and mapped here, never deleted.
    init(stored raw: String?) {
        self = raw.flatMap(AppSortOrder.init(rawValue:)) ?? .standard
    }
}

/// What the engine says about when the listed apps were last opened.
///
/// Three answers per app, kept apart because the screen draws three things:
/// a date (`opened`), "no record" (asked, and Spotlight had none) and nothing
/// (`unread`: not asked, the read cut short by its ceiling or deadline).
public struct AppOpenedReading: Equatable, Sendable {
    /// Path → last opened. An app that is not here and not in `unread` has no
    /// record.
    public let opened: [String: Date]
    /// Paths this read never got to.
    public let unread: [String]
    init(opened: [String: Date], unread: [String] = []) {
        self.opened = opened
        self.unread = unread
    }
}

/// The order of the Apps tab, as a pure function so it is tested without a
/// window and never decided inside a view.
public enum AppSort {

    /// Whether the date order can mean anything: only when Spotlight answered
    /// for at least one app. With no date at all, every row would read "no
    /// record" and the order would be the name order presented as a measurement.
    /// `nil` is a reading that has not been taken yet.
    public static func dateOrderAvailable(_ opened: [String: Date]?) -> Bool {
        !(opened?.isEmpty ?? true)
    }

    /// What the list is actually ordered by. A stored date order with nothing to
    /// order by shows as the name order; the stored choice itself is untouched.
    public static func effective(_ order: AppSortOrder, opened: [String: Date]?) -> AppSortOrder {
        order == .dateLastOpened && !dateOrderAvailable(opened) ? .name : order
    }

    /// `sizes` holds only what was measured, keyed by path: an absent path is
    /// "not measured", which is not the same as measured at zero. `opened` is
    /// `nil` until Spotlight has been asked; an absent path is "no record".
    ///
    /// `unread` is what the last-opened read never got to. In the date order those
    /// go after every app with an answer (by name among themselves): the head of
    /// that order says "least evidence this app is used", which Helm cannot say
    /// of an app it did not ask about.
    ///
    /// Ties fall to the name, then the path, so two rows equal in the key do not
    /// trade places on every redraw and two copies of one app stay put.
    public static func sorted(_ apps: [InstalledApp], order: AppSortOrder,
                              sizes: [String: Int], opened: [String: Date]?,
                              unread: Set<String> = []) -> [InstalledApp] {
        switch effective(order, opened: opened) {
        case .name:
            return apps.sorted(by: byName)
        case .size:
            // Nothing measured yet: the name order, until the sizes arrive.
            guard !sizes.isEmpty else { return apps.sorted(by: byName) }
            return apps.sorted { a, b in
                let (ga, gb) = (sizeGroup(a, sizes), sizeGroup(b, sizes))
                if ga != gb { return ga < gb }
                if ga == 0, let sa = sizes[a.path], let sb = sizes[b.path], sa != sb { return sa > sb }
                return byName(a, b)
            }
        case .dateLastOpened:
            let dates = opened ?? [:]
            return apps.sorted { a, b in
                let (ua, ub) = (unread.contains(a.path) && dates[a.path] == nil,
                                unread.contains(b.path) && dates[b.path] == nil)
                if ua != ub { return ub }
                switch (dates[a.path], dates[b.path]) {
                case (nil, nil): return byName(a, b)
                case (nil, _): return true
                case (_, nil): return false
                case (let da?, let db?): return da != db ? da < db : byName(a, b)
                }
            }
        }
    }

    /// 0 = measured above zero, 1 = not measured, 2 = measured as nothing. A
    /// bundle that read as zero promises nothing to free, so it cannot lead.
    private static func sizeGroup(_ app: InstalledApp, _ sizes: [String: Int]) -> Int {
        guard let size = sizes[app.path] else { return 1 }
        return size > 0 ? 0 : 2
    }

    private static func byName(_ a: InstalledApp, _ b: InstalledApp) -> Bool {
        switch a.name.localizedCaseInsensitiveCompare(b.name) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return a.path < b.path
        }
    }
}
