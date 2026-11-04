import SwiftUI

struct FolderPatchSelectionView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    let containerRoot: URL
    let folder: URL
    let onCreate: ([PatchDraftCandidate]) -> Void

    @State private var candidates: [PatchDraftCandidate] = []
    @State private var selectedIDs = Set<String>()
    @State private var isLoading = true
    @State private var validationMessageKey: String?

    private var selectedCandidates: [PatchDraftCandidate] {
        candidates.filter { selectedIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ParticleFieldBackground()

                Group {
                    if isLoading {
                        loadingState
                    } else if candidates.isEmpty {
                        emptyState
                    } else {
                        fileList
                    }
                }
            }
            .navigationTitle(language.text("patch.select_files"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("common.cancel")) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !isLoading && !candidates.isEmpty {
                    selectionActions
                }
            }
            .preferredColorScheme(.dark)
            .task { loadCandidates() }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(AppTheme.accent)
                .scaleEffect(1.15)
            Text(language.text("patch.folder_scanning"))
                .font(.headline)
                .foregroundStyle(.white)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 78, height: 78)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            Text(language.text("patch.folder_empty"))
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text(language.text("patch.folder_empty_message"))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.68))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fileList: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                selectionSummary

                if let validationMessageKey {
                    Label(
                        language.text(validationMessageKey),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                    }
                }

                LazyVStack(spacing: 10) {
                    ForEach(candidates) { candidate in
                        candidateCard(candidate)
                    }
                }

                Text(language.text("patch.folder_selection_footer"))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 3)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 18)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
    }

    private var selectionSummary: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.doc.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 42, height: 42)
                .background(AppTheme.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(language.text("patch.selected_count", Int64(selectedIDs.count)))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("\(candidates.count) · \(folder.lastPathComponent)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 21))
                .foregroundStyle(AppTheme.accent.opacity(0.9))
                .accessibilityHidden(true)
        }
        .padding(15)
        .background(Color(red: 0.075, green: 0.07, blue: 0.10).opacity(0.86), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
        }
    }

    private func candidateCard(_ candidate: PatchDraftCandidate) -> some View {
        let isSelected = selectedIDs.contains(candidate.id)
        return Button {
            toggle(candidate)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(candidate.url.lastPathComponent)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(candidate.relativePath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(ByteCountFormatter.string(fromByteCount: candidate.byteCount, countStyle: .file))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppTheme.accent.opacity(0.95))
                }

                Spacer(minLength: 5)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isSelected ? AppTheme.accent : .white.opacity(0.35))
                    .accessibilityHidden(true)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.065, green: 0.065, blue: 0.085).opacity(0.82), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(isSelected ? AppTheme.accent.opacity(0.48) : Color.white.opacity(0.09), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(candidate.url.lastPathComponent), \(ByteCountFormatter.string(fromByteCount: candidate.byteCount, countStyle: .file))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var selectionActions: some View {
        HStack(spacing: 11) {
            Button(selectionActionTitle, action: toggleAll)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                }

            Button {
                let selection = selectedCandidates
                dismiss()
                onCreate(selection)
            } label: {
                Label(language.text("patch.add_selected"), systemImage: "plus")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .disabled(selectedIDs.isEmpty)
            .opacity(selectedIDs.isEmpty ? 0.48 : 1)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 0.5)
        }
    }

    private var selectionActionTitle: String {
        selectedIDs.count == candidates.count
            ? language.text("patch.deselect_all")
            : language.text("patch.select_all")
    }

    private func loadCandidates() {
        guard isLoading else { return }
        let root = containerRoot
        let selectedFolder = folder
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try PatchDraftService.candidates(
                    in: selectedFolder,
                    containerRoot: root
                )
            }
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let loaded):
                    candidates = loaded
                    selectedIDs = Set(loaded.map(\.id))
                case .failure(let error as PatchPackageError):
                    validationMessageKey = error.localizationKey
                case .failure:
                    validationMessageKey = "patch.error.invalid_project"
                }
            }
        }
    }

    private func toggle(_ candidate: PatchDraftCandidate) {
        validationMessageKey = nil
        if selectedIDs.remove(candidate.id) != nil { return }
        selectedIDs.insert(candidate.id)
    }

    private func toggleAll() {
        validationMessageKey = nil
        if selectedIDs.count == candidates.count {
            selectedIDs.removeAll()
            return
        }
        selectedIDs = Set(candidates.map(\.id))
    }
}
