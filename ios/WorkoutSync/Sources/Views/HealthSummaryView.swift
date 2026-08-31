import SwiftUI
import UIKit

struct HealthSummaryView: View {
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var membership: TeamMembershipStore
    @EnvironmentObject var backendSync: BackendSyncService
    @EnvironmentObject var connectivityReceiver: WatchConnectivityReceiver
    @State private var copiedCode = false
    @State private var confirmLeave = false
    @State private var showLiveDetail = false

    private var moveProgress: Double {
        healthKitManager.moveGoal > 0 ? healthKitManager.moveCalories / healthKitManager.moveGoal : 0
    }
    private var exerciseProgress: Double {
        healthKitManager.exerciseGoal > 0 ? healthKitManager.exerciseMinutes / healthKitManager.exerciseGoal : 0
    }
    private var standProgress: Double {
        healthKitManager.standGoal > 0 ? healthKitManager.standHours / healthKitManager.standGoal : 0
    }

    private var isLive: Bool {
        switch connectivityReceiver.sessionState {
        case .active, .paused: return true
        case .idle: return false
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                if isLive { liveBanner }
                hero
                kpiGrid
                workoutsCard
                clubCard
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 36)
            .pulseReadable()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Pulse.bg.ignoresSafeArea())
        .fullScreenCover(isPresented: $showLiveDetail) {
            LiveWorkoutView(onClose: { showLiveDetail = false })
                .environmentObject(connectivityReceiver)
        }
        .task {
            backendSync.connect(athleteId: membership.athleteId)
            connectivityReceiver.sendAthleteIdentity(membership.athleteId)
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
        HStack(alignment: .center, spacing: 10) {
            PulseBrandMark(size: 26)
                .pulseRoleSwitch()
            VStack(alignment: .leading, spacing: 1) {
                Text("TeamPulse")
                    .font(.system(size: 20, weight: .bold))
                    .tracking(-0.4)
                    .foregroundColor(Pulse.text)
                    .lineLimit(1)
                Text("Player · \(membership.teamName)")
                    .font(.system(size: 13))
                    .foregroundColor(Pulse.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    PulseStatusDot(on: backendSync.isConnected || connectivityReceiver.isWatchConnected)
                    Text(backendSync.isConnected ? "On" : (connectivityReceiver.isWatchConnected ? "Watch" : "Off"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Pulse.muted)
                        .lineLimit(1)
                }
                Button {
                    Task { await healthKitManager.syncAllToBackend() }
                } label: {
                    Text(healthKitManager.isSyncing ? "…" : "Sync")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Pulse.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Pulse.card)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 12)
    }

    private var liveBanner: some View {
        Button { showLiveDetail = true } label: {
            HStack(spacing: 12) {
                PulseStatusDot(on: connectivityReceiver.sessionState != .paused)
                VStack(alignment: .leading, spacing: 2) {
                    Text(connectivityReceiver.sessionState == .paused ? "Watch paused" : "Live from Watch")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Pulse.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text("Tap for heart rate")
                        .font(.system(size: 12))
                        .foregroundColor(Pulse.muted)
                        .lineLimit(1)
                }
                .layoutPriority(1)
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text({
                        let bpm = connectivityReceiver.latestDataPoint?.heartRate ?? connectivityReceiver.lastReceivedHeartRate ?? 0
                        return bpm >= 30 ? "\(bpm)" : "—"
                    }())
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(Pulse.text)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("BPM")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Pulse.move)
                }
            }
            .padding(16)
            .background(Pulse.card)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Pulse.move.opacity(0.45), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 16) {
            ActivityRingsView(
                move: moveProgress,
                exercise: exerciseProgress,
                stand: standProgress,
                lineWidth: 14,
                gap: 5,
                diameter: 128
            )
            VStack(alignment: .leading, spacing: 10) {
                ringRow("Move", "\(Int(healthKitManager.moveCalories))/\(Int(healthKitManager.moveGoal))", "CAL", Pulse.move, moveProgress)
                ringRow("Exercise", "\(Int(healthKitManager.exerciseMinutes))/\(Int(healthKitManager.exerciseGoal))", "MIN", Pulse.exercise, exerciseProgress)
                ringRow("Stand", "\(Int(healthKitManager.standHours))/\(Int(healthKitManager.standGoal))", "HRS", Pulse.stand, standProgress)
            }
        }
        .pulseCard()
    }

    private func ringRow(_ title: String, _ value: String, _ unit: String, _ color: Color, _ progress: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(title.uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(color)
                    if progress >= 1 {
                        Text("Closed")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Pulse.ok)
                    }
                }
                Text(unit)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundColor(Pulse.muted)
            }
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .tracking(-0.4)
                .foregroundColor(Pulse.text)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var kpiGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            PulseKPI(label: "Resting HR", value: healthKitManager.latestRestingHR.map { "\($0)" } ?? "—")
            PulseKPI(label: "Sleep", value: healthKitManager.latestSleepHours.map { String(format: "%.1f", $0) } ?? "—")
            PulseKPI(label: "HRV", value: healthKitManager.latestHRVAvg.map { "\($0)" } ?? "—")
            PulseKPI(label: "Workouts", value: "\(healthKitManager.recentWorkouts.count)")
        }
    }

    private var workoutsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            PulseSectionLabel(text: "Today’s sessions")
            if healthKitManager.recentWorkouts.isEmpty {
                Text("Finish a session in Apple Workout. It appears here after you unlock your iPhone.")
                    .font(.system(size: 14))
                    .foregroundColor(Pulse.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(healthKitManager.recentWorkouts.prefix(5)) { workout in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pulseWorkoutTitle(workout.activityType))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Pulse.text)
                            Text(workout.start.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 12))
                                .foregroundColor(Pulse.muted)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(formatDuration(workout.duration))
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(Pulse.text)
                                .monospacedDigit()
                            Text(workout.avgHeartRate.map { "\($0) bpm" } ?? " ")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundColor(Pulse.muted)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .pulseCard()
    }

    private var clubCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            PulseSectionLabel(text: "Club")
            Text(membership.teamName)
                .font(.system(size: 20, weight: .semibold))
                .tracking(-0.3)
                .foregroundColor(Pulse.text)
            Text(membership.displayName.isEmpty ? "Athlete" : membership.displayName)
                .font(.system(size: 14))
                .foregroundColor(Pulse.muted)

            HStack(spacing: 10) {
                Text(membership.joinCode)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundColor(Pulse.text)
                Button(copiedCode ? "Copied" : "Copy") {
                    UIPasteboard.general.string = membership.joinCode
                    copiedCode = true
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Pulse.stand)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Pulse.card2)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text("Share this code so teammates can join.")
                .font(.system(size: 13))
                .foregroundColor(Pulse.muted)
            Text(syncLabel)
                .font(.system(size: 12))
                .foregroundColor(Pulse.muted)

            Button("Leave club") { confirmLeave = true }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Pulse.rest)
                .padding(.top, 4)
                .confirmationDialog("Leave this club?", isPresented: $confirmLeave, titleVisibility: .visible) {
                    Button("Leave club", role: .destructive) { membership.leaveClub() }
                    Button("Stay", role: .cancel) {}
                } message: {
                    Text("Your Health data will stop showing on the coach board until you join again.")
                }
        }
        .pulseCard()
    }

    private var syncLabel: String {
        if let date = healthKitManager.lastSyncDate {
            return "Last synced \(date.formatted(date: .omitted, time: .shortened))"
        }
        return "Pull down to sync from Apple Health"
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}
