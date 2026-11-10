import SwiftUI
import UIKit

struct ClockAlarmView: View {
    @EnvironmentObject private var clockStore: ClockFeatureStore
    @State private var alarmDraft: ClockAlarm?
    @State private var draftIsExisting = false
    @State private var isEditing = false
    @State private var activeAlert: ClockAlarmAlert?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Alarmes")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Gerencie horários e dias de repetição")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { isEditing.toggle() }
                } label: {
                    Text(isEditing ? "Concluir" : "Editar")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(ClockGlassButtonStyle(tint: AppTheme.accent))
                .accessibilityLabel(isEditing ? "Concluir edição dos alarmes" : "Editar alarmes")
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 14)

            ScrollView {
                LazyVStack(spacing: 10) {
                    if clockStore.alarms.isEmpty {
                        emptyState
                    } else {
                        ForEach(clockStore.alarms) { alarm in
                            alarmRow(alarm)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }

            Button(action: addAlarm) {
                Label("Adicionar alarme", systemImage: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .liquidGlass(
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous),
                        tint: AppTheme.accent,
                        opacity: 0.11,
                        interactive: true
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .sheet(item: $alarmDraft) { draft in
            ClockAlarmEditor(
                initialAlarm: draft,
                isExisting: draftIsExisting,
                onSave: { updated in await clockStore.saveAlarm(updated) },
                onDelete: { id in await clockStore.deleteAlarm(id: id) }
            )
            .environmentObject(clockStore)
            .preferredColorScheme(.dark)
        }
        .alert(item: $activeAlert) { alert in
            makeClockAlarmAlert(alert, openSettings: openSettings)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "alarm")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(AppTheme.accent)
            Text("Nenhum alarme cadastrado")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
            Text("Crie um alarme e escolha se ele toca uma vez ou se repete durante a semana.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 38)
        .padding(.horizontal, 24)
        .liquidGlassCard(cornerRadius: 18, tint: AppTheme.accent, opacity: 0.06)
    }

    private func alarmRow(_ alarm: ClockAlarm) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(alarm.timeText)
                    .font(.system(size: 40, weight: .light, design: .rounded).monospacedDigit())
                    .foregroundStyle(alarm.isEnabled ? .white : .secondary)
                HStack(spacing: 6) {
                    Text(alarm.label.isEmpty ? "Alarme" : alarm.label)
                    Text("·")
                    Text(alarm.repeatText)
                    Text("·")
                    Text(alarm.sound.title)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            if isEditing {
                Button {
                    draftIsExisting = true
                    alarmDraft = alarm
                } label: {
                    Label("Editar", systemImage: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                }
                .buttonStyle(ClockGlassButtonStyle(tint: AppTheme.accent))
                .accessibilityLabel("Editar alarme das \(alarm.timeText)")
            } else {
                Toggle("Ativo", isOn: Binding(
                    get: { alarm.isEnabled },
                    set: { newValue in
                        Task {
                            let result = await clockStore.setAlarmEnabled(id: alarm.id, isEnabled: newValue)
                            handle(result)
                        }
                    }
                ))
                .labelsHidden()
                .tint(AppTheme.accent)
                .accessibilityLabel(alarm.isEnabled ? "Desativar alarme das \(alarm.timeText)" : "Ativar alarme das \(alarm.timeText)")
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .liquidGlassCard(cornerRadius: 16, tint: AppTheme.accent, opacity: alarm.isEnabled ? 0.055 : 0.025)
    }

    private func addAlarm() {
        let nextMinute = Calendar.current.date(byAdding: .minute, value: 1, to: Date()) ?? Date()
        draftIsExisting = false
        alarmDraft = ClockAlarm(
            hour: Calendar.current.component(.hour, from: nextMinute),
            minute: Calendar.current.component(.minute, from: nextMinute)
        )
    }

    private func handle(_ result: ClockAlarmSaveResult) {
        switch result {
        case .saved:
            break
        case .notificationsDenied:
            activeAlert = .permission
        case .notificationLimit:
            activeAlert = .limit
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private enum ClockAlarmAlert: String, Identifiable {
    case permission
    case limit

    var id: String { rawValue }
}

private func makeClockAlarmAlert(_ alert: ClockAlarmAlert, openSettings: @escaping () -> Void) -> Alert {
    switch alert {
    case .permission:
        return Alert(
            title: Text("Alarmes sem autorização"),
            message: Text("Permita alarmes ou notificações para X nos Ajustes para receber avisos com som quando o app estiver fechado."),
            primaryButton: .default(Text("Abrir Ajustes"), action: openSettings),
            secondaryButton: .cancel(Text("Agora não"))
        )
    case .limit:
        return Alert(
            title: Text("Limite de alarmes ativos"),
            message: Text("O iOS limita a quantidade de alarmes pendentes. Desative outros alarmes ou diminua os dias de repetição."),
            dismissButton: .default(Text("OK"))
        )
    }
}

private struct ClockAlarmEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var clockStore: ClockFeatureStore
    @State private var time: Date
    @State private var label: String
    @State private var weekdays: Set<Int>
    @State private var isEnabled: Bool
    @State private var sound: ClockAlarmSound
    @State private var activeAlert: ClockAlarmAlert?
    @State private var isSaving = false

    let initialAlarm: ClockAlarm
    let isExisting: Bool
    let onSave: (ClockAlarm) async -> ClockAlarmSaveResult
    let onDelete: (UUID) async -> Void

    private let dayNames = [(1, "D"), (2, "S"), (3, "T"), (4, "Q"), (5, "Q"), (6, "S"), (7, "S")]

    init(
        initialAlarm: ClockAlarm,
        isExisting: Bool,
        onSave: @escaping (ClockAlarm) async -> ClockAlarmSaveResult,
        onDelete: @escaping (UUID) async -> Void
    ) {
        self.initialAlarm = initialAlarm
        self.isExisting = isExisting
        self.onSave = onSave
        self.onDelete = onDelete
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = initialAlarm.hour
        components.minute = initialAlarm.minute
        _time = State(initialValue: Calendar.current.date(from: components) ?? Date())
        _label = State(initialValue: initialAlarm.label)
        _weekdays = State(initialValue: Set(initialAlarm.weekdays))
        _isEnabled = State(initialValue: initialAlarm.isEnabled)
        _sound = State(initialValue: initialAlarm.sound)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        sectionCard(title: "Horário") {
                            DatePicker("Hora", selection: $time, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.wheel)
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                                .frame(height: 145)
                                .environment(\.locale, Locale(identifier: "pt_BR"))
                        }

                        sectionCard(title: "Repetir") {
                            HStack(spacing: 7) {
                                ForEach(dayNames, id: \.0) { weekday, name in
                                    let selected = weekdays.contains(weekday)
                                    Button {
                                        if selected { weekdays.remove(weekday) }
                                        else { weekdays.insert(weekday) }
                                    } label: {
                                        Text(name)
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(selected ? .black : .white)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 39)
                                            .liquidGlass(
                                                in: Circle(),
                                                tint: selected ? AppTheme.accent : .white,
                                                opacity: selected ? 0.28 : 0.055,
                                                interactive: true
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(fullDayName(weekday)) \(selected ? "selecionado" : "não selecionado")")
                                }
                            }
                        }

                        sectionCard(title: "Detalhes") {
                            TextField("Nome do alarme (opcional)", text: $label)
                                .textInputAutocapitalization(.sentences)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 11)
                                .liquidGlass(
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                                    tint: .white,
                                    opacity: 0.07,
                                    interactive: true
                                )
                            Toggle("Alarme ativo", isOn: $isEnabled)
                                .tint(AppTheme.accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .liquidGlass(
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                                    tint: AppTheme.accent,
                                    opacity: 0.06
                                )
                        }

                        sectionCard(title: "Som do alarme") {
                            ClockSoundPicker(selection: $sound, onPreview: clockStore.previewSound)
                        }

                        if isExisting {
                            Button(role: .destructive) {
                                Task {
                                    await onDelete(initialAlarm.id)
                                    dismiss()
                                }
                            } label: {
                                Label("Apagar alarme", systemImage: "trash")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                            }
                            .buttonStyle(ClockGlassButtonStyle(tint: .red))
                            .disabled(isSaving)
                        }
                    }
                    .padding(18)
                    .padding(.bottom, 12)
                }
            }
            .navigationTitle(isExisting ? "Editar alarme" : "Novo alarme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .liquidGlass(in: Capsule(), tint: AppTheme.accent, opacity: 0.08, interactive: true)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Salvando…" : "Salvar") { save() }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .liquidGlass(in: Capsule(), tint: AppTheme.accent, opacity: 0.08, interactive: true)
                        .disabled(isSaving)
                }
            }
        }
        .alert(item: $activeAlert) { alert in
            makeClockAlarmAlert(alert) {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        }
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.3)
                .foregroundStyle(AppTheme.accent)
            content()
        }
        .padding(15)
        .liquidGlassCard(cornerRadius: 18, tint: AppTheme.accent, opacity: 0.055)
    }

    private func save() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        var updated = initialAlarm
        updated.hour = components.hour ?? 0
        updated.minute = components.minute ?? 0
        updated.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.weekdays = weekdays.sorted()
        updated.isEnabled = isEnabled
        updated.sound = sound

        isSaving = true
        Task {
            let result = await onSave(updated)
            isSaving = false
            switch result {
            case .saved:
                dismiss()
            case .notificationsDenied:
                activeAlert = .permission
            case .notificationLimit:
                activeAlert = .limit
            }
        }
    }

    private func fullDayName(_ weekday: Int) -> String {
        [1: "Domingo", 2: "Segunda-feira", 3: "Terça-feira", 4: "Quarta-feira", 5: "Quinta-feira", 6: "Sexta-feira", 7: "Sábado"][weekday] ?? "Dia"
    }
}

private struct ClockSoundPicker: View {
    @Binding var selection: ClockAlarmSound
    let onPreview: (ClockAlarmSound) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(ClockAlarmSound.allCases) { tone in
                HStack(spacing: 8) {
                    Button { selection = tone } label: {
                        HStack(spacing: 10) {
                            Image(systemName: tone.symbolName)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(AppTheme.accent)
                                .frame(width: 30, height: 30)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(tone.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text(tone.subtitle)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            Spacer(minLength: 2)
                            Image(systemName: selection == tone ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(selection == tone ? AppTheme.accent : .secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .liquidGlass(
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous),
                            tint: selection == tone ? AppTheme.accent : .white,
                            opacity: selection == tone ? 0.13 : 0.035,
                            interactive: true
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Selecionar som \(tone.title)")

                    Button { onPreview(tone) } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 39, height: 39)
                            .liquidGlass(in: Circle(), tint: AppTheme.accent, opacity: 0.12, interactive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ouvir \(tone.title)")
                }
            }
        }
    }
}
