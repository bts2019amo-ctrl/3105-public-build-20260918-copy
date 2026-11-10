import SwiftUI
import UIKit

struct ScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
struct DeltaCardShadow: ViewModifier {
    var color: Color = DeltaColors.accent
    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.14), radius: 12, y: 4)
            .shadow(color: color.opacity(0.06), radius: 2, y: 1)
    }
}
extension View {
    func deltaCardShadow(_ color: Color = DeltaColors.accent) -> some View {
        modifier(DeltaCardShadow(color: color))
    }
}

struct ExternalSystemShellView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var keySession: IOSKeySession
    @EnvironmentObject private var patchStore: PatchProjectStore
    @StateObject private var remoteConfig = RemoteAppConfigStore()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.portugueseBrazil.rawValue

    @State private var route: DeltaRoute = .selector
    @State private var selectedGame: DeltaGame = .freeFire
    @State private var selectedTab: DeltaTab = .avatar
    @State private var showErrorBanner = false
    @AppStorage("externalSystem.streamProofEnabled") private var streamProofEnabled = false
    @AppStorage(DeltaColors.themeKey) private var themeRaw = DeltaTheme.graphite.rawValue
    @AppStorage(DeltaColors.darkModeKey) private var darkMode = false
    @AppStorage(DeltaColors.customHueKey) private var customHue = 0.53
    @State private var isScreenCaptured = UIScreen.screens.contains(where: { $0.isCaptured })
    @State private var screenshotShieldActive = false

    private var isVietnamese: Bool { false }
    private var motion: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.28) }

    var body: some View {
        ZStack {
            ParticleFieldBackground()
                .ignoresSafeArea()
                .accessibilityHidden(true)

            switch route {
            case .selector:
                DeltaGameSelectorView(
                    selectedGame: $selectedGame,
                    onEnter: {
                        selectedTab = .avatar
                        withAnimation(motion) { route = .dashboard }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            case .dashboard:
                DeltaDashboardView(
                    selectedGame: $selectedGame,
                    selectedTab: $selectedTab,
                    languageCode: $languageCode,
                    showErrorBanner: $showErrorBanner,
                    isVietnamese: isVietnamese,
                    appState: appState,
                    keySession: keySession,
                    onBackToGameSelection: {
                        withAnimation(motion) {
                            selectedTab = .avatar
                            route = .selector
                        }
                    }
                )
                .environmentObject(remoteConfig)
                .transition(.opacity)
            }

            if remoteConfig.config.maintenance.enabled {
                Color.black.opacity(0.55)
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .overlay {
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(DeltaColors.accent.opacity(0.18))
                                    .frame(width: 72, height: 72)
                                Image(systemName: "wrench.and.screwdriver.fill")
                                    .font(.system(size: 30, weight: .bold))
                                    .foregroundStyle(DeltaColors.accent)
                            }
                            Text(remoteConfig.config.maintenance.title.isEmpty ? "Em manutencao" : remoteConfig.config.maintenance.title)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(DeltaColors.ink)
                            Text(remoteConfig.config.maintenance.message)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(DeltaColors.muted)
                                .font(.subheadline)
                        }
                        .padding(36)
                        .background(DeltaColors.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(DeltaColors.line, lineWidth: 1)
                        )
                        .deltaCardShadow()
                        .padding(28)
                    }
                    .zIndex(30)
            }

            if streamProofEnabled && (isScreenCaptured || screenshotShieldActive) {
                Color.black
                    .ignoresSafeArea()
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: "eye.slash.fill")
                                .font(.system(size: 28, weight: .bold))
                            Text("Conteúdo protegido")
                                .font(.headline.weight(.bold))
                        }
                        .foregroundStyle(.white)
                    }
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .background(DeltaColors.page.ignoresSafeArea())
        .environmentObject(remoteConfig)
        .preferredColorScheme(.dark)
        .animation(motion, value: route)
        .task {
            remoteConfig.start()
            await remoteConfig.refresh()
        }
        .onChange(of: route) { newRoute in
            if newRoute == .dashboard {
                patchStore.syncNow()
            }
        }
        .onChange(of: selectedGame) { _ in
            patchStore.syncNow()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
            isScreenCaptured = UIScreen.screens.contains(where: { $0.isCaptured })
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            guard streamProofEnabled else { return }
            screenshotShieldActive = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                screenshotShieldActive = false
            }
        }
        .task(id: streamProofEnabled) {
            // The notification is not delivered consistently across iOS versions;
            // polling keeps the shield active during recording and mirroring.
            while !Task.isCancelled {
                let captured = UIScreen.screens.contains(where: { $0.isCaptured })
                if captured != isScreenCaptured {
                    isScreenCaptured = captured
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }
}

private struct DeltaColorWheel: View {
    @Binding var selectedHue: Double

    private let wheelColors: [Color] = [
        Color(hue: 0.00, saturation: 1, brightness: 1),
        Color(hue: 0.08, saturation: 1, brightness: 1),
        Color(hue: 0.17, saturation: 1, brightness: 1),
        Color(hue: 0.33, saturation: 1, brightness: 1),
        Color(hue: 0.52, saturation: 1, brightness: 1),
        Color(hue: 0.67, saturation: 1, brightness: 1),
        Color(hue: 0.82, saturation: 1, brightness: 1),
        Color(hue: 0.94, saturation: 1, brightness: 1),
        Color(hue: 1.00, saturation: 1, brightness: 1)
    ]

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = side * 0.39
            ZStack {
                Circle()
                    .strokeBorder(
                        AngularGradient(colors: wheelColors, center: .center),
                        lineWidth: side * 0.16
                    )
                    .shadow(color: Color(hue: selectedHue, saturation: 0.9, brightness: 1).opacity(0.55), radius: 18)
                Circle()
                    .fill(DeltaColors.card)
                    .frame(width: side * 0.52, height: side * 0.52)
                    .overlay {
                        VStack(spacing: 3) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(DeltaColors.accent)
                            Text("COLOR")
                                .font(.system(size: 9, weight: .black, design: .rounded))
                                .foregroundStyle(DeltaColors.muted)
                        }
                    }
                    .shadow(color: DeltaColors.accent.opacity(0.22), radius: 15)
                Circle()
                    .fill(Color(hue: selectedHue, saturation: 0.94, brightness: 1.0))
                    .frame(width: side * 0.095, height: side * 0.095)
                    .overlay(Circle().stroke(.white, lineWidth: 3))
                    .shadow(color: Color(hue: selectedHue, saturation: 0.94, brightness: 1.0).opacity(0.9), radius: 9)
                    .offset(
                        x: cos(selectedHue * 2 * .pi) * radius,
                        y: sin(selectedHue * 2 * .pi) * radius
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let dx = value.location.x - center.x
                let dy = value.location.y - center.y
                guard (dx * dx + dy * dy) > (side * 0.18) * (side * 0.18) else { return }
                var hue = atan2(dy, dx) / (2 * .pi)
                if hue < 0 { hue += 1 }
                selectedHue = hue
            })
        }
    }
}

