import SwiftUI

struct TeamJoinView: View {
    @EnvironmentObject var membership: TeamMembershipStore
    @EnvironmentObject var backendSync: BackendSyncService
    @EnvironmentObject var healthKitManager: HealthKitManager

    @State private var name: String = ""
    @State private var code: String = ""
    @State private var clubName: String = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var mode: Mode = .join

    enum Mode { case join, create }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    PulseBrandMark(size: 26)
                        .pulseRoleSwitch()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TeamPulse")
                            .font(.system(size: 20, weight: .bold))
                            .tracking(-0.4)
                            .foregroundColor(Pulse.text)
                        Text("Player")
                            .font(.system(size: 13))
                            .foregroundColor(Pulse.muted)
                    }
                }
                .padding(.top, 12)

                Text("Your coach sees today’s rings.")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.6)
                    .foregroundColor(Pulse.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Keep using Apple Workout. This app only sends Health to the club board.")
                    .font(.system(size: 15))
                    .foregroundColor(Pulse.muted)

                panel(title: mode == .join ? "Join a club" : "Create a club") {
                    HStack(spacing: 0) {
                        modeTab("Join", .join)
                        modeTab("Create", .create)
                    }
                    .background(Pulse.card2)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    field(placeholder: "Your name", text: $name)

                    if mode == .join {
                        field(placeholder: "Join code", text: $code)
                            .textInputAutocapitalization(.characters)
                            .onChange(of: code) { _, value in
                                let upper = value.uppercased()
                                if upper != value { code = upper }
                            }
                        PulsePrimaryButton(
                            title: isWorking ? "Joining…" : "Join club",
                            enabled: !isWorking,
                            action: { submit() }
                        )
                    } else {
                        field(placeholder: "Club name", text: $clubName)
                        PulseGhostButton(title: isWorking ? "Creating…" : "Create club", action: { submit() })
                            .disabled(isWorking)
                    }
                }

                panel(title: "Try a sample") {
                    PulseGhostButton(title: isWorking ? "Joining…" : "Join Northside FC") {
                        mode = .join
                        code = "NORTH1"
                        submit(forceDemo: true)
                    }
                    Text("Demo club · code NORTH1 · fake roster so you can see the board.")
                        .font(.system(size: 12))
                        .foregroundColor(Pulse.muted)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundColor(Pulse.rest)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 36)
            .pulseReadable()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Pulse.bg.ignoresSafeArea())
        .onAppear {
            if name.isEmpty { name = membership.displayName }
        }
    }

    private func panel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Pulse.text)
            content()
        }
        .pulseCard()
    }

    private func modeTab(_ title: String, _ value: Mode) -> some View {
        Button { mode = value } label: {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(mode == value ? .black : Pulse.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(mode == value ? Color.white : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(4)
    }

    private func field(placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 17, weight: .medium))
            .foregroundColor(Pulse.text)
            .padding(12)
            .background(Pulse.card2)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Pulse.hair, lineWidth: 1)
            )
    }

    private func submit(forceDemo: Bool = false) {
        errorMessage = nil
        var trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if forceDemo && trimmedName.isEmpty {
            trimmedName = "You"
            name = trimmedName
        }
        guard !trimmedName.isEmpty else {
            errorMessage = "Add your name so the coach can see you on the roster."
            return
        }
        isWorking = true
        Task {
            do {
                if mode == .join {
                    let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedCode.isEmpty else {
                        await MainActor.run {
                            errorMessage = "Enter the join code from your coach."
                            isWorking = false
                        }
                        return
                    }
                    let result = try await backendSync.joinTeam(
                        joinCode: trimmedCode,
                        athleteId: membership.athleteId,
                        displayName: trimmedName
                    )
                    await MainActor.run {
                        apply(result, fallbackName: "Club", code: trimmedCode.uppercased())
                    }
                } else {
                    let club = clubName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !club.isEmpty else {
                        await MainActor.run {
                            errorMessage = "Name the club."
                            isWorking = false
                        }
                        return
                    }
                    let created = try await backendSync.createTeam(name: club, sport: "soccer")
                    let team = created["team"] as? [String: Any] ?? created
                    let joinCode = (team["join_code"] as? String) ?? ""
                    _ = try await backendSync.joinTeam(
                        joinCode: joinCode,
                        athleteId: membership.athleteId,
                        displayName: trimmedName
                    )
                    await MainActor.run {
                        apply(team, fallbackName: club, code: joinCode)
                    }
                }
                await healthKitManager.syncAllToBackend()
            } catch {
                await MainActor.run {
                    errorMessage = "Couldn’t reach the club. Check the code, or start the backend."
                    isWorking = false
                }
            }
        }
    }

    @MainActor
    private func apply(_ result: [String: Any], fallbackName: String, code: String) {
        let team = result["team"] as? [String: Any] ?? result
        let id = (team["id"] as? String) ?? membership.teamId
        let name = (team["name"] as? String) ?? fallbackName
        let sport = (team["sport"] as? String) ?? "soccer"
        let resolvedCode = (team["join_code"] as? String) ?? code
        membership.applyJoinedTeam(id: id, name: name, code: resolvedCode, sport: sport, displayName: self.name)
        isWorking = false
    }
}
