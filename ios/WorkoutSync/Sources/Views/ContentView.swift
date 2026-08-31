import SwiftUI

struct ContentView: View {
    @EnvironmentObject var membership: TeamMembershipStore

    var body: some View {
        ZStack {
            Pulse.bg.ignoresSafeArea()
            if !membership.hasChosenRole {
                RoleSelectView()
            } else if membership.isCoach {
                if membership.hasCoachClub {
                    CoachBoardView()
                } else {
                    CoachClubGateView()
                }
            } else if membership.hasJoinedTeam {
                HealthSummaryView()
            } else {
                TeamJoinView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LiveWorkoutView: View {
    @EnvironmentObject var connectivityReceiver: WatchConnectivityReceiver
    var onClose: () -> Void

    @State private var elapsedSeconds: Int = 0
    @State private var sessionStartDate: Date?

    private var formattedElapsed: String {
        let h = elapsedSeconds / 3600
        let m = (elapsedSeconds % 3600) / 60
        let s = elapsedSeconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    private var bpm: Int { connectivityReceiver.latestDataPoint?.heartRate ?? connectivityReceiver.lastReceivedHeartRate ?? 0 }
    private var isPaused: Bool {
        if case .paused = connectivityReceiver.sessionState { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                PulseBrandMark(size: 28)
                    .pulseRoleSwitch()
                VStack(alignment: .leading, spacing: 2) {
                    Text(isPaused ? "Paused" : "Live")
                        .font(.system(size: 21, weight: .bold))
                        .tracking(-0.4)
                        .foregroundColor(Pulse.text)
                    Text("Heart rate from Apple Watch")
                        .font(.system(size: 13))
                        .foregroundColor(Pulse.muted)
                }
                Spacer()
                PulseStatusDot(on: !isPaused && bpm >= 30)
                Button("Done") { onClose() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Pulse.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Pulse.card)
                    .clipShape(Capsule())
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(bpm >= 30 ? "\(bpm)" : "—")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .tracking(-2)
                    .monospacedDigit()
                    .foregroundColor(Pulse.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("BPM")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(Pulse.move)
            }
            .pulseCard()

            HStack(spacing: 12) {
                PulseKPI(label: "Duration", value: formattedElapsed)
                PulseKPI(
                    label: "Move",
                    value: "\(Int(connectivityReceiver.latestDataPoint?.calories ?? 0))"
                )
            }

            if let zone = connectivityReceiver.latestDataPoint?.zone, bpm >= 30 {
                VStack(alignment: .leading, spacing: 10) {
                    PulseSectionLabel(text: "Load")
                    Text(zoneTitle(zone))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Pulse.text)
                    HStack(spacing: 4) {
                        ForEach(1...5, id: \.self) { step in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(step <= zoneNumber(zone) ? Pulse.move : Pulse.card2)
                                .frame(height: 8)
                        }
                    }
                }
                .pulseCard()
            } else {
                Text("Waiting for the Watch sensor to lock on your pulse. Keep TeamPulse open on your wrist.")
                    .font(.system(size: 15))
                    .foregroundColor(Pulse.muted)
                    .pulseCard()
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .pulseReadable()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Pulse.bg.ignoresSafeArea())
        .onAppear { sessionStartDate = connectivityReceiver.lastReceivedDate ?? Date() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard connectivityReceiver.sessionState != .idle else { return }
            if let start = sessionStartDate {
                elapsedSeconds = max(0, Int(Date().timeIntervalSince(start)))
            }
        }
    }

    private func zoneNumber(_ zone: String) -> Int {
        switch zone {
        case "zone_2": return 2
        case "zone_3": return 3
        case "zone_4": return 4
        case "zone_5": return 5
        default: return 1
        }
    }

    private func zoneTitle(_ zone: String) -> String {
        switch zone {
        case "zone_2": return "Aerobic"
        case "zone_3": return "Tempo"
        case "zone_4": return "Threshold"
        case "zone_5": return "VO2 max"
        default: return "Recovery"
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(WatchConnectivityReceiver.shared)
        .environmentObject(BackendSyncService.shared)
        .environmentObject(OfflineQueueManager.shared)
        .environmentObject(TeamMembershipStore.shared)
        .environmentObject(HealthKitManager.shared)
}
