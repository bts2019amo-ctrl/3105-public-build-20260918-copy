import Foundation
import Combine
import SwiftUI
import AVFoundation
import UserNotifications
#if canImport(AlarmKit)
import AlarmKit
import ActivityKit
#endif

enum ClockAlarmSound: String, CaseIterable, Codable, Identifiable {
    case brisa
    case pulsar
    case aurora

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var fileName: String { title + ".caf" }

    var subtitle: String {
        switch self {
        case .brisa: "Piano e celesta, suave e nítido"
        case .pulsar: "Marimba e kalimba, acolhedor"
        case .aurora: "Sinte e sinos, claro e otimista"
        }
    }

    var symbolName: String {
        switch self {
        case .brisa: "pianokeys"
        case .pulsar: "waveform"
        case .aurora: "sparkles"
        }
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
private struct ClockAlarmMetadata: AlarmMetadata {
    let label: String
    let soundID: String
}
#endif

private final class ClockNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ClockNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if notification.request.identifier.hasPrefix("x.clock.") {
            completionHandler([.sound])
        } else {
            completionHandler([.banner, .list, .sound])
        }
    }
}

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
    var id: UUID
    var hour: Int
    var minute: Int
    var label: String
    var weekdays: [Int]
    var isEnabled: Bool
    var sound: ClockAlarmSound

    init(
        id: UUID = UUID(),
        hour: Int,
        minute: Int,
        label: String = "",
        weekdays: [Int] = [],
        isEnabled: Bool = true,
        sound: ClockAlarmSound = .brisa
    ) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.label = label
        self.weekdays = weekdays
        self.isEnabled = isEnabled
        self.sound = sound
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case hour
        case minute
        case label
        case weekdays
        case isEnabled
        case sound
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        hour = try values.decode(Int.self, forKey: .hour)
        minute = try values.decode(Int.self, forKey: .minute)
        label = try values.decodeIfPresent(String.self, forKey: .label) ?? ""
        weekdays = try values.decodeIfPresent([Int].self, forKey: .weekdays) ?? []
        isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        sound = try values.decodeIfPresent(ClockAlarmSound.self, forKey: .sound) ?? .brisa
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(hour, forKey: .hour)
        try values.encode(minute, forKey: .minute)
        try values.encode(label, forKey: .label)
        try values.encode(weekdays, forKey: .weekdays)
        try values.encode(isEnabled, forKey: .isEnabled)
        try values.encode(sound, forKey: .sound)
    }

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
    @Published private(set) var timerSound: ClockAlarmSound = .brisa
    @Published private(set) var stopwatchIsRunning = false
    @Published private(set) var stopwatchLaps: [ClockStopwatchLap] = []

    private(set) var timerDuration: TimeInterval = 0
    private(set) var timerPausedRemaining: TimeInterval = 0
    private(set) var timerDeadline: Date?
    private var stopwatchAccumulated: TimeInterval = 0
    private var stopwatchStartDate: Date?
    private var previewPlayer: AVAudioPlayer?

    private let defaults: UserDefaults
    private let persistenceKey = "x.clock.features.state.v1"
    private let timerSoundPersistenceKey = "x.clock.timer.sound.v1"
    private let notificationCenter = UNUserNotificationCenter.current()
    private let alarmNotificationPrefix = "x.clock.alarm."
    private let timerNotificationIdentifier = "x.clock.timer"
    private static let timerAlarmID = UUID(uuidString: "a6f17243-5299-4a8b-a088-b39381001001")!

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
        notificationCenter.delegate = ClockNotificationDelegate.shared
        restoreState()
        timerSound = ClockAlarmSound(rawValue: defaults.string(forKey: timerSoundPersistenceKey) ?? "") ?? .brisa
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

    func setTimerSound(_ sound: ClockAlarmSound) {
        timerSound = sound
        defaults.set(sound.rawValue, forKey: timerSoundPersistenceKey)
    }

    func previewSound(_ sound: ClockAlarmSound) {
        guard let url = Bundle.main.url(forResource: sound.title, withExtension: "caf") else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            previewPlayer?.stop()
            previewPlayer = try AVAudioPlayer(contentsOf: url)
            previewPlayer?.prepareToPlay()
            previewPlayer?.play()
        } catch {
            previewPlayer = nil
        }
    }

    func stopSoundPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
    }

    func saveAlarm(_ alarm: ClockAlarm) async -> ClockAlarmSaveResult {
        if alarm.isEnabled {
            let deliveryAllowed = await requestAlarmDeliveryAuthorization()
            guard deliveryAllowed else { return .notificationsDenied }
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
        if isEnabled {
            let deliveryAllowed = await requestAlarmDeliveryAuthorization()
            guard deliveryAllowed else { return .notificationsDenied }
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

        let alarmKitAllowed = await requestAlarmKitAuthorization()
        var notificationsAllowed = false
        if !alarmKitAllowed {
            notificationsAllowed = await requestNotificationAuthorization()
        }
        guard alarmKitAllowed || notificationsAllowed else { return false }

        timerDuration = seconds ?? max(timerDuration, selectedDuration)
        timerPausedRemaining = selectedDuration
        timerDeadline = Date().addingTimeInterval(selectedDuration)
        timerIsRunning = true
        timerCompleted = false
        persist()

        notificationCenter.removePendingNotificationRequests(withIdentifiers: [timerNotificationIdentifier])
        cancelAlarmKit(id: Self.timerAlarmID)
#if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            if alarmKitAllowed, await scheduleTimerWithAlarmKit(duration: selectedDuration) {
                return true
            }
        }
#endif

        if !notificationsAllowed {
            notificationsAllowed = await requestNotificationAuthorization()
        }
        guard notificationsAllowed else {
            cancelTimer()
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = "Timer finalizado"
        content.body = "O tempo definido chegou ao fim."
        content.sound = notificationSound(for: timerSound)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, selectedDuration), repeats: false)
        let request = UNNotificationRequest(identifier: timerNotificationIdentifier, content: content, trigger: trigger)
        do {
            try await notificationCenter.add(request)
            return true
        } catch {
            cancelTimer()
            return false
        }
    }

    func pauseTimer() {
        guard timerIsRunning else { return }
        timerPausedRemaining = timerRemaining()
        timerDeadline = nil
        timerIsRunning = false
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [timerNotificationIdentifier])
        cancelAlarmKit(id: Self.timerAlarmID)
        persist()
    }

    func cancelTimer() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [timerNotificationIdentifier])
        cancelAlarmKit(id: Self.timerAlarmID)
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
        stopAlarmKit(id: Self.timerAlarmID)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [timerNotificationIdentifier])
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

    private func requestAlarmDeliveryAuthorization() async -> Bool {
        if await requestAlarmKitAuthorization() { return true }
        return await requestNotificationAuthorization()
    }

    private func requestAlarmKitAuthorization() async -> Bool {
#if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            let manager = AlarmManager.shared
            if manager.authorizationState == .authorized { return true }
            guard manager.authorizationState == .notDetermined else { return false }
            return (try? await manager.requestAuthorization()) == .authorized
        }
