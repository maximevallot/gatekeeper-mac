import SwiftUI

struct StartExamView: View {
    @EnvironmentObject var model: AppModel
    @Binding var screen: PopupView.Screen
    @State private var until = Self.roundedUp(Date().addingTimeInterval(3 * 3600))

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Header(title: "Exam mode") { screen = .today }

            VStack(alignment: .leading, spacing: 10) {
                Text("Until").font(Theme.font(13, .semibold)).foregroundStyle(Theme.muted)
                DatePicker("Until", selection: $until, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.field)
                HStack(spacing: 8) {
                    quick("2 h") { until = Self.roundedUp(Date().addingTimeInterval(2 * 3600)) }
                    quick("4 h") { until = Self.roundedUp(Date().addingTimeInterval(4 * 3600)) }
                    quick("Till 4:00") { until = Day.nextStart(after: Date(), hour: 4) }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Kept away").font(Theme.font(13, .semibold)).foregroundStyle(Theme.muted)
                Text(keptAway).font(Theme.font(14)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            PrimaryButton(title: "Start", systemImage: "lock.fill", color: Theme.accentFill) {
                model.startExam(until: until)
                screen = .today
            }
            .disabled(until <= Date())
        }
    }

    private var keptAway: String {
        var names = model.examApps.map(\.name)
        let mine = model.extensionBrowser.map(Browsers.name) ?? "Brave and Chrome"
        names.append("browsers other than \(mine)")
        return names.joined(separator: ", ")
    }

    private func quick(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(Theme.font(12, .semibold))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .foregroundStyle(Theme.accentText)
            .background(Theme.accentSoft, in: Capsule())
    }

    static func roundedUp(_ date: Date) -> Date {
        let step: TimeInterval = 15 * 60
        return Date(timeIntervalSince1970: (date.timeIntervalSince1970 / step).rounded(.up) * step)
    }
}

struct EndExamView: View {
    @EnvironmentObject var model: AppModel
    @Binding var screen: PopupView.Screen
    @State private var typed = ""
    @State private var wrong = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Header(title: "End early?") { screen = .today }

            if let until = model.examUntil {
                Text("It ends by itself at \(until.formatted(date: .omitted, time: .shortened)).")
                    .font(Theme.font(14)).foregroundStyle(Theme.muted)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Type this to end it now").font(Theme.font(13, .semibold)).foregroundStyle(Theme.muted)
                Text(AppModel.endSentence).font(Theme.font(14, .medium)).textSelection(.disabled)
                TextField("", text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(end)
                    .onChange(of: typed) { _, _ in wrong = false }
                if wrong {
                    Text("Not the same sentence.").font(Theme.font(12, .semibold)).foregroundStyle(Theme.closed)
                }
            }

            PrimaryButton(title: "End exam mode", systemImage: "lock.open", color: Theme.closed, action: end)
        }
    }

    private func end() {
        if model.endExam(sentence: typed) { screen = .today } else { wrong = true }
    }
}

struct Header: View {
    let title: String
    let back: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: back) {
                Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .accessibilityLabel("Back")
            Text(title).font(Theme.font(22, .heavy))
        }
    }
}

struct PrimaryButton: View {
    let title: String
    let systemImage: String
    let color: Color
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(Theme.font(15, .semibold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(Theme.onAccent)
                .background(color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
    }
}