private enum DeltaRoute: Equatable { case selector, dashboard }
private enum DeltaGame: String, CaseIterable { case freeFire, freeFireMax }
private enum DeltaTab: Hashable { case dashboard, cache, avatar, hologram, external, skin, settings, custom(String)
    var title: String {
        switch self {
        case .dashboard: return "Categorias"
        case .cache: return "Cache"
        case .avatar: return "Avatar"
        case .hologram: return "Holograma"
        case .external: return "EXTERNAL"
        case .skin: return "Skin"
        case .settings: return "Configurações"
        case .custom(let identifier): return identifier
        }
    }
    var vietnameseTitle: String {
        switch self {
        case .dashboard: return "Trang chá»§"
        case .cache: return "Cache"
        case .avatar: return "Avatar"
        case .hologram: return "Hologram"
        case .external: return "External"
        case .skin: return "Skin"
        case .settings: return "CÃ i Äáº·t"
        case .custom(let identifier): return identifier
        }
    }
    var icon: String {
        switch self {
        case .dashboard: return "house.fill"
        case .cache: return "externaldrive.fill"
        case .avatar: return "person.crop.circle.fill"
        case .hologram: return "wand.and.stars"
        case .external: return "scope"
        case .skin: return "tshirt.fill"
        case .settings: return "gearshape.fill"
        case .custom: return "square.grid.2x2.fill"
        }
    }
}

enum DeltaTheme: String, CaseIterable, Identifiable {
    case lavender, blue, emerald, red, orange, pink, cyan, gold, graphite, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lavender: return "Lavanda"
        case .blue: return "Azul"
        case .emerald: return "Esmeralda"
        case .red: return "Vermelho"
        case .orange: return "Laranja"
        case .pink: return "Rosa"
        case .cyan: return "Ciano"
        case .gold: return "Dourado"
        case .graphite: return "Grafite"
        case .dark: return "Dark"
        }
    }
    var swatch: Color {
        switch self {
        case .lavender: return Color(red: 0.53, green: 0.18, blue: 0.86)
        case .blue: return Color(red: 0.10, green: 0.38, blue: 0.90)
        case .emerald: return Color(red: 0.03, green: 0.55, blue: 0.39)
        case .red: return Color(red: 0.82, green: 0.12, blue: 0.20)
        case .orange: return Color(red: 0.93, green: 0.38, blue: 0.08)
        case .pink: return Color(red: 0.87, green: 0.16, blue: 0.48)
        case .cyan: return Color(red: 0.00, green: 0.52, blue: 0.70)
        case .gold: return Color(red: 0.72, green: 0.47, blue: 0.04)
        case .graphite: return Color(red: 0.22, green: 0.25, blue: 0.31)
        case .dark: return Color(red: 0.08, green: 0.09, blue: 0.12)
        }
    }
}

struct DeltaPalette {
    let primary: Color
    let dark: Color
    let page: Color
    let ink: Color
    let muted: Color
    let card: Color
    let line: Color

    static func make(_ theme: DeltaTheme, darkMode: Bool) -> DeltaPalette {
        let storedHue = UserDefaults.standard.object(forKey: DeltaColors.customHueKey) as? Double
        let primary = storedHue.map { Color(hue: $0, saturation: 0.95, brightness: 1.0) } ?? theme.swatch
        if darkMode || theme == .dark {
            return DeltaPalette(
                primary: primary,
                dark: Color(hue: storedHue ?? 0.76, saturation: 0.92, brightness: 0.78),
                page: Color(red: 0.018, green: 0.021, blue: 0.026),
                ink: Color.white.opacity(0.97),
                muted: Color(hue: storedHue ?? 0.76, saturation: 0.18, brightness: 0.72),
                card: Color(red: 0.065, green: 0.074, blue: 0.086).opacity(0.98),
                line: primary.opacity(0.32)
            )
        }
        return DeltaPalette(
            primary: primary,
            dark: Color(hue: storedHue ?? 0.76, saturation: 0.90, brightness: 0.68),
            page: Color(red: 0.018, green: 0.021, blue: 0.026),
            ink: Color(hue: storedHue ?? 0.76, saturation: 0.58, brightness: 0.16),
            muted: Color(hue: storedHue ?? 0.76, saturation: 0.22, brightness: 0.42),
            card: Color(red: 0.065, green: 0.074, blue: 0.086).opacity(0.98),
            line: primary.opacity(0.22)
        )
    }
}

enum DeltaColors {
    static let themeKey = "externalSystem.theme"
    static let darkModeKey = "externalSystem.darkMode"
    static let customHueKey = "externalSystem.customHue"
    private static let palette = DeltaPalette(
        primary: Color(red: 0.72, green: 0.74, blue: 0.76),
        dark: Color(red: 0.24, green: 0.25, blue: 0.27),
        page: Color(red: 0.018, green: 0.018, blue: 0.018),
        ink: Color.white.opacity(0.96),
        muted: Color(red: 0.62, green: 0.64, blue: 0.66),
        card: Color(red: 0.065, green: 0.065, blue: 0.065).opacity(0.98),
        line: Color.white.opacity(0.13)
    )
    static var accent: Color { palette.primary }
    static var purpleDark: Color { palette.dark }
    static var lavender: Color { palette.page }
    static var page: Color { palette.page }
    static var ink: Color { palette.ink }
    static var muted: Color { palette.muted }
    static var card: Color { palette.card }
    static var line: Color { palette.line }
    static var isDark: Bool {
        UserDefaults.standard.bool(forKey: darkModeKey)
            || (DeltaTheme(rawValue: UserDefaults.standard.string(forKey: themeKey) ?? "") == .dark)
    }
}

private struct DeltaGameSelectorView: View {
    @Binding var selectedGame: DeltaGame
    let onEnter: () -> Void
    @State private var pressed = false