#endif
        return false
    }

    private func alarmKitIsAuthorized() -> Bool {
#if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return AlarmManager.shared.authorizationState == .authorized
        }
#endif
        return false
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
        let localNotificationsAllowed = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral
        guard localNotificationsAllowed || alarmKitIsAuthorized() else { return }
        await scheduleAllAlarmNotifications()
    }

    private func scheduleAllAlarmNotifications() async {
        let allKnownIdentifiers = alarms.flatMap { possibleAlarmNotificationIdentifiers(for: $0.id) }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: allKnownIdentifiers)
        for alarm in alarms {
            if alarm.isEnabled {
                await scheduleAlarmNotifications(for: alarm)
            } else {
                await removeAlarmNotifications(for: alarm.id)
            }
        }
    }

    private func scheduleAlarmNotifications(for alarm: ClockAlarm) async {
        guard alarm.isEnabled else { return }
#if canImport(AlarmKit)
        if #available(iOS 26.0, *), await scheduleAlarmWithAlarmKit(for: alarm) {
            notificationCenter.removePendingNotificationRequests(withIdentifiers: possibleAlarmNotificationIdentifiers(for: alarm.id))
            return
        }
#endif
        guard await requestNotificationAuthorization() else { return }

        let content = UNMutableNotificationContent()
        content.title = alarm.label.isEmpty ? "Alarme" : alarm.label
        content.body = "Está na hora."
        content.sound = notificationSound(for: alarm.sound)

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
        cancelAlarmKit(id: id)
    }

    private func possibleAlarmNotificationIdentifiers(for id: UUID) -> [String] {
        [alarmNotificationPrefix + id.uuidString] + (1...7).map { alarmNotificationPrefix + id.uuidString + "." + String($0) }
    }

    private func notificationSound(for sound: ClockAlarmSound) -> UNNotificationSound {
        UNNotificationSound(named: UNNotificationSoundName(rawValue: sound.fileName))
    }

