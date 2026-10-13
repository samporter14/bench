// PhoneSettings.swift — Settings → Phone (DESIGN.md, Settings → Phone): a
// checklist that walks a first-time user from installing Tailscale to pairing
// a phone, each step ticked by what Bench detects (PhoneSetup.swift), then a
// single summary row. Below it: the switches, anything Bench needs to say, and
// the devices paired.
//
// The page draws values (`PhoneSetupModel`) and calls closures
// (`PhoneSetupActions`): the live tab passes Bench's own, and `--demo
// phone-settings` made-up ones that do nothing.
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// The live tab: Bench's controller, its devices and Tailscale. While setup
/// isn't done and the tab shows, it looks at Tailscale again every 5 s and
/// whenever Bench comes to the front; never while the tab is hidden.
struct PhoneSettingsView: View {
    @ObservedObject private var remote = RemoteController.shared
    @ObservedObject private var auth = RemoteController.shared.auth
    @AppStorage(SettingsKey.remotePhoneSkipped) private var phoneSkipped = false

    private var model: PhoneSetupModel {
        PhoneSetupModel(status: remote.status, enabled: remote.enabled, phoneSkipped: phoneSkipped,
                        devices: auth.devices, code: auth.code, wornOut: auth.wornOut)
    }

    private var isReady: Bool {
        PhoneSetup.state(model.input()).isReady
    }

    var body: some View {
        PhoneSetupPage(model: model, actions: actions)
            .onAppear {
                // A demo reads no stored devices and asks Tailscale nothing.
                guard Demo.mode == nil else { return }
                auth.load()
                // Devices not seen for 60 days leave the list.
                auth.dropExpired()
                remote.refresh()
            }
            // Cancelled when the tab goes, and once setup is done.
            .task(id: isReady) {
                guard Demo.mode == nil, !isReady else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: PhoneSetup.pollEvery)
                    guard !Task.isCancelled else { return }
                    remote.poll()
                }
            }
            // Back from Tailscale's app or its DNS page in the browser. (The
            // controller looks by itself only while its switch is on.)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                guard Demo.mode == nil, !isReady else { return }
                remote.poll()
            }
    }

    private var actions: PhoneSetupActions {
        let remote = remote
        let auth = auth
        return PhoneSetupActions(
            open: { NSWorkspace.shared.open($0) },
            openTailscale: {
                // Only the app whose signature Bench checked for its CLI.
                guard let binary = TailscaleCLI.locate() else { return }
                let app = binary.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
            },
            setEnabled: { remote.setEnabled($0) },
            skipPhone: { phoneSkipped = true },
            refresh: { remote.refresh() },
            issueCode: { remote.issueCode() },
            newCode: { remote.newCode() },
            withdrawCode: { auth.withdrawCode() },
            remove: { remote.remove($0) },
            removeAll: { remote.removeAll() })
    }
}

/// What the page shows: Bench's own, or made up for a demo.
struct PhoneSetupModel {
    var status: RemoteController.Status
    var enabled: Bool
    var phoneSkipped: Bool
    var devices: [RemoteDevice]
    var code: PairingCode?
    var wornOut = false

    func input(pairingAnotherFrom: Int? = nil) -> PhoneSetup.Input {
        PhoneSetup.Input(status: status, enabled: enabled, skippedPhone: phoneSkipped,
                         devices: devices.count, pairingAnotherFrom: pairingAnotherFrom)
    }
}

/// What the page's buttons and switches do.
struct PhoneSetupActions {
    var open: @MainActor (URL) -> Void
    var openTailscale: @MainActor () -> Void
    var setEnabled: @MainActor (Bool) -> Void
    var skipPhone: @MainActor () -> Void
    /// Try Again.
    var refresh: @MainActor () -> Void
    var issueCode: @MainActor () -> Void
    var newCode: @MainActor () -> Void
    var withdrawCode: @MainActor () -> Void
    var remove: @MainActor (RemoteDevice) -> Void
    var removeAll: @MainActor () -> Void

    /// A demo's: nothing opens, nothing changes, nothing is saved.
    static var none: PhoneSetupActions {
        PhoneSetupActions(open: { _ in }, openTailscale: {}, setEnabled: { _ in }, skipPhone: {}, refresh: {},
                          issueCode: {}, newCode: {}, withdrawCode: {}, remove: { _ in }, removeAll: {})
    }
}

