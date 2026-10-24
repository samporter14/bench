// QuickStartSettings.swift — Quick Start's part of Settings (DESIGN.md, Quick
// Start): the Recipes page (a grouped form, as the other pages are), and two
// sections of General: Keyboard (the two global keys, as pop-ups) and
// Shortcuts (the one switch that lets a shortcut start a session or send a
// message without asking). Settings stay the system's own controls.
import SwiftUI

// MARK: Recipes

/// Settings → Recipes: add, edit, delete and reorder. The first nine have ⌘1
/// to ⌘9 in Quick Start.
struct RecipesSettingsView: View {
    @State private var recipes: [Recipe] = []
    @State private var projects: [QuickStartProject] = []
    @State private var editing: Recipe?
    @State private var adding = false
    private let store = RecipeStore()
    /// Recipes and projects given instead of read: a snapshot's, which reads
    /// no settings and no database.
    private let seed: (recipes: [Recipe], projects: [QuickStartProject])?

    init(seed: (recipes: [Recipe], projects: [QuickStartProject])? = nil) {
        self.seed = seed
        _recipes = State(initialValue: seed?.recipes ?? [])
        _projects = State(initialValue: seed?.projects ?? [])
    }

    var body: some View {
        Form {
            Section {
                if recipes.isEmpty {
                    Text("No recipes yet. A recipe is a request you make again and again, with the project it belongs to.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(recipes.enumerated()), id: \.element.id) { index, recipe in
                    row(recipe, index: index)
                }
                Button("Add Recipe…") { adding = true }
                    .disabled(recipes.count >= RecipeStore.limit)
            } header: {
                Text("Recipes")
            } footer: {
                Text("The first nine have ⌘1 to ⌘9 in Quick Start. Pressing one fills the panel with its words, its project and its plan setting; nothing is sent until you press Start.")
            }
        }
        .settingsPage(height: 520)
        .task {
            guard seed == nil else { return }
            recipes = store.recipes
            projects = await QuickStartProjects.fromDatabase() ?? []
        }
        .sheet(isPresented: $adding) {
            RecipeEditor(recipe: Recipe(name: "", text: ""), projects: projects, isNew: true) { made in
                recipes.append(made)
                save()
            }
        }
        .sheet(item: $editing) { recipe in
            RecipeEditor(recipe: recipe, projects: projects, isNew: false) { changed in
                if let index = recipes.firstIndex(where: { $0.id == changed.id }) { recipes[index] = changed }
                save()
            }
        }
    }

    private func row(_ recipe: Recipe, index: Int) -> some View {
        LabeledContent {
            HStack(spacing: 8) {
                if index < RecipeStore.keyed {
                    Text("⌘\(index + 1)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Command \(index + 1)")
                }
                Menu {
                    Button("Edit…") { editing = recipe }
                    Divider()
                    Button("Move Up") { move(index, by: -1) }.disabled(index == 0)
                    Button("Move Down") { move(index, by: 1) }.disabled(index == recipes.count - 1)
                    Divider()
                    Button("Delete", role: .destructive) { delete(recipe) }
                } label: {
                    Text("More")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        } label: {
            Text(recipe.name)
            Text(summary(recipe))
        }
    }

    /// "Assay development · asks for a plan first".
    private func summary(_ recipe: Recipe) -> String {
        let place = recipe.project.map { id in projects.first { $0.id == id }?.name ?? "A project that isn't listed" } ?? "Any project"
        return recipe.planFirst ? place + " · asks for a plan first" : place
    }

    private func move(_ index: Int, by step: Int) {
        let target = index + step
        guard recipes.indices.contains(index), recipes.indices.contains(target) else { return }
        recipes.swapAt(index, target)
        save()
    }

    private func delete(_ recipe: Recipe) {
        recipes.removeAll { $0.id == recipe.id }
        save()
    }

    private func save() {
        store.recipes = recipes
    }
}

/// One recipe, in a sheet: its name, its project (or any), its words and
/// whether to ask for a plan first.
struct RecipeEditor: View {
    @State var recipe: Recipe
    let projects: [QuickStartProject]
    let isNew: Bool
    let done: (Recipe) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $recipe.name, prompt: Text("QC a plate-reader export"))
                    Picker("Project", selection: Binding(get: { recipe.project ?? "" }, set: { recipe.project = $0.isEmpty ? nil : $0 })) {
                        Text("Any project").tag("")
                        Divider()
                        ForEach(projects) { Text($0.name).tag($0.id) }
                        // A project saved before and not listed now: kept, so the choice reads true.
                        if let id = recipe.project, !projects.contains(where: { $0.id == id }) {
                            Text("A project that isn't listed").tag(id)
                        }
                    }
                    Toggle("Ask for a plan first", isOn: $recipe.planFirst)
                }
                Section("Request") {
                    TextEditor(text: $recipe.text)
                        .font(.body)
                        .frame(minHeight: 110)
                        .accessibilityLabel("Request")
                }
                if recipe.text.unicodeScalars.count > Recipe.textLimit {
                    Text(QuickStartFlow.Sentence.recipeTooLong).foregroundStyle(.secondary)
                } else if PhotoText.hasReference(recipe.text) {
                    Text(QuickStartFlow.Sentence.reference).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .toggleStyle(.switch)
            .tint(Theme.clay)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") {
                    recipe.name = recipe.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    recipe.text = recipe.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    done(recipe)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!recipe.isUsable || PhotoText.hasReference(recipe.text))
            }
            .padding(16)
        }
        .frame(width: 480, height: 460)
    }
}