#if canImport(AlarmKit)
    @available(iOS 26.0, *)
    private func alarmAttributes(title: String, sound: ClockAlarmSound) -> AlarmAttributes<ClockAlarmMetadata> {
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            stopButton: AlarmButton(text: "Parar", textColor: .white, systemImageName: "stop.circle"),
            secondaryButton: nil,
            secondaryButtonBehavior: nil
        )
        return AlarmAttributes<ClockAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: ClockAlarmMetadata(label: title, soundID: sound.rawValue),
            tintColor: Color.white
        )
    }

    @available(iOS 26.0, *)
    private func scheduleAlarmWithAlarmKit(for alarm: ClockAlarm) async -> Bool {
        guard alarmKitIsAuthorized() else { return false }
        do {
            let existingAlarms = try AlarmManager.shared.alarms
            if existingAlarms.contains(where: { $0.id == alarm.id }) { return true }
        } catch {
            return false
        }

        let selectedWeekdays = Set(alarm.weekdays.compactMap { weekday -> Locale.Weekday? in
            switch weekday {
            case 1: .sunday
            case 2: .monday
            case 3: .tuesday
            case 4: .wednesday
            case 5: .thursday
            case 6: .friday
            case 7: .saturday
            default: nil
            }
        })
        let time = Alarm.Schedule.Relative.Time(hour: alarm.hour, minute: alarm.minute)
        let recurrence: Alarm.Schedule.Relative.Recurrence = selectedWeekdays.isEmpty
            ? .never
            : .weekly(Array(selectedWeekdays))
        let schedule = Alarm.Schedule.relative(.init(time: time, repeats: recurrence))
        let title = alarm.label.isEmpty ? "Alarme" : alarm.label
        let attributes = alarmAttributes(title: title, sound: alarm.sound)
        let configuration = AlarmManager.AlarmConfiguration.alarm(
            schedule: schedule,
            attributes: attributes,
            sound: AlertConfiguration.AlertSound.named(alarm.sound.fileName)
        )

        do {
            _ = try await AlarmManager.shared.schedule(id: alarm.id, configuration: configuration)
            return true
        } catch {
            return false
        }
    }

    @available(iOS 26.0, *)
    private func scheduleTimerWithAlarmKit(duration: TimeInterval) async -> Bool {
        guard alarmKitIsAuthorized() else { return false }
        let attributes = alarmAttributes(title: "Timer finalizado", sound: timerSound)
        let configuration = AlarmManager.AlarmConfiguration.timer(
            duration: duration,
            attributes: attributes,
            sound: AlertConfiguration.AlertSound.named(timerSound.fileName)
        )
        do {
            _ = try await AlarmManager.shared.schedule(id: Self.timerAlarmID, configuration: configuration)
            return true
        } catch {
            return false
        }
    }
#endif

    private func cancelAlarmKit(id: UUID) {
#if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            try? AlarmManager.shared.cancel(id: id)
        }
#endif
    }

    private func stopAlarmKit(id: UUID) {
#if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            try? AlarmManager.shared.stop(id: id)
        }
#endif
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
