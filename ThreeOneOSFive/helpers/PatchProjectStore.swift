import CryptoKit
import Foundation
import UIKit

enum RemotePatchConfiguration {
    // Kept for the separate app-config and app-update services.
    static let baseURL = URL(string: "https://patch3105-ebnmw8rq.manus.space")!
    static let mobileCatalogURL = URL(string: "https://painel.proxysystem.org/api/mobile/catalog")!
    static let allowedRemoteFeatures: Set<String> = ["cache", "avatar", "hologram", "skin"]
    static let pollIntervalNanoseconds: UInt64 = 2_000_000_000

    static func stableRemoteID(_ value: String) -> Int {
        let digest = SHA256.hash(data: Data(value.utf8))
        let magnitude = digest.prefix(7).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        return -Int(magnitude) - 1
    }
}

private struct MobileCatalogResponse: Decodable {
    let catalogVersion: Int64
    let patches: [MobileCatalogPatch]
}

private struct MobileCatalogPatch: Decodable {
    let id: String
    let name: String
    let description: String?
    let maintenance: Bool?
    let packageURL: String
    let packageFilename: String
    let packageSize: Int
    let iconURL: String?
    let catalogVersion: Int64?
    let updatedAt: String
    let checksumSha256: String?
    let category: String?
    let feature: String?
    let password: String?

    func asRemotePatch(defaultVersion: Int64) throws -> RemoteFeedPatch {
        guard let catalogID = UUID(uuidString: id), !name.isEmpty, !packageURL.isEmpty,
              !packageFilename.isEmpty, packageSize > 0,
              let timestamp = Self.milliseconds(from: updatedAt) else {
            throw NSError(
                domain: "RemotePatchFeed",
                code: 422,
                userInfo: [NSLocalizedDescriptionKey: "O catálogo contém um patch com campos obrigatórios inválidos."]
            )
        }
        let normalizedFeature = feature?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let resolvedFeature = normalizedFeature.flatMap { $0.isEmpty ? nil : $0 }
            ?? Self.inferredFeature(name: name, fileName: packageFilename)
        return RemoteFeedPatch(
            id: RemotePatchConfiguration.stableRemoteID(catalogID.uuidString),
            name: name,
            category: category ?? "",
            feature: resolvedFeature,
            fileName: packageFilename,
            fileUrl: packageURL,
            fileSize: packageSize,
            version: Int(catalogVersion ?? defaultVersion),
            changelog: description,
            checksumSha256: checksumSha256,
            iconUrl: iconURL,
            password: password,
            updatedAt: timestamp,
            isUnderMaintenance: maintenance ?? false
        )
    }

    private static func milliseconds(from value: String) -> Int64? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: value)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: value)
        }
        guard let date else { return nil }
        return Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }

    private static func inferredFeature(name: String, fileName: String) -> String {
        let value = "\(name) \(fileName)"
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if value.contains("skin") { return "skin" }
        if value.contains("avatar") { return "avatar" }
        if value.contains("holo") { return "hologram" }
        return "cache"
    }
}

private struct RemoteFeed {
    let version: Int64
    let patches: [RemoteFeedPatch]

    init(catalog: MobileCatalogResponse) throws {
        version = catalog.catalogVersion
        patches = try catalog.patches.map { try $0.asRemotePatch(defaultVersion: catalog.catalogVersion) }
        guard Set(patches.map(\.id)).count == patches.count else {
            throw NSError(
                domain: "RemotePatchFeed",
                code: 422,
                userInfo: [NSLocalizedDescriptionKey: "O catálogo contém IDs de patch duplicados."]
            )
        }
    }
}

private struct RemoteFeedPatch {
    let id: Int
    let name: String
    let category: String
    let feature: String
    let fileName: String
    let fileUrl: String
    let fileSize: Int
    let version: Int
    let changelog: String?
    let checksumSha256: String?
    let iconUrl: String?
    let password: String?
    let updatedAt: Int64
    let isUnderMaintenance: Bool
}

enum RemoteSyncState: Equatable {
    case idle
    case syncing
    case online
    case offline
}

struct PatchStoreAlert: Identifiable {
    let id = UUID()
    let titleKey: String
    let messageKey: String
    var messageArgument: String?

    init(titleKey: String, messageKey: String, messageArgument: String? = nil) {
        self.titleKey = titleKey
        self.messageKey = messageKey
        self.messageArgument = messageArgument
    }

