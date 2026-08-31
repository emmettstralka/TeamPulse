import SwiftUI
import WatchKit

private var scale: CGFloat {
    WKInterfaceDevice.current().screenBounds.width / 198.0
}

private func sp(_ pts: CGFloat) -> CGFloat {
    pts * scale
}

struct ContentView: View {
    @EnvironmentObject var workoutManager: WorkoutManager

    var body: some View {
        ZStack {
            Pulse.bg.ignoresSafeArea()
            switch workoutManager.workoutState {
            case .idle:
                WatchHomeView()
            case .countdown:
                CountdownOverlay {
                    Task { await startFromCountdown() }
                }
            case .running, .paused:
                WorkoutActiveContainer()
            case .ended:
                WorkoutSummaryView()
            }
        }
    }

    private func startFromCountdown() async {
        do {
            try await workoutManager.startWorkout()
        } catch {
            await MainActor.run { workoutManager.dismissSummary() }
        }
    }
}

struct WatchHomeView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    @State private var isRequestingAuth = false
    @State private var showAuthError = false
    @State private var authErrorMessage = ""

    private var rings: ActivityRingData? { workoutManager.activityRings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: sp(8)) {
                HStack(spacing: sp(6)) {
                    WatchBrandMark(size: sp(16))
                    Text("TeamPulse")
                        .font(.system(size: sp(13), weight: .bold))
                        .foregroundColor(Pulse.text)
                    Spacer()
                }

                WatchRings(
                    move: rings?.moveProgress ?? 0,
                    exercise: rings?.exerciseProgress ?? 0,
                    stand: rings?.standProgress ?? 0
                )
                .frame(height: sp(84))
                .frame(maxWidth: .infinity)

                WatchRingRow(title: "Move", value: "\(Int(rings?.moveCalories ?? 0))/\(Int(rings?.moveGoal ?? 500))", unit: "CAL", color: Pulse.move)
                WatchRingRow(title: "Exercise", value: "\(rings?.exerciseMinutes ?? 0)/\(rings?.exerciseGoal ?? 30)", unit: "MIN", color: Pulse.exercise)
                WatchRingRow(title: "Stand", value: "\(rings?.standHours ?? 0)/\(rings?.standGoal ?? 12)", unit: "HRS", color: Pulse.stand)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: sp(6)) {
                    ForEach(WorkoutType.featured) { type in
                        Button {
                            workoutManager.selectWorkoutType(type)
                        } label: {
                            Text(type.displayName)
                                .font(.system(size: sp(11), weight: .semibold))
                                .foregroundColor(workoutManager.selectedWorkoutType == type ? .black : Pulse.text)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, sp(8))
                                .background(workoutManager.selectedWorkoutType == type ? Color.white : Pulse.card2)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, sp(4))

                Button(action: startWorkout) {
                    Text(isRequestingAuth ? "…" : "Start live HR")
                        .font(.system(size: sp(14), weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: sp(34))
                        .background(Color.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isRequestingAuth)

                Text("Coach sees this BPM")
                    .font(.system(size: sp(8)))
                    .foregroundColor(Pulse.muted)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, sp(8))
            .padding(.bottom, sp(8))
        }
        .background(Pulse.bg.ignoresSafeArea())
        .onAppear {
            Task { await workoutManager.fetchTodayActivityRings() }
        }
        .alert("Authorization", isPresented: $showAuthError) {
            Button("OK") {}
        } message: {
            Text(authErrorMessage)
        }
    }

    private func startWorkout() {
        isRequestingAuth = true
        Task {
            do {
                try await workoutManager.requestAuthorization()
                try await workoutManager.startWorkout()
            } catch {
                await MainActor.run {
                    authErrorMessage = error.localizedDescription
                    showAuthError = true
                }
            }
            await MainActor.run { isRequestingAuth = false }
        }
    }
}

struct WatchBrandMark: View {
    var size: CGFloat
    var body: some View {
        let sw = max(1.4, size * 0.1)
        ZStack {
            Circle().stroke(Pulse.move, lineWidth: sw)
            Circle().stroke(Pulse.exercise, lineWidth: sw).padding(size * 0.16)
            Circle().stroke(Pulse.stand, lineWidth: sw).padding(size * 0.32)
        }
        .frame(width: size, height: size)
    }
}

struct WatchRingRow: View {
    let title: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        HStack {
            Circle().fill(color).frame(width: sp(6), height: sp(6))
            Text(title.uppercased())
                .font(.system(size: sp(9), weight: .bold))
                .tracking(0.4)
                .foregroundColor(color)
            Spacer()
            Text(value)
                .font(.system(size: sp(12), weight: .bold, design: .rounded))
                .foregroundColor(Pulse.text)
                .monospacedDigit()
            Text(unit)
                .font(.system(size: sp(8), weight: .semibold))
                .foregroundColor(Pulse.muted)
        }
    }
}

struct WatchRings: View {
    var move: Double
    var exercise: Double
    var stand: Double

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let sw = max(7, size * 0.11)
            let gap = max(3, size * 0.045)
            let outer = size / 2 - sw / 2
            let mid = outer - sw - gap
            let inner = mid - sw - gap
            ZStack {
                ring(outer, move, Pulse.move, sw)
                ring(mid, exercise, Pulse.exercise, sw)
                ring(inner, stand, Pulse.stand, sw)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func ring(_ radius: CGFloat, _ progress: Double, _ color: Color, _ sw: CGFloat) -> some View {
        let shown = min(max(progress, 0), 1)
        return ZStack {
            Circle()
                .stroke(color.opacity(0.22), style: StrokeStyle(lineWidth: sw, lineCap: .round))
                .frame(width: radius * 2, height: radius * 2)
            Circle()
                .trim(from: 0, to: CGFloat(max(shown, 0.001)))
                .stroke(color, style: StrokeStyle(lineWidth: sw, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: radius * 2, height: radius * 2)
        }
    }
}

struct CountdownOverlay: View {
    let onComplete: () -> Void
    @State private var countdownValue = 3
    @State private var ringProgress: CGFloat = 0

    var body: some View {
        ZStack {
            Pulse.bg.ignoresSafeArea()
            Circle()
                .stroke(Pulse.move.opacity(0.22), lineWidth: 6)
                .frame(width: 104, height: 104)
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(Pulse.move, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: 104, height: 104)
                .rotationEffect(.degrees(-90))
            Text("\(countdownValue)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(Pulse.text)
        }
        .onAppear { startCountdown() }
    }

    private func startCountdown() {
        var elapsed: Double = 0
        let startTime = Date()
        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { timer in
            elapsed = Date().timeIntervalSince(startTime)
            let countSeconds = 3 - countdownValue
            ringProgress = CGFloat(min(1, elapsed - Double(countSeconds)))
            if elapsed >= Double(4 - countdownValue) {
                if countdownValue > 1 {
                    countdownValue -= 1
                    ringProgress = 0
                } else {
                    timer.invalidate()
                    onComplete()
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WorkoutManager.shared)
}
