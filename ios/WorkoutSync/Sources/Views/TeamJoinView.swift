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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Your Team")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 8)

                Text("Join with a coach code, or create a club. Keep using Apple Workout — this app only syncs Health to the board.")
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: "8E8E93"))

                HStack(spacing: 0) {
                    modeButton("Join", .join)
                    modeButton("Create", .create)
                }
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                field("Your name", text: $name)

                if mode == .join {
                    field("Join code", text: $code)
                        .textInputAutocapitalization(.characters)
                } else {
                    field("Club name", text: $clubName)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "FA114F"))
                }

                Button(action: submit) {
                    Text(isWorking ? "Working…" : (mode == .join ? "Join team" : "Create club"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(isWorking)

                Text("Demo club code: NORTH1")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(Color(hex: "8E8E93"))
            }
            .padding(20)
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            if name.isEmpty { name = membership.displayName }
        }
    }

    private func modeButton(_ title: String, _ value: Mode) -> some View {
        Button {
            mode = value
        } label: {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(mode == value ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(mode == value ? Color.white : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(4)
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(Color(hex: "8E8E93"))
            TextField("", text: text)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .padding(14)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func submit() {
        errorMessage = nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
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
                            errorMessage = "Enter the 6-character join code."
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
                        apply(result, fallbackName: "Team", code: trimmedCode.uppercased())
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
                    errorMessage = error.localizedDescription
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
