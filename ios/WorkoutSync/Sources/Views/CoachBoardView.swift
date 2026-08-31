import SwiftUI
import UIKit

struct RoleSelectView: View {
    @EnvironmentObject var membership: TeamMembershipStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                PulseBrandMark(size: 26)
                Text("TeamPulse")
                    .font(.system(size: 20, weight: .bold))
                    .tracking(-0.4)
                    .foregroundColor(Pulse.text)
            }
            .padding(.top, 12)

            Text("Who are you?")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.6)
                .foregroundColor(Pulse.text)

            Text("Pick once. TeamPulse remembers. Hold the rings logo later if you need to switch.")
                .font(.system(size: 15))
                .foregroundColor(Pulse.muted)

            roleCard(
                title: "Player",
                detail: "Train in Apple Workout. This phone sends today’s Move, Exercise, and Stand to your coach."
            ) {
                membership.chooseRole(.player)
            }

            roleCard(
                title: "Coach",
                detail: "Open a club board. See every athlete’s rings, who practiced, and who needs rest."
            ) {
                membership.chooseRole(.coach)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 36)
        .pulseReadable()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Pulse.bg.ignoresSafeArea())
    }

    private func roleCard(title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Pulse.text)
                Text(detail)
                    .font(.system(size: 15))
                    .foregroundColor(Pulse.muted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .pulseCard()
        }
        .buttonStyle(.plain)
    }
}

struct CoachClubGateView: View {
    @EnvironmentObject var membership: TeamMembershipStore
    @EnvironmentObject var backendSync: BackendSyncService

    @State private var code: String = ""
    @State private var clubName: String = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var mode: Mode = .open

    enum Mode { case open, create }

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
                        Text("Coach")
                            .font(.system(size: 13))
                            .foregroundColor(Pulse.muted)
                    }
                }
                .padding(.top, 12)

                Text("Open the club board.")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.6)
                    .foregroundColor(Pulse.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Same roster as the web dashboard. Athletes keep using Apple Workout.")
                    .font(.system(size: 15))
                    .foregroundColor(Pulse.muted)

                panel(title: mode == .open ? "Open a club" : "Create a club") {
                    HStack(spacing: 0) {
                        modeTab("Open", .open)
                        modeTab("Create", .create)
                    }
                    .background(Pulse.card2)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if mode == .open {
                        field(placeholder: "Join code", text: $code)
                            .textInputAutocapitalization(.characters)
                            .onChange(of: code) { _, value in
                                let upper = value.uppercased()
                                if upper != value { code = upper }
                            }
                        PulsePrimaryButton(
                            title: isWorking ? "Opening…" : "Open board",
                            enabled: !isWorking,
                            action: { open(code) }
                        )
                    } else {
                        field(placeholder: "Club name", text: $clubName)
                        PulseGhostButton(title: isWorking ? "Creating…" : "Create club", action: create)
                            .disabled(isWorking)
                    }
                }

                panel(title: "Try a sample") {
                    PulseGhostButton(title: isWorking ? "Opening…" : "Open Northside FC") {
                        open("NORTH1")
                    }
                    Text("Demo club · code NORTH1 · fake roster so you can see multiple athletes.")
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
            if code.isEmpty { code = membership.joinCode }
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

    private func open(_ raw: String) {
        errorMessage = nil
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else {
            errorMessage = "Enter the join code."
            return
        }
        isWorking = true
        Task {
            do {
                let board = try await backendSync.fetchTeamBoard(joinCode: trimmed)
                await MainActor.run {
                    apply(board, fallbackCode: trimmed)
                    isWorking = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Couldn’t open that club. Check the code, or start the backend."
                    isWorking = false
                }
            }
        }
    }

    private func create() {
        errorMessage = nil
        let name = clubName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Name the club."
            return
        }
        isWorking = true
        Task {
            do {
                let created = try await backendSync.createTeam(name: name, sport: "soccer")
                let team = created["team"] as? [String: Any] ?? created
                let joinCode = (team["join_code"] as? String) ?? ""
                let board = try await backendSync.fetchTeamBoard(joinCode: joinCode)
                await MainActor.run {
                    apply(board, fallbackCode: joinCode, fallbackName: name)
                    isWorking = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Couldn’t create the club. Is the server running?"
                    isWorking = false
                }
            }
        }
    }

    @MainActor
    private func apply(_ board: [String: Any], fallbackCode: String, fallbackName: String = "Club") {
        let team = board["team"] as? [String: Any] ?? [:]
        let id = (team["id"] as? String) ?? membership.coachTeamId
        let name = (team["name"] as? String) ?? fallbackName
        let code = (team["join_code"] as? String) ?? fallbackCode
        membership.applyCoachClub(id: id, name: name, code: code)
    }
}

