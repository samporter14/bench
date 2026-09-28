// LabModel.swift — STUB, to be replaced by the lab agent (DESIGN.md, "Lab").
// The public surface below is the contract the App relies on; keep every
// name and signature.
import SwiftUI

enum LabCard: Identifiable, Equatable {
    case needsInput(SessionStatus)
    case finished(SessionStatus)
    case web(WebNotification)
    case saved(URL)

    var id: String {
        switch self {
        case .needsInput(let s): "needs-\(s.id)"
        case .finished(let s): "finished-\(s.id)"
        case .web(let n): "web-\(n.id)"
        case .saved(let url): "saved-\(url.path)"
        }
    }
}

@MainActor
final class LabModel: ObservableObject {
    static let shared = LabModel()

    @Published private(set) var working: [SessionStatus] = []
    @Published private(set) var waiting: [SessionStatus] = []
    @Published private(set) var cards: [LabCard] = []

    private init() {}

    /// Starts watching; registers Router.webNotificationArrived and
    /// Router.downloadSaved.
    func start() {}
    func stop() {}
}

@MainActor
final class LabPanelController {
    static let shared = LabPanelController()
    private init() {}
    func start() {}
}

/// The toolbar's live status: a small scene and "Working · 4:12" or
/// "2 need you"; hidden when idle.
struct LabStatusCapsule: View {
    var body: some View { EmptyView() }
}