// MARK: Keyboard and Shortcuts (Settings → General)

/// The two global keys, as pop-ups. A key another app holds says so.
struct KeyboardSettingsSection: View {
    @AppStorage(SettingsKey.quickStartKey) private var quickStartKey = GlobalHotKey.Slot.quickStart.fallback.rawValue
    @AppStorage(SettingsKey.replyKey) private var replyKey = GlobalHotKey.Slot.reply.fallback.rawValue
    @ObservedObject private var keys = GlobalKeys.shared

    var body: some View {
        Section("Keyboard") {
            picker(.quickStart, selection: $quickStartKey, other: replyKey,
                   detail: "Opens Quick Start from any app: type a request, drop files, press Start.")
            picker(.reply, selection: $replyKey, other: quickStartKey,
                   detail: "Opens Reply on the session that has waited longest, when one needs you.")
        }
    }

    private func picker(_ slot: GlobalHotKey.Slot, selection: Binding<String>, other: String, detail: String) -> some View {
        let chosen = GlobalHotKey.Choice.parse(selection.wrappedValue, fallback: slot.fallback)
        let taken = GlobalHotKey.Choice.parse(other, fallback: .none)
        return Picker(selection: Binding(get: { chosen }, set: { selection.wrappedValue = $0.rawValue; GlobalKeys.shared.apply() })) {
            ForEach(GlobalHotKey.Choice.allCases) { choice in
                Text(choice.title).tag(choice)
                    .disabled(choice != .none && choice == taken)
            }
        } label: {
            Text(slot == .quickStart ? "Quick Start key" : "Reply key")
            if let problem = keys.problems[slot] {
                Text(problem).foregroundStyle(Theme.clayText)
            } else if chosen.mayBeTheInputSourceKey {
                Text("\(detail) macOS uses ⌃⌥Space for the next input source, if you've turned that on in Keyboard settings.")
            } else {
                Text(detail)
            }
        }
    }
}

/// "Let Shortcuts start sessions and send messages", off until chosen.
struct ShortcutsSettingsSection: View {
    @AppStorage(SettingsKey.shortcutsMayAct) private var mayAct = false

    var body: some View {
        Section("Shortcuts") {
            Toggle(isOn: $mayAct) {
                Text("Let Shortcuts start sessions and send messages")
                Text("Off, a shortcut that starts a session or sends a message asks you to confirm first, every time. On, it goes straight through, so only turn it on for shortcuts you trust.")
            }
        }
    }
}