struct CoachBoardView: View {
    @EnvironmentObject var membership: TeamMembershipStore
    @EnvironmentObject var backendSync: BackendSyncService

    @State private var board: [String: Any] = [:]
    @State private var query = ""
    @State private var errorMessage: String?
    @State private var copiedCode = false
    @State private var confirmClose = false
    @State private var isLoading = false

    private var team: [String: Any] { board["team"] as? [String: Any] ?? [:] }
    private var summary: [String: Any] { board["summary"] as? [String: Any] ?? [:] }
    private var rings: [String: Any] { summary["rings"] as? [String: Any] ?? [:] }
    private var roster: [[String: Any]] {
        (board["roster"] as? [[String: Any]]) ?? []
    }

    private var filteredRoster: [[String: Any]] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sorted = roster.sorted { a, b in
            let ra = flagRank(a["flag"] as? String)
            let rb = flagRank(b["flag"] as? String)
            if ra != rb { return ra < rb }
            let pa = practiced(a) ? 0 : 1
            let pb = practiced(b) ? 0 : 1
            if pa != pb { return pa < pb }
            return displayName(a).localizedCaseInsensitiveCompare(displayName(b)) == .orderedAscending
        }
        guard !q.isEmpty else { return sorted }
        return sorted.filter { displayName($0).lowercased().contains(q) }
    }

    private var needsAttention: [[String: Any]] {
        filteredRoster.filter { flag in
            let f = flag["flag"] as? String
            return f == "rest" || f == "watch"
        }
    }

    private var ready: [[String: Any]] {
        filteredRoster.filter { athlete in
            let f = athlete["flag"] as? String
            return f != "rest" && f != "watch"
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                hero
                kpiGrid
                searchField
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundColor(Pulse.rest)
                }
                if filteredRoster.isEmpty {
                    emptyCard
                } else {
                    if !needsAttention.isEmpty {
                        section(title: "Needs attention · \(needsAttention.count)", athletes: needsAttention)
                    }
                    if !ready.isEmpty {
                        section(title: "Roster · \(ready.count)", athletes: ready)
                    }
                }
                clubCard
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 36)
            .pulseReadable()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Pulse.bg.ignoresSafeArea())
        .refreshable { await loadBoard() }
        .task { await loadBoard() }
        .onReceive(Timer.publish(every: 12, on: .main, in: .common).autoconnect()) { _ in
            Task { await loadBoard(silent: true) }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            PulseBrandMark(size: 26)
                .pulseRoleSwitch()
            VStack(alignment: .leading, spacing: 1) {
                Text(membership.coachTeamName.isEmpty ? "TeamPulse" : membership.coachTeamName)
                    .font(.system(size: 20, weight: .bold))
                    .tracking(-0.4)
                    .foregroundColor(Pulse.text)
                    .lineLimit(1)
                Text("Coach")
                    .font(.system(size: 13))
                    .foregroundColor(Pulse.muted)
            }
            Spacer(minLength: 8)
            Button {
                Task { await loadBoard() }
            } label: {
                Text(isLoading ? "…" : "Refresh")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Pulse.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Pulse.card)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 12)
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 16) {
            ActivityRingsView(
                move: progress(jsonDouble(rings["move_kcal"]), jsonDouble(rings["move_goal"], fallback: 500)),
                exercise: progress(jsonDouble(rings["exercise_min"]), jsonDouble(rings["exercise_goal"], fallback: 30)),
                stand: progress(jsonDouble(rings["stand_hours"]), jsonDouble(rings["stand_goal"], fallback: 12)),
                lineWidth: 14,
                gap: 5,
                diameter: 128
            )
            VStack(alignment: .leading, spacing: 10) {
                ringRow("Move", "\(Int(jsonDouble(rings["move_kcal"])))/\(Int(jsonDouble(rings["move_goal"], fallback: 500)))", "CAL", Pulse.move)
                ringRow("Exercise", "\(Int(jsonDouble(rings["exercise_min"])))/\(Int(jsonDouble(rings["exercise_goal"], fallback: 30)))", "MIN", Pulse.exercise)
                ringRow("Stand", "\(Int(jsonDouble(rings["stand_hours"])))/\(Int(jsonDouble(rings["stand_goal"], fallback: 12)))", "HRS", Pulse.stand)
            }
        }
        .pulseCard()
    }

    private func ringRow(_ title: String, _ value: String, _ unit: String, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(color)
                Text(unit)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Pulse.muted)
            }
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Pulse.text)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var kpiGrid: some View {
        let n = Int(jsonDouble(summary["athletes"]))
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            PulseKPI(label: "Practiced", value: "\(Int(jsonDouble(summary["practiced_today"])))/\(n)")
            PulseKPI(label: "Needs rest", value: "\(Int(jsonDouble(summary["flagged"])))")
            PulseKPI(label: "Closed Move", value: "\(Int(jsonDouble(rings["closed_move"])))/\(Int(jsonDouble(rings["count"], fallback: Double(n))))")
            PulseKPI(label: "Closed Exercise", value: "\(Int(jsonDouble(rings["closed_exercise"])))/\(Int(jsonDouble(rings["count"], fallback: Double(n))))")
        }
    }

    private var searchField: some View {
        TextField("Search athletes", text: $query)
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(Pulse.text)
            .padding(12)
            .background(Pulse.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var emptyCard: some View {
        Text(query.isEmpty
             ? "No one on this club yet. Copy the join code and have athletes open TeamPulse as Player."
             : "No athletes match that name.")
            .font(.system(size: 14))
            .foregroundColor(Pulse.muted)
            .pulseCard()
    }

    private func section(title: String, athletes: [[String: Any]]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PulseSectionLabel(text: title)
            ForEach(identified(athletes)) { item in
                CoachAthleteRow(athlete: item.data)
            }
        }
    }

    private var clubCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            PulseSectionLabel(text: "Club")
            Text((team["name"] as? String) ?? membership.coachTeamName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Pulse.text)
            HStack(spacing: 10) {
                Text(membership.coachJoinCode)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundColor(Pulse.text)
                Button(copiedCode ? "Copied" : "Copy") {
                    UIPasteboard.general.string = membership.coachJoinCode
                    copiedCode = true
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Pulse.stand)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Pulse.card2)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text("Share this code so players can join.")
                .font(.system(size: 13))
                .foregroundColor(Pulse.muted)

            Button("Close board") { confirmClose = true }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Pulse.rest)
                .padding(.top, 4)
                .confirmationDialog("Close this board?", isPresented: $confirmClose, titleVisibility: .visible) {
                    Button("Close board", role: .destructive) { membership.closeCoachClub() }
                    Button("Stay", role: .cancel) {}
                } message: {
                    Text("You can open it again with the join code. Players are not removed.")
                }
        }
        .pulseCard()
    }

    private func loadBoard(silent: Bool = false) async {
        let code = membership.coachJoinCode
        guard !code.isEmpty else { return }
        if !silent { await MainActor.run { isLoading = true } }
        do {
            let json = try await backendSync.fetchTeamBoard(joinCode: code)
            await MainActor.run {
                board = json
                errorMessage = nil
                isLoading = false
                if let name = (json["team"] as? [String: Any])?["name"] as? String {
                    membership.applyCoachClub(
                        id: ((json["team"] as? [String: Any])?["id"] as? String) ?? membership.coachTeamId,
                        name: name,
                        code: code
                    )
                }
            }
        } catch {
            await MainActor.run {
                if !silent { errorMessage = "Couldn’t refresh the board. Is the backend running?" }
                isLoading = false
            }
        }
    }

    private func practiced(_ athlete: [String: Any]) -> Bool {
        let today = athlete["today"] as? [String: Any] ?? [:]
        if let b = today["practiced"] as? Bool { return b }
        if let i = today["practiced"] as? Int { return i != 0 }
        return false
    }

    private func displayName(_ athlete: [String: Any]) -> String {
        (athlete["display_name"] as? String) ?? "Athlete"
    }

    private func flagRank(_ flag: String?) -> Int {
        switch flag {
        case "rest": return 0
        case "watch": return 1
        default: return 2
        }
    }

    private func progress(_ value: Double, _ goal: Double) -> Double {
        goal > 0 ? value / goal : 0
    }

    private func jsonDouble(_ any: Any?, fallback: Double = 0) -> Double {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String, let d = Double(s) { return d }
        return fallback
    }

    private func identified(_ athletes: [[String: Any]]) -> [IdentifiedAthlete] {
        athletes.enumerated().map { index, athlete in
            IdentifiedAthlete(
                id: (athlete["athlete_id"] as? String) ?? "row-\(index)",
                data: athlete
            )
        }
    }
}

