import SwiftUI

struct LogView: View {
    @ObservedObject var appLog = AppLog.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appLanguage) private var language
    @State private var copied = false

    private var shareText: String {
        var lines: [String] = []
        lines.append("3105 Log")
        lines.append("iOS \(AppInfo.osVersion) (\(AppInfo.osBuild)) — \(AppInfo.machineName)")
        lines.append("Generated: \(Date())")
        lines.append("")
        lines.append(contentsOf: appLog.entries)
        return lines.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ParticleFieldBackground()

                VStack(spacing: 14) {
                    logSummary
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    if appLog.entries.isEmpty {
                        emptyState
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                    } else {
                        entriesList
                    }
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(language.text("logs.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(language.text("logs.clear"), role: .destructive) {
                        appLog.entries.removeAll()
                    }
                    .disabled(appLog.entries.isEmpty)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        UIPasteboard.general.string = shareText
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .disabled(appLog.entries.isEmpty)
                    .accessibilityLabel(language.text("logs.copy"))
                    .accessibilityValue(copied ? language.text("logs.copy") : "")

                    ShareLink(item: shareText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(appLog.entries.isEmpty)
                    .accessibilityLabel(language.text("logs.share"))

                    Button(language.text("common.done")) { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
        }
    }

    private var logSummary: some View {
        HStack(spacing: 13) {
            Image(systemName: "apple.terminal.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 44, height: 44)
                .background(AppTheme.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(language.text("logs.title"))
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("iOS \(AppInfo.osVersion) (\(AppInfo.osBuild))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.61))
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(appLog.entries.count)")
                    .font(.title3.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text(language.text("logs.title").uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(.white.opacity(0.48))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(appLog.entries.count) \(language.text("logs.title"))")
        }
        .padding(14)
        .background(
            Color(red: 0.055, green: 0.052, blue: 0.075).opacity(0.84),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 0.8)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "terminal")
                .font(.system(size: 27, weight: .medium))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 70, height: 70)
                .background(AppTheme.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
                .accessibilityHidden(true)
            Text(language.text("logs.empty_title"))
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(language.text("logs.empty_message"))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.64))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color(red: 0.055, green: 0.052, blue: 0.075).opacity(0.77),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.11), lineWidth: 0.8)
        }
        .accessibilityElement(children: .combine)
    }

    private var entriesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(appLog.entries.enumerated()), id: \.offset) { index, entry in
                        HStack(alignment: .top, spacing: 11) {
                            Text(String(format: "%03d", index + 1))
                                .font(.system(.caption2, design: .monospaced).weight(.medium))
                                .foregroundStyle(AppTheme.accent.opacity(0.78))
                                .frame(minWidth: 30, alignment: .trailing)
                                .padding(.top, 2)
                                .accessibilityHidden(true)

                            RoundedRectangle(cornerRadius: 1)
                                .fill(AppTheme.accent.opacity(0.42))
                                .frame(width: 2)
                                .frame(minHeight: 17)
                                .accessibilityHidden(true)

                            Text(entry)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.88))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(index.isMultiple(of: 2) ? Color.white.opacity(0.025) : Color.clear)
                        .id(index)
                        .accessibilityLabel(language.text("accessibility.log_entry", Int64(index + 1), entry))
                    }
                }
                .padding(.vertical, 5)
            }
            .background(Color(red: 0.035, green: 0.034, blue: 0.047).opacity(0.79), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 0.8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
            .onChange(of: appLog.entries.count) { count in
                guard count > 0 else { return }
                if reduceMotion {
                    proxy.scrollTo(count - 1, anchor: .bottom)
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(count - 1, anchor: .bottom)
                    }
                }
            }
        }
    }
}
