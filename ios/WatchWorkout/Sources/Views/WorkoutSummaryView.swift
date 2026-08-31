import SwiftUI
import WatchKit

private var scale: CGFloat {
    WKInterfaceDevice.current().screenBounds.width / 198.0
}

private func sp(_ pts: CGFloat) -> CGFloat {
    pts * scale
}

struct WorkoutSummaryView: View {
    @EnvironmentObject var workoutManager: WorkoutManager

    private var rings: ActivityRingData? { workoutManager.activityRings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: sp(8)) {
                Text(workoutManager.selectedWorkoutType.displayName.uppercased())
                    .font(.system(size: sp(9), weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(Pulse.muted)

                Text("AVG BPM")
                    .font(.system(size: sp(8), weight: .semibold))
                    .tracking(0.6)
                    .foregroundColor(Pulse.muted)

                Text(workoutManager.averageHeartRate > 0 ? "\(workoutManager.averageHeartRate)" : "—")
                    .font(.system(size: sp(28), weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(Pulse.text)

                Text(formatElapsed(workoutManager.elapsedSeconds))
                    .font(.system(size: sp(16), weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(Pulse.muted)

                WatchRings(
                    move: rings?.moveProgress ?? 0,
                    exercise: rings?.exerciseProgress ?? 0,
                    stand: rings?.standProgress ?? 0
                )
                .frame(height: sp(84))
                .frame(maxWidth: .infinity)

                WatchRingRow(
                    title: "Move",
                    value: "\(Int(rings?.moveCalories ?? workoutManager.activeCalories))",
                    unit: "CAL",
                    color: Pulse.move
                )
                WatchRingRow(
                    title: "Exercise",
                    value: "\(rings?.exerciseMinutes ?? workoutManager.elapsedSeconds / 60)",
                    unit: "MIN",
                    color: Pulse.exercise
                )
                WatchRingRow(
                    title: "Stand",
                    value: "\(rings?.standHours ?? 0)",
                    unit: "HRS",
                    color: Pulse.stand
                )

                HStack {
                    summaryStat("\(workoutManager.averageHeartRate)", "AVG BPM")
                    Spacer()
                    summaryStat("\(Int(workoutManager.activeCalories))", "CAL")
                }
                .padding(.top, sp(4))

                Button {
                    workoutManager.dismissSummary()
                } label: {
                    Text("Done")
                        .font(.system(size: sp(14), weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: sp(34))
                        .background(Color.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, sp(6))
            }
            .padding(.horizontal, sp(8))
            .padding(.bottom, sp(8))
        }
        .background(Pulse.bg.ignoresSafeArea())
    }

    private func summaryStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: sp(16), weight: .bold, design: .rounded))
                .foregroundColor(Pulse.text)
                .monospacedDigit()
            Text(label)
                .font(.system(size: sp(8), weight: .semibold))
                .foregroundColor(Pulse.muted)
        }
    }

    private func formatElapsed(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}

#Preview {
    WorkoutSummaryView()
        .environmentObject(WorkoutManager.shared)
}
