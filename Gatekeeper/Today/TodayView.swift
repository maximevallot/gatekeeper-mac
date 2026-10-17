import SwiftUI

/// The menu-bar popup. Today is the main screen; starting and ending exam mode replace it in place.
struct PopupView: View {
    @EnvironmentObject var model: AppModel
    @State private var screen: Screen = .today

    enum Screen { case today, startExam, endExam }

    var body: some View {
        Group {
            switch screen {
            case .today: TodayView(screen: $screen)
            case .startExam: StartExamView(screen: $screen)
            case .endExam: EndExamView(screen: $screen)
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

struct TodayView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Binding var screen: PopupView.Screen

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center) {
                Text("Today").font(Theme.font(22, .heavy))
                if model.isSample {
                    Text("sample")
                        .font(Theme.font(11, .medium))
                        .foregroundStyle(Theme.muted)
                        .help("No word from the extension yet. This is the design's sample day.")
                }
                Spacer()
                modeMenu
            }

            if model.rings.isEmpty {
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

    private var modeMenu: some View {
        Menu {
            if model.examOn {
                Button("End exam mode early…") { screen = .endExam }
            } else {
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
            ModeChip(examUntil: model.examUntil)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct ModeChip: View {
    let examUntil: Date?

    var body: some View {
        HStack(spacing: 5) {
            if let until = examUntil {
                Image(systemName: "lock.fill").font(.system(size: 10, weight: .bold))
                Text("Exam till \(until.formatted(date: .omitted, time: .shortened))")
            } else {
                Text("Normal day")
            }
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).opacity(0.7)
        }
        .font(Theme.font(12, .semibold))
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .foregroundStyle(examUntil == nil ? Theme.accentText : Theme.onAccent)
        .background(examUntil == nil ? Theme.accentSoft : Theme.accentFill, in: Capsule())
        .contentShape(Capsule())
    }
}
