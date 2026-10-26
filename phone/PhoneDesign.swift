import SwiftUI
import UIKit

func tr(_ en: String, _ zh: String, _ fr: String) -> String { cloudText(en, zh, fr) }

// Matches the Mac app's accent and neutral tokens in public/style.css.
enum Palette {
    static let accent = dynamic(0x4A62A8, 0x8EA2DC)
    static let accentSoft = dynamic(0xEEF1F8, 0x262C3C)
    static let active = dynamic(0x9AABDB, 0x56689F)
    static let warn = dynamic(0xB4691C, 0xE3A35A)
    static let live = dynamic(0x2F9E5B, 0x4CC77F)
    static let pending = dynamic(0xD9DAE0, 0x46464B)
    static let unknown = dynamic(0xC2C2C8, 0x5A5A60)
    static let track = dynamic(0xEBEBEF, 0x333337)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let page = Color(uiColor: .systemGroupedBackground)

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? rgb(dark) : rgb(light) })
    }
    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

struct Card: ViewModifier {
    var padding: CGFloat = 16
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.05), radius: 10, y: 3)
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(Card(padding: padding)) }
    func reveal(_ index: Int) -> some View { modifier(Reveal(index: index)) }
    func shimmer() -> some View { modifier(Shimmer()) }

    @ViewBuilder func zoomSource(_ id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) { matchedTransitionSource(id: id, in: namespace) } else { self }
    }
    @ViewBuilder func zoomDestination(_ id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) { navigationTransition(.zoom(sourceID: id, in: namespace)) } else { self }
    }
}

/// Fades and lifts content in once, staggered by position.
struct Reveal: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.opacity(shown ? 1 : 0).offset(y: shown || reduceMotion ? 0 : 16)
            .onAppear {
                guard !shown else { return }
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.55, bounce: 0.18).delay(Double(min(index, 10)) * 0.045)) { shown = true }
            }
    }
}

struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -0.7
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.overlay {
            if !reduceMotion {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.6).offset(x: phase * geo.size.width)
                }.mask(content).blendMode(.plusLighter)
            }
        }
        .onAppear { withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1.1 } }
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Counts up alongside the ring so the number and the arc always agree.
private struct CountingPercent: View, Animatable {
    var value: Double
    let font: Font
    var animatableData: Double { get { value } set { value = newValue } }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text("\(Int(value.rounded()))")
            Text("%").font(font.weight(.semibold)).scaleEffect(0.55, anchor: .leading).opacity(0.7)
        }.font(font).monospacedDigit()
    }
}

struct ProgressRing: View {
    let percent: Int
    var size: CGFloat = 54
    var lineWidth: CGFloat = 6
    var font: Font = .system(size: 15, weight: .bold, design: .rounded)
    @State private var shown = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Circle().stroke(Palette.track, lineWidth: lineWidth)
            Circle().trim(from: 0, to: shown / 100)
                .stroke(LinearGradient(colors: [Palette.accent.opacity(0.75), Palette.accent], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if percent >= 100 && shown >= 100 {
                Image(systemName: "checkmark").font(font).foregroundStyle(Palette.accent).transition(.scale.combined(with: .opacity))
            } else {
                CountingPercent(value: shown, font: font).foregroundStyle(.primary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(percent)%")
        .onAppear { animate(to: percent, delay: 0.12) }
        .onChange(of: percent) { _, value in animate(to: value, delay: 0) }
    }
    private func animate(to value: Int, delay: Double) {
        if reduceMotion { shown = Double(value); return }
        withAnimation(.spring(duration: 1.1, bounce: 0.12).delay(delay)) { shown = Double(value) }
    }
}

/// Composition of observed tasks. It is not a percentage of a known scope.
struct TaskBar: View {
    let counts: SnapshotCounts
    var height: CGFloat = 6
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static func segments(_ c: SnapshotCounts) -> [(Int, Color)] {
        [(c.done, Palette.accent), (c.active, Palette.active), (c.blocked, Palette.warn), (c.pending, Palette.pending), (c.unknown, Palette.unknown)]
    }
    var body: some View {
        GeometryReader { geo in
            let parts = Self.segments(counts).filter { $0.0 > 0 }
            let gaps = CGFloat(max(parts.count - 1, 0)) * 2
            HStack(spacing: 2) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    Capsule().fill(part.1)
                        .frame(width: max(height, (geo.size.width - gaps) * CGFloat(part.0) / CGFloat(max(counts.total, 1))))
                }
            }
            .scaleEffect(x: grown ? 1 : 0, anchor: .leading)
        }
        .frame(height: height)
        .clipShape(Capsule())
        .accessibilityHidden(true)
        .onAppear {
            if reduceMotion { grown = true } else { withAnimation(.spring(duration: 0.8, bounce: 0.1).delay(0.15)) { grown = true } }
        }
    }
}

// A recent capture indicator, not a heartbeat or Mac online status.
struct FreshnessDot: View {
    let recent: Bool
    var body: some View {
        Circle().fill(recent ? Palette.live : Color.secondary.opacity(0.6))
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }
}

struct IconBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 54
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(color.opacity(0.14))
            .frame(width: size, height: size)
            .overlay { Image(systemName: symbol).font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(color) }
            .accessibilityHidden(true)
    }
}

/// Mac → iPhone handoff drawn as a dot travelling along a dashed line.
struct SyncIllustration: View {
    @State private var travel = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "laptopcomputer").font(.system(size: 44, weight: .light))
            ZStack {
                Line().stroke(Palette.accent.opacity(0.35), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 6]))
                    .frame(height: 2)
                Circle().fill(Palette.accent).frame(width: 8, height: 8)
                    .shadow(color: Palette.accent.opacity(0.6), radius: 6)
                    .offset(x: travel ? 34 : -34)
                    .opacity(reduceMotion ? 0 : 1)
            }.frame(width: 84)
            Image(systemName: "iphone").font(.system(size: 38, weight: .light))
        }
        .foregroundStyle(Palette.accent)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .background(Palette.accentSoft.opacity(0.7), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityHidden(true)
        .onAppear { withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false)) { travel = true } }
    }
    private struct Line: Shape {
        func path(in rect: CGRect) -> Path { Path { $0.move(to: CGPoint(x: 0, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) } }
    }
}
