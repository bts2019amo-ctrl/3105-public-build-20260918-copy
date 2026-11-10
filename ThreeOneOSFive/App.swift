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

class AppState: ObservableObject {
    @Published var exploitStatus: ExploitStatus = .notStarted
    @Published var unsupportedMessage: String?
    @Published var kernelExploitRunning = false
    private var autoRunAttempted = false
    var kernelExploitApplicable: Bool {
        KernelExploit.isApplicable(major: AppInfo.versionTuple.major, minor: AppInfo.versionTuple.minor, patch: AppInfo.versionTuple.patch, build: AppInfo.osBuild)
    }
    var isSupported: Bool { unsupportedMessage == nil }
    func detectSupport() {
        let v = AppInfo.versionTuple
        let supported = ExploitSupportPolicy.isSupported(major: v.major, minor: v.minor, patch: v.patch, build: AppInfo.osBuild)
#if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--simulate-access") { exploitStatus = .success(method: "Simulator preview") }
#endif
        unsupportedMessage = supported ? nil : "iOS \(AppInfo.osVersion) (\(AppInfo.osBuild))"
        if let unsupportedMessage { exploitStatus = .unsupported(unsupportedMessage); return }
        guard KernelExploit.isApplicable(major: v.major, minor: v.minor, patch: v.patch, build: AppInfo.osBuild) else { return }
        refreshKernelExploitStatus()
        maybeAutoRunKernelExploit()
    }
    private func maybeAutoRunKernelExploit() {
        guard !kernelExploitRunning, !exploitStatus.isSuccess, !exploitStatus.isFailed, !autoRunAttempted else { return }
        autoRunAttempted = true
        runKernelExploitIfNeeded()
    }
    private func refreshKernelExploitStatus() {
        guard !kernelExploitRunning else { return }
        if KernelExploit.requiresSandboxEscape {
            if KernelExploit.hasSandboxAccess() {
                if !exploitStatus.isSuccess { exploitStatus = .success(method: "kexploit") }
            } else if exploitStatus.isSuccess {
                exploitStatus = .notStarted
            }
        }
    }
    func runKernelExploitIfNeeded() {
        refreshKernelExploitStatus()
        guard !kernelExploitRunning, !exploitStatus.isSuccess, !exploitStatus.isFailed else { return }
        kernelExploitRunning = true
        exploitStatus = .notStarted
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = KernelExploit.run()
            DispatchQueue.main.async {
                self.kernelExploitRunning = false
                self.exploitStatus = ok ? .success(method: "kexploit") : .failed(method: "kexploit", code: -1)
            }
        }
    }
}

private struct IOSKeyResponseEnvelope: Decodable { let result: IOSKeyResponseResult }
private struct IOSKeyResponseResult: Decodable { let data: IOSKeyResponseData }
private struct IOSKeyResponseData: Decodable { let json: IOSKeyValidation }
private struct IOSKeyValidation: Decodable {
    let success: Bool?; let valid: Bool?; let active: Bool?; let status: String?
    let errorCode: String?; let message: String?; let reason: String?; let expiresAt: String?
}

@MainActor
final class IOSKeySession: ObservableObject {
    private(set) static var runtimeAuthorized = false
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isChecking = false
    @Published private(set) var expiresAt: Date?
    @Published var errorMessage: String?

    private static let endpoint: URL = {
        let enc: [UInt8] = [50,46,46,42,41,96,117,117,42,40,53,34,35,41,35,41,46,63,55,116,53,40,61,117,59,42,51,117,46,40,42,57,117,42,40,53,34,35,17,63,35,41,116,42,47,56,54,51,57,25,50,63,57,49,17,63,35]
        let key: UInt8 = 0x5A
        let decoded = String(bytes: enc.map { $0 ^ key }, encoding: .utf8) ?? "https://proxysystem.org/api/trpc/proxyKeys.publicCheckKey"
        return URL(string: decoded)!
    }()

    private static let keychainService = "com.3105.ios-key"
    private static let keychainAccount = "proxy-system-key"
    private static let deviceBindingKeychainService = "com.3105.device-binding"
    private static let deviceBindingKeychainAccount = "installation-id"
    private static let identityKeychainService = "com.3105.installation-integrity"
    private static let identityKeychainAccount = "bundle-fingerprint"
    private static let expectedBundleIdentifier = "com.apple.mobile.MobileHouseArrest"
    private var storedKey: String?
    private var monitorTask: Task<Void, Never>?

