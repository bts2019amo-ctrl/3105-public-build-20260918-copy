import SwiftUI
import UIKit

struct ClockTimerView: View {
    @EnvironmentObject private var clockStore: ClockFeatureStore
    @State private var selectedHours = 0
    @State private var selectedMinutes = 0
    @State private var selectedSeconds = 0
    @State private var activeAlert: ClockTimerAlert?

    private var selectedDuration: TimeInterval {
        TimeInterval(selectedHours * 3600 + selectedMinutes * 60 + selectedSeconds)
    }

    private var hasTimerValue: Bool {
        clockStore.timerDuration > 0 || clockStore.timerPausedRemaining > 0 || clockStore.timerCompleted
    }

    var body: some View {
        VStack(spacing: 18) {
            titleBlock
            soundPickerControl

            if hasTimerValue {
                timerDisplay
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 12)
            } else {
                durationPicker
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(spacing: 14) {
                actionButton(
                    title: "Zerar",
                    tint: Color.white.opacity(0.16),
                    foreground: .white,
                    action: resetTimer
                )
                .disabled(!hasTimerValue && selectedDuration == 0)
                .opacity(!hasTimerValue && selectedDuration == 0 ? 0.45 : 1)

                actionButton(
                    title: clockStore.timerIsRunning ? "Pausar" : "Iniciar",
                    tint: clockStore.timerIsRunning ? Color.orange.opacity(0.18) : Color.green.opacity(0.18),
                    foreground: clockStore.timerIsRunning ? .orange : .green,
                    action: toggleTimer
                )
                .disabled(!clockStore.timerIsRunning && !hasTimerValue && selectedDuration == 0)
                .opacity(!clockStore.timerIsRunning && !hasTimerValue && selectedDuration == 0 ? 0.45 : 1)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .task(id: clockStore.timerIsRunning) {
            guard clockStore.timerIsRunning else { return }
            while !Task.isCancelled && clockStore.timerIsRunning {
                clockStore.finishTimerIfNeeded()
                if !clockStore.timerIsRunning { break }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        .onAppear {
            if clockStore.timerCompleted { activeAlert = .completed }
        }
        .onChange(of: clockStore.timerCompleted) { completed in
            if completed { activeAlert = .completed }
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .completed:
                return Alert(
                    title: Text("Tempo encerrado"),
                    message: Text("A contagem regressiva chegou ao fim."),
                    dismissButton: .default(Text("OK")) { clockStore.dismissTimerCompletion() }
                )
            case .notificationPermission:
                return Alert(
                    title: Text("Notificações desativadas"),
                    message: Text("O timer está contando, mas o iPhone não poderá mostrar o alerta se o app estiver fechado. Permita notificações para X nos Ajustes."),
                    primaryButton: .default(Text("Abrir Ajustes")) { openSettings() },
                    secondaryButton: .cancel(Text("Continuar"))
                )
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Timer")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Defina uma contagem regressiva")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 24)
    }

    private var soundPickerControl: some View {
        HStack(spacing: 9) {
            Menu {
                ForEach(ClockAlarmSound.allCases) { tone in
                    Button {
                        clockStore.setTimerSound(tone)
                        clockStore.previewSound(tone)
                    } label: {
                        Label(tone.title, systemImage: tone.symbolName)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .foregroundStyle(AppTheme.accent)
                    Text("Som: \(clockStore.timerSound.title)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .liquidGlass(in: Capsule(), tint: AppTheme.accent, opacity: 0.09, interactive: true)
            }
            .disabled(clockStore.timerIsRunning)
            .accessibilityLabel("Selecionar som do timer: \(clockStore.timerSound.title)")

            Button { clockStore.previewSound(clockStore.timerSound) } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .liquidGlass(in: Circle(), tint: AppTheme.accent, opacity: 0.12, interactive: true)
            }
            .buttonStyle(.plain)
            .disabled(clockStore.timerIsRunning)
            .accessibilityLabel("Ouvir som do timer")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }

    private var durationPicker: some View {
        HStack(spacing: 0) {
            wheelPicker(selection: $selectedHours, range: 0...23, suffix: "h")
            wheelPicker(selection: $selectedMinutes, range: 0...59, suffix: "min")
            wheelPicker(selection: $selectedSeconds, range: 0...59, suffix: "s")
        }
        .frame(height: 220)
        .padding(.horizontal, 12)
        .liquidGlassCard(cornerRadius: 20, tint: AppTheme.accent, opacity: 0.055)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
    }

    private func wheelPicker(selection: Binding<Int>, range: ClosedRange<Int>, suffix: String) -> some View {
        Picker(suffix, selection: selection) {
            ForEach(range, id: \.self) { value in
                Text(String(format: "%02d", value))
                    .font(.system(size: 22, weight: .medium, design: .rounded).monospacedDigit())
                    .tag(value)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            Text(suffix)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .offset(y: 18)
                .accessibilityHidden(true)
        }
    }

    private var timerDisplay: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let remaining = clockStore.timerRemaining(at: timeline.date)
            let progress = clockStore.timerDuration > 0 ? min(1, max(0, remaining / clockStore.timerDuration)) : 0
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(clockStore.timerIsRunning ? Color.green : AppTheme.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.25), value: progress)
                    Text(ClockTimeFormat.timer(remaining))
                        .font(.system(size: 48, weight: .light, design: .rounded).monospacedDigit())
                        .foregroundStyle(clockStore.timerIsRunning ? .white : .secondary)
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)
                        .padding(.horizontal, 24)
                        .accessibilityLabel("Tempo restante: \(ClockTimeFormat.spoken(remaining))")
                }
                .frame(width: 258, height: 258)
                .liquidGlass(in: Circle(), tint: AppTheme.accent, opacity: 0.075)
                .padding(.horizontal, 20)

                Text(clockStore.timerIsRunning ? "EM CONTAGEM" : (clockStore.timerCompleted ? "CONCLUÍDO" : "PAUSADO"))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func actionButton(title: String, tint: Color, foreground: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .liquidGlass(in: Capsule(), tint: tint, opacity: 0.22, interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func toggleTimer() {
        if clockStore.timerIsRunning {
            clockStore.pauseTimer()
            return
        }
        Task {
            let duration: TimeInterval? = hasTimerValue ? nil : selectedDuration
            let notificationAllowed = await clockStore.startTimer(seconds: duration)
            if !notificationAllowed { activeAlert = .notificationPermission }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func resetTimer() {
        clockStore.cancelTimer()
        selectedHours = 0
        selectedMinutes = 0
        selectedSeconds = 0
    }
}

struct ClockStopwatchView: View {
    @EnvironmentObject private var clockStore: ClockFeatureStore

    var body: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Cronômetro")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Tempo decorrido e voltas")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 24)

            TimelineView(.periodic(from: .now, by: 0.05)) { timeline in
                Text(ClockTimeFormat.stopwatch(clockStore.stopwatchElapsed(at: timeline.date)))
                    .font(.system(size: 51, weight: .light, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 34)
                    .accessibilityLabel("Tempo decorrido: \(ClockTimeFormat.spoken(clockStore.stopwatchElapsed(at: timeline.date)))")
            }

            HStack(spacing: 14) {
                stopwatchButton(
                    title: clockStore.stopwatchIsRunning ? "Volta" : "Zerar",
                    tint: Color.white.opacity(0.16),
                    foreground: .white
                ) {
                    if clockStore.stopwatchIsRunning { clockStore.recordStopwatchLap() }
                    else { clockStore.resetStopwatch() }
                }
                .disabled(!clockStore.stopwatchIsRunning && clockStore.stopwatchElapsed() == 0)
                .opacity(!clockStore.stopwatchIsRunning && clockStore.stopwatchElapsed() == 0 ? 0.45 : 1)

                stopwatchButton(
                    title: clockStore.stopwatchIsRunning ? "Pausar" : "Iniciar",
                    tint: clockStore.stopwatchIsRunning ? Color.orange.opacity(0.18) : Color.green.opacity(0.18),
                    foreground: clockStore.stopwatchIsRunning ? .orange : .green
                ) {
                    clockStore.toggleStopwatch()
                }
            }
            .padding(.horizontal, 20)

            lapList
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 20)
                .liquidGlassCard(cornerRadius: 18, tint: AppTheme.accent, opacity: 0.045)
                .padding(.bottom, 12)
        }
    }

    private var lapList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if clockStore.stopwatchLaps.isEmpty {
                    HStack {
                        Text("Voltas")
                        Spacer()
                        Text("—")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
                } else {
                    HStack {
                        Text("Volta")
                        Spacer()
                        Text("Parcial")
                        Spacer().frame(width: 22)
                        Text("Total")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)

                    ForEach(clockStore.stopwatchLaps.reversed()) { lap in
                        HStack {
                            Text("\(lap.number)")
                                .foregroundStyle(.white)
                            Spacer()
                            Text(ClockTimeFormat.stopwatch(lap.split))
                                .foregroundStyle(.secondary)
                            Spacer().frame(width: 22)
                            Text(ClockTimeFormat.stopwatch(lap.total))
                                .foregroundStyle(.white)
                        }
                        .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                        .padding(.vertical, 11)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.white.opacity(0.09)).frame(height: 0.5)
                        }
                    }
                }
            }
        }
        .accessibilityLabel("Histórico de voltas")
    }

    private func stopwatchButton(title: String, tint: Color, foreground: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .liquidGlass(in: Capsule(), tint: tint, opacity: 0.22, interactive: true)
        }
        .buttonStyle(.plain)
    }
}

private enum ClockTimerAlert: Identifiable {
    case completed
    case notificationPermission

    var id: String {
        switch self {
        case .completed: "completed"
        case .notificationPermission: "notificationPermission"
        }
    }
}

private enum ClockTimeFormat {
    static func timer(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    static func stopwatch(_ interval: TimeInterval) -> String {
        let centiseconds = max(0, Int(interval * 100))
        let hours = centiseconds / 360000
        let minutes = (centiseconds / 6000) % 60
        let seconds = (centiseconds / 100) % 60
        let fraction = centiseconds % 100
        if hours > 0 {
            return String(format: "%02d:%02d:%02d,%02d", hours, minutes, seconds, fraction)
        }
        return String(format: "%02d:%02d,%02d", minutes, seconds, fraction)
    }

    static func spoken(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) hora(s)") }
        if minutes > 0 { parts.append("\(minutes) minuto(s)") }
        if seconds > 0 || parts.isEmpty { parts.append("\(seconds) segundo(s)") }
        return parts.joined(separator: " e ")
    }
}
