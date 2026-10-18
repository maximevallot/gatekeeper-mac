import SwiftUI

/// The menu-bar popup. With the browser connected it is Today; without, it asks to connect. Starting exam mode
/// replaces it in place.
struct PopupView: View {
    @EnvironmentObject var model: AppModel
    @State private var screen: Screen = .today

    enum Screen { case today, startExam }

    var body: some View {
        Group {
            switch screen {
            case .today:
                if model.connected { TodayView(screen: $screen) } else { ConnectView(screen: $screen) }
            case .startExam:
                StartExamView(screen: $screen)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(width: 340)
        .background(Theme.background)
        .foregroundStyle(Theme.text)
    }
}

/// No browser has answered in the last two minutes. The Mac has no rules and no sample day of its own, so it
/// says how to connect, in one step. An exam mode the browser started still runs here until its end.
struct ConnectView: View {
    @EnvironmentObject var model: AppModel
    @Binding var screen: PopupView.Screen

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                Text("Gatekeeper").font(Theme.font(22, .heavy))
                Spacer()
                ModeMenu(screen: $screen)
            }

            Text("Connect Gatekeeper in your browser to see today and start exam mode here.")
                .font(Theme.font(15, .medium))
                .fixedSize(horizontal: false, vertical: true)

            if let heard = model.lastHeard {
                // Connected before: the switch is already on; the browser is closed or asleep (QA round 2, M4).
                Text("\(model.browserName) hasn't sent anything since \(Day.until(heard)). Open it to see today.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else if model.canOpenExtension {
                Text("In \(model.browserName), open Gatekeeper's Settings and turn on Mac app.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Add the Gatekeeper extension to Brave, Chrome or Safari first.")
                    .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let until = model.examUntil {
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent)
                    Text("Exam mode runs till \(Day.until(until)). Apps stay hidden.")
                        .font(Theme.font(14, .medium)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if model.canOpenExtension {
                PrimaryButton(title: "Open \(model.browserName)", systemImage: "arrow.up.forward.app",
                              color: Theme.accentFill, action: model.openRules)
            }
        }
    }
}

struct TodayView: View {
    @EnvironmentObject var model: AppModel
    @Binding var screen: PopupView.Screen

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center) {
                Text("Today").font(Theme.font(22, .heavy))
                Spacer()
                ModeMenu(screen: $screen)
            }

            if model.isStale {
                Text("Waiting for the browser")
                    .font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .help("A new day began. The browser sends today's minutes when it is next open.")
            } else if model.rings.isEmpty, let watch = model.snapshot?.watch {
                Text(watch.day.map { d in "Watch week · day \(d) of \(watch.of ?? 7)" } ?? "Watch week")
                    .font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .help("This first week counts your time and blocks nothing. Your limits come from it.")
            } else if model.rings.isEmpty {
                Text("Nothing watched").font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(model.rings) { RingView(ring: $0) }
                }
            }

            if let goal = model.goal {
                HStack(spacing: 12) {
                    Image(systemName: "scope")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.accent)
                    Text(goal).font(Theme.font(14, .medium)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Button(action: model.openTalk) {
                Label("Change something", systemImage: "bubble.left")
                    .font(Theme.font(15, .semibold))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .foregroundStyle(Theme.onAccent)
                    .background(Theme.accentFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!model.canOpenExtension)
            .opacity(model.canOpenExtension ? 1 : 0.5)
            .help(model.canOpenExtension ? "" : "The Gatekeeper extension was not found in Brave or Chrome.")

            HStack {
                link("All rules", model.openRules)
                Spacer()
                link("Your week", model.openWeek)
            }
        }
    }

    private func link(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(Theme.font(13, .medium))
            .foregroundStyle(Theme.link)
            .disabled(!model.canOpenExtension)
    }
}

/// The chip at the top right: what mode the engine says, and the menu behind it.
struct ModeMenu: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Binding var screen: PopupView.Screen

    var body: some View {
        Menu {
            if model.examOn {
                Button("End exam mode early…", action: model.endExamEarly)
                    .disabled(!model.canOpenExtension)
            } else if model.connected {
                Button("Start exam mode…") { screen = .startExam }
            }
            Divider()
            Button("Settings…") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Quit Gatekeeper") { NSApp.terminate(nil) }
                .disabled(model.examOn)
        } label: {
            ModeChip(state: state)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var state: ModeChip.State {
        if let until = model.confirmedExamUntil { return .exam(until) }
        if model.pendingStart != nil, model.examOn { return .starting }
        return model.connected ? .normal : .offline
    }
}

struct ModeChip: View {
    enum State: Equatable { case normal, offline, starting, exam(Date) }
    let state: State

    var body: some View {
        HStack(spacing: 5) {
            switch state {
            case let .exam(until):
                Image(systemName: "lock.fill").font(.system(size: 10, weight: .bold))
                Text("Exam till \(Day.until(until))")
            case .starting:
                Image(systemName: "lock.fill").font(.system(size: 10, weight: .bold))
                Text("Starting exam…")
            case .normal:
                Text("Normal day")
            case .offline:
                Text("Not connected")
            }
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).opacity(0.7)
        }
        .font(Theme.font(12, .semibold))
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .foregroundStyle(foreground)
        .background(background, in: Capsule())
        .contentShape(Capsule())
    }

    private var isExam: Bool { if case .exam = state { return true }; return state == .starting }
    private var foreground: Color { isExam ? Theme.onAccent : state == .offline ? Theme.muted : Theme.accentText }
    private var background: Color { isExam ? Theme.accentFill : state == .offline ? Theme.card : Theme.accentSoft }
}