// MARK: The page

struct PhoneSetupPage: View {
    let model: PhoneSetupModel
    let actions: PhoneSetupActions
    /// Pair Another Device was pressed with this many devices paired.
    @State private var pairingAnotherFrom: Int?
    @State private var confirmingRemoveAll = false

    private typealias Step = PhoneSetup.Step

    private var status: RemoteController.Status { model.status }
    private var input: PhoneSetup.Input { model.input(pairingAnotherFrom: pairingAnotherFrom) }

    /// Every state shows its whole checklist. Steps 1, 2, 3 and 5 open, and
    /// ready, fit entirely; with step 4 or 6 open (the QR codes) the
    /// switches and devices below are a scroll away.
    static let height: CGFloat = 760

    var body: some View {
        let state = PhoneSetup.state(input)
        Form {
            header

            Section("Set up") {
                setUp(state)
            }

            notes

            Section {
                // The switch is in "Turn on Bench on your phone" while that
                // step is open; here whenever it is on and that step isn't.
                if model.enabled, state.expanded != .turnOn {
                    Toggle(isOn: enabledBinding) {
                        Text("Use Bench from your phone")
                        Text("Off, your devices can't reach Bench. They stay paired.")
                    }
                }
                RemoteActionsToggle() // Phase 2 actions
                RemoteBrowseToggle() // Phase 3 browse
            }

            devicesSection
        }
        .settingsPage(height: Self.height)
        // Pairing another device ends when one pairs (or one is removed), and
        // when setup isn't done any more.
        .onChange(of: model.devices.count) { pairingAnotherFrom = nil }
        .onChange(of: state.isReady) { pairingAnotherFrom = nil }
        .confirmationDialog("Remove all paired devices?", isPresented: $confirmingRemoveAll) {
            Button("Remove All Devices", role: .destructive) { actions.removeAll() }
        } message: {
            Text("Each one will need the code again to use Bench.")
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(get: { model.enabled }, set: { actions.setEnabled($0) })
    }

    // MARK: Header

    private var header: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                    .frame(width: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(PhoneSetup.title)
                        .font(.title3.weight(.semibold))
                    Text(PhoneSetup.intro)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Setup guide") { actions.open(PhoneSetup.guide) }
                        .buttonStyle(.link)
                        .padding(.top, 2)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: Set up

    @ViewBuilder private func setUp(_ state: PhoneSetup.State) -> some View {
        if state.isChecking {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking Tailscale…").foregroundStyle(.secondary)
            }
        } else if state.isReady {
            // "Ready · 1 device", and the address under it, whole.
            StepLine(mark: .done) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(["Ready", state.facts[.pair]].compactMap { $0 }.joined(separator: " · "))
                    Text(state.facts[.turnOn] ?? "")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(state.summary ?? "Ready")
            } trailing: {
                if state.showsPairing {
                    Button("Cancel") {
                        pairingAnotherFrom = nil
                        actions.withdrawCode()
                    }
                } else {
                    Button("Pair Another Device") { pairingAnotherFrom = model.devices.count }
                }
            }
            if state.showsPairing, let url = input.servingURL {
                pairing(url)
                    .padding(.leading, stepIndent)
            }
        } else {
            ForEach(Step.allCases) { step in
                row(step, state)
            }
        }
    }

