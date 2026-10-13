// PhoneSetup.swift — Settings → Phone's checklist (DESIGN.md, Settings →
// Phone): six steps from installing Tailscale to pairing a phone, each ticked
// by what Bench detects, never by the user. Pure and tested: what Tailscale,
// the switch and the devices say goes in; which steps are done, which one is
// open, and what each found comes out. PhoneSettings.swift draws it.
import Foundation

enum PhoneSetup {
    enum Step: Int, CaseIterable, Identifiable, Sendable {
        case install = 1, signIn, https, phone, turnOn, pair

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .install: "Install Tailscale on this Mac"
            case .signIn: "Sign in to Tailscale"
            case .https: "Turn on HTTPS for your network"
            case .phone: "Put Tailscale on your phone"
            case .turnOn: "Turn on Bench on your phone"
            case .pair: "Pair your phone"
            }
        }

        /// The one line under the title while the step is open.
        var help: String {
            switch self {
            case .install: "Free. It links your own devices into a private network."
            case .signIn: "Use the same account you'll use on your phone."
            case .https: "One switch on Tailscale's DNS page, so your phone gets a secure address."
            case .phone: "Install Tailscale from the App Store and sign in with the same account."
            case .turnOn: "A private page for your devices on Tailscale. Never on the internet."
            case .pair: "Once per device, with a one-time code."
            }
        }
    }

    // MARK: Where the buttons go

    static let getTailscale = URL(string: "https://tailscale.com/download/mac")!
    /// Tailscale's DNS page, where HTTPS Certificates is turned on.
    static let dnsSettings = URL(string: "https://login.tailscale.com/admin/dns")!
    /// Tailscale in the App Store, for the QR code the phone scans.
    static let appStore = URL(string: "https://apps.apple.com/app/tailscale/id1470499037")!
    static let guide = URL(string: "https://github.com/samporter14/bench/blob/main/docs/phone.md")!

    /// How often the tab looks at Tailscale again while setup isn't done.
    static let pollEvery: Duration = .seconds(5)

    // MARK: The phone

    /// Tailscale's `OS` for a phone or a tablet: iPhones and iPads say
    /// "iOS" (an iPad may say "iPadOS"), Android phones "android".
    static let phoneOSes: Set<String> = ["ios", "ipados", "android"]

    /// A phone or tablet signed in as this Mac's user, online or not: an
    /// online one first, then by name.
    static func phone(in peers: [TailscalePeer]) -> TailscalePeer? {
        peers.filter { $0.sameUser && phoneOSes.contains($0.os.lowercased()) }
            .min { a, b in a.online != b.online ? a.online : a.hostName < b.hostName }
    }

    // MARK: The checklist

    /// What the checklist goes by.
    struct Input: Equatable, Sendable {
        /// A Tailscale CLI that Tailscale signed is here; nil before the
        /// first look.
        var installed: Bool?
        /// The signed-in login, while Tailscale is running (connected).
        var login: String?
        var httpsEnabled = false
        /// The tailnet's other devices.
        var peers: [TailscalePeer] = []
        /// "Skip" was pressed on "Put Tailscale on your phone".
        var skippedPhone = false
        /// Bench's page, while Tailscale serves it.
        var servingURL: URL?
        var devices = 0
        /// "Pair Another Device" was pressed with this many devices paired:
        /// "Pair your phone" is open again until one more pairs.
        var pairingAnotherFrom: Int?
    }

    /// What the checklist shows.
    struct State: Equatable, Sendable {
        var done: Set<Step> = []
        /// The one step open, with its action: the first not done, or
        /// "Pair your phone" again after Pair Another Device. Nil once
        /// everything is done, and before the first look.
        var expanded: Step?
        /// What each done step found: the login, the phone, the address…
        var facts: [Step: String] = [:]
        /// All six done: the section is one summary row.
        var isReady = false
        /// The first look at Tailscale is still under way: nothing is known.
        var isChecking = false
        /// "Ready · 1 device · https://…", once ready.
        var summary: String?

        /// The pairing QR code and one-time code show, and a code is issued,
        /// only while "Pair your phone" is the step open.
        var showsPairing: Bool { expanded == .pair }

        /// The steps after the open one: dimmed, with no buttons.
        func isLater(_ step: Step) -> Bool {
            expanded.map { step.rawValue > $0.rawValue } ?? false
        }
    }

    static func state(_ input: Input) -> State {
        guard let installed = input.installed else { return State(isChecking: true) }
        var state = State()
        var facts: [Step: String] = [:]
        if installed { facts[.install] = "Installed" }
        if let login = input.login { facts[.signIn] = login }
        if input.httpsEnabled { facts[.https] = "On" }
        if let phone = phone(in: input.peers) {
            facts[.phone] = "Found: \(RemoteDevice.cleanName(phone.hostName))"
        } else if input.skippedPhone {
            facts[.phone] = "Skipped"
        }
        if let url = input.servingURL { facts[.turnOn] = shown(url) }
        if input.devices > 0 { facts[.pair] = devices(input.devices) }
        state.facts = facts
        state.done = Set(facts.keys)
        state.isReady = state.done.count == Step.allCases.count
        let pairingAnother = input.pairingAnotherFrom.map { input.devices <= $0 } ?? false
        if state.isReady {
            state.expanded = pairingAnother ? .pair : nil
            state.summary = ["Ready", devices(input.devices), facts[.turnOn]].compactMap { $0 }.joined(separator: " · ")
        } else {
            state.expanded = Step.allCases.first { !state.done.contains($0) }
        }
        return state
    }

    /// "1 device", "2 devices".
    static func devices(_ count: Int) -> String {
        count == 1 ? "1 device" : "\(count) devices"
    }

    /// The address without its trailing slash.
    static func shown(_ url: URL) -> String {
        let text = url.absoluteString
        return text.hasSuffix("/") ? String(text.dropLast()) : text
    }

    /// The line under "Turn on Bench on your phone" once its switch is on,
    /// while Bench isn't served yet; nil for the usual help.
    static func turnOnDetail(_ serve: RemoteController.Status.Serve, port: UInt16?) -> String? {
        switch serve {
        case .off, .serving: nil
        case .starting: "Turning on…"
        case .waitingForTailscale: "Waiting for Tailscale to connect."
        case .httpsOff: "Waiting for HTTPS on your network."
        case .blocked: "Port 8443 already serves something else with Tailscale Serve. Bench leaves it alone."
        case .failed: port == nil ? "Bench couldn't listen on a port from 47280 to 47290." : "Tailscale couldn't serve Bench."
        }
    }
}

extension PhoneSetup.Input {
    /// From what Settings → Phone knows: the controller's status, the
    /// switch, Skip, the devices, and Pair Another Device.
    init(status: RemoteController.Status, enabled: Bool, skippedPhone: Bool, devices: Int, pairingAnotherFrom: Int? = nil) {
        let tailscale = status.tailscaleStatus
        self.init(installed: status.tailscale.map { $0 != .notInstalled },
                  login: tailscale?.running == true ? tailscale?.login : nil,
                  httpsEnabled: tailscale?.httpsEnabled ?? false,
                  peers: tailscale?.peers ?? [],
                  skippedPhone: skippedPhone,
                  servingURL: enabled ? status.url : nil,
                  devices: devices,
                  pairingAnotherFrom: pairingAnotherFrom)
    }
}
