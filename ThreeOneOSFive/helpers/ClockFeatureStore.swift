import Foundation
import Combine
import UserNotifications

struct ClockWorldCity: Codable, Identifiable, Equatable {
    let timeZoneIdentifier: String

    var id: String { timeZoneIdentifier }
    var timeZone: TimeZone? { TimeZone(identifier: timeZoneIdentifier) }
    var cityName: String {
        timeZoneIdentifier
            .split(separator: "/")
            .last
            .map(String.init)?
            .replacingOccurrences(of: "_", with: " ") ?? timeZoneIdentifier
    }

    static let initial: [ClockWorldCity] = [
        ClockWorldCity(timeZoneIdentifier: "America/Sao_Paulo"),
        ClockWorldCity(timeZoneIdentifier: "Europe/London"),
        ClockWorldCity(timeZoneIdentifier: "Asia/Tokyo")
    ]
}

struct ClockAlarm: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var hour: Int
    var minute: Int
    var label: String = ""
    var weekdays: [Int] = []
    var isEnabled: Bool = true

    var timeText: String {
        String(format: "%02d:%02d", hour, minute)
    }

    var repeatText: String {
        guard !weekdays.isEmpty else { return "Uma vez" }
        let names = [1: "Dom", 2: "Seg", 3: "Ter", 4: "Qua", 5: "Qui", 6: "Sex", 7: "Sáb"]
        return weekdays.sorted().compactMap { names[$0] }.joined(separator: " · ")
    }
}

struct ClockStopwatchLap: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var number: Int
    var split: TimeInterval
    var total: TimeInterval
}

enum ClockAlarmSaveResult {
    case saved
    case notificationsDenied
    case notificationLimit
}

@MainActor
final class ClockFeatureStore: ObservableObject {
    @Published private(set) var worldClocks: [ClockWorldCity] = ClockWorldCity.initial
    @Published private(set) var alarms: [ClockAlarm] = []
    @Published private(set) var timerIsRunning = false
    @Published private(set) var timerCompleted = false
    @Published private(set) var stopwatchIsRunning = false
    @Published private(set) var stopwatchLaps: [ClockStopwatchLap] = []

    private(set) var timerDuration: TimeInterval = 0
    private(set) var timerPausedRemaining: TimeInterval = 0
    private(set) var timerDeadline: Date?
    private var stopwatchAccumulated: TimeInterval = 0
    private var stopwatchStartDate: Date?

    private let defaults: UserDefaults
    private let persistenceKey = "x.clock.features.state.v1"
    private let notificationCenter = UNUserNotificationCenter.current()
    private let alarmNotificationPrefix = "x.clock.alarm."
    private let timerNotificationIdentifier = "x.clock.timer"

    private struct PersistedState: Codable {
        var version: Int = 1
        var worldClocks: [ClockWorldCity]
        var alarms: [ClockAlarm]
        var timerIsRunning: Bool
        var timerDuration: TimeInterval
        var timerPausedRemaining: TimeInterval
        var timerDeadline: Date?
        var stopwatchIsRunning: Bool
        var stopwatchAccumulated: TimeInterval
        var stopwatchStartDate: Date?
        var stopwatchLaps: [ClockStopwatchLap]
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restoreState()
        Task { await restoreAlarmNotifications() }
    }

    func addWorldClock(timeZoneIdentifier: String) {
        guard TimeZone(identifier: timeZoneIdentifier) != nil,
              !worldClocks.contains(where: { $0.timeZoneIdentifier == timeZoneIdentifier }) else { return }
        worldClocks.append(ClockWorldCity(timeZoneIdentifier: timeZoneIdentifier))
        persist()
    }

    func removeWorldClock(_ city: ClockWorldCity) {
        worldClocks.removeAll { $0.id == city.id }
        persist()
    }

    func saveAlarm(_ alarm: ClockAlarm) async -> ClockAlarmSaveResult {
        if alarm.isEnabled && !(await requestNotificationAuthorization()) {
            return .notificationsDenied
        }

        let nextAlarms = replacing(alarm, in: alarms)
        guard notificationRequestCount(for: nextAlarms) <= 64 else { return .notificationLimit }

        await removeAlarmNotifications(for: alarm.id)
        alarms = nextAlarms.sorted {
            if $0.hour != $1.hour { return $0.hour < $1.hour }
            return $0.minute < $1.minute
        }
        persist()
        await scheduleAlarmNotifications(for: alarm)
        return .saved
    }

