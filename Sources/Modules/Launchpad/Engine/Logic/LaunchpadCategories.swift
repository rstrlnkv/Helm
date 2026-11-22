import Foundation

/// The 28 categories a Mac app can declare (`LSApplicationCategoryType`, `public.app-category.<slug>`), declared once: the slug is
/// the raw value, so the grouping here and the words on the page (`LaunchpadCategoryName`) cannot disagree about which exist.
/// A case added at the end never renumbers a block's id.
public enum LaunchpadCategory: String, CaseIterable, Sendable {
    case books, bookmarks, business
    case developerTools = "developer-tools"
    case education, entertainment, finance
    case foodAndDrink = "food-and-drink"
    case games
    case graphicsDesign = "graphics-design"
    case healthFitness = "healthcare-fitness"
    case lifestyle
    case magazinesAndNewspapers = "magazines-and-newspapers"
    case medical, music, navigation, news, photography
    case photographyAndVideo = "photography-and-video"
    case productivity, reference, shopping
    case socialNetworking = "social-networking"
    case sports, travel, utilities, video, weather

    private static let prefix = "public.app-category."

    /// nil when `raw` is none, is not under the prefix, or names none of the 28; every `*-games` subtype is `.games`.
    public init?(raw: String?) {
        guard let lowered = raw?.lowercased(), lowered.hasPrefix(Self.prefix) else { return nil }
        let slug = String(lowered.dropFirst(Self.prefix.count))
        if slug.hasSuffix("-games") { self = .games; return }
        guard let found = Self(rawValue: slug) else { return nil }
        self = found
    }
}

/// Where a moved app is shown in the category view: one of the 28 categories, or Others. Not the block's `Kind`, which also has
/// `.recent`: that is never a place an app can be sent to. The slug is what the layout file holds, and no category is spelled "others".
public enum LaunchpadCategoryTarget: Hashable, Sendable {
    case category(LaunchpadCategory), others

    /// The app's own: its declared category, or Others when it declares none we know.
    public init(raw: String?) {
        self = LaunchpadCategory(raw: raw).map(Self.category) ?? .others
    }

    /// An exact slug; nil for any other text.
    init?(slug: String) {
        if slug == "others" { self = .others }
        else if let category = LaunchpadCategory(rawValue: slug) { self = .category(category) }
        else { return nil }
    }

    public var slug: String {
        switch self {
        case .category(let category): category.rawValue
        case .others: "others"
        }
    }

    public var kind: LaunchpadCategoryBlock.Kind {
        switch self {
        case .category(let category): .category(category)
        case .others: .others
        }
    }
}

/// One block of the category view: a kind, its apps already in order, and the launches of them all.
public struct LaunchpadCategoryBlock: Equatable, Sendable {
    public enum Kind: Hashable, Sendable {
        case recent, category(LaunchpadCategory), others
    }

    public let kind: Kind
    public let apps: [CatalogApp]
    public let launches: Int

    /// Fixed and independent of the language and of the order, so an open card is found again by it on every snapshot.
    public var id: UUID {
        let number: UInt8 = switch kind {
        case .recent: 0
        case .others: 1
        case .category(let category): UInt8(2 + (LaunchpadCategory.allCases.firstIndex(of: category) ?? 0))
        }
        return UUID(uuid: (0xCA, 0x7E, 0x60, 0x12, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, number))
    }
}

/// **Which blocks the category view shows, in what order, with which apps.** Pure.
///
/// - A hidden app is in no block, "Recently Added" included. Every visible app is in exactly one category block (an app with no
///   known category is in Others), and in "Recently Added" as well when it was added in the last `recentDays`.
/// - "Recently Added" is first, only when it is not empty; its apps are newest added first, then catalog order, not by count (a new
///   app has none, and counting would hide what is new). A date in the future or none is not recent.
/// - Category blocks go by the launches of their apps, most first, ties by name (`localizedStandardCompare`), then kind. Others is
///   always last: it is what is left, not a category. An empty block is not made.
/// - Inside a category: own count, most first, ties by catalog position.
/// - An app in `overrides` is in that block instead of its own, and nowhere else but "Recently Added" (by its date); its launches go with it.
public enum LaunchpadCategories {
    public static let recentDays = 30

    /// Added within the last `recentDays`; a date in the future or none is not recent.
    public static func isRecent(added: Date?, now: Date) -> Bool {
        guard let added else { return false }
        return (0...TimeInterval(recentDays) * 86_400).contains(now.timeIntervalSince(added))
    }

    /// The "new" badge: recent and never opened from Launchpad (`launches` is the app's count there, 0 when it has none).
    public static func isNew(added: Date?, launches: Int, now: Date) -> Bool { launches == 0 && isRecent(added: added, now: now) }

    /// `apps` is the catalog in presentation order; `name` is a block's title in the person's language, for the tie.
    public static func blocks(apps: [CatalogApp], hidden: Set<AppID>, counts: [AppID: Int], now: Date,
                              overrides: [AppID: LaunchpadCategoryTarget] = [:],
                              name: (LaunchpadCategoryBlock.Kind) -> String) -> [LaunchpadCategoryBlock] {
        let visible = apps.enumerated().filter { !hidden.contains($0.element.id) }
        func launches(_ id: AppID) -> Int { counts[id] ?? 0 }
        func byUse(_ a: (offset: Int, element: CatalogApp), _ b: (offset: Int, element: CatalogApp)) -> Bool {
            launches(a.element.id) == launches(b.element.id) ? a.offset < b.offset : launches(a.element.id) > launches(b.element.id)
        }
        func block(_ kind: LaunchpadCategoryBlock.Kind, _ members: [(offset: Int, element: CatalogApp)]) -> LaunchpadCategoryBlock {
            LaunchpadCategoryBlock(kind: kind, apps: members.map(\.element),
                                   launches: members.map { launches($0.element.id) }.saturatingSum())
        }

        var grouped: [LaunchpadCategoryBlock.Kind: [(offset: Int, element: CatalogApp)]] = [:]
        for entry in visible {
            let kind = (overrides[entry.element.id] ?? LaunchpadCategoryTarget(raw: entry.element.category)).kind
            grouped[kind, default: []].append(entry)
        }
        let others = grouped.removeValue(forKey: .others)
        let categories = grouped.map { block($0.key, $0.value.sorted(by: byUse)) }.sorted {
            if $0.launches != $1.launches { return $0.launches > $1.launches }
            let order = name($0.kind).localizedStandardCompare(name($1.kind))
            return order == .orderedSame ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
        }

        let recent = visible.filter { isRecent(added: $0.element.added, now: now) }.sorted {
            let (a, b) = ($0.element.added ?? .distantPast, $1.element.added ?? .distantPast)
            return a == b ? $0.offset < $1.offset : a > b
        }

        return (recent.isEmpty ? [] : [block(.recent, recent)]) + categories + (others.map { [block(.others, $0.sorted(by: byUse))] } ?? [])
    }
}