    var body: some View {
        VStack(spacing: 0) {
            DeltaHeader(showMenuButton: false, showKeyButton: false, isVietnamese: false, onMenu: {}, onSwitchKey: {})
                .padding(.top, 8)
                .padding(.horizontal, 20)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("SELECIONE SEU JOGO")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .tracking(1.6)
                            .foregroundStyle(DeltaColors.accent)
                        Text("Escolha a versão instalada")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .tracking(-0.4)
                            .foregroundStyle(DeltaColors.ink)
                        Text("Os patches exibidos serão referentes ao jogo selecionado.")
                            .font(.subheadline)
                            .foregroundStyle(DeltaColors.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 34)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("VERSÃO DO JOGO")
                                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                                    .tracking(1.2)
                                    .foregroundStyle(DeltaColors.accent)
                                Text("Selecione uma opção")
                                    .font(.caption)
                                    .foregroundStyle(DeltaColors.muted)
                            }
                            Spacer()
                            Image(systemName: "gamecontroller.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(DeltaColors.accent)
                                .frame(width: 38, height: 38)
                                .background(DeltaColors.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .padding(.bottom, 3)

                        DeltaGameRow(game: .freeFire, selected: selectedGame == .freeFire) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selectedGame = .freeFire }
                        }
                        DeltaGameRow(game: .freeFireMax, selected: selectedGame == .freeFireMax) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selectedGame = .freeFireMax }
                        }
                    }
                    .padding(16)
                    .background(DeltaColors.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(DeltaColors.line, lineWidth: 1))

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) { pressed = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) { pressed = false }
                            onEnter()
                        }
                    } label: {
                        HStack(spacing: 11) {
                            Text("CONTINUAR")
                                .font(.subheadline.weight(.heavy))
                                .tracking(0.7)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(LinearGradient(colors: [DeltaColors.purpleDark, DeltaColors.accent], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        .shadow(color: DeltaColors.accent.opacity(0.24), radius: 16, y: 7)
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(pressed ? 0.96 : 1)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
    }
}

private struct DeltaGameRow: View {
    let game: DeltaGame
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(game == .freeFire ? "FreeFireNormal" : "FreeFireMax")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1))
                VStack(alignment: .leading, spacing: 4) {
                    Text(game == .freeFire ? "Free Fire" : "Free Fire MAX")
                        .font(.system(.body, design: .rounded).weight(.bold))
                        .foregroundStyle(DeltaColors.ink)
                    Text(game == .freeFire ? "EDIÇÃO PADRÃO" : "EDIÇÃO MAX")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(DeltaColors.muted)
                }
                Spacer()
                ZStack {
                    Circle().stroke(selected ? DeltaColors.accent : Color.white.opacity(0.28), lineWidth: 1.5).frame(width: 21, height: 21)
                    if selected { Circle().fill(DeltaColors.accent).frame(width: 11, height: 11) }
                }
            }
            .padding(.horizontal, 13)
            .frame(minHeight: 74)
            .background(selected ? DeltaColors.accent.opacity(0.17) : Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(selected ? DeltaColors.accent.opacity(0.70) : DeltaColors.line, lineWidth: selected ? 1.3 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct DeltaDashboardView: View {
    @Binding var selectedGame: DeltaGame
    @Binding var selectedTab: DeltaTab
    @Binding var languageCode: String
    @Binding var showErrorBanner: Bool
    let isVietnamese: Bool
    let appState: AppState
    let keySession: IOSKeySession
    let onBackToGameSelection: () -> Void
    @State private var showQuickMenu = false

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                DeltaHeader(showMenuButton: true, showKeyButton: selectedTab == .avatar || selectedTab == .hologram || selectedTab == .cache || selectedTab == .skin || selectedTab == .external, isVietnamese: false, onMenu: { showQuickMenu = true }, onSwitchKey: { keySession.logout() })
                    .padding(.horizontal, 16)
                    .padding(.top, 7)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        Group {
                            switch selectedTab {
                            case .dashboard: DeltaRemoteFeatureTab(feature: .avatar, selectedGame: selectedGame)
                            case .cache: DeltaRemoteFeatureTab(feature: .cache, selectedGame: selectedGame)
                            case .avatar: DeltaRemoteFeatureTab(feature: .avatar, selectedGame: selectedGame)
                            case .hologram: DeltaRemoteFeatureTab(feature: .hologram, selectedGame: selectedGame)
                            case .external: DeltaRemoteFeatureTab(feature: .external, selectedGame: selectedGame)
                            case .skin: DeltaRemoteFeatureTab(feature: .skin, selectedGame: selectedGame)
                            case .settings: DeltaReferenceSettingsTab(languageCode: $languageCode, isVietnamese: isVietnamese, appState: appState, keySession: keySession)
                            case .custom(let identifier): DeltaRemoteCustomFeatureTab(identifier: identifier, selectedGame: selectedGame)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                    .id(selectedTab)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if showErrorBanner {
                DeltaErrorBanner {
                    withAnimation(.easeOut(duration: 0.2)) { showErrorBanner = false }
                }
                .padding(.top, 58)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(3)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: selectedTab)
        .animation(.easeInOut(duration: 0.22), value: showErrorBanner)
        .sheet(isPresented: $showQuickMenu) {
            DeltaQuickMenu(selectedTab: $selectedTab, isVietnamese: isVietnamese)
                .presentationDetents([.height(440)])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
    }
}

private struct DeltaHeader: View {
    let showMenuButton: Bool
    let showKeyButton: Bool
    let isVietnamese: Bool
    let onMenu: () -> Void
    let onSwitchKey: () -> Void
    @State private var showSwitchKeyConfirmation = false

    var body: some View {
        HStack(spacing: 10) {
            if showMenuButton {
                Button(action: onMenu) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(DeltaColors.ink)
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DeltaColors.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Abrir menu de navegação")
            } else {
                Color.clear.frame(width: 42, height: 42)
            }

            Text("EXTERNAL X")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(DeltaColors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            if showKeyButton {
                Button { showSwitchKeyConfirmation = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("TROCAR KEY")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .tracking(0.35)
                            .lineLimit(1)
                    }
                    .foregroundStyle(DeltaColors.accent)
                    .padding(.horizontal, 10)
                    .frame(height: 42)
                    .background(DeltaColors.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DeltaColors.accent.opacity(0.28), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Trocar key")
            } else {
                Color.clear.frame(width: 42, height: 42)
            }
        }
        .frame(height: 48)
        .alert("Trocar key?", isPresented: $showSwitchKeyConfirmation) {
            Button("Cancelar", role: .cancel) { }
            Button("Trocar key", role: .destructive, action: onSwitchKey)
        } message: {
            Text("Trocar a key encerra a sessão e tenta restaurar os patches aplicados antes de limpar os dados locais. Deseja continuar?")
        }
    }
}

private struct DeltaQuickMenu: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedTab: DeltaTab
    let isVietnamese: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NAVEGAÇÃO RÁPIDA")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(DeltaColors.accent)
                Text("Escolha uma categoria")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(DeltaColors.ink)
            }

            VStack(spacing: 9) {
                menuItem(.avatar, subtitle: "Patches de avatar")
                menuItem(.hologram, subtitle: "Patches de holograma")
                menuItem(.cache, subtitle: "Patches de cache")
                menuItem(.skin, subtitle: "Patches de skin")
                menuItem(.external, subtitle: "Patches EXTERNAL")
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                ParticleFieldBackground()
                DeltaColors.page.opacity(0.40)
            }
        }
    }

    private func menuItem(_ tab: DeltaTab, subtitle: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) { selectedTab = tab }
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tab.title).font(.subheadline.weight(.bold)).foregroundStyle(DeltaColors.ink)
                    Text(subtitle).font(.caption2).foregroundStyle(DeltaColors.muted)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption.weight(.bold)).foregroundStyle(DeltaColors.muted)
            }
            .padding(10)
            .background(DeltaColors.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(DeltaColors.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct DeltaTabBar: View {
    @EnvironmentObject private var patchStore: PatchProjectStore
    @EnvironmentObject private var remoteConfig: RemoteAppConfigStore
    @Binding var selectedTab: DeltaTab
    @Binding var selectedGame: DeltaGame
    let isVietnamese: Bool

    private var patchTabs: [DeltaTab] { [.avatar, .hologram, .cache, .skin, .external] }

    private func tab(for identifier: String) -> DeltaTab {
        switch identifier.lowercased() {
        case "cache": return .cache
        case "avatar": return .avatar
        case "hologram": return .hologram
        case "external": return .external
        case "skin": return .skin
        default: return .custom(identifier.lowercased())
        }
    }

    private func config(for tab: DeltaTab) -> RemoteAppCategory? {
        let identifier: String
        switch tab {
        case .cache: identifier = "cache"
        case .avatar: identifier = "avatar"
        case .hologram: identifier = "hologram"
        case .external: identifier = "external"
        case .skin: identifier = "skin"
        case .custom(let value): identifier = value
        default: return nil
        }
        return remoteConfig.config.categories.first { $0.id.lowercased() == identifier }
    }

    private func title(for tab: DeltaTab) -> String {
        switch tab {
        case .avatar: return "Avatar"
        case .hologram: return "Holograma"
        default: return config(for: tab)?.title ?? tab.title
        }
    }

    private var selectedCategory: PatchGameCategory {
        selectedGame == .freeFire ? .normal : .max
    }

    private func patchCount(for tab: DeltaTab) -> Int {
        let identifier: String
        switch tab {
        case .cache: identifier = "cache"
        case .avatar: identifier = "avatar"
        case .hologram: identifier = "hologram"
        case .external: identifier = "external"
        case .skin: identifier = "skin"
        case .custom(let value): identifier = value
        default: return 0
        }
        return patchStore.items.filter {
            PatchProjectLibrary.category(for: $0) == selectedCategory &&
            PatchProjectLibrary.featureIdentifier(for: $0) == identifier
        }.count
    }

    private func select(_ tab: DeltaTab) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            selectedTab = tab
        }
    }

    private func gameChoice(_ game: DeltaGame) -> some View {
        let active = selectedGame == game
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedGame = game }
        } label: {
            HStack(spacing: 8) {
                Image(game == .freeFire ? "FreeFireNormal" : "FreeFireMax")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(game == .freeFire ? "FREE FIRE" : "FREE FIRE MAX")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(0.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if active { Image(systemName: "checkmark.circle.fill").font(.system(size: 12, weight: .bold)) }
            }
            .foregroundStyle(active ? .white : DeltaColors.muted)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 8)
            .background(active ? DeltaColors.accent.opacity(0.68) : Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(active ? DeltaColors.accent.opacity(0.8) : DeltaColors.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("CENTRAL DE PATCHES")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(DeltaColors.accent)
                Text("O que vamos carregar?")
                    .font(.title2.weight(.bold))
                    .tracking(-0.4)
                    .foregroundStyle(DeltaColors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Selecione uma versão e explore as categorias de patches disponíveis.")
                    .font(.caption)
                    .foregroundStyle(DeltaColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 5)

            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Text("JOGO ATIVO")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(DeltaColors.muted)
                    Spacer()
                    Image(systemName: "gamecontroller.fill").font(.caption).foregroundStyle(DeltaColors.accent)
                }
                HStack(spacing: 8) {
                    gameChoice(.freeFire)
                    gameChoice(.freeFireMax)
                }
            }
            .padding(13)
            .background(DeltaColors.card, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(DeltaColors.line, lineWidth: 1))

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .lastTextBaseline) {
                    Text("CATEGORIAS")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1.25)
                        .foregroundStyle(DeltaColors.accent)
                    Spacer()
                    Text("\(patchStore.items.filter { PatchProjectLibrary.category(for: $0) == selectedCategory }.count) PATCHES")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(DeltaColors.muted)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(patchTabs, id: \.self) { tab in
                        DeltaCategoryCard(
                            tab: tab,
                            title: title(for: tab),
                            count: patchCount(for: tab),
                            isSelected: selectedTab == tab,
                            action: { select(tab) }
                        )
                    }
                }
            }

        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 22)
    }
}

