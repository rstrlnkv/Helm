import Foundation
import HelmUI

/// The name a new folder gets: the category the Mac App Store files an app under, in the app's language.
///
/// The words are copied from two tables of macOS, never read from them at run time (private files in a layout nobody
/// promised), into the module's catalog (`categoryBusiness` ...) and the kit's (`Utilities`, `Video`, which the host and
/// Autopilot draw too: `HelmWord`). The first source is the iPhone's own folder-naming table, `FolderNaming.loctable` in
/// `FrontBoard.framework`, which is what a person sees when the phone names a folder; the second, for the categories that table
/// lacks (Developer Tools, Graphics & Design, Video, Food & Drink, Magazines & Newspapers, Shopping), is the type descriptions of
/// `public.app-category.*` in `CoreTypes.bundle`'s `InfoPlist.loctable` (`Architecture/Launchpad.md` § Folder names). Every
/// games subtype is Games.
enum LaunchpadCategoryName {
    private static let prefix = "public.app-category."

    /// The category's name, or nil when it is none of the known ones.
    static func name(for category: String?, language: AppLanguage = AppLanguage.current) -> String? {
        guard let category, category.lowercased().hasPrefix(prefix) else { return nil }
        let name = category.lowercased().dropFirst(prefix.count)
        func word(_ resource: LocalizedStringResource) -> String { L(resource, language: language) }
        if name.hasSuffix("-games") { return word(.categoryGames) }
        switch name {
        case "books": return word(.categoryBooks)
        case "bookmarks": return word(.categoryBookmarks)
        case "business": return word(.categoryBusiness)
        case "developer-tools": return word(.categoryDeveloperTools)
        case "education": return word(.categoryEducation)
        case "entertainment": return word(.categoryEntertainment)
        case "finance": return word(.categoryFinance)
        case "food-and-drink": return word(.categoryFoodAndDrink)
        case "games": return word(.categoryGames)
        case "graphics-design": return word(.categoryGraphicsDesign)
        case "healthcare-fitness": return word(.categoryHealthFitness)
        case "lifestyle": return word(.categoryLifestyle)
        case "magazines-and-newspapers": return word(.categoryMagazinesAndNewspapers)
        case "medical": return word(.categoryMedical)
        case "music": return word(.categoryMusic)
        case "navigation": return word(.categoryNavigation)
        case "news": return word(.categoryNews)
        case "photography": return word(.categoryPhotography)
        case "photography-and-video": return word(.categoryPhotographyAndVideo)
        case "productivity": return word(.categoryProductivity)
        case "reference": return word(.categoryReference)
        case "shopping": return word(.categoryShopping)
        case "social-networking": return word(.categorySocialNetworking)
        case "sports": return word(.categorySports)
        case "travel": return word(.categoryTravel)
        case "utilities": return HelmWord.utilities(language: language)
        case "video": return HelmWord.video(language: language)
        case "weather": return word(.categoryWeather)
        default: return nil
        }
    }

    /// The target's category, else the dropped app's, else "Others".
    static func folderName(target: String?, dropped: String?) -> String {
        name(for: target) ?? name(for: dropped) ?? L(.categoryOther)
    }
}