    func message(language: AppLanguage) -> String {
        if let messageArgument {
            return language.text(messageKey, messageArgument)
        }
        return language.text(messageKey)
    }
}

@MainActor
final class PatchProjectStore: ObservableObject {
    @Published private(set) var items: [PatchLibraryItem] = []
    @Published private(set) var withdrawnRemoteItems: [PatchLibraryItem] = []
    @Published private(set) var withdrawnRestoreError: String?
    @Published private(set) var isBusy = false
    @Published private(set) var remoteSyncState: RemoteSyncState = .idle
    @Published private(set) var lastRemoteSyncAt: Date?
    @Published private(set) var lastRemoteSyncError: String?
    @Published var passwordRequest: PatchPasswordRequest?
    @Published var alert: PatchStoreAlert?
    @Published var unlockErrorKey: String?

    private struct PendingUnlock {
        let data: Data
        let summary: PatchPackageSummary
        let existingURL: URL?
        let origin: PatchPackageOrigin?
        let remoteID: Int?
        let remoteVersion: Int64?
        let remoteCategory: PatchGameCategory?
        let remoteFeature: PatchFeatureCategory?
    }

    private var pendingUnlock: PendingUnlock?
    private var remoteSyncTask: Task<Void, Never>?
    private var remoteSyncInFlight = false
    private var isActivated = false

    init(autoLoad: Bool = true) {
        guard autoLoad else { return }
        activate()
    }

