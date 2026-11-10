import SwiftUI
import UIKit
import Security
import CryptoKit
import MachO
import Darwin

@main
struct ThreeOneOSFiveApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var patchDraftCoordinator = PatchDraftCoordinator()
    @StateObject private var fileOperationCoordinator = FileOperationCoordinator()
    @StateObject private var patchStore = PatchProjectStore(autoLoad: false)
    @StateObject private var repositoryStore = PackageRepositoryStore()
    @StateObject private var keySession = IOSKeySession()
    @State private var hasEnteredApp = false
    @State private var authenticatedServicesActivated = false
    @State private var showAttribution = false
    @State private var updateOffer: AppUpdateChecker.Offer?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UserDefaults.standard.set(AppLanguage.portugueseBrazil.rawValue, forKey: AppLanguage.storageKey)
        AD_applyEarlyProtections()
        PatchWorkspaceService.removeLegacyDocumentsPatchStorage()
        setupLogCapture()
        log("app: 3105 launching — iOS \(AppInfo.osVersion) (\(AppInfo.osBuild)) \(AppInfo.machineName)")
    }

    private var language: AppLanguage { .portugueseBrazil }

    private func checkForUpdate() {
        Task {
            guard let offer = await AppUpdateChecker.check() else { return }
            await MainActor.run { updateOffer = offer }
        }
    }

    private func activateAuthenticatedServices() {
        guard !authenticatedServicesActivated else { return }
        authenticatedServicesActivated = true
        PatchProjectLibrary.removeObsoleteProtectedStorage()
        patchStore.activate()
        patchStore.startRemoteSync()
        appState.detectSupport()
        checkForUpdate()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if hasEnteredApp {
                    if keySession.isAuthenticated {
                        ContentView()
                            .environmentObject(appState)
                            .environmentObject(keySession)
                            .environmentObject(patchDraftCoordinator)
                            .environmentObject(fileOperationCoordinator)
                            .environmentObject(patchStore)
                            .environmentObject(repositoryStore)
                            .environment(\.appLanguage, language)
                            .environment(\.locale, language.locale)
                    } else {
                        IOSKeyLoginView(session: keySession)
                            .environment(\.appLanguage, language)
                            .environment(\.locale, language.locale)
                    }
                } else {
                    CalculadoraIPhoneView {
                        withAnimation(.easeInOut(duration: 0.22)) { hasEnteredApp = true }
                    }
                }
            }
            .displayIdentityAttribution(isPresented: $showAttribution, enabled: hasEnteredApp && keySession.isAuthenticated)
            .sheet(isPresented: $showAttribution) { DisplayAttributionSheet() }
            .alert(item: $updateOffer) { offer in
                Alert(
                    title: Text(language.text("update.title")),
                    message: Text(language.text("update.message", offer.version)),
                    primaryButton: .default(Text(language.text("update.agree"))) { UIApplication.shared.open(offer.url) },
                    secondaryButton: .cancel(Text(language.text("update.dismiss"))) { AppUpdateChecker.dismiss(token: offer.token) }
                )
            }
            .onAppear {
                if hasEnteredApp && keySession.isAuthenticated { activateAuthenticatedServices() }
            }
            .onChange(of: keySession.isAuthenticated) { authenticated in
                if authenticated && hasEnteredApp {
                    activateAuthenticatedServices()
                } else {
                    authenticatedServicesActivated = false
                    patchStore.deactivateAndClear()
                }
            }
            .onChange(of: hasEnteredApp) { entered in
                if entered && keySession.isAuthenticated { activateAuthenticatedServices() }
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active, hasEnteredApp, keySession.isAuthenticated else { return }
                keySession.validateIntegrityOnForeground()
                patchStore.reload()
                Task { await keySession.refresh() }
                checkForUpdate()
                appState.detectSupport()
            }
            .task(id: "\(hasEnteredApp)-\(keySession.isAuthenticated)") {
                guard hasEnteredApp, keySession.isAuthenticated else { return }
                while !Task.isCancelled {
                    checkForUpdate()
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                }
            }
            .onOpenURL { url in
                guard hasEnteredApp, keySession.isAuthenticated else { return }
                patchDraftCoordinator.presentImport(url)
            }
            .tint(AppTheme.accent)
            .preferredColorScheme(.dark)
        }
    }
}
