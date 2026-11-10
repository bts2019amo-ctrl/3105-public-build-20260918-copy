import SwiftUI

private enum XClockTab: Hashable {
    case world
    case alarms
    case timer
    case stopwatch
}

struct ClockHomeView: View {
    @EnvironmentObject private var clockStore: ClockFeatureStore
    let onContinue: () -> Void

    @State private var selectedTab: XClockTab = .world

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView(selection: $selectedTab) {
                ClockWorldView()
                    .tabItem { Label("Mundo", systemImage: "globe.americas") }
                    .tag(XClockTab.world)
                ClockAlarmView()
                    .tabItem { Label("Alarmes", systemImage: "alarm") }
                    .tag(XClockTab.alarms)
                ClockTimerView()
                    .tabItem { Label("Timer", systemImage: "timer") }
                    .tag(XClockTab.timer)
                ClockStopwatchView()
                    .tabItem { Label("Cronômetro", systemImage: "stopwatch") }
                    .tag(XClockTab.stopwatch)
            }
            .toolbarBackground(Color.black, for: .tabBar)
            .toolbarColorScheme(.dark, for: .tabBar)
        }
        .background(Color.black.ignoresSafeArea())
        .tint(AppTheme.accent)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image("BrandX")
                .resizable()
                .scaledToFit()
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)

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
                .foregroundStyle(.black)
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
                .background(AppTheme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Continuar para o login e os patches")
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color.black)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 0.5)
        }
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
                Button(isEditing ? "Concluir" : "Editar") {
                    withAnimation(.easeInOut(duration: 0.18)) { isEditing.toggle() }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .accessibilityLabel(isEditing ? "Concluir edição dos relógios" : "Editar relógios")
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 14)

            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(clockStore.worldClocks) { city in
                            worldClockRow(city, now: timeline.date)
                            Rectangle()
                                .fill(Color.white.opacity(0.11))
                                .frame(height: 0.5)
                                .padding(.leading, isEditing ? 58 : 0)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)
                }
            }

            if clockStore.worldClocks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "globe")
                        .font(.system(size: 30, weight: .light))
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
                .padding(.vertical, 28)
            }

            Button { showingCityPicker = true } label: {
                Label("Adicionar cidade", systemImage: "plus.circle.fill")
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
        .sheet(isPresented: $showingCityPicker) {
            ClockCityPicker(selectedTimeZones: Set(clockStore.worldClocks.map(\.timeZoneIdentifier))) { identifier in
                clockStore.addWorldClock(timeZoneIdentifier: identifier)
            }
            .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder
    private func worldClockRow(_ city: ClockWorldCity, now: Date) -> some View {
        HStack(spacing: 14) {
            if isEditing {
                Button(role: .destructive) { clockStore.removeWorldClock(city) } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 23))
                        .foregroundStyle(.red)
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
        .padding(.vertical, 18)
        .contentShape(Rectangle())
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
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(city.cityName)
                                .foregroundStyle(.primary)
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
                    .contentShape(Rectangle())
                }
                .disabled(selectedTimeZones.contains(identifier))
                .listRowBackground(Color(red: 0.07, green: 0.07, blue: 0.07))
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .searchable(text: $searchText, prompt: "Buscar cidade ou fuso")
            .navigationTitle("Adicionar cidade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
