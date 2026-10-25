// AnotherModel.swift — Ask Another Model's setting, key and list of models
// (DESIGN.md, Ask another model), and its Settings section. Claude sometimes
// won't answer; this is a side door to a model at Abliteration.ai (an
// OpenAI-compatible API) that the user chooses to open, reply by reply. It can't
// change the model Claude Science itself uses.
//
// Off by default, and it works only with the user's own key. The key is pasted
// by the user, kept in one file only the user can read (`FileDeviceStore`:
// Application Support/Bench, folder 0700, file 0600), read from that file each
// time it is sent, and sent only in the Authorization header to the address in
// Settings. It is never in the Keychain (Capsid is signed without a Team ID, so
// every update would ask for the password), never in UserDefaults and never in
// the log. Off, or with no key, nothing of the feature shows: no toolbar button,
// no menu item, no window.
//
// The log (`another-model`) says what happened in fixed words and counts:
// "Another model: asked, 812 characters, answered in 9 s". Never the question,
// the answer, the conversation, a model's name or the key.
import Foundation
import os
import SwiftUI

private let anotherModelLog = Logger(subsystem: "local.sam.bench", category: "another-model")

@MainActor
final class AnotherModel: ObservableObject {
    static let shared = AnotherModel(store: FileDeviceStore(name: AnotherModelKey.fileName), defaults: .standard,
                                     client: .shared, log: AnotherModel.writeLog)

    /// Settings → General → Another model's switch (`askAnotherModel`).
    @Published private(set) var isOn: Bool
    /// A key is saved.
    @Published private(set) var hasKey: Bool
    /// The address's models, as last listed.
    @Published private(set) var listing: Listing = .idle
    /// Why the last Save didn't keep the key, until the next try.
    @Published private(set) var keyProblem: String?

    enum Listing: Equatable {
        case idle
        case loading
        case listed([String])
        case failed(String)
    }

    let defaults: UserDefaults
    private let store: RemoteDeviceStore
    private let client: AnotherModelClient
    private let log: @MainActor (String) -> Void
    private var listTask: Task<Void, Never>?

    init(store: RemoteDeviceStore, defaults: UserDefaults, client: AnotherModelClient,
         log: @escaping @MainActor (String) -> Void) {
        self.store = store
        self.defaults = defaults
        self.client = client
        self.log = log
        isOn = defaults.bool(forKey: SettingsKey.askAnotherModel)
        hasKey = Self.key(in: store) != nil
    }

    /// The switch is on and a key is saved: only then does anything show.
    var isAvailable: Bool { isOn && hasKey }

    func setOn(_ on: Bool) {
        defaults.set(on, forKey: SettingsKey.askAnotherModel)
        isOn = on
        if on, hasKey, case .idle = listing { listModels() }
    }

    // MARK: The address and the model

    /// The address as typed in Settings, or Abliteration.ai's.
    var address: String {
        defaults.string(forKey: SettingsKey.anotherModelAddress) ?? AnotherModelAddress.usual
    }

    var addressURL: URL? { AnotherModelAddress.url(address) }

    /// The host the sentences name: the address's, or the usual one's while
    /// the address isn't one.
    var host: String {
        AnotherModelAddress.host(address) ?? AnotherModelAddress.host(AnotherModelAddress.usual) ?? "the address"
    }

    /// The model chosen, as the address lists it; nil before one is.
    var model: String? {
        guard let name = defaults.string(forKey: SettingsKey.anotherModelName), !name.isEmpty else { return nil }
        return name
    }

    /// The address was edited: the list belongs to the address it came from,
    /// so it is dropped until it is asked for again (Return, or List Models).
    /// Nothing is sent to an address while it is being typed.
    func addressEdited() {
        listTask?.cancel()
        if hasKey { listing = .idle }
    }

    func choose(_ model: String) {
        defaults.set(model, forKey: SettingsKey.anotherModelName)
        objectWillChange.send()
    }

    // MARK: The key

    /// Keeps a pasted key in its file. False, with `keyProblem` said, when it
    /// isn't one or couldn't be written.
    @discardableResult
    func saveKey(_ pasted: String) -> Bool {
        guard let key = AnotherModelKey.cleaned(pasted) else {
            keyProblem = "That doesn\u{2019}t look like a key. Paste it again, all of it."
            return false
        }
        do {
            try store.save(Data(key.utf8))
        } catch {
            keyProblem = "Couldn\u{2019}t save the key on this Mac."
            log("Another model: the key couldn't be saved")
            return false
        }
        keyProblem = nil
        hasKey = true
        log("Another model: key saved")
        listModels()
        return true
    }

    /// Deletes the key's file. The list goes with it; the model chosen stays,
    /// for the next key.
    func removeKey() {
        try? store.delete()
        hasKey = Self.key(in: store) != nil
        listTask?.cancel()
        listing = .idle
        keyProblem = nil
        log("Another model: key removed")
    }

    /// The key, read from its file now: it is never kept in memory beyond a
    /// request.
    func currentKey() -> String? {
        Self.key(in: store)
    }

    private static func key(in store: RemoteDeviceStore) -> String? {
        guard let data = try? store.load() else { return nil }
        return AnotherModelKey.cleaned(String(decoding: data, as: UTF8.self))
    }

    // MARK: Asking

