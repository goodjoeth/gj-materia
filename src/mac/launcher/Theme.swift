// Theme.swift - the launcher's look, after the app icon: a dark crimson night, a red Meteor, gunmetal
// and gold. Colours, the Play page's sky, the gold title, the crimson Play button and the dark
// glass cards the pages put their boxes on. SwiftUI only, so an iPad build shares it.
import SwiftUI
#if os(macOS)
import AppKit
#endif

enum Theme {
    static let gold = Color(red: 0.93, green: 0.72, blue: 0.32)
    static let goldLight = Color(red: 1.0, green: 0.9, blue: 0.6)
    static let goldDark = Color(red: 0.55, green: 0.35, blue: 0.08)
    static let crimson = Color(red: 0.72, green: 0.06, blue: 0.1)
    static let crimsonDark = Color(red: 0.32, green: 0.02, blue: 0.05)
    static let night = Color(red: 0.06, green: 0.03, blue: 0.05)
    static let ember = Color(red: 1.0, green: 0.45, blue: 0.15)

    static var goldGradient: LinearGradient {
        LinearGradient(colors: [goldLight, gold, goldDark], startPoint: .top, endPoint: .bottom)
    }
}

/// A night full of stars: a few hundred of them (some tinted, the brightest with a cross of light,
/// twinkling slowly) over faint crimson and violet nebulae. Every page sits on it; `dim` darkens it
/// under the lists.
struct StarField: View {
    var dim = false
    private struct Star { let x, y, r, phase: CGFloat; let tint: Int }
    private static let stars: [Star] = {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
        return (0..<420).map { _ in
            let big = rnd() > 0.93
            return Star(x: rnd(), y: rnd(), r: big ? 1.2 + rnd() * 1.4 : 0.4 + rnd() * 0.8, phase: rnd() * 6.28, tint: Int(rnd() * 10))
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { c, size in
                c.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                    Gradient(colors: [Color(red: 0.1, green: 0.03, blue: 0.08), Color(red: 0.03, green: 0.02, blue: 0.05), Color(red: 0.01, green: 0.01, blue: 0.02)]),
                    startPoint: .zero, endPoint: CGPoint(x: size.width * 0.3, y: size.height)))
                // nebulae
                for (x, y, r, col) in [(0.2, 0.3, 0.45, Color(red: 0.5, green: 0.05, blue: 0.2)), (0.7, 0.75, 0.5, Color(red: 0.25, green: 0.08, blue: 0.45)),
                                       (0.95, 0.1, 0.35, Color(red: 0.6, green: 0.12, blue: 0.08))] as [(CGFloat, CGFloat, CGFloat, Color)] {
                    let R = r * max(size.width, size.height)
                    c.fill(Path(ellipseIn: CGRect(x: x * size.width - R, y: y * size.height - R * 0.6, width: R * 2, height: R * 1.2)),
                           with: .radialGradient(Gradient(colors: [col.opacity(0.28), .clear]), center: CGPoint(x: x * size.width, y: y * size.height), startRadius: 0, endRadius: R))
                }
                for s in Self.stars {
                    let p = CGPoint(x: s.x * size.width, y: s.y * size.height)
                    let tw = 0.55 + 0.45 * sin(t * (0.6 + Double(s.phase) * 0.15) + Double(s.phase))
                    let col: Color = s.tint == 0 ? Color(red: 1, green: 0.75, blue: 0.6) : s.tint == 1 ? Color(red: 0.7, green: 0.8, blue: 1) : .white
                    c.fill(Path(ellipseIn: CGRect(x: p.x - s.r, y: p.y - s.r, width: s.r * 2, height: s.r * 2)), with: .color(col.opacity(0.35 + 0.6 * tw)))
                    if s.r > 1.8 {   // the brightest: a small cross of light
                        let l = s.r * 4 * tw
                        var cross = Path()
                        cross.move(to: CGPoint(x: p.x - l, y: p.y)); cross.addLine(to: CGPoint(x: p.x + l, y: p.y))
                        cross.move(to: CGPoint(x: p.x, y: p.y - l)); cross.addLine(to: CGPoint(x: p.x, y: p.y + l))
                        c.stroke(cross, with: .color(col.opacity(0.35 * tw)), lineWidth: 0.8)
                    }
                }
                if dim { c.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.35))) }
            }
        }
        .ignoresSafeArea()
    }
}

