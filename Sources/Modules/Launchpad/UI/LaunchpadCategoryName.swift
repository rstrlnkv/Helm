import Foundation
import HelmUI
import Module_Launchpad_Engine

/// The name a new folder gets: the category the Mac App Store files an app under, in the app's language.
///
/// The words are copied from two tables of macOS, never read from them at run time (private files in a layout nobody
/// promised), into the module's catalog (`categoryBusiness` ...) and the kit's (`Utilities`, `Video`, which the host and
/// Autopilot draw too: `HelmWord`). The first source is the iPhone's own folder-naming table, `FolderNaming.loctable` in
/// `FrontBoard.framework`, which is what a person sees when the phone names a folder; the second, for the categories that table
/// lacks (Developer Tools, Graphics & Design, Video, Food & Drink, Magazines & Newspapers, Shopping), is the type descriptions of
/// `public.app-category.*` in `CoreTypes.bundle`'s `InfoPlist.loctable` (`Architecture/Launchpad.md` § The catalog and the layout). Every
/// games subtype is Games.
enum LaunchpadCategoryName {
    /// The category's name, or nil when it is none of the known ones.
    static func name(for category: String?, language: AppLanguage = AppLanguage.current) -> String? {
        LaunchpadCategory(raw: category).map { name(of: $0, language: language) }
    }

    static func name(of category: LaunchpadCategory, language: AppLanguage = AppLanguage.current) -> String {
        func word(_ resource: LocalizedStringResource) -> String { L(resource, language: language) }
        return switch category {
        case .books: word(.categoryBooks)
        case .bookmarks: word(.categoryBookmarks)
        case .business: word(.categoryBusiness)
        case .developerTools: word(.categoryDeveloperTools)
        case .education: word(.categoryEducation)
        case .entertainment: word(.categoryEntertainment)
        case .finance: word(.categoryFinance)
        case .foodAndDrink: word(.categoryFoodAndDrink)
        case .games: word(.categoryGames)
        case .graphicsDesign: word(.categoryGraphicsDesign)
        case .healthFitness: word(.categoryHealthFitness)
        case .lifestyle: word(.categoryLifestyle)
        case .magazinesAndNewspapers: word(.categoryMagazinesAndNewspapers)
        case .medical: word(.categoryMedical)
        case .music: word(.categoryMusic)
        case .navigation: word(.categoryNavigation)
        case .news: word(.categoryNews)
        case .photography: word(.categoryPhotography)
        case .photographyAndVideo: word(.categoryPhotographyAndVideo)
        case .productivity: word(.categoryProductivity)
        case .reference: word(.categoryReference)
        case .shopping: word(.categoryShopping)
        case .socialNetworking: word(.categorySocialNetworking)
        case .sports: word(.categorySports)
        case .travel: word(.categoryTravel)
        case .utilities: HelmWord.utilities(language: language)
        case .video: HelmWord.video(language: language)
        case .weather: word(.categoryWeather)
        }
    }

    /// A block's title in the category view: its category's word, "Recently Added", or "Others".
    static func title(for kind: LaunchpadCategoryBlock.Kind, language: AppLanguage = AppLanguage.current) -> String {
        switch kind {
        case .recent: L(.recentlyAdded, language: language)
        case .others: L(.categoryOther, language: language)
        case .category(let category): name(of: category, language: language)
        }
    }

    /// Where an app can be moved to, as a menu lists it: the 28 categories by title (`localizedStandardCompare`, then slug), then
    /// "Others" last, because it is what is left, not a category. Not cached: the language can change while the app runs.
    static func choices(language: AppLanguage = AppLanguage.current) -> [(target: LaunchpadCategoryTarget, title: String)] {
        let sorted = LaunchpadCategory.allCases.map { (target: LaunchpadCategoryTarget.category($0), title: name(of: $0, language: language)) }
            .sorted {
                let order = $0.title.localizedStandardCompare($1.title)
                return order == .orderedSame ? $0.target.slug < $1.target.slug : order == .orderedAscending
            }
        return sorted + [(target: .others, title: title(for: .others, language: language))]
    }

    /// The target's category, else the dropped app's, else "Others".
    static func folderName(target: String?, dropped: String?) -> String {
        name(for: target) ?? name(for: dropped) ?? L(.categoryOther)
    }
}
