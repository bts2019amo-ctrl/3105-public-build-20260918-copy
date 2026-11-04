import Foundation
import SwiftUI

enum AppAccentPalette: String, CaseIterable, Identifiable {
    case orange
    case blue
    case purple
    case green
    case pink
    case red
    case teal
    case cyan
    case yellow
    case indigo
    case lavender
    case gold
    case lime
    case crimson
    case sky
    case magenta
    case slate

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .orange: return Color(red: 0.92, green: 0.40, blue: 0.16)
        case .blue: return Color(red: 0.16, green: 0.45, blue: 0.95)
        case .purple: return Color(red: 0.55, green: 0.30, blue: 0.90)
        case .green: return Color(red: 0.12, green: 0.62, blue: 0.36)
        case .pink: return Color(red: 0.92, green: 0.25, blue: 0.52)
        case .red: return Color(red: 0.88, green: 0.18, blue: 0.20)
        case .teal: return Color(red: 0.08, green: 0.62, blue: 0.66)
        case .cyan: return Color(red: 0.05, green: 0.78, blue: 0.88)
        case .yellow: return Color(red: 0.98, green: 0.78, blue: 0.12)
        case .indigo: return Color(red: 0.30, green: 0.32, blue: 0.92)
        case .lavender: return Color(red: 0.70, green: 0.52, blue: 0.96)
        case .gold: return Color(red: 0.92, green: 0.60, blue: 0.14)
        case .lime: return Color(red: 0.56, green: 0.78, blue: 0.12)
        case .crimson: return Color(red: 0.72, green: 0.08, blue: 0.24)
        case .sky: return Color(red: 0.22, green: 0.62, blue: 0.96)
        case .magenta: return Color(red: 0.78, green: 0.16, blue: 0.72)
        case .slate: return Color(red: 0.55, green: 0.57, blue: 0.59)
        }
    }
}

enum AppTheme {
    static let accentPaletteStorageKey = "theme.accent.palette"
    static let glassOpacityStorageKey = "theme.glass.opacity"
    static let wallpaperBlurStorageKey = "theme.wallpaper.blur"
    static let animationSpeedStorageKey = "theme.animation.speed"
    static let saturationStorageKey = "theme.saturation"
    static let defaultAccentPalette = AppAccentPalette.slate.rawValue
    static let defaultGlassOpacity = 0.14
    static let defaultWallpaperBlur = 26.0
    static let defaultAnimationSpeed = 1.0
    static let defaultSaturation = 1.0

    static var accent: Color { Color(red: 0.70, green: 0.72, blue: 0.74) }
    static var glassOpacity: Double { UserDefaults.standard.object(forKey: glassOpacityStorageKey) as? Double ?? defaultGlassOpacity }
    static var wallpaperBlur: CGFloat { CGFloat(UserDefaults.standard.object(forKey: wallpaperBlurStorageKey) as? Double ?? defaultWallpaperBlur) }
    static var animationSpeed: Double { UserDefaults.standard.object(forKey: animationSpeedStorageKey) as? Double ?? defaultAnimationSpeed }
    static var saturation: Double { UserDefaults.standard.object(forKey: saturationStorageKey) as? Double ?? defaultSaturation }
    static let pageBackground = Color.black
    static let consoleBackground = Color(red: 0.075, green: 0.075, blue: 0.075)
    static let pageInset: CGFloat = 16
    static let rowIconSize: CGFloat = 17
    static let rowIconFrame: CGFloat = 28
    static let fileRowIconSize: CGFloat = 17
    static let fileRowIconFrame: CGFloat = 30
    static let fileRowHeight: CGFloat = 60
    static let appIconSize: CGFloat = 32
    static let emptyIconSize: CGFloat = 30
    static let selectionIconSize: CGFloat = 18
    static let contentCardCornerRadius: CGFloat = 14
    static let contentCardInset: CGFloat = 16
    static let contentCardPadding: CGFloat = 16
}

struct AppCardBorder: View {
    var body: some View {
        RoundedRectangle(
            cornerRadius: AppTheme.contentCardCornerRadius,
            style: .continuous
        )
        .strokeBorder(
            Color(uiColor: .separator).opacity(0.22),
            lineWidth: 0.5
        )
        .accessibilityHidden(true)
    }
}

struct LiquidGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = AppTheme.contentCardCornerRadius
    var tint: Color = .white
    var opacity: Double = 0.14

    func body(content: Content) -> some View {
        content
            .background(Color(red: 0.075, green: 0.075, blue: 0.075).opacity(0.82), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(tint.opacity(opacity * 0.34), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.22), .white.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius - 1, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 3)
                    .blur(radius: 2)
                    .mask(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(LinearGradient(colors: [.white, .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
            }
            .shadow(color: .black.opacity(0.38), radius: 16, y: 8)
    }
}

extension View {
    func liquidGlassCard(
        cornerRadius: CGFloat = AppTheme.contentCardCornerRadius,
        tint: Color = .white,
        opacity: Double = 0.14
    ) -> some View {
        modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, tint: tint, opacity: opacity))
    }
}

