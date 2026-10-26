// AnotherModelRulesTests.swift — the search in Settings' Model field
// (AnotherModelRules, since 1.0.6): every typed word must be in the id, case
// and accents aside, in the list's order and a dozen at most; and what Return
// chooses. Made-up ids; nothing is asked of any address.
import Foundation
import Testing
@testable import Bench

struct AnotherModelRulesTests {
    private let names = [
        "anthropic/claude-sonnet-4.5", "openai/gpt-5-mini", "anthropic/claude-opus-4.1",
        "google/gemini-2.5-pro", "vendor/Ménage-Sonnet", "openai/gpt-5",
    ]

    @Test func everyTypedWordMustBeInTheIdInTheListsOrder() {
        #expect(AnotherModelRules.matches(names, query: "sonnet") == ["anthropic/claude-sonnet-4.5", "vendor/Ménage-Sonnet"])
        #expect(AnotherModelRules.matches(names, query: "anthropic sonnet") == ["anthropic/claude-sonnet-4.5"])
        // The words can come in any order, and white space around them doesn't matter.
        #expect(AnotherModelRules.matches(names, query: "  sonnet   anthropic ") == ["anthropic/claude-sonnet-4.5"])
        #expect(AnotherModelRules.matches(names, query: "openai mini") == ["openai/gpt-5-mini"])
        #expect(AnotherModelRules.matches(names, query: "sonnet opus") == [])
        #expect(AnotherModelRules.matches(names, query: "nothing-like-it") == [])
        #expect(AnotherModelRules.matches([], query: "sonnet") == [])
    }

    @Test func caseAndAccentsDoNotMatter() {
        #expect(AnotherModelRules.matches(names, query: "SONNET") == ["anthropic/claude-sonnet-4.5", "vendor/Ménage-Sonnet"])
        #expect(AnotherModelRules.matches(names, query: "menage") == ["vendor/Ménage-Sonnet"])
        #expect(AnotherModelRules.matches(names, query: "MÉNAGE sonnet") == ["vendor/Ménage-Sonnet"])
        // The name comes back as the list spelled it.
        #expect(AnotherModelRules.matches(["vendor/Ménage-Sonnet"], query: "menage") == ["vendor/Ménage-Sonnet"])
    }

    @Test func anEmptyQueryGivesTheFirstOnesAndTheLimitHolds() {
        #expect(AnotherModelRules.maxSuggestions == 12)
        #expect(AnotherModelRules.matches(names, query: "") == names)
        #expect(AnotherModelRules.matches(names, query: "   ") == names)
        #expect(AnotherModelRules.matches(names, query: "", limit: 2) == Array(names.prefix(2)))
        #expect(AnotherModelRules.matches(names, query: "o", limit: 3) == ["anthropic/claude-sonnet-4.5", "openai/gpt-5-mini", "anthropic/claude-opus-4.1"])
        #expect(AnotherModelRules.matches(names, query: "", limit: 0) == [])
        // By default, a dozen of many.
        let many = (1...466).map { "vendor/model-\($0)" }
        let found = AnotherModelRules.matches(many, query: "model")
        #expect(found == Array(many.prefix(12)))
        #expect(AnotherModelRules.matches(many, query: "model-46") == ["vendor/model-46"] + (460...466).map { "vendor/model-\($0)" })
    }

    @Test func returnChoosesWhatTheTextSpells() {
        // A listed name, as typed or in other case: the list's own spelling.
        #expect(AnotherModelRules.choice(typed: "openai/gpt-5", listed: names) == "openai/gpt-5")
        #expect(AnotherModelRules.choice(typed: "OpenAI/GPT-5", listed: names) == "openai/gpt-5")
        #expect(AnotherModelRules.choice(typed: " vendor/menage-sonnet\n", listed: names) == "vendor/Ménage-Sonnet")
        // An id the list leaves out, even when listed names begin with it.
        #expect(AnotherModelRules.choice(typed: "openai/gpt-5-preview", listed: names) == "openai/gpt-5-preview")
        #expect(AnotherModelRules.choice(typed: "gpt", listed: names) == "gpt")
        #expect(AnotherModelRules.choice(typed: "vendor/new", listed: []) == "vendor/new")
    }

    @Test func returnChoosesNothingFromEmptyTextASearchOrNoName() {
        #expect(AnotherModelRules.choice(typed: "", listed: names) == nil)
        #expect(AnotherModelRules.choice(typed: "  \n", listed: names) == nil)
        // Words are a search, not an id.
        #expect(AnotherModelRules.choice(typed: "anthropic sonnet", listed: names) == nil)
        #expect(AnotherModelRules.choice(typed: "bad\u{7}id", listed: names) == nil)
        #expect(AnotherModelRules.choice(typed: String(repeating: "m", count: 201), listed: names) == nil)
        #expect(AnotherModelRules.choice(typed: String(repeating: "m", count: 200), listed: names) == String(repeating: "m", count: 200))
        // A listed name with a space in it (a display name) is still chosen, by its own spelling.
        #expect(AnotherModelRules.choice(typed: "claude sonnet", listed: ["Claude Sonnet"]) == "Claude Sonnet")
    }
}
