import SafariServices
import SwiftUI
import UniformTypeIdentifiers

/// The one settings screen. It opens by itself on the first launch.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmLeave = false

    /// nil: not asked yet; .unknown: Safari doesn't list the extension (QA round 2, M5).
    @State private var safariOn: SafariState?

    enum SafariState { case on, off, unknown }

    private var safariState: String {
        switch safariOn {
        case .on?: return "Gatekeeper is on in Safari"
        case .off?: return "Gatekeeper is off in Safari"
        case .unknown?: return "Safari doesn't see Gatekeeper yet"
        case nil: return "Gatekeeper for Safari"
        }
    }

    /// Safari's copy keeps rules of its own until Gatekeeper has one account per person (QA round 2, H4).
    private var safariNote: String {
        let rules = "In Safari, join the same Gatekeeper with a code, like any browser."
        if safariOn == .unknown {
            return "In Safari: Settings › Developer › Allow unsigned extensions, then Extensions. It turns off each time Safari quits. " + rules
        }
        return rules
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                GateIcon().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gatekeeper on your Mac").font(Theme.font(20, .heavy))
                    Text("Today's time in the menu bar. Exam mode for your apps.")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            section("At login") {
                Toggle("Open Gatekeeper when you log in", isOn: Binding(
                    get: { model.opensAtLogin }, set: { model.setOpensAtLogin($0) }))
                if model.loginItemNeedsApproval {
                    Button("Allow it in System Settings") { SMAppServiceHelper.openLoginItems() }
                        .buttonStyle(.link)
                }
            }

            section("Your Gatekeeper") {
                if let m = model.membership {
                    HStack {
                        Text("This Mac is in your Gatekeeper since \(m.joinedAt.formatted(date: .abbreviated, time: .omitted)).")
                            .font(Theme.font(14))
                        Spacer()
                        Button("Leave") { confirmLeave = true }
                    }
                    Text("Rules, today's minutes and exam mode come from your Gatekeeper, shared by every browser and this Mac. Leaving loosens nothing: exam mode already on runs to its end.")
                        .font(Theme.font(12)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Not joined. In your browser's Gatekeeper, click Add a device on Today, then type its code in the menu-bar popup.")
                        .font(Theme.font(14)).fixedSize(horizontal: false, vertical: true)
                }
            }
            .confirmationDialog("Leave your Gatekeeper on this Mac?", isPresented: $confirmLeave) {
                Button("Leave", role: .destructive) { Task { await model.leaveAccount() } }
            } message: {
                Text("This Mac stops showing today. Exam mode already on keeps hiding apps until it ends.")
            }

            section("Safari") {
                HStack {
                    Text(safariState).font(Theme.font(14))
                    Spacer()
                    Button("Open Safari's extension settings") {
                        SFSafariApplication.showPreferencesForExtension(withIdentifier: Browsers.safariExtensionID)
                    }
                }
                Text(safariNote)
                    .font(Theme.font(12)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            section("Appearance") {
                Picker("", selection: $model.appearance) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
            }

            section("In exam mode") {
                VStack(spacing: 0) {
                    ForEach(model.examApps) { app in
                        row(icon: AppIcon(bundleID: app.bundleID), name: app.name,
                            action: Binding(get: { app.action }, set: { model.setAction($0, for: app) }),
                            remove: model.canRemove(app) ? { model.remove(app) } : nil)
                        Divider()
                    }
                    row(icon: Image(systemName: "safari").resizable().scaledToFit().padding(2).foregroundStyle(Theme.muted),
                        name: "Other browsers",
                        action: Binding(get: { model.browserAction }, set: { model.setBrowserAction($0) }),
                        remove: nil)
                }
                HStack {
                    Button("Add an app…", action: addApp)
                    Spacer()
                    if let b = model.extensionBrowser {
                        Text("\(Browsers.name(b)) has the extension and stays open")
                            .font(Theme.font(12)).foregroundStyle(Theme.muted)
                    }
                }
                if model.examOn {
                    Text("Exam mode is on: apps can be added, not taken off.")
                        .font(Theme.font(12, .semibold)).foregroundStyle(Theme.closed)
                }
            }

            Text("No macOS permission needed: hiding and quitting apps works without one.")
                .font(Theme.font(12)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 460)
        .background(Theme.background)
        .onAppear {
            model.refreshLoginItem()
            SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: Browsers.safariExtensionID) { state, _ in
                let value: SafariState = state.map { $0.isEnabled ? .on : .off } ?? .unknown
                DispatchQueue.main.async { safariOn = value }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.font(13, .semibold)).foregroundStyle(Theme.muted)
            content()
        }
    }

    private func row<Icon: View>(icon: Icon, name: String, action: Binding<ExamAction>, remove: (() -> Void)?) -> some View {
        HStack(spacing: 10) {
            icon.frame(width: 22, height: 22)
            Text(name).font(Theme.font(14))
            Spacer()
            Picker("", selection: action) {
                ForEach(ExamAction.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 120)
            Button(action: { remove?() }) { Image(systemName: "minus.circle") }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.muted)
                .opacity(remove == nil ? 0 : 1)
                .disabled(remove == nil)
                .accessibilityLabel("Take \(name) off the list")
        }
        .padding(.vertical, 7)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { model.add(appAt: url) }
    }
}

struct AppIcon: View {
    let bundleID: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
        } else {
            Image(systemName: "app.dashed").resizable().scaledToFit().foregroundStyle(Theme.muted)
        }
    }
}

/// The app icon's look, drawn: the gate mark in white on the accent.
struct GateIcon: View {
    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.22, style: .continuous).fill(Color(red: 0x3B / 255, green: 0x5B / 255, blue: 0xDB / 255))
                Canvas { ctx, size in
                    let rect = CGRect(origin: .zero, size: size)
                    let path = GateMark.path(in: rect, lineWidth: side * 0.11)
                    var flipped = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -size.height)
                    if let cg = path.cgPath.copy(using: &flipped) {
                        ctx.stroke(Path(cg), with: .color(.white),
                                   style: StrokeStyle(lineWidth: side * 0.11, lineCap: .round, lineJoin: .round))
                    }
                }
            }
        }
    }
}

enum SMAppServiceHelper {
    static func openLoginItems() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