    @ViewBuilder private func row(_ step: Step, _ state: PhoneSetup.State) -> some View {
        let done = state.done.contains(step)
        if state.expanded == step {
            VStack(alignment: .leading, spacing: 8) {
                StepLine(mark: .open(step)) {
                    Text(step.title).fontWeight(.semibold)
                } trailing: {
                    if step == .turnOn {
                        Toggle(step.title, isOn: enabledBinding)
                            .labelsHidden()
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(help(step))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    action(step)
                }
                .padding(.leading, stepIndent)
            }
            .padding(.vertical, 4)
        } else if state.isLater(step) {
            // After the open step: dimmed, no buttons (a later step already
            // done still shows its tick).
            StepLine(mark: done ? .done : .later(step)) {
                Text(step.title)
            } trailing: {
                EmptyView()
            }
            .foregroundStyle(.tertiary)
        } else {
            StepLine(mark: .done) {
                Text(step.title)
            } trailing: {
                Text(state.facts[step] ?? "")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
    }

    private func help(_ step: Step) -> String {
        switch step {
        case .signIn:
            // Signed in, but Tailscale is off (disconnected).
            if status.tailscaleStatus?.login != nil { return "Tailscale is off. Open it and connect, with the same account you'll use on your phone." }
        case .turnOn:
            if model.enabled, let detail = PhoneSetup.turnOnDetail(status.serve, port: status.port) { return detail }
        default:
            break
        }
        return step.help
    }

    /// The open step's action: one button in the one accent, or what it
    /// needs instead.
    @ViewBuilder private func action(_ step: Step) -> some View {
        switch step {
        case .install:
            primary("Get Tailscale") { actions.open(PhoneSetup.getTailscale) }
        case .signIn:
            primary("Open Tailscale") { actions.openTailscale() }
        case .https:
            primary("Open DNS Settings…") { actions.open(enableURL ?? PhoneSetup.dnsSettings) }
        case .phone:
            phoneStep
        case .turnOn:
            if model.enabled, status.serve == .failed || status.serve == .blocked {
                Button("Try Again") { actions.refresh() }
                    .disabled(status.checking)
            }
        case .pair:
            if let url = input.servingURL { pairing(url) }
        }
    }

    /// The page `serve` printed to turn HTTPS on, when it printed one.
    private var enableURL: URL? {
        if case .httpsOff(let url?) = status.serve { url } else { nil }
    }

    private func primary(_ title: String, _ action: @escaping @MainActor () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .tint(Theme.clay)
    }

    /// The App Store's QR code for the phone, what to check when the phone
    /// doesn't show up, and Skip.
    private var phoneStep: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 4) {
                if let qr = QRCode.image(for: PhoneSetup.appStore.absoluteString) {
                    Image(nsImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 96, height: 96)
                        .accessibilityLabel("QR code for Tailscale in the App Store")
                }
                Text("Scan for the App Store")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(PhoneSetup.phoneMissing)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Skip") { actions.skipPhone() }
                    .buttonStyle(.link)
                    .font(.callout)
                    .help("For pairing a computer instead of a phone")
            }
        }
    }

    private func pairing(_ url: URL) -> some View {
        PairingBlock(url: url, code: model.code, wornOut: model.wornOut,
                     issueCode: actions.issueCode, newCode: actions.newCode)
    }

    // MARK: Notes

    private var sharesAddress: Bool { status.othersShare && status.serve == .serving }

    /// What Bench needs to say, when it applies.
    @ViewBuilder private var notes: some View {
        if status.otherLogin || status.mappingLeft || sharesAddress {
            Section {
                if status.otherLogin {
                    Note(text: "Tailscale is signed in as someone else now, so your devices can't reach Bench. To use this account, turn Bench on your phone off and on again.")
                }
                if status.mappingLeft {
                    LabeledContent {
                        Button("Try Again") { actions.refresh() }
                            .disabled(status.checking)
                    } label: {
                        Note(text: "Bench couldn't remove its Tailscale mapping. Tailscale still passes what your devices ask to a port Bench no longer listens on. Bench tries again when Tailscale is running.")
                    }
                }
                if sharesAddress {
                    Note(text: "Other Tailscale Serve sites on this Mac share its address, and can see your devices' Bench sign-in. Serve only things you trust here.")
                }
            }
        }
    }

    // MARK: Devices

