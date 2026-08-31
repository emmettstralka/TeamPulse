import SwiftUI

struct HealthSummaryView: View {
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var membership: TeamMembershipStore
    @EnvironmentObject var backendSync: BackendSyncService
    @EnvironmentObject var connectivityReceiver: WatchConnectivityReceiver

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header
                activityCard
                metricsRow
                workoutsCard
                teamCard
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 36)
        }
        .background(Color.black.ignoresSafeArea())
        .task {
            backendSync.connect(athleteId: membership.athleteId)
            if healthKitManager.isAuthorized || healthKitManager.isHealthDataAvailable {
                await healthKitManager.fetchTodayActivityRings()
                await healthKitManager.fetchRecentWorkouts()
                await healthKitManager.syncAllToBackend()
            }
        }
        .refreshable {
            await healthKitManager.syncAllToBackend()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Summary")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.white)
                Text(membership.hasJoinedTeam ? membership.teamName : "Not on a team yet")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(hex: "8E8E93"))
            }
            Spacer()
            Button {
                Task { await healthKitManager.syncAllToBackend() }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 40, height: 40)
                    SyncGlyph()
                        .frame(width: 18, height: 18)
                        .foregroundColor(.white)
                        .rotationEffect(.degrees(healthKitManager.isSyncing ? 360 : 0))
                        .animation(healthKitManager.isSyncing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: healthKitManager.isSyncing)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Activity")
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(Color(hex: "8E8E93"))

            HStack(spacing: 20) {
                ActivityRingsView(
                    move: healthKitManager.moveGoal > 0 ? healthKitManager.moveCalories / healthKitManager.moveGoal : 0,
                    exercise: healthKitManager.exerciseGoal > 0 ? healthKitManager.exerciseMinutes / healthKitManager.exerciseGoal : 0,
                    stand: healthKitManager.standGoal > 0 ? healthKitManager.standHours / healthKitManager.standGoal : 0,
                    lineWidth: 16,
                    gap: 7
                )
                .frame(width: 148, height: 148)

                VStack(alignment: .leading, spacing: 10) {
                    ringLegend(title: "Move", value: "\(Int(healthKitManager.moveCalories))/\(Int(healthKitManager.moveGoal))", unit: "kcal", color: Color(hex: "FA114F"))
                    ringLegend(title: "Exercise", value: "\(Int(healthKitManager.exerciseMinutes))/\(Int(healthKitManager.exerciseGoal))", unit: "min", color: Color(hex: "96F22B"))
                    ringLegend(title: "Stand", value: "\(Int(healthKitManager.standHours))/\(Int(healthKitManager.standGoal))", unit: "hrs", color: Color(hex: "32ADE6"))
                }
            }
        }
        .padding(18)
        .background(Color(hex: "1C1C1E"))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func ringLegend(title: String, value: String, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Text(unit)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "8E8E93"))
            }
        }
    }

    private var metricsRow: some View {
        HStack(spacing: 12) {
            metricCard(
                title: "Heart",
                value: healthKitManager.latestRestingHR.map { "\($0)" } ?? "—",
                unit: "BPM rest",
                color: Color(hex: "FA114F"),
                icon: .heart
            )
            metricCard(
                title: "Sleep",
                value: healthKitManager.latestSleepHours.map { String(format: "%.1f", $0) } ?? "—",
                unit: "HRS",
                color: Color(hex: "5E5CE6"),
                icon: .sleep
            )
        }
    }

    private func metricCard(title: String, value: String, unit: String, color: Color, icon: HealthMetricIcon.Kind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HealthMetricIcon(kind: icon, color: color)
                    .frame(width: 16, height: 16)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)
            }
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(unit)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(hex: "8E8E93"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(hex: "1C1C1E"))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var workoutsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workouts")
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(Color(hex: "8E8E93"))

            if healthKitManager.recentWorkouts.isEmpty {
                Text("Record a session in Apple’s Workout app. TeamPulse reads it from Health and sends it to your coach.")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "8E8E93"))
            } else {
                ForEach(healthKitManager.recentWorkouts.prefix(5)) { workout in
                    HStack {
                        HealthMetricIcon(kind: .workout, color: Color(hex: "FA114F"))
                            .frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workout.activityType.capitalized)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                            Text(workout.start.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "8E8E93"))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(formatDuration(workout.duration))
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                            Text(workout.avgHeartRate.map { "\($0) bpm" } ?? " ")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundColor(Color(hex: "8E8E93"))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(18)
        .background(Color(hex: "1C1C1E"))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var teamCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Club")
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(Color(hex: "8E8E93"))
            if membership.hasJoinedTeam {
                Text(membership.displayName.isEmpty ? "Athlete" : membership.displayName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                Text("Code \(membership.joinCode)")
                    .font(.system(size: 15, design: .rounded))
                    .foregroundColor(Color(hex: "32ADE6"))
                Text(syncLabel)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "8E8E93"))
            } else {
                Text("Join a team so your coach can see today’s load.")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "8E8E93"))
            }
        }
        .padding(18)
        .background(Color(hex: "1C1C1E"))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var syncLabel: String {
        if let date = healthKitManager.lastSyncDate {
            return "Last synced \(date.formatted(date: .omitted, time: .shortened))"
        }
        return "Pull to sync from Apple Health"
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}

private struct SyncGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                path.addArc(center: CGPoint(x: w / 2, y: h / 2), radius: min(w, h) / 2 - 1, startAngle: .degrees(-40), endAngle: .degrees(200), clockwise: false)
                path.move(to: CGPoint(x: w * 0.72, y: h * 0.12))
                path.addLine(to: CGPoint(x: w * 0.88, y: h * 0.22))
                path.addLine(to: CGPoint(x: w * 0.64, y: h * 0.30))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
    }
}
