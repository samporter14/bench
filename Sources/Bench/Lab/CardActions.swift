// CardActions.swift — what a needs-input card offers, and doing it (DESIGN.md,
// Answering from the card, and Activity list → Acting from a row). The card
// (LabPanelView) and the activity list's rows (ActivityList) both read
// `CardOffer.of` for what may be done and call `CardActions.perform` to do it,
// so a row can never offer, send or word anything a card would not: the same
// states, the same gates (the card's settings are what lets `PlanApprover` and
// `QuestionReplier` hold a state at all), and the same core beneath
// (`PlanApprover.approve`, `QuestionReplier.decide`, the reply window).
import Foundation

/// One thing a needs-input card can do.
enum CardAction: Equatable, Sendable {
    case approve, reply, review, allowOnce, deny, requestChanges
    /// Open the session in Capsid (a card's Open; "Open in Capsid" where the
    /// card has no answer of its own to offer).
    case open, openInCapsid

    /// The card's button.
    var title: String {
        switch self {
        case .approve: "Approve"
        case .reply: "Reply"
        case .review: "Review"
        case .allowOnce: "Allow Once"
        case .deny: "Deny"
        case .requestChanges: "Request changes…"
        case .open: "Open"
        case .openInCapsid: "Open in Capsid"
        }
    }

    /// A row's button: those that open a window say so with an ellipsis.
    var rowTitle: String {
        switch self {
        case .reply: "Reply…"
        case .review: "Review…"
        default: title
        }
    }

    var help: String? {
        switch self {
        case .approve: "Approve this plan. Capsid checks it's still the same plan first."
        case .reply: "Answer here. Capsid checks it's still the same question before sending."
        case .review: "Read the code, then allow it once or deny it."
        case .allowOnce: "Allow this once. Capsid checks it's still the same request first."
        case .deny: "Deny it. Claude carries on without it."
        case .requestChanges: "Tell Claude what to change. The plan waits for your approval again."
        case .open, .openInCapsid: nil
        }
    }

    /// Whether it opens a window of its own (the reply window), which is
    /// where a row's popover steps aside; the others show their outcome in place.
    var opensWindow: Bool {
        switch self {
        case .reply, .review, .requestChanges: true
        default: false
        }
    }
}

/// What a needs-input card shows where its buttons are, from the states the
/// card reads. Pure: every card and every row is told by this, one case at a time.
struct CardOffer: Equatable, Sendable {
    enum Lead: Equatable, Sendable {
        /// The primary button: Approve, Reply, Review or Allow Once, else
        /// Open (the card's, in the clay).
        case button(CardAction)
        /// The answer is on its way: a spinner, named for VoiceOver.
        case sending(String)
        /// It went: this line, with a checkmark, in place of the buttons.
        case done(String)
    }

    var lead: Lead
    /// A plain Open after the lead.
    var hasOpen = false
    /// Deny, after the lead: where the Mac's table says a plain no is all it is.
    var hasDeny = false
    /// Later's menu offers Open itself, for a card with no room for its own.
    var laterHasOpen = false
    /// Request changes… under a plan: while it is ready to approve, or when
    /// approving it didn't go.
    var canRequestChanges = false
    /// Why a send didn't go, or a request that changed or is gone: a sentence
    /// for under the title.
    var problem: String?

    /// What a card offers for a session waiting for `reason`, from the states
    /// the card has read: the plan's, the question or request's, and where
    /// each reply stands. A state is only read while the card's settings are
    /// on, so with them off there are none and the offer is just Open.
    static func of(reason: WaitingReason?, plan: PlanCardState?, question: QuestionCardState?,
                   reply: ReplyPhase?, permission: ReplyPhase?) -> CardOffer {
        let reason = reason ?? .other
        let plan = reason == .plan ? plan : nil
        let question = QuestionCardState.reads(reason) ? question : nil
        if let question, plan == nil {
            return offer(question, reply: reply, permission: permission)
        }
        return offer(plan)
    }

    /// A plan's card: Approve while it is ready, its progress and its
    /// "Approved" after, Open otherwise.
    private static func offer(_ plan: PlanCardState?) -> CardOffer {
        switch plan {
        case .approved?:
            return CardOffer(lead: .done("Approved"))
        case .ready?:
            return CardOffer(lead: .button(.approve), hasOpen: true, canRequestChanges: true)
        case .approving?:
            return CardOffer(lead: .sending("Approving"), hasOpen: true)
        case .problem(let message, _)?:
            return CardOffer(lead: .button(.open), canRequestChanges: true, problem: message)
        default:
            return CardOffer(lead: .button(.open))
        }
    }

