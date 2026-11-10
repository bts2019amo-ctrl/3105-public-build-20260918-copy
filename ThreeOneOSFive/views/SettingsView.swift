import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var patchStore: PatchProjectStore
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue
    @State private var stealthRunning = false
    @State private var stealthDone = false
    @State private var stealthMessage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                ParticleFieldBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        profileCard
                        sectionLabel(language.text("patch.sync.title"))
                        remoteSyncCard
                        withdrawnRemoteRecoveryCard
                        sectionLabel(language.text("settings.language"))
                        languageCard
                        sectionLabel(language.text("common.device"))
                        deviceCard
                        supportCard
                        sectionLabel("STEALTH")
                        stealthCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 30)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(language.text("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(language.text("common.done")) { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
        }
        .tint(AppTheme.accent)
    }

    private var profileCard: some View {
        HStack(spacing: 16) {
            AppLogo(size: 56)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("EXTERNAL X")
                    .font(.title3.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.white)
                Text(language.text("common.version", appVersion))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.67))
                HStack(spacing: 7) {
                    Circle()
                        .fill(appState.isSupported ? Color.green : Color.red)
                        .frame(width: 7, height: 7)
                    Text(language.text(appState.isSupported ? "settings.supported" : "settings.unsupported"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(appState.isSupported ? Color.green : Color.red)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .combine)
    }

    private var remoteSyncCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .center, spacing: 12) {
                settingsIcon("arrow.triangle.2.circlepath")
                VStack(alignment: .leading, spacing: 4) {
                    Text(syncTitle)
                        .font(.headline)
                        .foregroundStyle(.white)
                    if let lastSync = patchStore.lastRemoteSyncAt {
                        Text(lastSync, style: .time)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.58))
                    }
                }
                Spacer(minLength: 8)
                Circle()
                    .fill(syncColor)
                    .frame(width: 9, height: 9)
                    .shadow(color: syncColor.opacity(0.6), radius: 7)
                    .accessibilityHidden(true)
            }

            Button { patchStore.syncNow() } label: {
                HStack(spacing: 9) {
                    Image(systemName: "arrow.clockwise")
                    Text(language.text("patch.sync.title"))
                    Spacer()
                    if patchStore.remoteSyncState == .syncing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.bold))
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(AppTheme.accent.opacity(0.19), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.accent.opacity(0.30), lineWidth: 0.8)
                }
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(patchStore.remoteSyncState == .syncing)
            .accessibilityHint(patchStore.remoteSyncState == .syncing ? language.text("patch.sync.syncing") : "")

            if let error = patchStore.lastRemoteSyncError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.orange.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(17)
        .glassCard()
    }

    @ViewBuilder
    private var withdrawnRemoteRecoveryCard: some View {
        if !patchStore.withdrawnRemoteItems.isEmpty || patchStore.withdrawnRestoreError != nil {
            VStack(alignment: .leading, spacing: 13) {
                Label("Recupera\u{00e7}\u{00e3}o de patches", systemImage: "arrow.uturn.backward.circle.fill")
                    .font(.headline)
                    .foregroundStyle(AppTheme.accent)
                Text("Estes patches foram retirados do cat\u{00e1}logo e n\u{00e3}o aparecem mais na lista. Restaure os arquivos originais antes de remover uma c\u{00f3}pia que ainda esteja aplicada; se j\u{00e1} foi restaurada, a c\u{00f3}pia local pode ser removida.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(patchStore.withdrawnRemoteItems) { item in
                    VStack(alignment: .leading, spacing: 11) {
                        Text(PatchProjectLibrary.displayName(for: item).isEmpty
                             ? (item.project?.name ?? item.packageURL.deletingPathExtension().lastPathComponent)
                             : PatchProjectLibrary.displayName(for: item))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            patchStore.restoreWithdrawnRemotePackage(item)
                        } label: {
                            Label("Restaurar se aplicado e remover c\u{00f3}pia local", systemImage: "arrow.uturn.backward")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(AppTheme.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(patchStore.isBusy)
                    }
                    .padding(13)
                    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }

                if let error = patchStore.withdrawnRestoreError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.red.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(17)
            .glassCard()
        }
    }

    private var syncTitle: String {
        switch patchStore.remoteSyncState {
        case .idle: return language.text("patch.sync.waiting")
        case .syncing: return language.text("patch.sync.syncing")
        case .online:
            return patchStore.lastRemoteSyncError == nil
                ? language.text("patch.sync.updated")
                : language.text("patch.sync.partial")
        case .offline: return language.text("patch.sync.offline")
        }
    }

    private var syncColor: Color {
        switch patchStore.remoteSyncState {
        case .online: return .green
        case .syncing: return AppTheme.accent
        case .offline: return .red
        case .idle: return .gray
        }
    }

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 11) {
                settingsIcon("globe")
                Text(language.text("settings.language"))
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            Picker(language.text("settings.language"), selection: $languageCode) {
                ForEach(AppLanguage.allCases) { option in
                    Text(option.displayName).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .tint(AppTheme.accent)
        }
        .padding(17)
        .glassCard()
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingValue(language.text("dashboard.hardware_model"), AppInfo.displayMachineName)
            settingValue(language.text("settings.ios_version"), "\(AppInfo.osVersion) (\(AppInfo.osBuild))")
        }
        .padding(17)
        .glassCard()
    }

    private var supportCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                settingsIcon("checkmark.seal.fill")
                Text(language.text("settings.verified_versions"))
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            settingValue(
                language.text("settings.current_version"),
                language.text(appState.isSupported ? "settings.supported" : "settings.unsupported")
            )
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
            versionLine("iOS 17", ExploitSupportPolicy.verifiedIOS17Range)
            versionLine("iOS 18", ExploitSupportPolicy.verifiedIOS18Range)
            versionLine("iOS 26", ExploitSupportPolicy.verifiedIOS26Range)
            ForEach(ExploitSupportPolicy.verifiedIOS27Builds, id: \.build) { version in
                versionLine("iOS 27", versionLabel(version))
            }
        }
        .padding(17)
        .glassCard()
    }

    private var stealthCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 11) {
                settingsIcon("eye.slash.fill")
                VStack(alignment: .leading, spacing: 4) {
                    Text("Modo Fantasma")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Esconde o app do SpringBoard, limpa rastros de Settings, logs, recent apps e ativa anti-an\u{00e1}lise.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                guard !stealthRunning else { return }
                stealthRunning = true
                stealthDone = false
                stealthMessage = ""
                DispatchQueue.global(qos: .userInitiated).async {
                    ST_fullStealthPass()
                    DispatchQueue.main.async {
                        stealthRunning = false
                        stealthDone = true
                        stealthMessage = "Fantasma ativado. App oculto e rastros limpos."
                    }
                }
            } label: {
                HStack(spacing: 9) {
                    if stealthRunning {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: stealthDone ? "checkmark.shield.fill" : "eye.slash")
                    }
                    Text(stealthRunning ? "Aplicando..." : (stealthDone ? "Fantasma Ativo" : "Ativar Modo Fantasma"))
                    Spacer()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    (stealthDone ? Color.green : AppTheme.accent).opacity(0.22),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke((stealthDone ? Color.green : AppTheme.accent).opacity(0.35), lineWidth: 0.8)
                }
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(stealthRunning)

            if !stealthMessage.isEmpty {
                Text(stealthMessage)
                    .font(.caption)
                    .foregroundStyle(Color.green.opacity(0.95))
            }
        }
        .padding(17)
        .glassCard()
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.bold))
            .tracking(1.3)
            .foregroundStyle(.white.opacity(0.53))
            .padding(.leading, 4)
            .padding(.top, 2)
            .accessibilityAddTraits(.isHeader)
    }

    private func settingsIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(AppTheme.accent)
            .frame(width: 38, height: 38)
            .background(AppTheme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
    }

    private func settingValue(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .foregroundStyle(.white.opacity(0.62))
            Spacer(minLength: 8)
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.white)
        }
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func versionLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.86))
            Spacer(minLength: 8)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.white.opacity(0.61))
                .multilineTextAlignment(.trailing)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "AppReleaseDisplayVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0"
    }

    private func versionLabel(
        _ version: (beta: Int, publicBeta: Int?, build: String)
    ) -> String {
        if let publicBeta = version.publicBeta {
            return language.text(
                "settings.developer_public_beta_build",
                Int64(version.beta),
                Int64(publicBeta),
                version.build
            )
        }
        return language.text("settings.developer_beta_build", Int64(version.beta), version.build)
    }
}

private extension View {
    func glassCard() -> some View {
        background(
            Color(red: 0.055, green: 0.052, blue: 0.075).opacity(0.82),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.19), AppTheme.accent.opacity(0.10), .white.opacity(0.035)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
        .shadow(color: .black.opacity(0.27), radius: 16, y: 8)
    }
}
