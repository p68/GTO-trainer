import Foundation
import Observation

/// Saved drills and session history, stored as JSON in Application Support.
@MainActor
@Observable
final class AppStore {
    var drills: [DrillConfig] = []
    var sessions: [SessionRecord] = []

    private let directory: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("GTOTrainer", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        drills = load("drills.json") ?? AppStore.presets
        sessions = load("sessions.json") ?? []
    }

    // MARK: Drills

    func save(drill: DrillConfig) {
        if let i = drills.firstIndex(where: { $0.id == drill.id }) { drills[i] = drill } else { drills.insert(drill, at: 0) }
        write(drills, "drills.json")
    }

    func delete(drills offsets: IndexSet) {
        drills.remove(atOffsets: offsets)
        write(drills, "drills.json")
    }

    // MARK: Sessions

    func save(session: SessionRecord) {
        guard !session.hands.isEmpty else { return }
        if let i = sessions.firstIndex(where: { $0.id == session.id }) { sessions[i] = session } else { sessions.insert(session, at: 0) }
        write(sessions, "sessions.json")
    }

    func delete(sessions offsets: IndexSet) {
        sessions.remove(atOffsets: offsets)
        write(sessions, "sessions.json")
    }

    func clearHistory() {
        sessions = []
        write(sessions, "sessions.json")
    }

    var allHands: [HandRecord] { sessions.flatMap(\.hands) }

    var handsToday: [HandRecord] {
        let cal = Calendar.current
        return allHands.filter { cal.isDateInToday($0.date) }
    }

    // MARK: Files

    private func load<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    // MARK: Presets

    static let presets: [DrillConfig] = {
        var all = DrillConfig(); all.name = "Full hands – any spot"

        var preflop = DrillConfig(); preflop.name = "Preflop – any spot"; preflop.gameMode = .street

        var rfi = DrillConfig(); rfi.name = "RFI – all positions"; rfi.preflopAction = .rfi; rfi.gameMode = .spot

        var bbDefense = DrillConfig(); bbDefense.name = "BB vs BTN open"
        bbDefense.preflopAction = .vsOpen; bbDefense.hero = .bb; bbDefense.opponent = .btn

        var btnVsBB = DrillConfig(); btnVsBB.name = "BTN open vs BB (postflop)"
        btnVsBB.hero = .btn; btnVsBB.preflopAction = .rfi

        var vs3bet = DrillConfig(); vs3bet.name = "Facing 3bets"; vs3bet.preflopAction = .vs3bet

        return [all, preflop, rfi, bbDefense, btnVsBB, vs3bet]
    }()
}
