import SwiftUI

enum Pulse {
    static let bg = Color.black
    static let card = Color(hex: "1C1C1E")
    static let card2 = Color(hex: "2C2C2E")
    static let hair = Color(hex: "3A3A3C")
    static let text = Color(hex: "F5F5F7")
    static let muted = Color(hex: "8E8E93")
    static let move = Color(hex: "FA114F")
    static let exercise = Color(hex: "92ED2C")
    static let stand = Color(hex: "00D3EA")
    static let ok = Color(hex: "30D158")
    static let watch = Color(hex: "FFD60A")
    static let rest = Color(hex: "FF453A")
}

enum PulseLayout {
    static let maxReadableWidth: CGFloat = 430

    static func gutter(for width: CGFloat) -> CGFloat {
        width < 360 ? 16 : 20
    }

    static func ringDiameter(for width: CGFloat) -> CGFloat {
        min(168, max(124, width * 0.36))
    }

    static func headlineSize(for width: CGFloat) -> CGFloat {
        width < 360 ? 26 : 28
    }
}

struct PulseCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Pulse.card)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct PulseReadableWidth: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: PulseLayout.maxReadableWidth)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    func pulseCard() -> some View {
        modifier(PulseCard())
    }

    func pulseReadable() -> some View {
        modifier(PulseReadableWidth())
    }
}

struct PulseBrandMark: View {
    var size: CGFloat = 28

    var body: some View {
        let sw = max(2.2, size * 0.09)
        ZStack {
            Circle().stroke(Pulse.move, lineWidth: sw)
            Circle().stroke(Pulse.exercise, lineWidth: sw)
                .padding(size * 0.14)
            Circle().stroke(Pulse.stand, lineWidth: sw)
                .padding(size * 0.28)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("TeamPulse")
    }
}

struct PulseRoleSwitch: ViewModifier {
    @EnvironmentObject var membership: TeamMembershipStore
    @State private var showSwitch = false

    func body(content: Content) -> some View {
        content
            .onLongPressGesture(minimumDuration: 0.85) { showSwitch = true }
            .confirmationDialog("Switch role", isPresented: $showSwitch, titleVisibility: .visible) {
                if membership.isCoach {
                    Button("Use as Player") { membership.chooseRole(.player) }
                } else if membership.hasChosenRole {
                    Button("Use as Coach") { membership.chooseRole(.coach) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Player sends your rings. Coach shows the full roster. Hold the rings logo anytime to switch.")
            }
    }
}

extension View {
    func pulseRoleSwitch() -> some View {
        modifier(PulseRoleSwitch())
    }
}

struct PulseSectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold))
            .tracking(0.8)
            .foregroundColor(Pulse.muted)
    }
}

struct PulseStatusDot: View {
    var on: Bool
    var body: some View {
        Circle()
            .fill(on ? Pulse.ok : Pulse.rest)
            .frame(width: 8, height: 8)
            .shadow(color: on ? Pulse.ok.opacity(0.8) : .clear, radius: 6)
    }
}

func pulseWorkoutTitle(_ raw: String) -> String {
    switch raw.lowercased() {
    case "running": return "Run"
    case "cycling": return "Bike"
    case "functionalstrengthtraining", "functional_strength_training": return "Strength"
    case "highintensityintervaltraining", "high_intensity_interval_training", "hiit": return "HIIT"
    case "mixedcardio", "mixed_cardio": return "Practice"
    case "hiking": return "Hike"
    case "rowing": return "Row"
    case "elliptical": return "Elliptical"
    case "yoga": return "Yoga"
    case "soccer", "football": return "Practice"
    default: return raw.capitalized
    }
}

struct PulsePrimaryButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

struct PulseGhostButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Pulse.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Pulse.card2)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Apple Watch–style Move / Exercise / Stand rings.
/// Fixed `diameter` — never wrap this in GeometryReader inside a ScrollView.
struct ActivityRingsView: View {
    var move: Double
    var exercise: Double
    var stand: Double
    var lineWidth: CGFloat = 14
    var gap: CGFloat = 5
    var diameter: CGFloat = 148

    var body: some View {
        let outer = diameter / 2 - lineWidth / 2
        let middle = outer - lineWidth - gap
        let inner = max(lineWidth, middle - lineWidth - gap)

        ZStack {
            ringTrack(radius: outer, color: Pulse.move)
            ringFill(radius: outer, progress: move, color: Pulse.move)
            ringTrack(radius: middle, color: Pulse.exercise)
            ringFill(radius: middle, progress: exercise, color: Pulse.exercise)
            ringTrack(radius: inner, color: Pulse.stand)
            ringFill(radius: inner, progress: stand, color: Pulse.stand)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Move, Exercise, and Stand rings")
    }

    private func ringTrack(radius: CGFloat, color: Color) -> some View {
        Circle()
            .stroke(color.opacity(0.22), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: radius * 2, height: radius * 2)
    }

    private func ringFill(radius: CGFloat, progress: Double, color: Color) -> some View {
        let clamped = min(max(progress, 0), 1)
        let overflow = min(max(progress - 1, 0), 1)
        return ZStack {
            Circle()
                .trim(from: 0, to: CGFloat(max(clamped, 0.001)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if overflow > 0 {
                Circle()
                    .trim(from: 0, to: CGFloat(overflow))
                    .stroke(color.opacity(0.85), style: StrokeStyle(lineWidth: lineWidth * 0.55, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: radius * 2, height: radius * 2)
    }
}

struct PulseRingLegendRow: View {
    let title: String
    let detail: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 13, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(color)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(Pulse.muted)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.4)
                .foregroundColor(Pulse.text)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Text(unit)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(Pulse.muted)
            }
        }
    }
}

struct PulseKPI: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(Pulse.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .tracking(-0.6)
                .foregroundColor(Pulse.text)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Pulse.card2)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
