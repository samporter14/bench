// RemoteBudget.swift — how much each paired device may ask of Bench (DESIGN.md,
// Bench on your phone → Budgets). A token bucket on every authenticated
// `/api/*` route, at most two file transfers and two event streams at a time,
// Open on Mac once every 3 s and the test push three times a minute. A
// device may be lost or stolen, or simply buggy: none of this should let it
// hold Bench's memory, the page's main thread or the shared push key.
//
// Pure and tested; the server keeps one `DeviceBudgets` and asks it before
// it answers. Over budget is 429 `{"error":"slowDown"}`, two transfers
// already under way 429 `{"error":"busy"}`, each with a `Retry-After`.
import Foundation

// MARK: The bucket

/// 120 tokens a device, refilled evenly at two a second (120 a minute) and
/// never more than 120 saved up. A route costs what it makes Bench do
/// (`RemoteRoute.cost`).
struct RequestBucket {
    static let capacity = 120.0
    static let perSecond = 2.0

    private var buckets: [String: (tokens: Double, at: Date)] = [:]

    /// Spends `cost` when the device has it. Nil when it was spent; else the
    /// whole seconds until it would have it.
    mutating func spend(_ cost: Int, device: String, at now: Date) -> Int? {
        // A device whose bucket would be full again is forgotten.
        let refill = Self.capacity / Self.perSecond
        buckets = buckets.filter { now.timeIntervalSince($0.value.at) < refill }
        var bucket = buckets[device] ?? (Self.capacity, now)
        // A clock that went back refills nothing.
        let elapsed = max(0, now.timeIntervalSince(bucket.at))
        bucket = (min(Self.capacity, bucket.tokens + elapsed * Self.perSecond), max(bucket.at, now))
        let price = Double(cost)
        guard bucket.tokens >= price else {
            buckets[device] = bucket
            return max(1, Int(((price - bucket.tokens) / Self.perSecond).rounded(.up)))
        }
        bucket.tokens -= price
        buckets[device] = bucket
        return nil
    }
}

extension RemoteRoute {
    /// What a request on this route spends from its device's bucket: the
    /// whole conversation's pages and one turn whole read the page with
    /// care (3), a file's thumbnail or text likewise (3), and a download up
    /// to 8 MB more still (10), as does a photo (decoded, drawn again and
    /// handed to the page: Phase 4). Everything else is 1.
    var cost: Int {
        switch self {
        case .history, .turn: 3
        case .files(.download): 10
        case .files(.thumb), .files(.text): 3
        case .photo: RemotePhotoRoute.cost // Phase 4 photos
        default: 1
        }
    }

    /// A file's bytes, read through the page and held whole until sent:
    /// `/api/files/<v>/thumb`, `/text` and `/download`.
    var isTransfer: Bool {
        switch self {
        case .files(.thumb), .files(.text), .files(.download): true
        default: false
        }
    }
}

// MARK: Windows

/// At most `limit` in any `window` seconds per device, counted when allowed.
struct DeviceWindow {
    let limit: Int
    let window: TimeInterval
    private var times: [String: [Date]] = [:]

    init(limit: Int, window: TimeInterval) {
        self.limit = limit
        self.window = window
    }

    /// Nil when one more is allowed now; else the whole seconds until it is.
    func wait(_ device: String, at now: Date) -> Int? {
        let recent = (times[device] ?? []).filter { now.timeIntervalSince($0) < window && $0 <= now }
        guard recent.count >= limit, let oldest = recent.min() else { return nil }
        return max(1, Int((window - now.timeIntervalSince(oldest)).rounded(.up)))
    }

    mutating func record(_ device: String, at now: Date) {
        times = times.compactMapValues { list in
            let recent = list.filter { now.timeIntervalSince($0) < window && $0 <= now }
            return recent.isEmpty ? nil : recent
        }
        times[device, default: []].append(now)
    }
}

// MARK: Everything a device may ask

/// The budgets of every device together, in the order the server asks:
/// two transfers under way already (busy: nothing is spent), the route's
/// own window (`/open`, `/api/push/test`), then the bucket.
struct DeviceBudgets {
    /// File transfers a device may have under way at once.
    static let transfers = 2

    private var bucket = RequestBucket()
    private var opens = DeviceWindow(limit: 1, window: 3)
    private var pushTests = DeviceWindow(limit: 3, window: 60)
    private var underWay: [String: Int] = [:]

    enum Verdict: Equatable {
        /// Go on. `transfer`: one more of the device's transfers is under
        /// way, until `finishTransfer`.
        case go(transfer: Bool)
        /// 429 with this error word, and `Retry-After` in whole seconds.
        case refuse(error: String, retryAfter: Int)
    }

    static let slowDown = "slowDown"
    static let busy = "busy"

    mutating func admit(_ route: RemoteRoute, device: String, at now: Date) -> Verdict {
        if route.isTransfer, underWay[device, default: 0] >= Self.transfers {
            return .refuse(error: Self.busy, retryAfter: 1)
        }
        if let wait = window(for: route)?.wait(device, at: now) {
            return .refuse(error: Self.slowDown, retryAfter: wait)
        }
        if let wait = bucket.spend(route.cost, device: device, at: now) {
            return .refuse(error: Self.slowDown, retryAfter: wait)
        }
        switch route {
        case .openSession: opens.record(device, at: now)
        case .push(.test): pushTests.record(device, at: now)
        default: break
        }
        guard route.isTransfer else { return .go(transfer: false) }
        underWay[device, default: 0] += 1
        return .go(transfer: true)
    }

    /// A transfer is over: its response was sent, or its connection went.
    mutating func finishTransfer(device: String) {
        guard let count = underWay[device] else { return }
        underWay[device] = count > 1 ? count - 1 : nil
    }

    func transfersUnderWay(_ device: String) -> Int { underWay[device, default: 0] }

    private func window(for route: RemoteRoute) -> DeviceWindow? {
        switch route {
        case .openSession: opens
        case .push(.test): pushTests
        default: nil
        }
    }
}

// MARK: Event streams

/// At most two event streams a device and eight in all. A phone that
/// reconnects leaves its last stream behind until the drop is noticed, so
/// the oldest goes: that device's own first, so one device can't push out
/// another's.
enum StreamCap {
    static let perDevice = 2
    static let total = 8

    struct Stream: Equatable {
        let id: Int
        let device: String
        let opened: Date
    }

    /// The streams to close so one more for `device` fits.
    static func toClose(_ streams: [Stream], for device: String) -> [Int] {
        var open = streams.sorted { ($0.opened, $0.id) < ($1.opened, $1.id) }
        let mine = open.filter { $0.device == device }
        var closing = mine.prefix(max(0, mine.count - perDevice + 1)).map(\.id)
        open.removeAll { closing.contains($0.id) }
        closing += open.prefix(max(0, open.count - total + 1)).map(\.id)
        return closing
    }
}