    func activate() {
        guard IOSKeySession.runtimeAuthorized, !isActivated else { return }
        isActivated = true
        isBusy = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let loadedItems = PatchProjectLibrary.load()
            let withdrawnItems = PatchProjectLibrary.loadWithdrawnRemoteItems()
            await self?.finishInitialLoad(loadedItems, withdrawnItems: withdrawnItems)
        }
    }

    func deactivateAndClear() {
        isActivated = false
        stopRemoteSync()
        try? PatchProjectLibrary.resetAll()
        items = []
        withdrawnRemoteItems = []
        withdrawnRestoreError = nil
        isBusy = false
        remoteSyncState = .idle
        lastRemoteSyncAt = nil
        lastRemoteSyncError = nil
        passwordRequest = nil
        alert = nil
        unlockErrorKey = nil
    }

    func reload() {
        items = PatchProjectLibrary.load()
        withdrawnRemoteItems = PatchProjectLibrary.loadWithdrawnRemoteItems()
        if withdrawnRemoteItems.isEmpty { withdrawnRestoreError = nil }
    }

    func startRemoteSync() {
        guard IOSKeySession.runtimeAuthorized, isActivated, remoteSyncTask == nil else { return }
        remoteSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.synchronizeRemoteFeed()
                try? await Task.sleep(nanoseconds: RemotePatchConfiguration.pollIntervalNanoseconds)
            }
        }
    }

    func stopRemoteSync() {
        remoteSyncTask?.cancel()
        remoteSyncTask = nil
    }

    func syncNow() {
        guard IOSKeySession.runtimeAuthorized else { return }
        Task { await synchronizeRemoteFeed() }
    }

    private static func inferredGameCategory(name: String, fileName: String) -> PatchGameCategory {
        let value = "\(name) \(fileName)".lowercased()
        return value.contains("max") || value.contains("freefiremax") ? .max : .normal
    }

    private func synchronizeRemoteFeed() async {
        guard IOSKeySession.runtimeAuthorized, isActivated, !remoteSyncInFlight else { return }
        remoteSyncInFlight = true
        defer { remoteSyncInFlight = false }
        remoteSyncState = .syncing
        do {
            let feedURL = RemotePatchConfiguration.mobileCatalogURL
            let networkConfiguration = URLSessionConfiguration.default
            networkConfiguration.waitsForConnectivity = true
            networkConfiguration.timeoutIntervalForRequest = 45
            networkConfiguration.timeoutIntervalForResource = 120
            networkConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
            let networkSession = URLSession(configuration: networkConfiguration)
            var feedRequest = URLRequest(url: feedURL)
            feedRequest.httpMethod = "GET"
            feedRequest.timeoutInterval = 30
            feedRequest.cachePolicy = .reloadIgnoringLocalCacheData
            feedRequest.setValue("application/json", forHTTPHeaderField: "Accept")
            feedRequest.setValue("3105-iOS", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await Self.fetchWithRetry(
                feedRequest,
                session: networkSession
            )
            guard let response = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            guard response.url?.host?.lowercased() == feedURL.host?.lowercased() else {
                throw URLError(.badServerResponse)
            }
            guard (200..<300).contains(response.statusCode) else {
                let body = String(data: data.prefix(512), encoding: .utf8) ?? "empty response"
                throw NSError(domain: "RemotePatchFeed", code: response.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(response.statusCode): \(body)"])
            }
            let catalog = try JSONDecoder().decode(MobileCatalogResponse.self, from: data)
            let feed = try RemoteFeed(catalog: catalog)

            let allLocalItems = await Task.detached(priority: .utility) {
                PatchProjectLibrary.load(includeWithdrawn: true)
            }.value
            var reservedPackageIDs = Set(allLocalItems.map(\.id))
            var claimedPackageIDs = Set<UUID>()
            var importedCount = 0
            var skippedCount = 0
            for patch in feed.patches {
                await Task.yield()
                do {
                    if patch.isUnderMaintenance {
                        skippedCount += 1
                        continue
                    }
                    let featureIdentifier = patch.feature.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    guard RemotePatchConfiguration.allowedRemoteFeatures.contains(featureIdentifier),
                          let feature = PatchFeatureCategory(rawValue: featureIdentifier),
                          feature != .external else {
                        skippedCount += 1
                        continue
                    }
                    let mappedID = PatchProjectLibrary.remotePackageID(for: patch.id)
                    let hasCurrentPackage = mappedID.map { id in allLocalItems.contains(where: { $0.id == id }) } ?? false
                    let category = PatchGameCategory(rawValue: patch.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                        ?? Self.inferredGameCategory(name: patch.name, fileName: patch.fileName)
                    guard let url = Self.remoteURL(for: patch.fileUrl) else { continue }
                    if hasCurrentPackage && patch.updatedAt <= PatchProjectLibrary.remoteVersion(for: patch.id) {
                        if let mappedID {
                            PatchProjectLibrary.setCategory(category, for: mappedID)
                            PatchProjectLibrary.setFeatureCategory(feature, for: mappedID)
                            PatchProjectLibrary.setFeatureIdentifier(featureIdentifier, for: mappedID)
                            PatchProjectLibrary.clearRemoteWithdrawal(for: patch.id)
                        }
                        continue
                    }
                    var packageRequest = URLRequest(url: url)
                    packageRequest.timeoutInterval = 30
                    packageRequest.cachePolicy = .reloadIgnoringLocalCacheData
                    packageRequest.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
                    packageRequest.setValue("3105-iOS", forHTTPHeaderField: "User-Agent")
                    var (packageData, packageResponse) = try await Self.fetchWithRetry(
                        packageRequest,
                        session: networkSession
                    )
                    let downloadedData = packageData
                    let checksum = await Task.detached(priority: .utility) {
                        Self.sha256Hex(downloadedData)
                    }.value
                    let sizeMatches = packageData.count == patch.fileSize
                    let checksumMatches = patch.checksumSha256.map {
                        checksum == $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    } ?? true
                    guard let packageResponse = packageResponse as? HTTPURLResponse,
                          (200..<300).contains(packageResponse.statusCode),
                          packageResponse.url?.host?.lowercased()
                            == RemotePatchConfiguration.mobileCatalogURL.host?.lowercased(),
                          sizeMatches,
                          checksumMatches else { continue }
                    let inspectedData = packageData
                    var summary = try await Task.detached(priority: .utility) {
                        try PatchPackageCodec.inspect(inspectedData)
                    }.value
                    var existingURL = allLocalItems.first(where: { $0.id == mappedID })?.packageURL
                    if !summary.isPasswordProtected,
                       (mappedID == nil || (mappedID != nil && claimedPackageIDs.contains(mappedID!)))
                        && reservedPackageIDs.contains(summary.packageID) {
                        let dataToDecode = packageData
                        let decoded = try await Task.detached(priority: .utility) {
                            try PatchPackageCodec.decode(dataToDecode, password: nil)
                        }.value
                        let newID = UUID()
                        let dataToReidentify = packageData
                        packageData = try await Task.detached(priority: .utility) {
                            try PatchPackageCodec.reidentifyPublicPackage(
                                dataToReidentify,
                                decoded: decoded,
                                newID: newID
                            )
                        }.value
                        let reidentifiedData = packageData
                        summary = try await Task.detached(priority: .utility) {
                            try PatchPackageCodec.inspect(reidentifiedData)
                        }.value
                        existingURL = nil
                    }
                    let dataToPersist = packageData
                    let summaryToPersist = summary
                    let urlToPersist = existingURL
                    let pendingUnlock: PendingUnlock?
                    do {
                        pendingUnlock = try await Task.detached(priority: .utility) {
                            try Self.persistImportedPackage(
                                data: dataToPersist,
                                summary: summaryToPersist,
                                existingURL: urlToPersist,
                                password: patch.password,
                                category: category,
                                feature: feature,
                                remoteID: patch.id,
                                remoteVersion: patch.updatedAt,
                                remoteName: patch.name
                            )
                        }.value
                    } catch {
                        // Never hide a protected remote patch because the stored password
                        // is stale, mistyped, or incompatible with this package revision.
                        // Keep it locally and present the normal unlock prompt instead.
                        guard summaryToPersist.isPasswordProtected else { throw error }
                        pendingUnlock = try await Task.detached(priority: .utility) {
                            try Self.persistImportedPackage(
                                data: dataToPersist,
                                summary: summaryToPersist,
                                existingURL: urlToPersist,
                                password: nil,
                                category: category,
                                feature: feature,
                                remoteID: patch.id,
                                remoteVersion: patch.updatedAt,
                                remoteName: patch.name
                            )
                        }.value
                    }
                    if pendingUnlock != nil {
                        let dataToSave = packageData
                        let urlToSave = existingURL
                        let summaryToSave = summary
                        try await Task.detached(priority: .utility) {
                            _ = try PatchProjectLibrary.save(
                                data: dataToSave,
                                projectName: patch.name,
                                existingURL: urlToSave
                            )
                            PatchProjectLibrary.setCategory(category, for: summaryToSave.packageID)
                            PatchProjectLibrary.setFeatureCategory(feature, for: summaryToSave.packageID)
                            PatchProjectLibrary.setFeatureIdentifier(featureIdentifier, for: summaryToSave.packageID)
                        }.value
                    }
                    PatchProjectLibrary.setRemotePackageID(summary.packageID, for: patch.id)
                    PatchProjectLibrary.setRemoteVersion(patch.updatedAt, for: patch.id)
                    PatchProjectLibrary.setDisplayName(patch.name, for: summary.packageID)
                    PatchProjectLibrary.setFeatureIdentifier(featureIdentifier, for: summary.packageID)
                    PatchProjectLibrary.setRemoteIconURL(
                        patch.iconUrl.flatMap { Self.remoteURL(for: $0)?.absoluteString },
                        for: summary.packageID
                    )
                    PatchProjectLibrary.setRemoteMetadata(
                        version: patch.version,
                        changelog: patch.changelog,
                        checksum: checksum,
                        for: summary.packageID
                    )
                    reservedPackageIDs.insert(summary.packageID)
                    claimedPackageIDs.insert(summary.packageID)
                    importedCount += 1
                } catch {
                    skippedCount += 1
                    // One malformed or incompatible remote package must not hide the rest.
                    continue
                }
            }
            // The feed was decoded and passed the HTTP/checksum flow, so it is a
            // complete catalog snapshot. Unpublished packages with active receipts
            // are tombstoned and kept for recovery; inactive ones are removed.
            let acceptedRemoteIDs = Set(feed.patches.map(\.id))
            PatchProjectLibrary.removeRemotePackagesNotInFeed(remoteIDs: acceptedRemoteIDs)
            items = await Task.detached(priority: .utility) {
                PatchProjectLibrary.load()
            }.value
            withdrawnRemoteItems = await Task.detached(priority: .utility) {
                PatchProjectLibrary.loadWithdrawnRemoteItems()
            }.value
            if withdrawnRemoteItems.isEmpty { withdrawnRestoreError = nil }
            remoteSyncState = .online
            lastRemoteSyncAt = Date()
            lastRemoteSyncError = skippedCount == 0
                ? nil
                : "Feed recebido: \(feed.patches.count) patches; \(importedCount) importados e \(skippedCount) ignorados."
        } catch {
            remoteSyncState = .offline
            lastRemoteSyncError = error.localizedDescription
        }
    }

    private static func remoteURL(for value: String) -> URL? {
        guard let candidate = URL(string: value, relativeTo: RemotePatchConfiguration.mobileCatalogURL)?.absoluteURL,
              candidate.scheme?.lowercased() == "https",
              candidate.host?.lowercased() == RemotePatchConfiguration.mobileCatalogURL.host?.lowercased() else { return nil }
        return candidate
    }

    private static func fetchWithRetry(
        _ request: URLRequest,
        session: URLSession
    ) async throws -> (Data, URLResponse) {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                return try await session.data(for: request)
            } catch {
                lastError = error
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    private nonisolated static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func finishInitialLoad(
        _ loadedItems: [PatchLibraryItem],
        withdrawnItems: [PatchLibraryItem]
    ) {
        items = loadedItems
        withdrawnRemoteItems = withdrawnItems
        isBusy = false
    }

    func create(project: PatchProject, password: String?) {
        runOperation(successMessageKey: "patch.created_message") {
            let encoded = try PatchPackageCodec.encodeNew(project: project, password: password)
            let summary = try PatchPackageCodec.inspect(encoded.data)
            let workspace = try PatchWorkspaceService.createWorkspace(for: project)
            var savedURL: URL?
            do {
                if summary.isPasswordProtected {
                    try PatchKeyStore.store(encoded.contentKey, for: summary)
                }
                savedURL = try PatchProjectLibrary.save(
                    data: encoded.data,
                    projectName: project.name
                )
                try PatchProjectLibrary.markAsAuthorCopy(packageID: project.id)
                PatchProjectLibrary.setCategory(
                    PatchProjectLibrary.selectedCategory,
                    for: project.id
                )
                PatchProjectLibrary.setFeatureCategory(
                    PatchProjectLibrary.selectedFeatureCategory,
                    for: project.id
                )
            } catch {
                try? FileManager.default.removeItem(at: workspace)
                if let savedURL {
                    try? FileManager.default.removeItem(at: savedURL)
                }
                try? PatchKeyStore.delete(for: summary)
                throw error
            }
        }
    }

    func update(project: PatchProject) {
        guard let item = items.first(where: { $0.id == project.id }),
              let contentKey = item.contentKey else {
            present(.invalidProject)
            return
        }
        runOperation(successMessageKey: "patch.updated_message") {
            let original = try PatchProjectLibrary.readPackage(at: item.packageURL)
            let updated = try PatchPackageCodec.update(
                original,
                project: project,
                contentKey: contentKey,
                schemaVersion: PatchPackageCodec.latestSchemaVersion
            )
            _ = try PatchProjectLibrary.save(
                data: updated,
                projectName: project.name,
                existingURL: item.packageURL
            )
        }
    }

    func importPackage(at sourceURL: URL) {
        guard !isBusy else { return }
        isBusy = true
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        Task.detached(priority: .userInitiated) { [weak self] in
            defer {
                if hasAccess { sourceURL.stopAccessingSecurityScopedResource() }
            }
            do {
                let data = try PatchProjectLibrary.readPackage(at: sourceURL)
                let summary = try PatchPackageCodec.inspect(data)
                let existingURL = await self?.existingPackageURL(for: summary.packageID)
                if let pending = try Self.persistImportedPackage(
                    data: data,
                    summary: summary,
                    existingURL: existingURL
                ) {
                    await self?.requestPassword(pending: pending)
                } else {
                    await self?.finishOperation(successMessageKey: "patch.imported_message")
                }
            } catch let error as PatchPackageError {
                await self?.failOperation(error)
            } catch {
                await self?.failOperation(.unsupportedFormat)
            }
        }
    }

    @discardableResult
    func importPackage(
        data: Data,
        password: String? = nil,
        origin: PatchPackageOrigin? = nil
    ) -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let summary = try PatchPackageCodec.inspect(data)
                let existingURL = await self?.existingPackageURL(for: summary.packageID)
                if let pending = try Self.persistImportedPackage(
                    data: data,
                    summary: summary,
                    existingURL: existingURL,
                    password: password,
                    origin: origin
                ) {
                    await self?.requestPassword(pending: pending)
                } else {
                    await self?.finishOperation(successMessageKey: "patch.imported_message")
                }
            } catch let error as PatchPackageError {
                await self?.failOperation(error)
            } catch {
                await self?.failOperation(.unsupportedFormat)
            }
        }
        return true
    }

    func presentImportError(_ error: PatchPackageError) {
        present(error)
    }

    func importPackage(from source: PatchImportSource) {
        switch source {
        case .file(let url):
            importPackage(at: url)
        case .remote(let url):
            importPackage(fromRemoteURL: url)
        case .invalid:
            present(.invalidImportLink)
        }
    }

    private func importPackage(fromRemoteURL remoteURL: URL) {
        guard !isBusy,
              PatchImportRoute.validatedRemoteURL(remoteURL) != nil else {
            if !isBusy { present(.invalidImportLink) }
            return
        }
        isBusy = true
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 60
                configuration.timeoutIntervalForResource = 600
                let session = URLSession(configuration: configuration)
                defer { session.invalidateAndCancel() }

                let (temporaryURL, response) = try await session.download(from: remoteURL)
                defer { try? FileManager.default.removeItem(at: temporaryURL) }
                guard let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode),
                      let finalURL = response.url,
                      PatchImportRoute.validatedRemoteURL(finalURL) != nil else {
                    throw PatchPackageError.remoteImportFailed
                }

                let data = try PatchProjectLibrary.readPackage(at: temporaryURL)
                let summary = try PatchPackageCodec.inspect(data)
                let existingURL = await self?.existingPackageURL(for: summary.packageID)
                if let pending = try Self.persistImportedPackage(
                    data: data,
                    summary: summary,
                    existingURL: existingURL
                ) {
                    await self?.requestPassword(pending: pending)
                } else {
                    await self?.finishOperation(successMessageKey: "patch.imported_message")
                }
            } catch let error as PatchPackageError {
                await self?.failOperation(error)
            } catch {
                await self?.failOperation(.remoteImportFailed)
            }
        }
    }

    func requestUnlock(for item: PatchLibraryItem) {
        guard item.isLocked, !isBusy else { return }
        do {
            let data = try PatchProjectLibrary.readPackage(at: item.packageURL)
            pendingUnlock = PendingUnlock(
                data: data,
                summary: item.summary,
                existingURL: item.packageURL,
                origin: item.origin,
                remoteID: nil,
                remoteVersion: nil,
                remoteCategory: nil,
                remoteFeature: nil
            )
            passwordRequest = PatchPasswordRequest(
                summary: item.summary,
                origin: item.origin
            )
        } catch let error as PatchPackageError {
            present(error)
        } catch {
            present(.unsupportedFormat)
        }
    }

    func unlock(password: String) {
        guard let pending = pendingUnlock, !isBusy else { return }
        isBusy = true
        unlockErrorKey = nil
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let decoded = try PatchPackageCodec.decode(pending.data, password: password)
                try PatchKeyStore.store(decoded.contentKey, for: pending.summary)
                do {
                    try PatchProjectLibrary.installImportedPackage(
                        data: pending.data,
                        decoded: decoded,
                        summary: pending.summary,
                        existingURL: pending.existingURL,
                        origin: pending.origin
                    )
                    if let category = pending.remoteCategory {
                        PatchProjectLibrary.setCategory(category, for: pending.summary.packageID)
                    } else {
                        PatchProjectLibrary.setCategory(PatchProjectLibrary.selectedCategory, for: pending.summary.packageID)
                    }
                    if let feature = pending.remoteFeature {
                        PatchProjectLibrary.setFeatureCategory(feature, for: pending.summary.packageID)
                    } else {
                        PatchProjectLibrary.setFeatureCategory(PatchProjectLibrary.selectedFeatureCategory, for: pending.summary.packageID)
                    }
                    if let remoteID = pending.remoteID {
                        PatchProjectLibrary.setRemotePackageID(pending.summary.packageID, for: remoteID)
                        PatchProjectLibrary.setRemoteVersion(pending.remoteVersion ?? 0, for: remoteID)
                    }
                } catch {
                    try? PatchKeyStore.delete(for: pending.summary)
                    throw error
                }
                await self?.clearPendingUnlock()
                await self?.finishOperation(successMessageKey: "patch.unlocked_message")
            } catch let error as PatchPackageError {
                await self?.failUnlock(error)
            } catch {
                await self?.failUnlock(.invalidPasswordOrCorruptedPackage)
            }
        }
    }

    func cancelUnlock() {
        clearPendingUnlock()
        isBusy = false
    }

    func clearUnlockError() {
        unlockErrorKey = nil
    }

    func delete(_ item: PatchLibraryItem) {
        do {
            try PatchProjectLibrary.delete(item)
            reload()
        } catch let error as PatchPackageError {
            present(error)
        } catch {
            present(.invalidProject)
        }
    }

    func restoreWithdrawnRemotePackage(_ item: PatchLibraryItem) {
        guard !isBusy,
              withdrawnRemoteItems.contains(where: { $0.id == item.id }) else { return }
        isBusy = true
        withdrawnRestoreError = nil
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                if let receipt = DevicePatchService.latestReceipt(projectID: item.id) {
                    try DevicePatchService.restore(receipt: receipt, allowChangedTargets: true)
                }
                try PatchProjectLibrary.finalizeRemoteWithdrawal(item)
                await self?.finishWithdrawnRemoteRestore()
            } catch {
                await self?.failWithdrawnRemoteRestore(error.localizedDescription)
            }
        }
    }

    private func finishWithdrawnRemoteRestore() {
        reload()
        isBusy = false
        withdrawnRestoreError = nil
    }

    private func failWithdrawnRemoteRestore(_ error: String) {
        // Keep the package, key, workspace, backup and tombstone intact on failure.
        withdrawnRestoreError = "Não foi possível restaurar os arquivos originais: \(error). A cópia e o backup foram mantidos para uma nova tentativa."
        isBusy = false
    }

    func synchronizeWorkspace(projectID: UUID, reportsSuccess: Bool = false) {
        guard let item = items.first(where: { $0.id == projectID }),
              item.summary.schemaVersion >= 2,
              !isBusy else { return }
        isBusy = true
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                _ = try PatchProjectLibrary.synchronizeWorkspace(item: item)
                await self?.finishWorkspaceSynchronization(reportsSuccess: reportsSuccess)
            } catch let error as PatchPackageError {
                await self?.failOperation(error)
            } catch {
                await self?.failOperation(.invalidProject)
            }
        }
    }

    func applyInline(_ item: PatchLibraryItem) {
        guard !isBusy else { return }
        guard let project = item.project else {
            requestUnlock(for: item)
            return
        }
        guard DevicePatchService.latestReceipt(projectID: item.id) == nil else {
            alert = PatchStoreAlert(
                titleKey: "common.done",
                messageKey: "patch.error.already_applied"
            )
            return
        }
        isBusy = true
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let synchronized = item.summary.schemaVersion >= 2 && item.canInspectContents
                    ? try PatchProjectLibrary.synchronizeWorkspace(item: item)
                    : project
                _ = try DevicePatchService.apply(project: synchronized)
                await self?.finishInlineApply(success: true)
            } catch let error as PatchPackageError {
                await self?.failOperation(error)
            } catch {
                await self?.failOperation(.applyFailed)
            }
        }
    }

    func restoreInline(_ item: PatchLibraryItem) {
        guard !isBusy,
              let receipt = DevicePatchService.latestReceipt(projectID: item.id) else {
            return
        }
        isBusy = true
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try DevicePatchService.restore(receipt: receipt, allowChangedTargets: true)
                await self?.finishInlineRestore(success: true)
            } catch let error as PatchPackageError {
                await self?.failOperation(error)
            } catch {
                await self?.failOperation(.restoreFailed)
            }
        }
    }

    private func finishInlineRestore(success: Bool) {
        reload()
        isBusy = false
        if success {
            alert = PatchStoreAlert(
                titleKey: "common.done",
                messageKey: "patch.restored_message"
            )
        }
    }

    private func finishInlineApply(success: Bool) {
        reload()
        isBusy = false
        if success {
            alert = PatchStoreAlert(
                titleKey: "common.done",
                messageKey: "patch.applied_message"
            )
        }
    }

    private func finishWorkspaceSynchronization(reportsSuccess: Bool) {
        reload()
        isBusy = false
        if reportsSuccess {
            alert = PatchStoreAlert(
                titleKey: "common.done",
                messageKey: "patch.workspace_synced_message"
            )
        }
    }

    private func runOperation(
        successMessageKey: String,
        operation: @escaping () throws -> Void
    ) {
        guard !isBusy else { return }
        isBusy = true
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try operation()
                await self?.finishOperation(successMessageKey: successMessageKey)
            } catch let error as PatchPackageError {
                await self?.failOperation(error)
            } catch {
                await self?.failOperation(.invalidProject)
            }
        }
    }

    private func requestPassword(pending: PendingUnlock) {
        pendingUnlock = pending
        passwordRequest = PatchPasswordRequest(
            summary: pending.summary,
            origin: pending.origin
        )
        isBusy = false
    }

    private func existingPackageURL(for packageID: UUID) -> URL? {
        items.first(where: { $0.id == packageID })?.packageURL
    }

    private nonisolated static func persistImportedPackage(
        data: Data,
        summary: PatchPackageSummary,
        existingURL: URL?,
        password: String? = nil,
        origin: PatchPackageOrigin? = nil,
        category: PatchGameCategory? = nil,
        feature: PatchFeatureCategory? = nil,
        remoteID: Int? = nil,
        remoteVersion: Int64? = nil,
        remoteName: String? = nil
    ) throws -> PendingUnlock? {
        let assignedCategory = category ?? PatchProjectLibrary.selectedCategory
        let assignedFeature = feature ?? PatchProjectLibrary.selectedFeatureCategory
        if let key = try PatchKeyStore.load(for: summary) {
            let decoded = try PatchPackageCodec.decode(data, contentKey: key)
            try PatchProjectLibrary.installImportedPackage(
                data: data,
                decoded: decoded,
                summary: summary,
                existingURL: existingURL,
                origin: origin
            )
            PatchProjectLibrary.setCategory(assignedCategory, for: summary.packageID)
            PatchProjectLibrary.setFeatureCategory(assignedFeature, for: summary.packageID)
            if let remoteID {
                PatchProjectLibrary.setRemotePackageID(summary.packageID, for: remoteID)
                PatchProjectLibrary.setRemoteVersion(remoteVersion ?? 0, for: remoteID)
                if let remoteName { PatchProjectLibrary.setDisplayName(remoteName, for: summary.packageID) }
            }
            return nil
        }
        if summary.isPasswordProtected {
            guard let password else {
                return PendingUnlock(
                    data: data,
                    summary: summary,
                    existingURL: existingURL,
                    origin: origin,
                    remoteID: remoteID,
                    remoteVersion: remoteVersion,
                    remoteCategory: category,
                    remoteFeature: feature
                )
            }
            let decoded = try PatchPackageCodec.decode(data, password: password)
            try PatchKeyStore.store(decoded.contentKey, for: summary)
            do {
                try PatchProjectLibrary.installImportedPackage(
                    data: data,
                    decoded: decoded,
                    summary: summary,
                    existingURL: existingURL,
                    origin: origin
                )
                PatchProjectLibrary.setCategory(assignedCategory, for: summary.packageID)
                PatchProjectLibrary.setFeatureCategory(assignedFeature, for: summary.packageID)
                if let remoteID {
                    PatchProjectLibrary.setRemotePackageID(summary.packageID, for: remoteID)
                    PatchProjectLibrary.setRemoteVersion(remoteVersion ?? 0, for: remoteID)
                    if let remoteName { PatchProjectLibrary.setDisplayName(remoteName, for: summary.packageID) }
                }
            } catch {
                try? PatchKeyStore.delete(for: summary)
                throw error
            }
            return nil
        }
        let decoded = try PatchPackageCodec.decode(data, password: nil)
        try PatchProjectLibrary.installImportedPackage(
            data: data,
            decoded: decoded,
            summary: summary,
            existingURL: existingURL,
            origin: origin
        )
        PatchProjectLibrary.setCategory(assignedCategory, for: summary.packageID)
        PatchProjectLibrary.setFeatureCategory(assignedFeature, for: summary.packageID)
        if let remoteID {
            PatchProjectLibrary.setRemotePackageID(summary.packageID, for: remoteID)
            PatchProjectLibrary.setRemoteVersion(remoteVersion ?? 0, for: remoteID)
            if let remoteName { PatchProjectLibrary.setDisplayName(remoteName, for: summary.packageID) }
        }
        return nil
    }

    private func clearPendingUnlock() {
        pendingUnlock = nil
        passwordRequest = nil
        unlockErrorKey = nil
    }

    private func finishOperation(successMessageKey: String) {
        reload()
        isBusy = false
        alert = PatchStoreAlert(titleKey: "common.done", messageKey: successMessageKey)
    }

    private func failOperation(_ error: PatchPackageError) {
        isBusy = false
        present(error)
    }

    private func failUnlock(_ error: PatchPackageError) {
        isBusy = false
        // Keep the password sheet open so the user can retry.
        // Presenting an alert while dismissing the sheet swallows the message.
        if case .invalidPasswordOrCorruptedPackage = error {
            unlockErrorKey = "patch.error.wrong_password"
        } else {
            unlockErrorKey = error.localizationKey
        }
    }

    private func present(_ error: PatchPackageError) {
        alert = PatchStoreAlert(
            titleKey: "common.failed",
            messageKey: error.localizationKey,
            messageArgument: error.localizationArgument
        )
    }
}
