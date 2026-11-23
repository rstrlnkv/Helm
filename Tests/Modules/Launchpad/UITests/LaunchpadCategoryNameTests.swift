import HelmUI
import XCTest
@testable import Module_Launchpad_UI

/// The folder names: one word for each of the 28 categories a Mac app can declare, every games subtype Games, anything else
/// nobody's.
final class LaunchpadCategoryNameTests: XCTestCase {
    private let categories = ["bookmarks", "books", "business", "developer-tools", "education", "entertainment", "finance", "food-and-drink",
                              "games", "graphics-design", "healthcare-fitness", "lifestyle", "magazines-and-newspapers", "medical", "music",
                              "navigation", "news", "photography", "photography-and-video", "productivity", "reference", "shopping",
                              "social-networking", "sports", "travel", "utilities", "video", "weather"]
    private let gameSubtypes = ["action-games", "adventure-games", "arcade-games", "board-games", "card-games", "casino-games", "dice-games",
                                "educational-games", "family-games", "kids-games", "music-games", "puzzle-games", "racing-games",
                                "role-playing-games", "simulation-games", "sports-games", "strategy-games", "trivia-games", "word-games"]

    func testEveryCategoryHasAWordOfItsOwnInEveryLanguage() {
        for language in AppLanguage.allCases {
            var words = Set<String>()
            for name in categories {
                let word = LaunchpadCategoryName.name(for: "public.app-category." + name, language: language)
                XCTAssertNotNil(word, name)
                guard let word else { continue }
                XCTAssertFalse(word.isEmpty, "\(name) in \(language)")
                XCTAssertFalse(word.hasPrefix("category"), "\(name) in \(language) is its key: no translation")
                words.insert(word)
            }
            XCTAssertEqual(words.count, categories.count, "\(language): \(categories.count) categories, as many words")
        }
    }

    func testEveryGamesSubtypeIsGamesAndTheMusicAndSportsCategoriesAreNot() {
        for name in gameSubtypes {
            XCTAssertEqual(LaunchpadCategoryName.name(for: "public.app-category." + name), L(.categoryGames), name)
        }
        XCTAssertEqual(LaunchpadCategoryName.name(for: "public.app-category.sports"), L(.categorySports))
        XCTAssertEqual(LaunchpadCategoryName.name(for: "public.app-category.music"), L(.categoryMusic))
    }

    func testUtilitiesAndVideoAreTheKitsWordsAndTheOtherFolderIsAPluralOfItsOwn() {
        XCTAssertEqual(LaunchpadCategoryName.name(for: "public.app-category.utilities"), HelmWord.utilities)
        XCTAssertEqual(LaunchpadCategoryName.name(for: "public.app-category.video"), HelmWord.video)
        XCTAssertEqual(L(.categoryOther, language: .en), "Others")
        XCTAssertEqual(L(.categoryOther, language: .fr), "Autres")
    }

    func testAnUnknownMissingOrForeignCategoryIsNothingAndTheFolderIsOthers() {
        for raw in [nil, "", "public.app-category.", "public.app-category.nonsense", "music", "com.example.games"] as [String?] {
            XCTAssertNil(LaunchpadCategoryName.name(for: raw), "\(raw ?? "nil")")
        }
        XCTAssertEqual(LaunchpadCategoryName.folderName(target: "public.app-category.nonsense", dropped: nil), L(.categoryOther))
        XCTAssertEqual(LaunchpadCategoryName.folderName(target: nil, dropped: "public.app-category.news"), L(.categoryNews))
        XCTAssertEqual(LaunchpadCategoryName.folderName(target: "public.app-category.video", dropped: "public.app-category.news"), HelmWord.video)
    }
}