/// A low-cost, decorative constellation field used behind app surfaces.
/// Motion is deliberately slow and automatically becomes static when Reduce Motion is enabled.
struct ParticleFieldBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { _ in
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.018, green: 0.018, blue: 0.018), Color(red: 0.032, green: 0.032, blue: 0.032), .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if reduceMotion {
                    Canvas { context, size in
                        Self.drawConstellation(in: &context, size: size, phase: 0)
                    }
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 16.0)) { timeline in
                        Canvas { context, size in
                            let phase = timeline.date.timeIntervalSinceReferenceDate * 0.12
                            Self.drawConstellation(in: &context, size: size, phase: phase)
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func drawConstellation(in context: inout GraphicsContext, size: CGSize, phase: Double) {
        guard size.width > 0, size.height > 0 else { return }
        let count = 25
        let points: [CGPoint] = (0..<count).map { index in
            let seed = Double(index)
            let baseX = (seed * 0.61803398875).truncatingRemainder(dividingBy: 1)
            let baseY = (seed * 0.75487766625 + 0.17).truncatingRemainder(dividingBy: 1)
            let driftX = sin(phase + seed * 1.73) * 0.018
            let driftY = cos(phase * 0.83 + seed * 1.21) * 0.018
            return CGPoint(
                x: CGFloat(min(1, max(0, baseX + driftX))) * size.width,
                y: CGFloat(min(1, max(0, baseY + driftY))) * size.height
            )
        }

        let maxDistance = min(size.width, size.height) * 0.27
        for first in 0..<count {
            for second in (first + 1)..<count {
                let a = points[first]
                let b = points[second]
                let dx = a.x - b.x
                let dy = a.y - b.y
                let distance = hypot(dx, dy)
                guard distance < maxDistance else { continue }
                var path = Path()
                path.move(to: a)
                path.addLine(to: b)
                let opacity = Double(0.11 * (1 - distance / maxDistance))
                context.stroke(path, with: .color(Color(red: 0.62, green: 0.64, blue: 0.66).opacity(opacity)), lineWidth: 0.55)
            }
        }

        for (index, point) in points.enumerated() {
            let radius: CGFloat = index.isMultiple(of: 5) ? 2.1 : 1.25
            let dot = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            context.fill(dot, with: .color(Color(red: 0.72, green: 0.74, blue: 0.76).opacity(index.isMultiple(of: 4) ? 0.42 : 0.20)))
        }
    }
}

struct ParallaxBrandHeader: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate * AppTheme.animationSpeed
            HStack(spacing: 8) {
                AppLogo(size: 28)
                    .offset(x: sin(phase * 0.8) * 1.6, y: cos(phase * 0.7) * 0.8)
                VStack(alignment: .leading, spacing: 1) {
                    Text("EXTERNAL SYSTEM")
                        .font(.subheadline.weight(.black))
                        .tracking(0.8)
                        .offset(x: cos(phase * 0.55) * 0.8)
                    Text("PATCH CONTROL")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)
                        .offset(x: sin(phase * 0.45) * 0.5)
                }
                Circle()
                    .fill(Color.white.opacity(0.72))
                    .frame(width: 6, height: 6)
                    .shadow(color: .white.opacity(0.45), radius: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .liquidGlassCard(cornerRadius: 16, tint: AppTheme.accent, opacity: 0.08)
        }
        .frame(height: 42)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("External System")
    }
}

struct AnimatedGlassWallpaper: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate * AppTheme.animationSpeed
            let intensity = max(0.65, min(2.0, AppTheme.glassOpacity / AppTheme.defaultGlassOpacity))
            ZStack {
                LinearGradient(
                    colors: [
                        Color.black,
                        Color(red: 0.055, green: 0.055, blue: 0.055),
                        Color.black
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                blob(
                    color: AppTheme.accent.opacity(min(0.28, 0.12 * intensity)),
                    size: 340,
                    x: sin(phase * 0.34) * 125,
                    y: cos(phase * 0.28) * 155
                )
                blob(
                    color: Color.white.opacity(min(0.12, 0.045 * intensity)),
                    size: 280,
                    x: cos(phase * 0.24) * 155,
                    y: sin(phase * 0.38) * 175
                )
                blob(
                    color: AppTheme.accent.opacity(min(0.18, 0.07 * intensity)),
                    size: 190,
                    x: sin(phase * 0.20 + 2) * 150,
                    y: cos(phase * 0.30 + 1) * 110
                )
            }
            .blur(radius: AppTheme.wallpaperBlur)
            .saturation(AppTheme.saturation)
        }
        .allowsHitTesting(false)
    }

    private func blob(color: Color, size: CGFloat, x: Double, y: Double) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .offset(x: x, y: y)
    }
}

struct AppRowIcon: View {
    let systemName: String
    var tint: Color = AppTheme.accent
    var symbolSize: CGFloat = AppTheme.rowIconSize
    var frameSize: CGFloat = AppTheme.rowIconFrame

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint.opacity(0.12))
            Image(systemName: systemName)
                .font(.system(size: symbolSize, weight: .medium))
                .foregroundStyle(tint)
        }
        .frame(width: frameSize, height: frameSize)
        .accessibilityHidden(true)
    }
}

struct AppSearchField: View {
    @Binding var text: String
    let prompt: String
    let clearLabel: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(prompt, text: $text)
                .font(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(clearLabel)
            }
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 36)
        .background(
            Color(uiColor: .secondarySystemFill),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .padding(.horizontal, AppTheme.pageInset)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct AppLogo: View {
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let icon = UIImage(named: "AppIcon60x60")
                ?? Bundle.main.path(forResource: "AppIcon60x60@2x", ofType: "png").flatMap(UIImage.init(contentsOfFile:))
                ?? UIImage(named: "AppIcon") {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "slider.horizontal.3")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }
}


struct ReferenceToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(configuration.isOn ? Color.white : Color.white.opacity(0.32))
                .frame(width: 54, height: 30)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(configuration.isOn ? Color.black : Color.white)
                        .frame(width: 26, height: 26)
                        .padding(3)
                }
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.22), lineWidth: 0.6))
                .animation(.easeOut(duration: 0.18), value: configuration.isOn)
                .onTapGesture { configuration.isOn.toggle() }
        }
    }
}
