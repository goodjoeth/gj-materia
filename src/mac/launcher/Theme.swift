// Theme.swift - the launcher's look, after the app icon: a dark crimson night, a red Meteor, gunmetal
// and gold. Colours, the Play page's sky, the gold title, the crimson Play button and the dark
// glass cards the pages put their boxes on. SwiftUI only, so an iPad build shares it.
import SwiftUI

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

/// The Play page's background: a dark crimson night with the red Meteor up and right, a few stars,
/// and a cloak's dark folds along the bottom.
struct MeteorSky: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let r = min(w, h) * 0.17
            ZStack {
                LinearGradient(colors: [Color(red: 0.2, green: 0.04, blue: 0.06), Theme.night, Color(red: 0.02, green: 0.02, blue: 0.03)],
                               startPoint: .top, endPoint: .bottom)
                // stars
                ForEach(0..<28, id: \.self) { i in
                    let x = CGFloat((i * 137) % 1000) / 1000, y = CGFloat((i * 251) % 1000) / 1000 * 0.6
                    Circle().fill(.white.opacity(0.25 + Double(i % 4) * 0.12))
                        .frame(width: CGFloat(1 + i % 3), height: CGFloat(1 + i % 3))
                        .position(x: x * w, y: y * h)
                }
                // the Meteor and its glow
                Circle()
                    .fill(RadialGradient(colors: [Theme.ember.opacity(0.45), .clear], center: .center, startRadius: r * 0.8, endRadius: r * 2.2))
                    .frame(width: r * 4.4, height: r * 4.4)
                    .position(x: w * 0.8, y: h * 0.18)
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 1, green: 0.85, blue: 0.45), Theme.ember, Theme.crimson, Theme.crimsonDark],
                                         center: UnitPoint(x: 0.38, y: 0.62), startRadius: 0, endRadius: r))
                    .frame(width: r * 2, height: r * 2)
                    .overlay(Circle().fill(Color(red: 0.3, green: 0.03, blue: 0.03).opacity(0.18)).blur(radius: r * 0.08).frame(width: r * 0.6, height: r * 0.45).offset(x: r * 0.35, y: -r * 0.3))
                    .overlay(Circle().fill(Color(red: 0.3, green: 0.03, blue: 0.03).opacity(0.15)).blur(radius: r * 0.08).frame(width: r * 0.45, height: r * 0.55).offset(x: -r * 0.45, y: r * 0.35))
                    .position(x: w * 0.8, y: h * 0.18)
                    .opacity(0.9)
                // the cloak's folds
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