    /// Any other wait's card: a question's Reply, or a permission request's
    /// buttons from the Mac's table.
    private static func offer(_ question: QuestionCardState, reply: ReplyPhase?, permission: ReplyPhase?) -> CardOffer {
        switch (question, reply) {
        case (.ready, .sending?):
            return CardOffer(lead: .sending("Sending the answer"), hasOpen: true)
        case (.ready, .sent?):
            return CardOffer(lead: .done("Sent"))
        case (.ready, _):
            return CardOffer(lead: .button(.reply), hasOpen: true)
        case (.permission(let request), _):
            return offer(request, phase: permission)
        case (.unsupported, _):
            return CardOffer(lead: .button(.openInCapsid))
        default:
            return CardOffer(lead: .button(.open))
        }
    }

    /// A permission request: code to run is read in the reply window first
    /// (Review), a read-only tool may be allowed once right here, and Deny
    /// wherever a plain no is all a deny is. The rest open in Capsid, which also
    /// offers how long an allow lasts.
    private static func offer(_ request: PermissionRequest, phase: ReplyPhase?) -> CardOffer {
        let decision = RemotePermission.decideOnMac(request)
        switch phase {
        case .sending?:
            return CardOffer(lead: .sending("Sending"), hasOpen: true)
        case .sent(let sentence)?:
            return CardOffer(lead: .done(sentence == PermissionDecide.Sentence.allowed ? "Allowed once" : "Denied"))
        case .closed(let sentence)?:
            return CardOffer(lead: .button(.open), problem: sentence)
        default:
            let lead: CardAction = if decision.canAllow, request.known == .localExec {
                .review
            } else if decision.canAllow {
                .allowOnce
            } else {
                decision.canDeny ? .open : .openInCapsid
            }
            var problem: String?
            switch phase {
            case .changed(let sentence)?, .failed(let sentence)?: problem = sentence
            default: break
            }
            return CardOffer(lead: .button(lead), hasDeny: decision.canDeny, laterHasOpen: decision.canAllow,
                             problem: problem)
        }
    }

    /// What a row of the activity list offers on hover: the answers (not Open,
    /// which the row is), in the order the card puts them.
    var rowActions: [CardAction] {
        var actions: [CardAction] = []
        if case .button(let lead) = lead, lead != .open, lead != .openInCapsid { actions.append(lead) }
        if hasDeny { actions.append(.deny) }
        if canRequestChanges { actions.append(.requestChanges) }
        return actions
    }
}

/// Reads and does what cards and rows offer. Tests make their own, over their
/// own model and fakes; the app uses `shared`.
@MainActor
struct CardActions {
    static let shared = CardActions(model: .shared, plans: .shared, questions: .shared)

    let model: LabModel
    let plans: PlanApprover
    let questions: QuestionReplier
    /// Opens the reply window on a session: `plan` for what to change in its plan.
    var showReply: (String, Bool) -> Void = { ReplyWindowController.shared.show($0, plan: $1) }

    /// What the session's needs-input card offers now.
    func offer(for session: SessionStatus) -> CardOffer {
        let id = session.id
        return CardOffer.of(reason: session.waitingReason, plan: plans.state(for: id), question: questions.cardState(for: id),
                            reply: questions.replies[id]?.phase, permission: questions.permissionReplies[id]?.phase)
    }

    /// Reads what a card in the queue would show, if nothing has: the card on
    /// top is read as it comes, any other when a row asks (hover, focus, the
    /// list opening). Nothing when the card's settings are off or the session
    /// has no card in the queue.
    func prepare(_ session: SessionStatus) {
        if session.waitingReason == .plan {
            plans.prepare(session.id)
        } else {
            questions.prepare(session.id)
        }
    }

    /// Does what the card's button does, by the same calls.
    func perform(_ action: CardAction, for session: SessionStatus) {
        switch action {
        case .approve: plans.approve(session.id)
        case .allowOnce: questions.decide(session.id, allow: true)
        case .deny: questions.decide(session.id, allow: false)
        case .reply, .review: showReply(session.id, false)
        case .requestChanges: showReply(session.id, true)
        case .open, .openInCapsid: model.open(session)
        }
    }
}
