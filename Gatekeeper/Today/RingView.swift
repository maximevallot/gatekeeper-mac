import SwiftUI

/// One kind of site: a ring of minutes left, or a red lock when it is closed.
struct RingView: View {
    let ring: Ring
    var size: CGFloat = 84

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                switch ring.state {
                case let .open(minutesLeft, fraction):
                    Circle().stroke(Theme.track, lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: max(0.02, fraction))
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(minutesLeft)")
                        .font(Theme.font(21, .heavy))
                        .foregroundStyle(Theme.text)
                        .monospacedDigit()
                case .spent, .closedAllDay:
                    Circle().stroke(Theme.closedSoft, lineWidth: 9)
                    Image(systemName: "lock")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.closed)
                }
            }
            .frame(width: size - 9, height: size - 9)
            .frame(width: size, height: size)

            Text(ring.name)
                .font(Theme.font(13, .semibold))
                .foregroundStyle(Theme.text)
            caption
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var caption: some View {
        switch ring.state {
        case .open:
            Text("min left").font(Theme.font(11)).foregroundStyle(Theme.muted)
        case let .spent(reopens):
            Text("till \(reopens.formatted(date: .omitted, time: .shortened))")
                .font(Theme.font(11, .semibold)).foregroundStyle(Theme.closed)
        case .closedAllDay:
            Text("all day").font(Theme.font(11, .semibold)).foregroundStyle(Theme.closed)
        }
    }

    private var accessibilityText: String {
        switch ring.state {
        case let .open(left, _): return "\(ring.name): \(left) minutes left"
        case let .spent(reopens): return "\(ring.name): closed until \(reopens.formatted(date: .omitted, time: .shortened))"
        case .closedAllDay: return "\(ring.name): closed all day"
        }
    }
}