/// The Play page's background: the starry night, the red Meteor up and right, a cloak's edge below.
struct MeteorSky: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let r = min(w, h) * 0.15
            ZStack {
                StarField()
                Circle()
                    .fill(RadialGradient(colors: [Theme.ember.opacity(0.4), .clear], center: .center, startRadius: r * 0.8, endRadius: r * 2.2))
                    .frame(width: r * 4.4, height: r * 4.4)
                    .position(x: w * 0.82, y: h * 0.17)
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 1, green: 0.85, blue: 0.45), Theme.ember, Theme.crimson, Theme.crimsonDark],
                                         center: UnitPoint(x: 0.38, y: 0.62), startRadius: 0, endRadius: r))
                    .frame(width: r * 2, height: r * 2)
                    .position(x: w * 0.82, y: h * 0.17)
                    .opacity(0.92)
                CloakEdge().fill(LinearGradient(colors: [Theme.crimson.opacity(0.35), Theme.crimsonDark.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                    .frame(height: h * 0.1).frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .ignoresSafeArea()
    }
}

/// A torn cloth edge across the bottom of its frame.
struct CloakEdge: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.35))
        let teeth: [CGFloat] = [0.05, 0.03, 0.07, 0.04, 0.06, 0.025, 0.08, 0.035, 0.05, 0.03, 0.07, 0.04, 0.06, 0.03, 0.08, 0.04, 0.06, 0.05, 0.06]
        var x = rect.minX
        var low = true
        for t in teeth {
            x += rect.width * t
            p.addLine(to: CGPoint(x: min(x, rect.maxX), y: rect.minY + rect.height * (low ? 0.6 + t * 2 : 0.05 + t * 3)))
            low.toggle()
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.3))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Text in engraved gold.
struct GoldText: View {
    let text: String
    let size: CGFloat
    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold, design: .serif))
            .tracking(size * 0.04)
            .foregroundStyle(Theme.goldGradient)
            .shadow(color: .black.opacity(0.8), radius: 2, y: 2)
            .shadow(color: Theme.ember.opacity(0.25), radius: 18)
    }
}

/// The big crimson Play button, gold-rimmed, glowing when it can be pressed.
struct CrimsonButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration c: Configuration) -> some View {
        c.label
            .font(.system(size: 22, weight: .heavy, design: .rounded))
            .foregroundStyle(enabled ? Theme.goldLight : .white.opacity(0.35))
            .padding(.horizontal, 54).padding(.vertical, 14)
            .background(
                Capsule().fill(LinearGradient(colors: enabled ? [Color(red: 0.9, green: 0.15, blue: 0.16), Theme.crimsonDark]
                                                              : [Color(white: 0.25), Color(white: 0.12)],
                                              startPoint: .top, endPoint: .bottom))
            )
            .overlay(Capsule().strokeBorder(enabled ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Color.white.opacity(0.15)), lineWidth: 2))
            .shadow(color: enabled ? Theme.crimson.opacity(c.isPressed ? 0.4 : 0.75) : .clear, radius: c.isPressed ? 8 : 18)
            .scaleEffect(c.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: c.isPressed)
    }
}

/// A dark glass card with a gold hairline, for boxes over the sky.
struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.45)))
            .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial).opacity(0.5))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.gold.opacity(0.35), lineWidth: 1))
    }
}

extension View {
    func glassCard() -> some View { modifier(GlassCard()) }
}

/// A row of pill choices (the start picker): the chosen one in gold.
struct GoldChoice<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { value, title in
                Button { selection = value } label: {
                    Text(title).font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .foregroundStyle(selection == value ? Theme.night : Theme.goldLight.opacity(0.85))
                        .background(Capsule().fill(selection == value ? AnyShapeStyle(Theme.goldGradient) : AnyShapeStyle(Color.clear)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(.black.opacity(0.45)))
        .overlay(Capsule().strokeBorder(Theme.gold.opacity(0.35), lineWidth: 1))
    }
}