private struct DeltaCompactTabButton: View {
    let tab: DeltaTab
    let selectedTab: DeltaTab
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(selectedTab == tab ? DeltaColors.accent : DeltaColors.muted)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(selectedTab == tab ? DeltaColors.accent.opacity(0.16) : DeltaColors.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct DeltaCategoryCard: View {
    let tab: DeltaTab
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: tab.icon)
                        .font(.system(size: tab == .skin ? 21 : 17, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : DeltaColors.accent)
                        .frame(width: 39, height: 39)
                        .background(isSelected ? Color.white.opacity(0.16) : DeltaColors.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "arrow.up.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isSelected ? .white.opacity(0.88) : DeltaColors.muted)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text("\(count) patches")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.78) : DeltaColors.muted)
                }
            }
            .foregroundStyle(isSelected ? .white : DeltaColors.ink)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
            .background(
                isSelected
                    ? AnyShapeStyle(LinearGradient(colors: [DeltaColors.purpleDark.opacity(0.94), DeltaColors.accent.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyShapeStyle(DeltaColors.card),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? DeltaColors.accent.opacity(0.54) : DeltaColors.line, lineWidth: 1)
            }
            .shadow(color: isSelected ? DeltaColors.accent.opacity(0.22) : .black.opacity(0.12), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct DeltaHomeTab: View {
    @EnvironmentObject private var patchStore: PatchProjectStore
    let selectedGame: DeltaGame

    private var selectedCategory: PatchGameCategory {
        selectedGame == .freeFire ? .normal : .max
    }

    private var remoteItems: [PatchLibraryItem] {
        patchStore.items.filter {
            PatchProjectLibrary.category(for: $0) == selectedCategory
        }
    }

    private func featureCount(_ feature: PatchFeatureCategory) -> Int {
        remoteItems.filter { PatchProjectLibrary.featureCategory(for: $0) == feature }.count
    }

    var body: some View {
        VStack(spacing: 12) {
            DeltaCard {
                Label("Welcome back to EXTERNAL X! Have a good day.", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DeltaColors.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            DeltaCard {
                DeltaSectionTitle("INJECTED TARGET GAME", icon: "gamecontroller.fill")
                HStack(spacing: 10) {
                    Image(selectedGame == .freeFire ? "FreeFireNormal" : "FreeFireMax")
                        .resizable().scaledToFill().frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedGame == .freeFire ? "Free Fire" : "Free Fire MAX").font(.subheadline.weight(.bold)).foregroundStyle(DeltaColors.ink)
                        Text("com.dts.freefireth").font(.caption2.monospaced()).foregroundStyle(DeltaColors.muted)
                    }
                    Spacer()
                    DeltaStatusBadge(text: "ACTIVE")
                }
            }
            DeltaCard {
                HStack {
                    DeltaSectionTitle("REMOTE PATCHES", icon: "arrow.down.circle.fill")
                    Spacer()
                    Button {
                        patchStore.syncNow()
                    } label: {
                        Image(systemName: patchStore.remoteSyncState == .syncing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(DeltaColors.accent)
                            .rotationEffect(.degrees(patchStore.remoteSyncState == .syncing ? 180 : 0))
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 7) {
                    Circle()
                        .fill(patchStore.remoteSyncState == .online ? Color.white.opacity(0.72) : patchStore.remoteSyncState == .syncing ? Color.white.opacity(0.38) : Color.gray.opacity(0.65))
                        .frame(width: 7, height: 7)
                    Text(remoteStatusTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DeltaColors.muted)
                    Spacer()
                    Text("\(remoteItems.count) patches")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(DeltaColors.accent)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                    remoteFeatureBadge("Cache", icon: "externaldrive.fill", count: featureCount(.cache))
                    remoteFeatureBadge("Avatar", icon: "person.crop.circle.fill", count: featureCount(.avatar))
                    remoteFeatureBadge("Hologram", icon: "wand.and.stars", count: featureCount(.hologram))
                    remoteFeatureBadge("Aimbot / ESP", icon: "scope", count: featureCount(.external))
                    remoteFeatureBadge("Skin", icon: "tshirt.fill", count: featureCount(.skin), emphasized: true)
                }

            }
        }
    }

    private var remoteStatusTitle: String {
        switch patchStore.remoteSyncState {
        case .idle: return "Remote feed aguardando"
        case .syncing: return "Sincronizando feed remoto..."
        case .online: return "Feed remoto online"
        case .offline: return "Feed remoto offline"
        }
    }

    private func remoteFeatureBadge(_ title: String, icon: String, count: Int, emphasized: Bool = false) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: emphasized ? 22 : 16, weight: .semibold))
                .frame(width: emphasized ? 34 : 24, height: emphasized ? 28 : 22)
                .foregroundStyle(DeltaColors.accent)
            Text(title)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(DeltaColors.ink)
                .lineLimit(1)
            Text("\(count)")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(DeltaColors.accent)
        }
        .frame(maxWidth: .infinity, minHeight: emphasized ? 62 : 54)
        .background(DeltaColors.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DeltaExternalPanelTab: View {
    @EnvironmentObject private var patchStore: PatchProjectStore
    let selectedGame: DeltaGame

    private var selectedCategory: PatchGameCategory {
        selectedGame == .freeFire ? .normal : .max
    }

    private var externalPatch: PatchLibraryItem? {
        let exactNamed = patchStore.items.filter { item in
            let displayName = PatchProjectLibrary.displayName(for: item).trimmingCharacters(in: .whitespacesAndNewlines)
            let projectName = (item.project?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let fileName = item.packageURL.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            return displayName.caseInsensitiveCompare("External") == .orderedSame
                || projectName.caseInsensitiveCompare("External") == .orderedSame
                || fileName.caseInsensitiveCompare("External") == .orderedSame
        }
        return exactNamed.first(where: { PatchProjectLibrary.category(for: $0) == selectedCategory })
            ?? exactNamed.first
            ?? patchStore.items.first {
                PatchProjectLibrary.category(for: $0) == selectedCategory
                    && PatchProjectLibrary.featureCategory(for: $0) == .external
            }
    }

    var body: some View {
        ExternalPanelView(
            store: patchStore,
            item: externalPatch,
            onRequestUnlock: { patchStore.requestUnlock(for: $0) }
        )
        .padding(.vertical, 8)
    }
}

private struct DeltaRemoteFeatureTab: View {
    @EnvironmentObject private var patchStore: PatchProjectStore
    let feature: PatchFeatureCategory
    let selectedGame: DeltaGame
    @State private var expandedItemID: UUID?

    private var items: [PatchLibraryItem] {
        let category: PatchGameCategory = selectedGame == .freeFire ? .normal : .max
        return patchStore.items.filter {
            guard PatchProjectLibrary.category(for: $0) == category else { return false }
            return PatchProjectLibrary.featureCategory(for: $0) == feature
        }
    }

    private var title: String {
        switch feature {
        case .cache: return "PATCHES DE CACHE"
        case .avatar: return "PATCHES DE AVATAR"
        case .hologram: return "PATCHES DE HOLOGRAMA"
        case .external: return "PATCHES EXTERNOS"
        case .skin: return "PATCHES DE SKIN"
        }
    }

    private var icon: String {
        switch feature {
        case .cache: return "externaldrive.fill"
        case .avatar: return "person.crop.circle.fill"
        case .hologram: return "wand.and.stars"
        case .external: return "scope"
        case .skin: return "tshirt.fill"
        }
    }

    private func isApplied(_ item: PatchLibraryItem) -> Bool {
        DevicePatchService.latestReceipt(projectID: item.id) != nil
    }

    var body: some View {
        VStack(spacing: 12) {
            DeltaCard {
                HStack {
                    if feature == .skin {
                        Image(systemName: icon)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(DeltaColors.accent)
                            .frame(width: 42, height: 42)
                            .background(DeltaColors.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Text(title)
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(DeltaColors.ink)
                    } else {
                        DeltaSectionTitle(title, icon: icon)
                    }
                    Spacer()
                    Text("\(items.count) REMOTOS")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(DeltaColors.accent)
                }
                Text("Toque em um patch para ver os controles. Você pode ativá-lo ou restaurar o original.")
                    .font(.caption)
                    .foregroundStyle(DeltaColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if items.isEmpty {
                DeltaCard {
                    VStack(spacing: 10) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(DeltaColors.accent)
                        Text(patchStore.remoteSyncState == .syncing ? "Sincronizando patches remotos..." : "Nenhum patch nesta categoria ainda")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DeltaColors.ink)
                            .multilineTextAlignment(.center)
                        Text("Atualize a lista de patches e permaneça nesta categoria para acompanhar novos itens.")
                            .font(.caption)
                            .foregroundStyle(DeltaColors.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                }
            } else {
                ForEach(items) { item in
                    let applied = isApplied(item)
                    DeltaCard {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                expandedItemID = expandedItemID == item.id ? nil : item.id
                            }
                        } label: {
                            HStack(spacing: 10) {
                                if let iconURL = PatchProjectLibrary.remoteIconURL(for: item.id) {
                                    AsyncImage(url: iconURL) { phase in
                                        if let image = phase.image { image.resizable().scaledToFit().padding(7) }
                                        else { Image(systemName: icon).resizable().scaledToFit().padding(15).foregroundStyle(DeltaColors.accent) }
                                    }
                                    .frame(width: 78, height: 78)
                                    .background(DeltaColors.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                } else {
                                    Image(systemName: icon)
                                        .font(.title3)
                                        .foregroundStyle(DeltaColors.accent)
                                        .frame(width: 42, height: 42)
                                        .background(DeltaColors.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(PatchProjectLibrary.displayName(for: item).isEmpty ? (item.project?.name ?? item.packageURL.deletingPathExtension().lastPathComponent) : PatchProjectLibrary.displayName(for: item))
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(DeltaColors.ink)
                                        .lineLimit(1)
                                    Text(applied ? (feature == .external ? "Ativo — toque para limpar os dados" : "Aplicado — toque para restaurar") : item.isLocked ? "Protegido — toque para desbloquear" : "Toque para configurar")
                                        .font(.caption2)
                                        .foregroundStyle(DeltaColors.muted)
                                }
                                Spacer()
                                Image(systemName: expandedItemID == item.id ? "chevron.up.circle.fill" : "chevron.down.circle")
                                    .foregroundStyle(DeltaColors.accent)
                            }
                        }
                        .buttonStyle(.plain)

                        if expandedItemID == item.id {
                            Divider().overlay(DeltaColors.accent.opacity(0.12))
                            if item.isLocked {
                                Button {
                                    patchStore.requestUnlock(for: item)
                                } label: {
                                    Label("DESBLOQUEAR PATCH", systemImage: "lock.open.fill")
                                        .font(.system(size: 11, weight: .black))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity, minHeight: 40)
                                        .background(DeltaColors.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .disabled(patchStore.isBusy)
                            } else {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(applied ? (feature == .external ? "Em execução" : "Aplicado") : "Desativado")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(DeltaColors.ink)
                                            .lineLimit(1)
                                        Text(applied
                                              ? (feature == .external ? "Desative para limpar os dados" : "Desative para restaurar o original")
                                              : (feature == .external ? "Ative para iniciar" : "Ative para aplicar o patch"))
                                            .font(.caption2)
                                            .foregroundStyle(DeltaColors.muted)
                                            .lineLimit(2)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 4)
                                    HStack(spacing: 9) {
                                        if patchStore.isBusy {
                                            ProgressView()
                                                .scaleEffect(0.78)
                                                .tint(DeltaColors.accent)
                                                .accessibilityLabel("Aplicando patch")
                                        }
                                        Button {
                                            if applied {
                                                patchStore.restoreInline(item)
                                            } else {
                                                patchStore.applyInline(item)
                                            }
                                        } label: {
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(applied ? DeltaColors.accent : Color.gray.opacity(0.45))
                                                .frame(width: 37, height: 23)
                                                .overlay(alignment: applied ? .trailing : .leading) {
                                                    Circle().fill(.white).frame(width: 18, height: 18).padding(2)
                                                }
                                                .animation(.spring(response: 0.24, dampingFraction: 0.8), value: applied)
                                                .frame(width: 52, height: 44)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(ScaleButtonStyle(scale: 0.93))
                                        .disabled(patchStore.isBusy)
                                        .accessibilityLabel(applied ? "Desativar patch" : "Ativar patch")
                                        .accessibilityValue(applied ? "Ativo" : "Desativado")
                                        Button {
                                            patchStore.restoreInline(item)
                                        } label: {
                                            Label("Restaurar", systemImage: "arrow.counterclockwise")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(DeltaColors.accent)
                                                .padding(.horizontal, 10)
                                                .frame(height: 36)
                                                .background(DeltaColors.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                                                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(DeltaColors.accent.opacity(0.24), lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(!applied || patchStore.isBusy)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
        }
    }
}


private struct DeltaRemoteCustomFeatureTab: View {
    @EnvironmentObject private var patchStore: PatchProjectStore
    @EnvironmentObject private var remoteConfig: RemoteAppConfigStore
    let identifier: String
    let selectedGame: DeltaGame
    @State private var expandedItemID: UUID?

    private var metadata: RemoteAppCategory? {
        remoteConfig.config.categories.first { $0.id.lowercased() == identifier.lowercased() }
    }
    private var items: [PatchLibraryItem] {
        let game: PatchGameCategory = selectedGame == .freeFire ? .normal : .max
        return patchStore.items.filter {
            PatchProjectLibrary.category(for: $0) == game &&
            PatchProjectLibrary.featureIdentifier(for: $0) == identifier.lowercased()
        }
    }
    private var title: String { metadata?.title ?? identifier.capitalized }
    private var icon: String { metadata?.icon.isEmpty == false ? metadata!.icon : "square.grid.2x2.fill" }

    var body: some View {
        VStack(spacing: 12) {
            DeltaCard {
                DeltaSectionTitle("\(title.uppercased()) PATCHES", icon: icon)
                Text("Toque em um patch para ver os controles. Você pode ativá-lo ou restaurar o original.")
                    .font(.caption)
                    .foregroundStyle(DeltaColors.muted)
            }
            if items.isEmpty {
                DeltaCard {
                    VStack(spacing: 10) {
                        Image(systemName: icon).font(.system(size: 28, weight: .light)).foregroundStyle(DeltaColors.accent)
                        Text("Nenhum patch nesta categoria ainda").font(.subheadline.weight(.semibold)).foregroundStyle(DeltaColors.ink)
                    }.frame(maxWidth: .infinity).padding(.vertical, 22)
                }
            } else {
                ForEach(items) { item in
                    let applied = DevicePatchService.latestReceipt(projectID: item.id) != nil
                    DeltaCard {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { expandedItemID = expandedItemID == item.id ? nil : item.id }
                        } label: {
                            HStack(spacing: 10) {
                                if let iconURL = PatchProjectLibrary.remoteIconURL(for: item.id) {
                                    AsyncImage(url: iconURL) { phase in
                                        if let image = phase.image { image.resizable().scaledToFit().padding(7) }
                                        else { Image(systemName: icon).resizable().scaledToFit().padding(15).foregroundStyle(DeltaColors.accent) }
                                    }.frame(width: 58, height: 58).background(DeltaColors.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous)).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                } else {
                                    Image(systemName: icon).font(.title3).foregroundStyle(DeltaColors.accent).frame(width: 42, height: 42).background(DeltaColors.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(PatchProjectLibrary.displayName(for: item)).font(.subheadline.weight(.bold)).foregroundStyle(DeltaColors.ink).lineLimit(1)
                                    Text(applied ? "Aplicado — toque para restaurar" : item.isLocked ? "Protegido — toque para desbloquear" : "Toque para configurar").font(.caption2).foregroundStyle(DeltaColors.muted)
                                }
                                Spacer()
                                Image(systemName: expandedItemID == item.id ? "chevron.up.circle.fill" : "chevron.down.circle").foregroundStyle(DeltaColors.accent)
                            }
                        }.buttonStyle(.plain)
                        if expandedItemID == item.id {
                            Divider().overlay(DeltaColors.accent.opacity(0.12))
                            if item.isLocked {
                                Button { patchStore.requestUnlock(for: item) } label: {
                                    Label("DESBLOQUEAR PATCH", systemImage: "lock.open.fill")
                                        .font(.system(size: 11, weight: .black))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity, minHeight: 40)
                                        .background(DeltaColors.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .disabled(patchStore.isBusy)
                            } else {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(applied ? "Aplicado" : "Não aplicado")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(DeltaColors.ink)
                                        Text(applied ? "Desative para restaurar o original" : "Ative para aplicar o patch")
                                            .font(.caption2)
                                            .foregroundStyle(DeltaColors.muted)
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { applied },
                                        set: { on in
                                            if on { patchStore.applyInline(item) }
                                            else { patchStore.restoreInline(item) }
                                        }
                                    ))
                                    .labelsHidden()
                                    .toggleStyle(DeltaToggleStyle())
                                    .disabled(patchStore.isBusy)
                                    Button {
                                        patchStore.restoreInline(item)
                                    } label: {
                                        Label("Restaurar", systemImage: "arrow.counterclockwise")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(DeltaColors.accent)
                                            .padding(.horizontal, 10)
                                            .frame(height: 36)
                                            .background(DeltaColors.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(DeltaColors.accent.opacity(0.24), lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!applied || patchStore.isBusy)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct DeltaAimbotTab: View {
    @State private var launchAntiBan = false
    @State private var aimbot = true
    @State private var vector = false
    @State private var silent = false
    @State private var bone = 0
    @State private var drawFOV = false
    @State private var fov = 120.0
    @State private var distance = 150.0
    @State private var ignoreKnocked = false

    var body: some View {
        VStack(spacing: 12) {
            DeltaCard {
                DeltaSectionTitle("ANTI-BAN", icon: "shield.fill")
                DeltaToggleRow("Launch Anti-Ban", isOn: $launchAntiBan)
            }
            DeltaCard {
                DeltaSectionTitle("AIMBOT TYPE", icon: "scope")
                DeltaToggleRow("Aimbot", isOn: $aimbot)
                DeltaToggleRow("Aimbot Vector", isOn: $vector)
                DeltaToggleRow("Aim Silent", isOn: $silent)
                DeltaSegmented(title: "Bone:", items: ["Head", "Neck", "Body"], selection: $bone)
            }
            DeltaCard {
                DeltaSectionTitle("AIMBOT SETTINGS", icon: "slider.horizontal.3")
                DeltaToggleRow("Draw Field Of View", isOn: $drawFOV)
                DeltaSliderRow("Field Of View", value: $fov, range: 0...120, suffix: "Â°")
                DeltaSliderRow("Aimbot Distance", value: $distance, range: 0...150, suffix: "m")
                DeltaToggleRow("Ignore Knocked", isOn: $ignoreKnocked)
            }
        }
    }
}

private struct DeltaVisualTab: View {
    @Binding var showErrorBanner: Bool
    @State private var master = false
    @State private var line = false
    @State private var box = false
    @State private var name = false
    @State private var distance = false
    @State private var health = false
    @State private var skeleton = false
    @State private var count = false
    @State private var boxType = 0
    @State private var healthType = 0
    @State private var textSize = 1.0
    @State private var thickness = 1.0
    @State private var visualDistance = 150.0

    var body: some View {
        VStack(spacing: 12) {
            DeltaCard {
                DeltaSectionTitle("ESP MAIN", icon: "eye.fill")
                DeltaToggleRow("ESP Master", isOn: $master)
                DeltaToggleRow("ESP Line", isOn: $line, enabled: master) { if !master { showErrorBanner = true } }
                DeltaToggleRow("ESP Box", isOn: $box, enabled: master) { if !master { showErrorBanner = true } }
                DeltaSegmented(title: "Box Type:", items: ["Cornered", "2D Bounding"], selection: $boxType)
                DeltaToggleRow("ESP Name", isOn: $name, enabled: master) { if !master { showErrorBanner = true } }
                DeltaToggleRow("ESP Distance", isOn: $distance, enabled: master) { if !master { showErrorBanner = true } }
                DeltaToggleRow("ESP Health", isOn: $health, enabled: master) { if !master { showErrorBanner = true } }
                DeltaSegmented(title: "Health Type:", items: ["Right", "Left"], selection: $healthType)
                DeltaToggleRow("ESP Skeleton", isOn: $skeleton, enabled: master) { if !master { showErrorBanner = true } }
                DeltaToggleRow("Draw Count Enemies", isOn: $count, enabled: master) { if !master { showErrorBanner = true } }
            }
            DeltaCard {
                DeltaSectionTitle("VISUAL SLIDERS", icon: "slider.horizontal.3")
                DeltaSliderRow("Text Size", value: $textSize, range: 0.5...2.0, suffix: "")
                DeltaSliderRow("Thickness Size", value: $thickness, range: 0.5...2.0, suffix: "")
                DeltaSliderRow("Visual Distance", value: $visualDistance, range: 0...150, suffix: "m")
            }
        }
    }
}

private struct DeltaMiscTab: View {
    @State private var noRecoil = false
    @State private var noReload = false
    @State private var speedHacks = false
    @State private var speed = 1.0
    @State private var fastMedkit = false
    @State private var rapidFire = false
    @State private var rapid = 1.0

    var body: some View {
        VStack(spacing: 12) {
            DeltaCard {
                DeltaSectionTitle("MISC FEATURES", icon: "bolt.fill")
                DeltaToggleRow("No Recoil", isOn: $noRecoil)
                DeltaToggleRow("No Reload", isOn: $noReload)
                DeltaToggleRow("Speed Hacks", isOn: $speedHacks)
                DeltaSliderRow("Speed", value: $speed, range: 0.5...2.0, suffix: "x")
                DeltaToggleRow("Fast Medkit", isOn: $fastMedkit)
                DeltaToggleRow("Rapid Fire", isOn: $rapidFire)
                DeltaSliderRow("Rapid", value: $rapid, range: 0.5...2.0, suffix: "x")
            }
        }
    }
}

private struct DeltaReferenceSettingsTab: View {
    @EnvironmentObject private var remoteConfig: RemoteAppConfigStore
    @Binding var languageCode: String
    let isVietnamese: Bool
    let appState: AppState
    let keySession: IOSKeySession
    @AppStorage("externalSystem.streamProofEnabled") private var streamProof = false
    @State private var copied = false
    @State private var stealthRunning = false
    @State private var stealthDone = false
    private var deviceUID: String {
        UIDevice.current.identifierForVendor?.uuidString.uppercased() ?? "UNAVAILABLE"
    }

    var body: some View {
        VStack(spacing: 12) {
            DeltaCard {
                DeltaSectionTitle(isVietnamese ? "QUYá»N RIÃNG TÆ¯" : "PRIVACY", icon: "video.slash.fill")
                DeltaToggleRow(isVietnamese ? "Chá»ng stream" : "Stream Proof", isOn: $streamProof)
            }
            DeltaCard {
                DeltaSectionTitle("MODO FANTASMA", icon: "eye.slash.fill")
                Text("Oculta o app e limpa os rastros locais do dispositivo.")
                    .font(.caption)
                    .foregroundStyle(DeltaColors.muted)
                Button {
                    guard !stealthRunning else { return }
                    stealthRunning = true
                    stealthDone = false
                    DispatchQueue.global(qos: .userInitiated).async {
                        ST_fullStealthPass()
                        DispatchQueue.main.async {
                            stealthRunning = false
                            stealthDone = true
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if stealthRunning {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: stealthDone ? "checkmark.shield.fill" : "eye.slash")
                        }
                        Text(stealthRunning ? "Aplicando..." : (stealthDone ? "Fantasma Ativo" : "Ativar Modo Fantasma"))
                        Spacer()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background((stealthDone ? Color.green : DeltaColors.accent).opacity(0.24), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(stealthRunning)
            }
            DeltaCard {
                DeltaSectionTitle(isVietnamese ? "THÃNG TIN Báº¢N QUYá»N" : "LICENSE INFORMATION", icon: "key.fill")
                DeltaInfoRow(isVietnamese ? "Báº£n quyá»n:" : "License:", value: "EXTERNAL X")
                DeltaInfoRow(isVietnamese ? "Háº¡n dÃ¹ng:" : "Expired:", value: "Lifetime")
                HStack {
                    Text("UID:").font(.caption).foregroundStyle(DeltaColors.muted)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = deviceUID
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation { copied = false } }
                    } label: {
                        Text(copied ? "â" : (isVietnamese ? "Sao chÃ©p" : "Copy"))
                            .font(.caption.weight(.bold)).foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 5).background(DeltaColors.accent, in: Capsule())
                    }.buttonStyle(.plain)
                }
                Text(deviceUID).font(.system(size: 8, design: .monospaced)).foregroundStyle(DeltaColors.ink).lineLimit(1).minimumScaleFactor(0.6)
            }
            DeltaCard {
                DeltaSectionTitle(isVietnamese ? "TÆ¯Æ NG THÃCH Há» ÄIá»U HÃNH" : "SYSTEM COMPATIBILITY", icon: "apple.logo")
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isVietnamese ? "PhiÃªn báº£n iOS hiá»n táº¡i:" : "Current iOS Version:").font(.caption).foregroundStyle(DeltaColors.ink)
                        Text("iOS \(AppInfo.osVersion) (\(AppInfo.osBuild))").font(.caption2).foregroundStyle(DeltaColors.muted)
                    }
                    Spacer()
                    DeltaStatusBadge(text: appState.isSupported ? (isVietnamese ? "Há» TRá»¢" : "SUPPORTED") : "UNSUPPORTED")
                }
            }
            DeltaCard {
                DeltaSectionTitle(isVietnamese ? "NGÃN NGá»®" : "LANGUAGE", icon: "globe")
                HStack(spacing: 0) {
                    DeltaLanguageButton(title: "English", active: languageCode == AppLanguage.english.rawValue) { languageCode = AppLanguage.english.rawValue }
                    DeltaLanguageButton(title: "Tiáº¿ng Viá»t", active: languageCode == AppLanguage.vietnamese.rawValue) { languageCode = AppLanguage.vietnamese.rawValue }
                }
                .padding(3).background(DeltaColors.line.opacity(0.18), in: Capsule())
            }
            DeltaCard {
                DeltaSectionTitle(isVietnamese ? "SISTEMA" : "SYSTEM", icon: "gearshape.fill")
                Button { keySession.logout() } label: { DeltaActionRow(icon: "rectangle.portrait.and.arrow.right", title: isVietnamese ? "ÄÄng xuáº¥t tÃ i khoáº£n" : "Sign Out", color: .red) }.buttonStyle(.plain)
            }
        }
    }
}

private struct DeltaCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) { content }
            .padding(15)
            .background(DeltaColors.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(DeltaColors.line, lineWidth: 0.9)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.18), radius: 13, y: 5)
    }
}

private struct DeltaSectionTitle: View {
    let title: String
    let icon: String
    init(_ title: String, icon: String) { self.title = title; self.icon = icon }
    var body: some View { Label(title, systemImage: icon).font(.system(size: 9, weight: .black)).tracking(0.7).foregroundStyle(DeltaColors.accent).shadow(color: DeltaColors.accent.opacity(0.85), radius: 7) }
}

private struct DeltaStatusBadge: View {
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.white.opacity(0.72)).frame(width: 5, height: 5)
            Text(text).font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(Color.white.opacity(0.72))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.10), in: Capsule())
        .shadow(color: Color.white.opacity(0.14), radius: 5)
    }
}

private struct DeltaMetric: View {
    let title: String
    let subtitle: String
    let icon: String
    init(_ title: String, subtitle: String, icon: String) { self.title = title; self.subtitle = subtitle; self.icon = icon }
    var body: some View { VStack(alignment: .leading, spacing: 3) { Image(systemName: icon).font(.caption2).foregroundStyle(DeltaColors.accent); Text(title).font(.caption2.weight(.bold)).foregroundStyle(DeltaColors.ink); Text(subtitle).font(.system(size: 8)).foregroundStyle(DeltaColors.muted) }.frame(maxWidth: .infinity, alignment: .leading).padding(8).background(DeltaColors.card, in: RoundedRectangle(cornerRadius: 7)).shadow(color: DeltaColors.accent.opacity(0.28), radius: 10) }
}

private struct DeltaToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            RoundedRectangle(cornerRadius: 12)
                .fill(configuration.isOn ? DeltaColors.accent : Color.gray.opacity(0.45))
                .frame(width: 37, height: 23)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(.white).frame(width: 18, height: 18).padding(2)
                }
                .animation(.spring(response: 0.24, dampingFraction: 0.8), value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("Ativar patch")
        .accessibilityValue(configuration.isOn ? "Ativo" : "Desativado")
    }
}

private struct DeltaToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var enabled = true
    var onDisabledTap: (() -> Void)? = nil
    init(_ title: String, isOn: Binding<Bool>, enabled: Bool = true, onDisabledTap: (() -> Void)? = nil) { self.title = title; self._isOn = isOn; self.enabled = enabled; self.onDisabledTap = onDisabledTap }
    var body: some View { HStack { Text(title).font(.caption).foregroundStyle(enabled ? DeltaColors.ink : DeltaColors.muted); Spacer(); Toggle("", isOn: $isOn).labelsHidden().toggleStyle(DeltaToggleStyle()).opacity(enabled ? 1 : 0.70) }.contentShape(Rectangle()).onTapGesture { if !enabled { onDisabledTap?() } } }
}

private struct DeltaSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let suffix: String
    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) {
        self.title = title
        self._value = value
        self.range = range
        self.suffix = suffix
    }
    var body: some View { VStack(spacing: 2) { HStack { Text(title).font(.caption).foregroundStyle(DeltaColors.ink); Spacer(); Text(String(format: suffix == "m" ? "%.0f%@" : suffix == "Â°" ? "%.0f%@" : "%.1f%@", value, suffix)).font(.caption2.weight(.bold)).foregroundStyle(DeltaColors.accent) }; Slider(value: $value, in: range).tint(DeltaColors.accent) } }
}

private struct DeltaSegmented: View {
    let title: String
    let items: [String]
    @Binding var selection: Int
    var body: some View { HStack(spacing: 8) { Text(title).font(.caption2).foregroundStyle(DeltaColors.muted); HStack(spacing: 0) { ForEach(items.indices, id: \.self) { index in Button(items[index]) { withAnimation(.easeInOut(duration: 0.18)) { selection = index } }.font(.system(size: 9, weight: .medium)).foregroundStyle(selection == index ? DeltaColors.ink : DeltaColors.muted).frame(maxWidth: .infinity, minHeight: 24).background(selection == index ? DeltaColors.card : .clear, in: Capsule()) } }.padding(2).background(DeltaColors.line.opacity(0.18), in: Capsule()) } }
}

private struct DeltaInfoRow: View {
    let label: String
    let value: String
    init(_ label: String, value: String) { self.label = label; self.value = value }
    var body: some View { HStack { Text(label).font(.caption).foregroundStyle(DeltaColors.muted).shadow(color: DeltaColors.accent.opacity(0.35), radius: 4); Spacer(); Text(value).font(.caption.weight(.bold)).foregroundStyle(DeltaColors.ink).shadow(color: DeltaColors.accent.opacity(0.35), radius: 4) } }
}

private struct DeltaLanguageButton: View {
    let title: String
    let active: Bool
    let action: () -> Void
    var body: some View { Button(action: action) { Text(title).font(.caption2.weight(active ? .bold : .medium)).foregroundStyle(active ? DeltaColors.ink : DeltaColors.muted).frame(maxWidth: .infinity, minHeight: 25).background(active ? DeltaColors.card : .clear, in: Capsule()) }.buttonStyle(.plain) }
}

private struct DeltaActionRow: View {
    let icon: String
    let title: String
    let color: Color
    var body: some View { HStack(spacing: 8) { Image(systemName: icon).foregroundStyle(color).frame(width: 20).shadow(color: color.opacity(0.90), radius: 8); Text(title).font(.caption.weight(.semibold)).foregroundStyle(color).shadow(color: color.opacity(0.65), radius: 6); Spacer(); Image(systemName: "arrow.up.right").font(.caption2.bold()).foregroundStyle(color).shadow(color: color.opacity(0.80), radius: 7) }.padding(.vertical, 7) }
}

private struct DeltaErrorBanner: View {
    let dismiss: () -> Void
    var body: some View { HStack { Text("ESP OFF (báº­t ESP Master)").font(.caption.weight(.bold)).foregroundStyle(.white); Spacer(); Button(action: dismiss) { Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.8)) } }.padding(.horizontal, 14).padding(.vertical, 11).background(Color(red: 0.04, green: 0.04, blue: 0.06)).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous)).shadow(color: .black.opacity(0.18), radius: 10, y: 5).padding(.horizontal, 8) }
}