    private var devicesSection: some View {
        Section {
            if model.devices.isEmpty {
                Text("No devices yet. Paired devices stay paired when Bench on your phone is off.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.devices) { device in
                    LabeledContent {
                        Button("Remove") { actions.remove(device) }
                    } label: {
                        Text(device.name)
                        Text(Self.deviceLine(device))
                        if device.push?.subscription != nil { Text("Notifications on") } // Phase 2 push
                    }
                }
                HStack {
                    Spacer()
                    Button("Remove All Devices…") { confirmingRemoveAll = true }
                }
            }
        } header: {
            Text("Paired devices")
        } footer: {
            Text("Expires if unused for 60 days.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    static func deviceLine(_ device: RemoteDevice) -> String {
        let paired = "Paired \(device.pairedAt.formatted(date: .abbreviated, time: .omitted))"
        guard let seen = device.lastSeen else { return paired }
        return "\(paired) · Last seen \(seen.formatted(.relative(presentation: .named)))"
    }
}

extension PhoneSetup {
    static let title = "Bench on your phone"
    static let intro = "Use Claude Science from your iPhone or iPad: see what needs you, answer, approve and send messages, over your own private Tailscale network."
    /// Under the App Store's QR code.
    static let phoneMissing = "Don't see it? Make sure Tailscale is on and signed in with the same account on your phone (Apple, Google and GitHub sign-ins are separate accounts)."
}

// MARK: Rows

/// From a step's edge to its title: the mark's column and the gap.
private let stepIndent: CGFloat = 30

/// A step's line: its mark, its title, and what sits at the end of the line.
private struct StepLine<Title: View, Trailing: View>: View {
    enum Mark {
        case done
        /// The step open now.
        case open(PhoneSetup.Step)
        /// A step after the open one.
        case later(PhoneSetup.Step)
    }

    let mark: Mark
    @ViewBuilder let title: () -> Title
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            symbol
                .imageScale(.large)
                .frame(width: 22)
            title()
            Spacer(minLength: 12)
            trailing()
        }
    }

    @ViewBuilder private var symbol: some View {
        switch mark {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Done")
        case .open(let step):
            Image(systemName: "\(step.rawValue).circle")
                .foregroundStyle(.primary)
                .accessibilityLabel("Step \(step.rawValue), next")
        case .later(let step):
            Image(systemName: "\(step.rawValue).circle")
                .accessibilityLabel("Step \(step.rawValue)")
        }
    }
}

/// Something Bench needs to say, with a warning sign.
private struct Note: View {
    let text: String

    var body: some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }
}

// MARK: Pairing

/// The QR code of the page, the one-time code with its countdown, and the
/// three steps. A code is issued only while this shows: while "Pair your
/// phone" is the step open.
private struct PairingBlock: View {
    let url: URL
    let code: PairingCode?
    let wornOut: Bool
    let issueCode: @MainActor () -> Void
    let newCode: @MainActor () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            if let qr = QRCode.image(for: url.absoluteString) {
                Image(nsImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 136, height: 136)
                    .accessibilityLabel("QR code of \(url.absoluteString)")
            }
            VStack(alignment: .leading, spacing: 10) {
                if wornOut {
                    Text("Too many wrong codes.")
                        .font(.headline)
                    Button("New Code") { newCode() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.clay)
                } else if let code {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.spaced(code.digits))
                            .font(.system(size: 30, weight: .semibold, design: .monospaced))
                            .textSelection(.enabled)
                            .accessibilityLabel("Code \(code.digits.map(String.init).joined(separator: " "))")
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text("Expires in \(ElapsedClock.format(code.expiresAt.timeIntervalSince(context.date)))")
                                .monospacedDigit()
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("1. Scan the QR code with your phone's camera, and open the page.")
                    Text("2. Tap Share, then Add to Home Screen.")
                    Text("3. Open Bench from your Home Screen, and enter the code.")
                }
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        // A new code when there is none (used) and when this one runs out;
        // after one worn out by wrong tries, only from New Code.
        .task(id: code) {
            guard let code, !code.isExpired(at: Date()) else {
                issueCode()
                return
            }
            try? await Task.sleep(for: .seconds(code.expiresAt.timeIntervalSinceNow + 0.5))
            guard !Task.isCancelled else { return }
            issueCode()
        }
    }

    /// "123 456".
    static func spaced(_ digits: String) -> String {
        digits.count == 6 ? "\(digits.prefix(3)) \(digits.suffix(3))" : digits
    }
}

/// A QR code from CoreImage, its modules kept square when scaled.
@MainActor
enum QRCode {
    private static var cache: [String: NSImage] = [:]

    static func image(for text: String) -> NSImage? {
        if let cached = cache[text] { return cached }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
        // The pairing page's and the App Store's.
        if cache.count >= 2 { cache = [:] }
        cache[text] = image
        return image
    }
}
