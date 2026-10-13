// PhoneSettings.swift — Settings → Phone (DESIGN.md, Settings → Phone): the
// switch, what Tailscale says, pairing a device by its QR code and one-time
// code, and the devices paired.
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

struct PhoneSettingsView: View {
    @ObservedObject private var remote = RemoteController.shared
    @ObservedObject private var auth = RemoteController.shared.auth
    @State private var confirmingRemoveAll = false

    private var status: RemoteController.Status { remote.status }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { remote.enabled }, set: { remote.setEnabled($0) })) {
                    Text("Use Bench from your phone")
                    Text("A private page for your iPhone or another computer, over your Tailscale network. Paired devices see your sessions' titles and status. Nothing is on the internet.")
                }
            }

            Section {
                checks
            } header: {
                HStack {
                    Text("Tailscale")
                    Spacer()
                    if status.checking {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Check Again") { remote.refresh() }
                            .buttonStyle(.link)
                            .font(.callout)
                    }
                }
            }

            if remote.enabled, let url = status.url {
                PairSection(url: url)
            }

            Section("Paired devices") {
                if auth.devices.isEmpty {
                    Text("No devices yet. Paired devices stay paired when the switch is off.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(auth.devices) { device in
                        LabeledContent {
                            Button("Remove") { remote.remove(device) }
                        } label: {
                            Text(device.name)
                            Text(Self.deviceLine(device))
                        }
                    }
                    HStack {
                        Spacer()
                        Button("Remove All Devices…") { confirmingRemoveAll = true }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .tint(Theme.clay)
        .frame(width: 600, height: 720)
        .onAppear {
            // A demo reads no Keychain and asks Tailscale nothing.
            guard Demo.mode == nil else { return }
            auth.load()
            remote.refresh()
        }
        .confirmationDialog("Remove all paired devices?", isPresented: $confirmingRemoveAll) {
            Button("Remove All Devices", role: .destructive) { remote.removeAll() }
        } message: {
            Text("Each one will need the code again to use Bench.")
        }
    }

    // MARK: The checks

    @ViewBuilder private var checks: some View {
        let tailscale = status.tailscaleStatus
        CheckRow(title: "Tailscale installed", state: installedState,
                 detail: status.tailscale == .notInstalled ? "Install Tailscale from tailscale.com or the Mac App Store." : nil)
        CheckRow(title: "Signed in", state: signedInState,
                 detail: tailscale?.login ?? (status.tailscale == .notRunning || tailscale?.running == false
                     ? "Open Tailscale and sign in." : nil))
        if status.otherLogin {
            CheckRow(title: "Same account as when you turned this on", state: .failed,
                     detail: "Tailscale is signed in as someone else now. Turn the switch off and on again to use this account.")
        }
        LabeledContent {
            if case .httpsOff(let url?) = status.serve, tailscale?.httpsEnabled != true {
                Button("Turn On HTTPS…") { NSWorkspace.shared.open(url) }
            }
        } label: {
            CheckLabel(title: "HTTPS on for your tailnet", state: httpsState,
                       detail: tailscale?.httpsEnabled == false
                           ? "Your devices reach Bench with a certificate from Tailscale. Turn on HTTPS for your tailnet, then check again."
                           : nil)
        }
        CheckRow(title: status.url.map { "Serving at \($0.absoluteString)" } ?? "Serving at https://…:8443",
                 state: servingState, detail: servingDetail)
    }

    private var installedState: CheckState {
        switch status.tailscale {
        case nil: status.checking ? .checking : .unknown
        case .notInstalled?: .failed
        default: .ok
        }
    }

    private var signedInState: CheckState {
        guard let tailscale = status.tailscale else { return status.checking ? .checking : .unknown }
        guard let current = status.tailscaleStatus else { return tailscale == .notInstalled ? .unknown : .failed }
        return current.running && current.login != nil ? .ok : .failed
    }

    private var httpsState: CheckState {
        guard let current = status.tailscaleStatus, current.running else { return status.checking ? .checking : .unknown }
        return current.httpsEnabled ? .ok : .failed
    }

    private var servingState: CheckState {
        switch status.serve {
        case .off: .unknown
        case .starting: .checking
        case .serving: .ok
        case .waitingForTailscale, .httpsOff: .unknown
        case .blocked, .failed: .failed
        }
    }

    private var servingDetail: String? {
        switch status.serve {
        case .off: "Turn on the switch above."
        case .starting: nil
        case .serving: "Bench answers only on this Mac; Tailscale Serve passes on what your devices ask."
        case .waitingForTailscale: "Once Tailscale is running and signed in."
        case .httpsOff: "Once HTTPS is on."
        case .blocked: "Port 8443 already serves something else with Tailscale Serve. Bench leaves it alone."
        case .failed: status.port == nil ? "Bench couldn't listen on a port from 47280 to 47290." : "Tailscale couldn't serve Bench. Check again in a moment."
        }
    }

    static func deviceLine(_ device: RemoteDevice) -> String {
        let paired = "Paired \(device.pairedAt.formatted(date: .abbreviated, time: .omitted))"
        guard let seen = device.lastSeen else { return paired }
        return "\(paired) · Last seen \(seen.formatted(.relative(presentation: .named)))"
    }
}

// MARK: Pairing

/// The QR code of the page, the one-time code with its countdown, and the
/// three steps. A code is made only while this shows.
private struct PairSection: View {
    let url: URL
    @ObservedObject private var auth = RemoteController.shared.auth

    var body: some View {
        Section("Pair a device") {
            HStack(alignment: .top, spacing: 20) {
                if let qr = QRCode.image(for: url.absoluteString) {
                    Image(nsImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 150, height: 150)
                        .accessibilityLabel("QR code of \(url.absoluteString)")
                }
                VStack(alignment: .leading, spacing: 10) {
                    if let code = auth.code {
                        Text(Self.spaced(code.digits))
                            .font(.system(size: 30, weight: .semibold, design: .monospaced))
                            .textSelection(.enabled)
                            .accessibilityLabel("Code \(code.digits.map(String.init).joined(separator: " "))")
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text("Expires in \(ElapsedClock.format(code.expiresAt.timeIntervalSince(context.date)))")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. Scan the QR code with your iPhone's camera, and open the page.")
                        Text("2. Tap Share, then Add to Home Screen.")
                        Text("3. Open Bench from your Home Screen, and enter the code.")
                    }
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
        // A new code when there is none (used, or worn out by wrong tries)
        // and when this one runs out.
        .task(id: auth.code) {
            guard let code = auth.code, !code.isExpired(at: Date()) else {
                RemoteController.shared.issueCode()
                return
            }
            try? await Task.sleep(for: .seconds(code.expiresAt.timeIntervalSinceNow + 0.5))
            guard !Task.isCancelled else { return }
            RemoteController.shared.issueCode()
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
        cache = [text: image]
        return image
    }
}

// MARK: Rows

enum CheckState {
    case ok, failed, checking, unknown
}

/// A check's status symbol, title and a line under it.
private struct CheckLabel: View {
    let title: String
    let state: CheckState
    let detail: String?

    var body: some View {
        Label {
            Text(title)
            if let detail { Text(detail) }
        } icon: {
            switch state {
            case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            case .checking: ProgressView().controlSize(.small)
            case .unknown: Image(systemName: "circle.dashed").foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Self.spoken(state))
    }

    private static func spoken(_ state: CheckState) -> String {
        switch state {
        case .ok: "Done"
        case .failed: "Not yet"
        case .checking: "Checking"
        case .unknown: "Unknown"
        }
    }
}

private struct CheckRow: View {
    let title: String
    let state: CheckState
    let detail: String?

    var body: some View {
        CheckLabel(title: title, state: state, detail: detail)
    }
}
