import SwiftUI
import UniformTypeIdentifiers

/// The one settings screen. It opens by itself on the first launch.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                GateIcon().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gatekeeper on your Mac").font(Theme.font(20, .heavy))
                    Text("Today's time in the menu bar. Exam mode for your apps.")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
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
        }
        .padding(24)
        .frame(width: 460)
        .background(Theme.background)
        .onAppear { model.refreshLoginItem() }
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
                RoundedRectangle(cornerRadius: side * 0.22, style: .continuous).fill(Theme.accent)
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