    /// Lists the address's models (`GET /models`). With none chosen yet, or
    /// the chosen one gone from the list, the first is chosen.
    func listModels() {
        listTask?.cancel()
        // Off: nothing is asked of the address, not even the list.
        guard isOn else {
            listing = .idle
            return
        }
        guard let url = addressURL else {
            listing = .failed(AnotherModelFailure.notSet(.address).sentence(host: host, limit: client.listLimit, inSettings: true))
            return
        }
        guard let key = currentKey() else {
            listing = .idle
            return
        }
        listing = .loading
        let host = host, limit = client.listLimit
        listTask = Task { [weak self] in
            guard let self else { return }
            let result = await client.models(address: url, key: key)
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let names):
                listing = .listed(names)
                if let first = names.first, !names.contains(model ?? "") { choose(first) }
                log("Another model: listed \(names.count) models")
            case .failure(let failure):
                listing = .failed(failure.sentence(host: host, limit: limit, inSettings: true))
                log("Another model: listing models failed, \(failure.word)")
            }
        }
    }

    /// Asks the chosen model, with the key read from its file now; `progress`
    /// hears the words as they arrive. Nothing is sent while the switch is off,
    /// even from a window left open.
    func ask(_ turns: [ChatTurn], progress: @escaping @MainActor (AskProgress) -> Void = { _ in }) async -> AnotherModelAnswer {
        guard isOn else { return .failed(.notSet(.switchedOff)) }
        guard let url = addressURL else { return .failed(.notSet(.address)) }
        guard let key = currentKey() else { return .failed(.notSet(.key)) }
        guard let model else { return .failed(.notSet(.model)) }
        return await client.ask(address: url, key: key, model: model, turns: turns, progress: progress)
    }

    var askLimit: Duration { client.askLimit }

    /// A line in Capsid's log: fixed words and counts only, so it is public.
    static func writeLog(_ line: String) {
        anotherModelLog.notice("\(line, privacy: .public)")
    }
}

// MARK: Settings → General

/// "Another model": the switch, and while it is on, the key (pasted, then
/// Save; Remove once saved), the address, the model from the address's own
/// list, and one line on what is sent and where.
struct AnotherModelSection: View {
    @ObservedObject var model: AnotherModel
    @AppStorage private var address: String
    @State private var draft = ""

    init(model: AnotherModel = .shared) {
        self.model = model
        _address = AppStorage(wrappedValue: AnotherModelAddress.usual, SettingsKey.anotherModelAddress, store: model.defaults)
    }

    var body: some View {
        Section("Another model") {
            Toggle(isOn: Binding(get: { model.isOn }, set: { model.setOn($0) })) {
                Text("Ask another model")
                Text("Ask a model at another provider, with your own key: from the toolbar, the File menu or Claude Science\u{2019}s model menu.")
            }
            if model.isOn {
                keyRow
                LabeledContent {
                    TextField("Address", text: $address, prompt: Text(AnotherModelAddress.usual))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 250)
                        .onSubmit { model.listModels() }
                        .onChange(of: address) { model.addressEdited() }
                } label: {
                    Text("Address")
                    Text(AnotherModelAddress.url(address) == nil
                         ? "Use an https address, like \(AnotherModelAddress.usual)."
                         : "An OpenAI-compatible API, https only.")
                }
                if model.hasKey { modelRow }
                Text("What you send goes to \(model.host). Capsid sends only what you see in the window.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { if model.isAvailable, case .idle = model.listing { model.listModels() } }
    }

    private var keyRow: some View {
        LabeledContent {
            if model.hasKey {
                HStack(spacing: 8) {
                    Text(verbatim: "\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Key saved")
                    Button("Remove") { model.removeKey() }
                }
            } else {
                HStack(spacing: 8) {
                    SecureField("Key", text: $draft, prompt: Text("Paste your key"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                        .onSubmit(save)
                    Button("Save", action: save)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        } label: {
            Text("Key")
            if let problem = model.keyProblem {
                Text(problem).foregroundStyle(Theme.clayText)
            } else {
                Text(model.hasKey ? "Saved on this Mac, in a file only you can read."
                                  : "Your own Abliteration.ai key. Capsid keeps it in a file only you can read.")
            }
        }
    }

    @ViewBuilder
    private var modelRow: some View {
        LabeledContent {
            switch model.listing {
            case .listed(let names) where !names.isEmpty:
                Picker("Model", selection: Binding(get: { model.model ?? "" }, set: { model.choose($0) })) {
                    ForEach(names, id: \.self) { Text($0).tag($0) }
                    // A model chosen before and not listed now: still shown, so the choice reads true.
                    if let chosen = model.model, !names.contains(chosen) {
                        Text("\(chosen) (not listed)").tag(chosen)
                    }
                }
                .labelsHidden()
                .fixedSize()
            case .loading:
                ProgressView().controlSize(.small)
            case .failed:
                Button("Try Again") { model.listModels() }
            default:
                Button("List Models") { model.listModels() }
            }
        } label: {
            Text("Model")
            switch model.listing {
            case .failed(let sentence): Text(sentence)
            case .listed(let names) where names.isEmpty: Text("The address lists no models.")
            case .loading: Text("Asking the address for its models\u{2026}")
            default: Text("From the address\u{2019}s own list.")
            }
        }
    }

    private func save() {
        if model.saveKey(draft) { draft = "" }
    }
}
