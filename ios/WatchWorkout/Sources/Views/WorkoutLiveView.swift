import SwiftUI
import WatchKit

private var scale: CGFloat {
    WKInterfaceDevice.current().screenBounds.width / 198.0
}

private func sp(_ pts: CGFloat) -> CGFloat {
    pts * scale
}

struct WorkoutActiveContainer: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    @State private var currentPage = 0

    var body: some View {
        TabView(selection: $currentPage) {
            WorkoutLiveMetricsView()
                .tag(0)
            WorkoutRingsPage()
                .tag(1)
            WorkoutControlsView(onReturnToPage0: {
                withAnimation { currentPage = 0 }
            })
            .tag(2)
        }
        .tabViewStyle(.verticalPage)
        .indexViewStyle(.page)
        .background(Pulse.bg.ignoresSafeArea())
    }
}

struct WorkoutLiveMetricsView: View {
    @EnvironmentObject var workoutManager: WorkoutManager

    var body: some View {
        VStack(alignment: .leading, spacing: sp(4)) {
            HStack {
                Text(workoutManager.workoutState == .paused ? "PAUSED" : "LIVE")
                    .font(.system(size: sp(9), weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(workoutManager.workoutState == .paused ? Pulse.watch : Pulse.ok)
                Spacer()
                Text(workoutManager.selectedWorkoutType.displayName.uppercased())
                    .font(.system(size: sp(9), weight: .bold))
                    .foregroundColor(Pulse.muted)
            }

            HStack(alignment: .firstTextBaseline, spacing: sp(4)) {
                Text(workoutManager.currentHeartRate >= 30 ? "\(workoutManager.currentHeartRate)" : "—")
                    .font(.system(size: sp(52), weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(Pulse.text)
                Text("BPM")
                    .font(.system(size: sp(12), weight: .bold))
                    .foregroundColor(Pulse.move)
            }

            if workoutManager.isAcquiringHeartRate && workoutManager.currentHeartRate < 30 {
                Text("Acquiring…")
                    .font(.system(size: sp(10), weight: .semibold))
                    .foregroundColor(Pulse.muted)
            }

            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(formatElapsed(workoutManager.elapsedSeconds))
                        .font(.system(size: sp(16), weight: .bold, design: .rounded))
                        .foregroundColor(Pulse.text)
                        .monospacedDigit()
                    Text("TIME")
                        .font(.system(size: sp(8), weight: .bold))
                        .foregroundColor(Pulse.muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(Int(workoutManager.activeCalories))")
                        .font(.system(size: sp(16), weight: .bold, design: .rounded))
                        .foregroundColor(Pulse.text)
                        .monospacedDigit()
                    Text("CAL")
                        .font(.system(size: sp(8), weight: .bold))
                        .foregroundColor(Pulse.move)
                }
            }
            .padding(.top, sp(6))
        }
        .padding(.horizontal, sp(8))
        .background(Pulse.bg.ignoresSafeArea())
    }
}

struct WorkoutRingsPage: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    private var rings: ActivityRingData? { workoutManager.activityRings }

    var body: some View {
        VStack(alignment: .leading, spacing: sp(8)) {
            WatchRings(
                move: rings?.moveProgress ?? 0,
                exercise: rings?.exerciseProgress ?? 0,
                stand: rings?.standProgress ?? 0
            )
            .frame(height: sp(78))
            .frame(maxWidth: .infinity)

            WatchRingRow(
                title: "Move",
                value: "\(Int(rings?.moveCalories ?? workoutManager.activeCalories))/\(Int(rings?.moveGoal ?? 500))",
                unit: "CAL",
                color: Pulse.move
            )
            WatchRingRow(
                title: "Exercise",
                value: "\(rings?.exerciseMinutes ?? workoutManager.elapsedSeconds / 60)/\(rings?.exerciseGoal ?? 30)",
                unit: "MIN",
                color: Pulse.exercise
            )
            WatchRingRow(
                title: "Stand",
                value: "\(rings?.standHours ?? 0)/\(rings?.standGoal ?? 12)",
                unit: "HRS",
                color: Pulse.stand
            )
        }
        .padding(.horizontal, sp(8))
        .background(Pulse.bg.ignoresSafeArea())
    }
}

struct WorkoutControlsView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    let onReturnToPage0: () -> Void
    @State private var autoReturnTimer: Timer?
    @State private var confirmEnd = false

    var body: some View {
        VStack(spacing: sp(10)) {
            Text(confirmEnd ? "End this session?" : workoutManager.selectedWorkoutType.displayName.uppercased())
                .font(.system(size: sp(10), weight: .bold))
                .tracking(0.4)
                .foregroundColor(Pulse.muted)
                .multilineTextAlignment(.center)

            if confirmEnd {
                Button {
                    Task { try? await workoutManager.endWorkout() }
                } label: {
                    Text("End session")
                        .font(.system(size: sp(14), weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: sp(34))
                        .background(Pulse.rest)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    confirmEnd = false
                    resetAutoReturnTimer()
                } label: {
                    Text("Keep going")
                        .font(.system(size: sp(14), weight: .semibold))
                        .foregroundColor(Pulse.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: sp(34))
                        .background(Pulse.card2)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    confirmEnd = true
                    resetAutoReturnTimer()
                } label: {
                    Text("End")
                        .font(.system(size: sp(14), weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: sp(34))
                        .background(Pulse.rest)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    if workoutManager.workoutState == .running {
                        workoutManager.pauseWorkout()
                    } else {
                        workoutManager.resumeWorkout()
                    }
                    onReturnToPage0()
                } label: {
                    Text(workoutManager.workoutState == .paused ? "Resume" : "Pause")
                        .font(.system(size: sp(14), weight: .semibold))
                        .foregroundColor(Pulse.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: sp(34))
                        .background(Pulse.card2)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, sp(10))
        .background(Pulse.bg.ignoresSafeArea())
        .onAppear { resetAutoReturnTimer() }
        .onDisappear { autoReturnTimer?.invalidate() }
    }

    private func resetAutoReturnTimer() {
        autoReturnTimer?.invalidate()
        autoReturnTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { _ in
            onReturnToPage0()
        }
    }
}

private func formatElapsed(_ seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
    return String(format: "%02d:%02d", m, s)
}

#Preview("Active") {
    WorkoutActiveContainer()
        .environmentObject(WorkoutManager.shared)
}
