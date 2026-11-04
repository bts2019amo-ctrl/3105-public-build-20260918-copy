import SwiftUI

private enum OnboardingStep: Int, CaseIterable {
    case language = 0, welcome, versions, install

    var next: OnboardingStep? { Self(rawValue: rawValue + 1) }
    var prev: OnboardingStep? { Self(rawValue: rawValue - 1) }
}

private enum OnboardingNavigationDirection {
    case forward
    case backward
}

struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue
    @State private var step: OnboardingStep = .language
    @State private var navigationDirection: OnboardingNavigationDirection = .forward
    var onComplete: () -> Void

    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .english }
    private var motionAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.24)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                pageContent
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            controls
        }
        .tint(AppTheme.accent)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("EXTERNAL SYSTEM")
                        .font(.headline.weight(.black))
                        .tracking(1.8)
                        .foregroundStyle(.white)
                    Text(language.text("onboarding.step", "\(step.rawValue + 1)", "\(OnboardingStep.allCases.count)"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.62))
                }
                Spacer()
                Text("0\(step.rawValue + 1)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(AppTheme.accent.opacity(0.12), in: Capsule())
                    .accessibilityHidden(true)
            }
            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                    Capsule()
                        .fill(s.rawValue <= step.rawValue ? AppTheme.accent : Color.white.opacity(0.14))
                        .frame(height: s == step ? 5 : 3)
                        .frame(maxWidth: .infinity)
                        .animation(motionAnimation, value: step)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(Color.black.opacity(0.24))
    }

    @ViewBuilder
    private var pageContent: some View {
        ZStack {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                if s == step {
                    ScrollView(.vertical, showsIndicators: false) {
                        page(for: s)
                            .frame(maxWidth: 560)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .padding(.bottom, 28)
                    }
                    .transition(pageTransition)
                    .id(s.rawValue)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let insertionEdge: Edge = navigationDirection == .forward ? .trailing : .leading
        let removalEdge: Edge = navigationDirection == .forward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }

    @ViewBuilder
    private func page(for s: OnboardingStep) -> some View {
        switch s {
        case .language: languagePage
        case .welcome: welcomePage
        case .versions: versionsPage
        case .install: installPage
        }
    }

    private var languagePage: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle().fill(AppTheme.accent.opacity(0.12)).frame(width: 102, height: 102)
                AppLogo(size: 68)
                    .shadow(color: AppTheme.accent.opacity(0.25), radius: 18, y: 5)
            }

            VStack(spacing: 8) {
                Text(language.text("onboarding.language_title"))
                    .font(.title2.weight(.black))
                    .textCase(.uppercase)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(language.text("onboarding.language_subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.66))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                ForEach(AppLanguage.allCases) { option in
                    let isSelected = languageCode == option.rawValue
                    Button {
                        languageCode = option.rawValue
                    } label: {
                        HStack(spacing: 12) {
                            Text(option.displayName)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppTheme.accent)
                                    .font(.title3)
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(.white.opacity(0.28))
                            }
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 58)
                        .background(Color.white.opacity(isSelected ? 0.105 : 0.045), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(isSelected ? AppTheme.accent.opacity(0.72) : Color.white.opacity(0.12), lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .animation(motionAnimation, value: languageCode)
                }
            }

            Text(language.text("onboarding.language_hint", language.displayName))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var welcomePage: some View {
        VStack(spacing: 20) {
            featureIcon(systemName: "sparkles", color: AppTheme.accent)

            VStack(spacing: 10) {
                Text(language.text("onboarding.welcome_title"))
                    .font(.title2.weight(.black))
                    .textCase(.uppercase)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(language.text("onboarding.welcome_message"))
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label(language.text("onboarding.welcome_badge"), systemImage: "checkmark.seal.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(.white.opacity(0.11), lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var versionsPage: some View {
        VStack(spacing: 20) {
            featureIcon(systemName: "iphone.gen2", color: AppTheme.accent)

            VStack(spacing: 8) {
                Text(language.text("onboarding.versions_title"))
                    .font(.title3.weight(.black))
                    .textCase(.uppercase)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(language.text("onboarding.versions_subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                versionRow(icon: "checkmark.circle.fill", title: "iOS 17", value: ExploitSupportPolicy.verifiedIOS17Range, color: .green)
                versionRow(icon: "checkmark.circle.fill", title: "iOS 18", value: ExploitSupportPolicy.verifiedIOS18Range, color: .green)
                versionRow(icon: "checkmark.circle.fill", title: "iOS 26", value: ExploitSupportPolicy.verifiedIOS26Range, color: .green)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("iOS 27.0").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(language.text("onboarding.beta")).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.58))
                    }
                    ForEach(ExploitSupportPolicy.verifiedIOS27Builds, id: \.build) { v in
                        let betaLabel = language.text("onboarding.developer_beta", "\(v.beta)")
                            + (v.publicBeta.map {
                                " · " + language.text("onboarding.public_beta", "\($0)")
                            } ?? "")
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) {
                                Text(betaLabel)
                                Spacer()
                                Text(v.build)
                                    .font(.caption.monospaced().weight(.medium))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(betaLabel)
                                Text(v.build)
                                    .font(.caption.monospaced().weight(.medium))
                            }
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.66))
                        .padding(.leading, 24)
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1))
            }

            Text(language.text("onboarding.versions_footer", AppInfo.osVersion, AppInfo.osBuild))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var installPage: some View {
        VStack(spacing: 20) {
            featureIcon(systemName: "exclamationmark.shield.fill", color: .orange)

            VStack(spacing: 8) {
                Text(language.text("onboarding.install_title"))
                    .font(.title3.weight(.black))
                    .textCase(.uppercase)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(language.text("onboarding.install_message"))
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                installBullet(icon: "checkmark.seal.fill", text: language.text("onboarding.install_ok"), color: .green)
                installBullet(icon: "xmark.octagon.fill", text: language.text("onboarding.install_bad"), color: .red)
                installBullet(icon: "exclamationmark.triangle.fill", text: language.text("onboarding.install_jailbreak"), color: .orange)
            }
            .padding(14)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1))

            Text(language.text("onboarding.install_footer"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func featureIcon(systemName: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.065))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(color.opacity(0.42), lineWidth: 1)
                )
            Image(systemName: systemName)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(color)
        }
        .frame(width: 72, height: 72)
        .accessibilityHidden(true)
    }

    private func versionRow(icon: String, title: String, value: String, color: Color) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).fontWeight(.semibold)
                Spacer()
                Text(value)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                    Text(title)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
                Text(value)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.leading, 26)
            }
        }
        .font(.subheadline)
        .padding(12)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1))
    }

    private func installBullet(icon: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.body.weight(.semibold))
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    controlButtons
                }
                VStack(spacing: 10) {
                    controlButtons
                }
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 20)
        }
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.58))
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.12)).frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var controlButtons: some View {
        if step != .language {
            Button {
                guard let previousStep = step.prev else { return }
                navigate(to: previousStep, direction: .backward)
            } label: {
                Label(language.text("common.back"), systemImage: "chevron.left")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.white.opacity(0.78))
        }

        Button {
            if let nextStep = step.next {
                navigate(to: nextStep, direction: .forward)
            } else {
                onComplete()
            }
        } label: {
            HStack(spacing: 6) {
                Text(language.text(step == .install ? "common.finish" : "common.next"))
                if step != .install {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(AppTheme.accent)
    }

    private func navigate(to destination: OnboardingStep, direction: OnboardingNavigationDirection) {
        withAnimation(motionAnimation) {
            navigationDirection = direction
            step = destination
        }
    }
}

enum OnboardingStore {
    static let completedVersionKey = "onboarding.completedVersion"
    static let completedFingerprintKey = "onboarding.completedFingerprint"

    static var currentVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(v) (\(b))"
    }

    /// Per-install token: executable mtime changes on every overwrite even if version stays the same.
    static var bundleToken: String {
        if let exe = Bundle.main.executablePath,
           let attrs = try? FileManager.default.attributesOfItem(atPath: exe),
           let date = attrs[.modificationDate] as? Date {
            return String(Int(date.timeIntervalSince1970))
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: Bundle.main.bundlePath),
           let date = (attrs[.creationDate] as? Date) ?? (attrs[.modificationDate] as? Date) {
            return String(Int(date.timeIntervalSince1970))
        }
        return "0"
    }

    static var currentFingerprint: String { "\(currentVersion)#\(bundleToken)" }

    static var completedVersion: String? {
        UserDefaults.standard.string(forKey: completedVersionKey)
    }

    static var completedFingerprint: String? {
        UserDefaults.standard.string(forKey: completedFingerprintKey)
    }

    static func shouldShow() -> Bool {
#if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--skip-onboarding") { return false }
        if ProcessInfo.processInfo.arguments.contains("--reset-onboarding") { return true }
#endif
        let fp = currentFingerprint
        if let stored = completedFingerprint, !stored.isEmpty {
            return stored != fp
        }
        // Migration: old installs only have completedVersion
        if let completed = completedVersion, !completed.isEmpty {
            if completed == currentVersion {
                // Same version, migrate silently — next overwrite will be detected via fingerprint
                UserDefaults.standard.set(fp, forKey: completedFingerprintKey)
                return false
            }
            return true
        }
        return true
    }

    static func markCompleted() {
        UserDefaults.standard.set(currentVersion, forKey: completedVersionKey)
        UserDefaults.standard.set(currentFingerprint, forKey: completedFingerprintKey)
    }
}
