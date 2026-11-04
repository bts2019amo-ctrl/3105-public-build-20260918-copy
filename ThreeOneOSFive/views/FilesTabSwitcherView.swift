import SwiftUI

struct FilesTabSwitcherView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @Binding var session: FilesTabSession
    @State private var renameTargetID: UUID?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                ParticleFieldBackground()
                List {
                    ForEach(session.tabs) { tab in
                        Button {
                            session.selectTab(tab.id)
                            dismiss()
                        } label: {
                            tabRow(tab)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .contextMenu { tabActions(tab) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                session.closeTab(tab.id)
                            } label: {
                                Label(language.text("browser.close_tab"), systemImage: "xmark")
                            }
                            Button {
                                beginRename(tab)
                            } label: {
                                Label(language.text("browser.rename_tab"), systemImage: "pencil")
                            }
                            .tint(AppTheme.accent)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
            .navigationTitle(language.text("browser.tabs"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("common.done")) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        session.openTab()
                        dismiss()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(language.text("browser.new_tab"))
                }
            }
            .alert(
                language.text("browser.rename_tab"),
                isPresented: renamePresentation
            ) {
                TextField(language.text("browser.tab_name"), text: $renameText)
                Button(language.text("common.cancel"), role: .cancel) {
                    renameTargetID = nil
                }
                Button(language.text("common.done")) {
                    if let renameTargetID {
                        session.renameTab(renameTargetID, to: renameText)
                    }
                    renameTargetID = nil
                }
            } message: {
                Text(language.text("browser.tab_name_message"))
            }
        }
    }

    private func tabRow(_ tab: FilesTabState) -> some View {
        HStack(spacing: 12) {
            Image(systemName: tab.id == session.selectedTabID ? "folder.fill" : "folder")
                .foregroundStyle(tab.id == session.selectedTabID ? AppTheme.accent : Color.secondary)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(AppTheme.accent.opacity(tab.id == session.selectedTabID ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(tab.displayTitle(defaultTitle: language.text("browser.tabs_root")))
                    .font(.body.weight(tab.id == session.selectedTabID ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(tab.currentPath ?? language.text("browser.tabs_root_detail"))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
            if tab.id == session.selectedTabID {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(12)
        .liquidGlassCard(cornerRadius: 16, tint: AppTheme.accent, opacity: tab.id == session.selectedTabID ? 0.10 : 0.055)
    }

    @ViewBuilder
    private func tabActions(_ tab: FilesTabState) -> some View {
        Button {
            beginRename(tab)
        } label: {
            Label(language.text("browser.rename_tab"), systemImage: "pencil")
        }
        Button {
            session.closeOtherTabs(keeping: tab.id)
        } label: {
            Label(language.text("browser.close_other_tabs"), systemImage: "square.on.square.dashed")
        }
        Button(role: .destructive) {
            session.closeTab(tab.id)
        } label: {
            Label(language.text("browser.close_tab"), systemImage: "xmark")
        }
    }

    private var renamePresentation: Binding<Bool> {
        Binding(
            get: { renameTargetID != nil },
            set: { if !$0 { renameTargetID = nil } }
        )
    }

    private func beginRename(_ tab: FilesTabState) {
        renameText = tab.displayTitle(defaultTitle: language.text("browser.tabs_root"))
        renameTargetID = tab.id
    }
}
