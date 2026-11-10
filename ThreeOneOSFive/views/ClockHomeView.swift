import SwiftUI

private enum XClockTab: String, CaseIterable, Identifiable, Hashable {
    case world
    case alarms
    case timer
    case stopwatch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .world: "Mundo"
        case .alarms: "Alarme"
        case .timer: "Timer"
        case .stopwatch: "Cronômetro"
        }
    }

    var symbol: String {
        switch self {
        case .world: "globe.americas"
        case .alarms: "alarm"
        case .timer: "timer"
        case .stopwatch: "stopwatch"
        }
    }
}

struct ClockHomeView: View {
    @EnvironmentObject private var clockStore: ClockFeatureStore
    let onContinue: () -> Void

    @State private var selectedTab: XClockTab = .world

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Group {
                    switch selectedTab {
                    case .world:
                        ClockWorldView()
                    case .alarms:
                        ClockAlarmView()
                    case .timer:
                        ClockTimerView()
                    case .stopwatch:
                        ClockStopwatchView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.18), value: selectedTab)

                tabBar
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
            }
        }
        .tint(AppTheme.accent)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 11) {
            AppLogo(size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("RELÓGIO")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(2.0)
                    .foregroundStyle(AppTheme.accent)
                Text("X")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            Spacer(minLength: 8)

            Button(action: onContinue) {
                HStack(spacing: 7) {
                    Text("Entrar")
                        .font(.system(size: 14, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
            }
            .buttonStyle(ClockGlassButtonStyle(tint: AppTheme.accent))
            .accessibilityLabel("Continuar para o login e os patches")
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(XClockTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .frame(height: 18)
                        Text(tab.title)
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selectedTab == tab ? .white : Color.white.opacity(0.62))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .liquidGlass(
                        in: Capsule(),
                        tint: selectedTab == tab ? AppTheme.accent : .white,
                        opacity: selectedTab == tab ? 0.16 : 0.035,
                        interactive: true
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(5)
        .liquidGlass(in: Capsule(), tint: AppTheme.accent, opacity: 0.08)
    }
}

private struct ClockWorldView: View {
    @EnvironmentObject private var clockStore: ClockFeatureStore
    @State private var showingCityPicker = false
    @State private var isEditing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Relógio mundial")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Horários em diferentes fusos")
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
                .accessibilityLabel(isEditing ? "Concluir edição dos relógios" : "Editar relógios")
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 14)

            if clockStore.worldClocks.isEmpty {
                emptyState
                    .padding(.horizontal, 20)
                    .frame(maxHeight: .infinity)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    ScrollView {
                        LazyVStack(spacing: 9) {
                            ForEach(clockStore.worldClocks) { city in
                                worldClockRow(city, now: timeline.date)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 18)
                    }
                }
            }

            Button { showingCityPicker = true } label: {
                Label("Adicionar cidade", systemImage: "plus.circle.fill")
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
        .sheet(isPresented: $showingCityPicker) {
            ClockCityPicker(selectedTimeZones: Set(clockStore.worldClocks.map(\.timeZoneIdentifier))) { identifier in
                clockStore.addWorldClock(timeZoneIdentifier: identifier)
            }
            .preferredColorScheme(.dark)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 11) {
            Image(systemName: "globe")
                .font(.system(size: 31, weight: .light))
                .foregroundStyle(AppTheme.accent)
            Text("Sem relógios")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
            Text("Adicione uma cidade para acompanhar o horário local.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 30)
        .liquidGlassCard(cornerRadius: 18, tint: AppTheme.accent, opacity: 0.06)
    }

    private func worldClockRow(_ city: ClockWorldCity, now: Date) -> some View {
        HStack(spacing: 13) {
            if isEditing {
                Button(role: .destructive) { clockStore.removeWorldClock(city) } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.red)
                        .frame(width: 36, height: 36)
                        .liquidGlass(in: Circle(), tint: .red, opacity: 0.12, interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remover relógio de \(city.cityName)")
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(city.cityName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Text(timeDifference(for: city, at: now))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(timeText(for: city, at: now))
                .font(.system(size: 34, weight: .light, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .accessibilityLabel("Horário em \(city.cityName): \(timeText(for: city, at: now))")
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .liquidGlassCard(cornerRadius: 16, tint: AppTheme.accent, opacity: 0.05)
    }

    private func timeText(for city: ClockWorldCity, at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.timeZone = city.timeZone ?? .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func timeDifference(for city: ClockWorldCity, at date: Date) -> String {
        guard let zone = city.timeZone else { return "Fuso indisponível" }
        let difference = zone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)
        if difference == 0 { return "Mesmo fuso local" }
        let minutes = abs(difference) / 60
        let hours = minutes / 60
        let remainder = minutes % 60
        let amount = remainder == 0 ? "\(hours)h" : "\(hours)h\(String(format: "%02d", remainder))"
        return difference > 0 ? "\(amount) adiantado" : "\(amount) atrás"
    }
}

private struct ClockCityPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    let selectedTimeZones: Set<String>
    let onSelect: (String) -> Void

    private var allTimeZones: [String] {
        TimeZone.knownTimeZoneIdentifiers
            .filter { !$0.hasPrefix("Etc/") && !$0.hasPrefix("SystemV/") }
            .sorted()
    }

    private var filteredTimeZones: [String] {
        guard !searchText.isEmpty else { return allTimeZones }
        return allTimeZones.filter { identifier in
            let city = ClockWorldCity(timeZoneIdentifier: identifier).cityName
            return city.localizedCaseInsensitiveContains(searchText)
                || identifier.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredTimeZones, id: \.self) { identifier in
                let city = ClockWorldCity(timeZoneIdentifier: identifier)
                Button {
                    onSelect(identifier)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "globe.americas.fill")
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 28, height: 28)
                            .liquidGlass(in: Circle(), tint: AppTheme.accent, opacity: 0.10)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(city.cityName)
                                .foregroundStyle(.white)
                            Text(identifier)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedTimeZones.contains(identifier) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .liquidGlassCard(cornerRadius: 13, tint: AppTheme.accent, opacity: 0.04)
                }
                .buttonStyle(.plain)
                .disabled(selectedTimeZones.contains(identifier))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .searchable(text: $searchText, prompt: "Buscar cidade ou fuso")
            .navigationTitle("Adicionar cidade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .liquidGlass(in: Capsule(), tint: AppTheme.accent, opacity: 0.08, interactive: true)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }
}
