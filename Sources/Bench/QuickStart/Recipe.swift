// Recipe.swift — Quick Start's recipes (DESIGN.md, Quick Start → Recipes): a
// request worth saying again, kept with the project it belongs to and whether
// it asks for a plan first. They are the person's own words, so they live in
// settings as one JSON string (`SettingsKey.recipes`), nothing more, and are
// read afresh each time Quick Start opens. ⌘1 to ⌘9 in Quick Start fill the
// panel from the first nine, in the order Settings → Recipes keeps them.
import Foundation

struct Recipe: Identifiable, Equatable, Codable, Sendable {
    var id: String
    var name: String
    /// A project's id, or nil for any project (the one chosen in Quick Start).
    var project: String?
    var text: String
    var planFirst: Bool

    init(id: String = UUID().uuidString.lowercased(), name: String, project: String? = nil, text: String, planFirst: Bool = true) {
        self.id = id
        self.name = name
        self.project = project
        self.text = text
        self.planFirst = planFirst
    }

    /// The most a recipe's name and text may be: the name is a row's label, the
    /// text is a request (`QuickStartFlow.textLimit`).
    static let nameLimit = 80
    static let textLimit = QuickStartFlow.textLimit

    /// Whether Settings may keep it: a name and some text, within the limits.
    var isUsable: Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.count <= Self.nameLimit && !text.isEmpty && text.unicodeScalars.count <= Self.textLimit
    }
}

/// The two things settings storage is asked here: a string, and to keep one.
/// `UserDefaults` is one; a test's is a dictionary, so no preferences file is
/// made for it.
protocol SettingsStoring: AnyObject {
    func string(forKey defaultName: String) -> String?
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: SettingsStoring {}

/// Reads and writes the recipes in settings (the app's own, or a test's).
struct RecipeStore {
    /// ⌘1 to ⌘9.
    static let keyed = 9
    /// More than this is a mistake, not a collection.
    static let limit = 60

    private let defaults: SettingsStoring

    init(defaults: SettingsStoring = UserDefaults.standard) {
        self.defaults = defaults
    }

    /// The recipes, in order. What can't be read (not JSON, the wrong shape)
    /// is none; one that isn't usable (no name, no text) is left out, so a
    /// hand-edited value can't put an empty row in Quick Start.
    var recipes: [Recipe] {
        get { Self.decode(defaults.string(forKey: SettingsKey.recipes)) }
        nonmutating set { defaults.set(Self.encode(newValue), forKey: SettingsKey.recipes) }
    }

    static func decode(_ json: String?) -> [Recipe] {
        guard let json, let data = json.data(using: .utf8),
              let list = try? JSONDecoder().decode([Recipe].self, from: data) else { return [] }
        var seen = Set<String>()
        return list.filter { $0.isUsable && seen.insert($0.id).inserted }.prefix(limit).map { $0 }
    }

    /// The JSON for a list: stable key order, so what is saved doesn't change
    /// when nothing did.
    static func encode(_ recipes: [Recipe]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(Array(recipes.prefix(limit))) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// ⌘1 to ⌘9 over the recipes in Quick Start.
enum RecipeKeys {
    /// The recipe ⌘`number` picks: the number'th of the first nine. Nil for a
    /// number out of 1…9 or past the end.
    static func recipe(for number: Int, in recipes: [Recipe]) -> Recipe? {
        guard (1...RecipeStore.keyed).contains(number), number <= recipes.count else { return nil }
        return recipes[number - 1]
    }

    /// The recipes that have a key: the first nine.
    static func keyed(_ recipes: [Recipe]) -> [Recipe] {
        Array(recipes.prefix(RecipeStore.keyed))
    }
}