struct CoachAthleteRow: View {
    let athlete: [String: Any]

    private var rings: [String: Any] { athlete["rings"] as? [String: Any] ?? [:] }
    private var today: [String: Any] { athlete["today"] as? [String: Any] ?? [:] }
    private var flag: String { (athlete["flag"] as? String) ?? "ok" }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ActivityRingsView(
                move: progress(num(rings["move_kcal"]), num(rings["move_goal"], 500)),
                exercise: progress(num(rings["exercise_min"]), num(rings["exercise_goal"], 30)),
                stand: progress(num(rings["stand_hours"]), num(rings["stand_goal"], 12)),
                lineWidth: 6,
                gap: 2,
                diameter: 56
            )
            VStack(alignment: .leading, spacing: 4) {
                Text((athlete["display_name"] as? String) ?? "Athlete")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Pulse.text)
                    .lineLimit(1)
                Text(sessionLine)
                    .font(.system(size: 12))
                    .foregroundColor(Pulse.muted)
                    .lineLimit(1)
                Text(flagLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(flagColor)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(num(rings["move_kcal"])))/\(Int(num(rings["move_goal"], 500)))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Pulse.text)
                    .monospacedDigit()
                Text("CAL")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Pulse.muted)
            }
        }
        .pulseCard()
    }

    private var sessionLine: String {
        let practiced: Bool = {
            if let b = today["practiced"] as? Bool { return b }
            if let i = today["practiced"] as? Int { return i != 0 }
            return false
        }()
        guard practiced else { return "No workout yet today" }
        let type = pulseWorkoutTitle((today["workout_type"] as? String) ?? "workout")
        let mins = Int(num(today["duration_seconds"]) / 60)
        if let hr = today["avg_hr"] {
            return "\(type) · \(mins) min · \(Int(num(hr))) bpm"
        }
        return "\(type) · \(mins) min"
    }

    private var flagLabel: String {
        switch flag {
        case "rest": return "Needs rest"
        case "watch": return "High load"
        default: return "Ready"
        }
    }

    private var flagColor: Color {
        switch flag {
        case "rest": return Pulse.rest
        case "watch": return Pulse.watch
        default: return Pulse.ok
        }
    }

    private func progress(_ value: Double, _ goal: Double) -> Double {
        goal > 0 ? value / goal : 0
    }

    private func num(_ any: Any?, _ fallback: Double = 0) -> Double {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String, let d = Double(s) { return d }
        return fallback
    }
}

private struct IdentifiedAthlete: Identifiable {
    let id: String
    let data: [String: Any]
}
