import Foundation
import Combine

/// Persistent athlete + club membership. The iPhone app is a HealthKit bridge, not a workout UI.
final class TeamMembershipStore: ObservableObject {
    static let shared = TeamMembershipStore()

    @Published var athleteId: String
    @Published var displayName: String
    @Published var teamId: String
    @Published var teamName: String
    @Published var joinCode: String
    @Published var sport: String

    var hasJoinedTeam: Bool {
        !teamId.isEmpty && !joinCode.isEmpty
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let athleteId = "teampulse.athleteId"
        static let displayName = "teampulse.displayName"
        static let teamId = "teampulse.teamId"
        static let teamName = "teampulse.teamName"
        static let joinCode = "teampulse.joinCode"
        static let sport = "teampulse.sport"
        static let lastWorkoutSync = "teampulse.lastWorkoutSync"
    }

    private init() {
        if let existing = defaults.string(forKey: Keys.athleteId), !existing.isEmpty {
            athleteId = existing
        } else {
            let generated = "ath-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10).lowercased()
            athleteId = String(generated)
            defaults.set(athleteId, forKey: Keys.athleteId)
        }
        displayName = defaults.string(forKey: Keys.displayName) ?? ""
        teamId = defaults.string(forKey: Keys.teamId) ?? ""
        teamName = defaults.string(forKey: Keys.teamName) ?? ""
        joinCode = defaults.string(forKey: Keys.joinCode) ?? ""
        sport = defaults.string(forKey: Keys.sport) ?? "soccer"
    }

    func updateProfile(name: String) {
        displayName = name
        defaults.set(name, forKey: Keys.displayName)
    }

    func leaveClub() {
        teamId = ""
        teamName = ""
        joinCode = ""
        defaults.removeObject(forKey: Keys.teamId)
        defaults.removeObject(forKey: Keys.teamName)
        defaults.removeObject(forKey: Keys.joinCode)
    }

    func applyJoinedTeam(id: String, name: String, code: String, sport: String, displayName: String) {
        teamId = id
        teamName = name
        joinCode = code.uppercased()
        self.sport = sport
        self.displayName = displayName
        defaults.set(id, forKey: Keys.teamId)
        defaults.set(name, forKey: Keys.teamName)
        defaults.set(joinCode, forKey: Keys.joinCode)
        defaults.set(sport, forKey: Keys.sport)
        defaults.set(displayName, forKey: Keys.displayName)
    }

    var lastWorkoutSyncDate: Date? {
        get { defaults.object(forKey: Keys.lastWorkoutSync) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastWorkoutSync) }
    }
}
