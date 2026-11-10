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
                Button(isEditing ? "Concluir" : "Editar") {
                    withAnimation(.easeInOut(duration: 0.18)) { isEditing.toggle() }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
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
                    .padding(.vertical, 15)
                    .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .background(Color.black)
        .sheet(item: $alarmDraft) { draft in
            ClockAlarmEditor(
                initialAlarm: draft,
                isExisting: draftIsExisting,
                onSave: { updated in await clockStore.saveAlarm(updated) },
                onDelete: { id in await clockStore.deleteAlarm(id: id) }
            )
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
        .padding(.vertical, 42)
        .padding(.horizontal, 24)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                }
                .font(.system(size: 12, weight: .medium))
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
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
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
                .tint(.green)
                .accessibilityLabel(alarm.isEnabled ? "Desativar alarme das \(alarm.timeText)" : "Ativar alarme das \(alarm.timeText)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(red: 0.075, green: 0.075, blue: 0.075), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.075), lineWidth: 1)
        }
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
            title: Text("Notificações desativadas"),
            message: Text("Permita notificações para X nos Ajustes para receber alarmes com o app fechado."),
            primaryButton: .default(Text("Abrir Ajustes"), action: openSettings),
            secondaryButton: .cancel(Text("Agora não"))
        )
    case .limit:
        return Alert(
            title: Text("Limite de alarmes ativos"),
            message: Text("O iOS limita a quantidade de alertas locais pendentes. Desative outros alarmes ou diminua os dias de repetição."),
            dismissButton: .default(Text("OK"))
        )
    }
}

private struct ClockAlarmEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var time: Date
    @State private var label: String
    @State private var weekdays: Set<Int>
    @State private var isEnabled: Bool
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
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Horário") {
                    DatePicker("Hora", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .environment(\.locale, Locale(identifier: "pt_BR"))
                }
                .listRowBackground(Color(red: 0.075, green: 0.075, blue: 0.075))

                Section("Repetir") {
                    HStack(spacing: 8) {
                        ForEach(dayNames, id: \.0) { weekday, name in
                            let selected = weekdays.contains(weekday)
                            Button {
                                if selected { weekdays.remove(weekday) }
                                else { weekdays.insert(weekday) }
                            } label: {
                                Text(name)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(selected ? .black : .white)
                                    .frame(width: 36, height: 36)
                                    .background(selected ? AppTheme.accent : Color.white.opacity(0.10), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(fullDayName(weekday)) \(selected ? "selecionado" : "não selecionado")")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .listRowBackground(Color(red: 0.075, green: 0.075, blue: 0.075))
                }

                Section("Detalhes") {
                    TextField("Nome do alarme (opcional)", text: $label)
                        .textInputAutocapitalization(.sentences)
                        .listRowBackground(Color(red: 0.075, green: 0.075, blue: 0.075))
                    Toggle("Ativo", isOn: $isEnabled)
                        .tint(.green)
                        .listRowBackground(Color(red: 0.075, green: 0.075, blue: 0.075))
                }

                if isExisting {
                    Section {
                        Button("Apagar alarme", role: .destructive) {
                            Task {
                                await onDelete(initialAlarm.id)
                                dismiss()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color(red: 0.075, green: 0.075, blue: 0.075))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle(isExisting ? "Editar alarme" : "Novo alarme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Salvando…" : "Salvar") { save() }
                        .disabled(isSaving)
                        .fontWeight(.semibold)
                }
            }
        }
        .alert(item: $activeAlert) { alert in
            makeClockAlarmAlert(alert) {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        }
    }

    private func save() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        var updated = initialAlarm
        updated.hour = components.hour ?? 0
        updated.minute = components.minute ?? 0
        updated.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.weekdays = weekdays.sorted()
        updated.isEnabled = isEnabled

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