    func setAlarmEnabled(id: UUID, isEnabled: Bool) async -> ClockAlarmSaveResult {
        guard let existing = alarms.first(where: { $0.id == id }) else { return .saved }
        if isEnabled && !(await requestNotificationAuthorization()) {
            return .notificationsDenied
        }

        var updated = existing
        updated.isEnabled = isEnabled
        let nextAlarms = replacing(updated, in: alarms)
        guard notificationRequestCount(for: nextAlarms) <= 64 else { return .notificationLimit }

        await removeAlarmNotifications(for: id)
        alarms = nextAlarms
        persist()
        if isEnabled { await scheduleAlarmNotifications(for: updated) }
        return .saved
    }

    func deleteAlarm(id: UUID) async {
        await removeAlarmNotifications(for: id)
        alarms.removeAll { $0.id == id }
        persist()
    }

    func timerRemaining(at date: Date = Date()) -> TimeInterval {
        guard timerIsRunning, let timerDeadline else { return max(0, timerPausedRemaining) }
        return max(0, timerDeadline.timeIntervalSince(date))
    }

    func startTimer(seconds: TimeInterval? = nil) async -> Bool {
        let selectedDuration = seconds ?? timerPausedRemaining
        guard selectedDuration > 0 else { return false }

        let notificationAllowed = await requestNotificationAuthorization()
        timerDuration = seconds ?? max(timerDuration, selectedDuration)
        timerPausedRemaining = selectedDuration
        timerDeadline = Date().addingTimeInterval(selectedDuration)
        timerIsRunning = true
        timerCompleted = false
        persist()

        notificationCenter.removePendingNotificationRequests(withIdentifiers: [timerNotificationIdentifier])
        if notificationAllowed {
            let content = UNMutableNotificationContent()
            content.title = "Timer finalizado"
            content.body = "O tempo definido chegou ao fim."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, selectedDuration), repeats: false)
            let request = UNNotificationRequest(identifier: timerNotificationIdentifier, content: content, trigger: trigger)
            try? await notificationCenter.add(request)
        }
        return notificationAllowed
    }

    func pauseTimer() {
        guard timerIsRunning else { return }
        timerPausedRemaining = timerRemaining()
        timerDeadline = nil
        timerIsRunning = false
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [timerNotificationIdentifier])
        persist()
    }

    func cancelTimer() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [timerNotificationIdentifier])
        timerIsRunning = false
        timerCompleted = false
        timerDuration = 0
        timerPausedRemaining = 0
        timerDeadline = nil
        persist()
    }

    func finishTimerIfNeeded(at date: Date = Date()) {
        guard timerIsRunning, timerRemaining(at: date) <= 0 else { return }
        timerIsRunning = false
        timerCompleted = true
        timerDuration = 0
        timerPausedRemaining = 0
        timerDeadline = nil
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [timerNotificationIdentifier])
        persist()
    }

    func dismissTimerCompletion() {
        timerCompleted = false
        persist()
    }

    func stopwatchElapsed(at date: Date = Date()) -> TimeInterval {
        guard stopwatchIsRunning, let stopwatchStartDate else { return stopwatchAccumulated }
        return max(0, stopwatchAccumulated + date.timeIntervalSince(stopwatchStartDate))
    }

    func toggleStopwatch() {
        if stopwatchIsRunning {
            stopwatchAccumulated = stopwatchElapsed()
            stopwatchStartDate = nil
            stopwatchIsRunning = false
        } else {
            stopwatchStartDate = Date()
            stopwatchIsRunning = true
        }
        persist()
    }

    func recordStopwatchLap(at date: Date = Date()) {
        guard stopwatchIsRunning else { return }
        let total = stopwatchElapsed(at: date)
        let previousTotal = stopwatchLaps.last?.total ?? 0
        stopwatchLaps.append(ClockStopwatchLap(number: stopwatchLaps.count + 1, split: max(0, total - previousTotal), total: total))
        persist()
    }

    func resetStopwatch() {
        stopwatchIsRunning = false
        stopwatchAccumulated = 0
        stopwatchStartDate = nil
        stopwatchLaps.removeAll()
        persist()
    }

    private func replacing(_ alarm: ClockAlarm, in current: [ClockAlarm]) -> [ClockAlarm] {
        if let index = current.firstIndex(where: { $0.id == alarm.id }) {
            var result = current
            result[index] = alarm
            return result
        }
        return current + [alarm]
    }

    private func notificationRequestCount(for values: [ClockAlarm]) -> Int {
        values.reduce(0) { count, alarm in
            guard alarm.isEnabled else { return count }
            return count + max(1, Set(alarm.weekdays).count)
        }
    }

    private func requestNotificationAuthorization() async -> Bool {
        let settings = await notificationCenter.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private func restoreAlarmNotifications() async {
        let settings = await notificationCenter.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        await scheduleAllAlarmNotifications()
    }

    private func scheduleAllAlarmNotifications() async {
        let allKnownIdentifiers = alarms.flatMap { possibleAlarmNotificationIdentifiers(for: $0.id) }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: allKnownIdentifiers)
        for alarm in alarms where alarm.isEnabled {
            await scheduleAlarmNotifications(for: alarm)
        }
    }

    private func scheduleAlarmNotifications(for alarm: ClockAlarm) async {
        guard alarm.isEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = alarm.label.isEmpty ? "Alarme" : alarm.label
        content.body = "Está na hora."
        content.sound = .default

        if alarm.weekdays.isEmpty {
            var matching = DateComponents()
            matching.hour = alarm.hour
            matching.minute = alarm.minute
            let after = Date().addingTimeInterval(2)
            guard let nextDate = Calendar.current.nextDate(after: after, matching: matching, matchingPolicy: .nextTime) else { return }
            var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: nextDate)
            dateComponents.hour = alarm.hour
            dateComponents.minute = alarm.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
            let request = UNNotificationRequest(identifier: alarmNotificationPrefix + alarm.id.uuidString, content: content, trigger: trigger)
            try? await notificationCenter.add(request)
            return
        }

        for weekday in Set(alarm.weekdays).sorted() where (1...7).contains(weekday) {
            var dateComponents = DateComponents()
            dateComponents.weekday = weekday
            dateComponents.hour = alarm.hour
            dateComponents.minute = alarm.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let identifier = alarmNotificationPrefix + alarm.id.uuidString + "." + String(weekday)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            try? await notificationCenter.add(request)
        }
    }

    private func removeAlarmNotifications(for id: UUID) async {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: possibleAlarmNotificationIdentifiers(for: id))
    }

    private func possibleAlarmNotificationIdentifiers(for id: UUID) -> [String] {
        [alarmNotificationPrefix + id.uuidString] + (1...7).map { alarmNotificationPrefix + id.uuidString + "." + String($0) }
    }

    private func restoreState() {
        guard let data = defaults.data(forKey: persistenceKey),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data),
              state.version == 1 else { return }

        worldClocks = state.worldClocks
        alarms = state.alarms
        timerIsRunning = state.timerIsRunning
        timerDuration = state.timerDuration
        timerPausedRemaining = state.timerPausedRemaining
        timerDeadline = state.timerDeadline
        stopwatchIsRunning = state.stopwatchIsRunning
        stopwatchAccumulated = state.stopwatchAccumulated
        stopwatchStartDate = state.stopwatchStartDate
        stopwatchLaps = state.stopwatchLaps

        if timerIsRunning, timerRemaining() <= 0 {
            timerIsRunning = false
            timerCompleted = true
            timerDuration = 0
            timerPausedRemaining = 0
            timerDeadline = nil
        }
    }

    private func persist() {
        let state = PersistedState(
            worldClocks: worldClocks,
            alarms: alarms,
            timerIsRunning: timerIsRunning,
            timerDuration: timerDuration,
            timerPausedRemaining: timerPausedRemaining,
            timerDeadline: timerDeadline,
            stopwatchIsRunning: stopwatchIsRunning,
            stopwatchAccumulated: stopwatchAccumulated,
            stopwatchStartDate: stopwatchStartDate,
            stopwatchLaps: stopwatchLaps
        )
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: persistenceKey)
        }
    }
}