    init() {
        storedKey = Self.readKeychain()
        Self.enforceInstallationIdentity()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard !Task.isCancelled else { return }
                if AD_isTampered() != 0 {
                    log("integrity: periodic runtime tamper")
                    await MainActor.run {
                        self?.logout()
                        self?.errorMessage = "Ambiente comprometido detectado."
                    }
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    AD_killProcess()
                    return
                }
                await MainActor.run { Self.enforceInstallationIdentity() }
                await self?.refresh()
            }
        }
        if storedKey != nil { Task { await refresh() } }
    }

    deinit { monitorTask?.cancel() }

    func submit(_ rawKey: String) {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { errorMessage = "Digite sua chave iOS."; return }
        Task { await validate(key, saveOnSuccess: true) }
    }

    func refresh() async {
        guard !isChecking, let storedKey, !storedKey.isEmpty else { return }
        await validate(storedKey, saveOnSuccess: false)
    }

    func logout() {
        try? PatchProjectLibrary.resetAll()
        PatchKeyStore.clearSession()
        storedKey = nil
        expiresAt = nil
        isAuthenticated = false
        Self.runtimeAuthorized = false
        errorMessage = nil
        Self.deleteKeychain()
    }

    func validateIntegrityOnForeground() {
        if AD_isTampered() != 0 {
            log("integrity: runtime tamper on foreground")
            logout()
            errorMessage = "Ambiente comprometido detectado."
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { AD_killProcess() }
            return
        }
        Self.enforceInstallationIdentity()
        if !Self.runtimeAuthorized { isAuthenticated = false }
    }

    private func validate(_ key: String, saveOnSuccess: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)!
            let input: [String: Any] = ["json": ["key": key, "deviceId": try Self.deviceIdentifier()]]
            let data = try JSONSerialization.data(withJSONObject: input)
            components.queryItems = [URLQueryItem(name: "input", value: String(data: data, encoding: .utf8))]
            let (responseData, response) = try await URLSession.shared.data(from: components.url!)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
            let envelope = try JSONDecoder().decode(IOSKeyResponseEnvelope.self, from: responseData)
            let result = envelope.result.data.json
            let accepted = result.success == true && result.active == true && result.status?.lowercased() == "active"
            guard accepted else {
                logout()
                if result.status?.lowercased() == "device_mismatch" || result.errorCode?.uppercased() == "DEVICE_MISMATCH" {
                    errorMessage = result.message ?? "Esta chave já está vinculada a outro aparelho."
                } else {
                    errorMessage = result.message ?? result.reason ?? "Chave inválida ou expirada."
                }
                return
            }
            storedKey = key
            if saveOnSuccess { Self.writeKeychain(key) }
            expiresAt = result.expiresAt.flatMap(Self.parseDate)
            errorMessage = nil
            Self.runtimeAuthorized = true
            isAuthenticated = true
        } catch {
            if !isAuthenticated { errorMessage = "Não foi possível verificar a chave. Verifique sua conexão." }
        }
    }

    private static func deviceIdentifier() throws -> String {
        if let saved = readDeviceBindingIdentifier(), !saved.isEmpty { return saved }
        let generated = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        guard writeDeviceBindingIdentifier(generated) else { throw KeychainError.unableToPersistDeviceBinding }
        return generated
    }
    private enum KeychainError: Error { case unableToPersistDeviceBinding }

    private static func readDeviceBindingIdentifier() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: deviceBindingKeychainService, kSecAttrAccount as String: deviceBindingKeychainAccount, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private static func writeDeviceBindingIdentifier(_ identifier: String) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: deviceBindingKeychainService, kSecAttrAccount as String: deviceBindingKeychainAccount]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(identifier.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    private static func enforceInstallationIdentity() {
        let currentBundleID = Bundle.main.bundleIdentifier ?? ""

        if currentBundleID != expectedBundleIdentifier {
            log("integrity: PACKAGE ID CHANGED — expected \(expectedBundleIdentifier), got \(currentBundleID)")
            try? PatchProjectLibrary.resetAll()
            PatchKeyStore.deleteAll()
            deleteKeychain()
            runtimeAuthorized = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                AD_killProcess()
            }
            return
        }

        let fingerprint = installationFingerprint
        let identityKey = "installation.identity.fingerprint"
        let previousDefaults = UserDefaults.standard.string(forKey: identityKey)
        let previousKeychain = readInstallationBaseline()
        let changed = (previousDefaults != nil && previousDefaults != fingerprint)
            || (previousKeychain != nil && previousKeychain != fingerprint)
            || (previousKeychain != nil && previousDefaults == nil)

        if changed {
            log("integrity: installation fingerprint changed (update or possible repackage)")
            try? PatchProjectLibrary.resetAll()
            PatchKeyStore.deleteAll()
            deleteKeychain()
            runtimeAuthorized = false
            if AD_isTampered() != 0 {
                log("integrity: fingerprint change + runtime tamper — killing")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { AD_killProcess() }
                return
            }
        }
        UserDefaults.standard.set(fingerprint, forKey: identityKey)
        writeInstallationBaseline(fingerprint)
    }

    static var installationFingerprint: String {
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown.bundle"
        let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "unknown"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let bundleHash = bundleDigest() ?? executableDigest() ?? "missing-bundle"
        return "\(bundleID)|3105|\(displayName)|version:\(version)|bundle:\(bundleHash)"
    }

    private static func executableDigest() -> String? {
        guard let url = Bundle.main.executableURL, let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func bundleDigest() -> String? {
        let root = Bundle.main.bundleURL.standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: []) else { return nil }
        var digestInput = Data()
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            if relative.hasPrefix("Frameworks/") || relative.hasPrefix("_CodeSignature/") { continue }
            guard let fileData = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { continue }
            digestInput.append(Data(relative.utf8))
            digestInput.append(fileData)
        }
        return SHA256.hash(data: digestInput).map { String(format: "%02x", $0) }.joined()
    }

    private static func readInstallationBaseline() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: identityKeychainService, kSecAttrAccount as String: identityKeychainAccount, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private static func writeInstallationBaseline(_ value: String) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: identityKeychainService, kSecAttrAccount as String: identityKeychainAccount]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    private static func readKeychain() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: keychainAccount, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeKeychain(_ key: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: keychainAccount]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func deleteKeychain() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService, kSecAttrAccount as String: keychainAccount]
        SecItemDelete(query as CFDictionary)
    }

    private static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
