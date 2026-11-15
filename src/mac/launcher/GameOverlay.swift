// GameOverlay.swift - drawn over the game, not by it (src/android BoosterIcons.java): the game
// boosters' icons in the top-right corner while one is on (speed 2x / 3x, random battles off,
// battle enhancement) and the "Achievement unlocked" banner. Their state comes from the companion
// snapshot (src/ffnx_port/companion.cpp ff7_companion_json), polled twice a second. SwiftUI, so an
// iPad build hosts the same view over its game view.
import SwiftUI
#if os(macOS)
import AppKit
#endif

@_silgen_name("ff7_companion_json") func c_companion_json(_ out: UnsafeMutablePointer<CChar>, _ cap: Int32) -> Int32

@MainActor
final class OverlayModel: ObservableObject {
    @Published var speed = 1
    @Published var noBattles = false
    @Published var battlePlus = false
    let iconStyle = Settings.load().boosterIcons         // Settings > the special modes' icons
    @Published var banner: (title: String, points: Int)?
    // the achievements panel (F1 / Select+Triangle): both sets, scrolled with up / down
    @Published var panelOpen = false
    @Published var scroll = 0
    @Published var local: [Achievement] = []
    @Published var steam: [SteamLink.Item] = []
    func reloadLists() {
        local = Achievements.load()
        steam = SteamLink.readState()
    }
    private var achSeq: Int64 = -1
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func poll() {
        var buf = [CChar](repeating: 0, count: 16384)
        guard c_companion_json(&buf, Int32(buf.count)) > 0,
              let j = try? JSONSerialization.jsonObject(with: Data(String(cString: buf).utf8)) as? [String: Any],
              (j["ready"] as? Int) == 1 else { return }
        let sp = max(1, j["speed"] as? Int ?? 1), nb = (j["noenc"] as? Int) == 1, bp = (j["bplus"] as? Int) == 1
        if sp != speed { speed = sp }
        if nb != noBattles { noBattles = nb }
        if bp != battlePlus { battlePlus = bp }
        let seq = (j["achseq"] as? NSNumber)?.int64Value ?? 0
        if achSeq >= 0, seq != achSeq, seq > 0 {
            banner = (j["ach"] as? String ?? "", j["achpts"] as? Int ?? 0)
            if panelOpen { reloadLists() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.banner = nil }
        }
        achSeq = seq
    }
}

struct GameOverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        GeometryReader { g in
            let s = g.size.height / 1080                       // sizes as on a 1080-high screen
            ZStack(alignment: .top) {
                HStack(alignment: .top) {
                    Spacer()
                    BoosterIcons(speed: model.speed, noBattles: model.noBattles, battlePlus: model.battlePlus, style: model.iconStyle, s: s)
                }
                .padding(.top, 20 * s).padding(.trailing, 24 * s)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: model.speed)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: model.noBattles)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: model.battlePlus)
                if let b = model.banner {
                    HStack(spacing: 20 * s) {
                        Image(systemName: "star.fill").font(.system(size: 54 * s)).foregroundStyle(Color(red: 0.91, green: 0.76, blue: 0.35))
                        VStack(alignment: .leading, spacing: 4 * s) {
                            Text("Achievement unlocked").font(.system(size: 28 * s, weight: .bold)).foregroundStyle(Color(red: 0.91, green: 0.76, blue: 0.35))
                            Text(b.title + (b.points > 0 ? "  (\(b.points))" : "")).font(.system(size: 36 * s, weight: .bold)).foregroundStyle(.white)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 28 * s).frame(width: 760 * s, height: 112 * s)
                    .background(RoundedRectangle(cornerRadius: 22 * s).fill(Color(red: 0.08, green: 0.1, blue: 0.2).opacity(0.9)))
                    .overlay(RoundedRectangle(cornerRadius: 22 * s).stroke(Color(red: 0.91, green: 0.76, blue: 0.35), lineWidth: 3 * s))
                    .padding(.top, 24 * s)
                    .transition(.opacity)
                }
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .top)
            if model.panelOpen { AchievementsPanel(model: model, scale: s).frame(width: g.size.width, height: g.size.height).transition(.opacity) }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.15), value: model.panelOpen)
        .animation(.easeInOut(duration: 0.25), value: model.banner?.title)
    }
}

/// The special modes' icons, top right while a mode is on, in the style chosen in Settings:
/// 0 Materia orbs, 1 the classic squares, 2 one compact strip (the default), 3 none. Also the Settings preview.
struct BoosterIcons: View {
    let speed: Int
    let noBattles: Bool
    let battlePlus: Bool
    let style: Int
    let s: CGFloat
    static let styles = ["ลูก Materia", "สี่เหลี่ยมแบบเดิม", "แถบเล็ก", "ไม่แสดง"]   // default 2 (Settings)
    static let yellow = Color(red: 0.98, green: 0.78, blue: 0.16), purple = Color(red: 0.62, green: 0.3, blue: 0.95),
               red = Color(red: 0.95, green: 0.16, blue: 0.16), gold = Color(red: 1, green: 0.88, blue: 0.55)

    var body: some View {
        Group {
            switch style {
            case 1: classic
            case 2: compact
            case 3: EmptyView()
            default: orbs
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: speed)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: noBattles)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: battlePlus)
    }

    // Materia colours: command (yellow), independent (purple), summon (red)
    var orbs: some View {
        HStack(alignment: .top, spacing: 14 * s) {
            if speed > 1 {
                BoosterOrb(core: Self.yellow, label: "SPEED", s: s) {
                    HStack(spacing: -6 * s) { Image(systemName: "chevron.right"); Image(systemName: "chevron.right") }
                        .font(.system(size: 22 * s, weight: .black))
                        .overlay(alignment: .bottom) {
                            Text("\(speed)×").font(.system(size: 17 * s, weight: .heavy, design: .rounded)).offset(y: 18 * s)
                        }
                        .offset(y: -6 * s)
                }
            }
            if noBattles {
                BoosterOrb(core: Self.purple, label: "NO BATTLES", s: s) {
                    ZStack {
                        Text("!").font(.system(size: 38 * s, weight: .black, design: .serif))
                        Capsule().frame(width: 46 * s, height: 5 * s).rotationEffect(.degrees(-45)).shadow(color: .black.opacity(0.6), radius: 1 * s)
                    }
                }
            }
            if battlePlus {
                BoosterOrb(core: Self.red, label: "BATTLE+", s: s) {
                    Image(systemName: "heart.fill").font(.system(size: 30 * s, weight: .bold))
                        .overlay(Image(systemName: "plus").font(.system(size: 15 * s, weight: .black)).foregroundStyle(Color(red: 0.55, green: 0.04, blue: 0.06)))
                }
            }
        }
        .padding(.top, 20 * s).padding(.trailing, 24 * s)
    }

    // the first icons: coloured squares
    var classic: some View {
        HStack(spacing: 12 * s) {
            if speed > 1 {
                square(Color(red: 0.18, green: 0.54, blue: 0.34)) {
                    VStack(spacing: 0) {
                        Image(systemName: "forward.fill").font(.system(size: 24 * s, weight: .bold))
                        Text("\(speed)×").font(.system(size: 22 * s, weight: .heavy))
                    }
                }
            }
            if noBattles {
                square(Color(red: 0.18, green: 0.37, blue: 0.66)) {
                    ZStack {
                        Image(systemName: "exclamationmark").font(.system(size: 34 * s, weight: .heavy))
                        Rectangle().frame(width: 44 * s, height: 5 * s).rotationEffect(.degrees(-45))
                    }
                }
            }
            if battlePlus {
                square(Color(red: 0.69, green: 0.19, blue: 0.29)) {
                    Image(systemName: "heart.fill").font(.system(size: 30 * s, weight: .bold))
                        .overlay(Image(systemName: "plus").font(.system(size: 16 * s, weight: .heavy)).foregroundStyle(Color(red: 0.69, green: 0.19, blue: 0.29)))
                }
            }
        }
        .padding(.top, 22 * s).padding(.trailing, 22 * s)
    }

    func square<C: View>(_ color: Color, @ViewBuilder _ content: () -> C) -> some View {
        content().foregroundStyle(.white)
            .frame(width: 64 * s, height: 64 * s)
            .background(RoundedRectangle(cornerRadius: 14 * s).fill(color.opacity(0.8)))
            .overlay(RoundedRectangle(cornerRadius: 14 * s).stroke(.white.opacity(0.7), lineWidth: 2.5 * s))
            .transition(.scale(scale: 0.5).combined(with: .opacity))
    }

    // one small strip: a coloured dot and a word per mode, out of the way
    var compact: some View {
        HStack(spacing: 14 * s) {
            if speed > 1 { chip(Self.yellow, "\(speed)×", "forward.fill") }
            if noBattles { chip(Self.purple, "NO BATTLES", "exclamationmark") }
            if battlePlus { chip(Self.red, "BATTLE+", "heart.fill") }
        }
        .padding(.horizontal, 14 * s).padding(.vertical, 7 * s)
        .background(Capsule().fill(.black.opacity(0.55)))
        .overlay(Capsule().stroke(Self.gold.opacity(0.6), lineWidth: 1.5 * s))
        .opacity(speed > 1 || noBattles || battlePlus ? 1 : 0)
        .padding(.top, 18 * s).padding(.trailing, 20 * s)
    }

    func chip(_ c: Color, _ text: String, _ symbol: String) -> some View {
        HStack(spacing: 6 * s) {
            Image(systemName: symbol).font(.system(size: 13 * s, weight: .black)).foregroundStyle(.white)
                .frame(width: 24 * s, height: 24 * s).background(Circle().fill(c)).shadow(color: c.opacity(0.8), radius: 4 * s)
            Text(text).font(.system(size: 15 * s, weight: .heavy, design: .rounded)).foregroundStyle(Self.gold)
        }
        .transition(.opacity)
    }
}

/// A special mode's icon (top right while it is on): a Materia orb in the mode's colour, held in a
/// gunmetal-and-gold setting like the app icon, its sign in white, its name under it.
struct BoosterOrb<Glyph: View>: View {
    let core: Color
    let label: String
    let s: CGFloat
    @ViewBuilder var glyph: () -> Glyph

    var body: some View {
        VStack(spacing: 5 * s) {
            ZStack {
                // the setting: a gold ring on a dark steel disc
                Circle().fill(LinearGradient(colors: [Color(white: 0.42), Color(white: 0.12)], startPoint: .top, endPoint: .bottom))
                Circle().strokeBorder(LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.55), Color(red: 0.86, green: 0.6, blue: 0.18),
                                                              Color(red: 0.5, green: 0.3, blue: 0.06)], startPoint: .top, endPoint: .bottom),
                                      lineWidth: 4 * s)
                // the orb
                Circle()
                    .fill(RadialGradient(colors: [core.opacity(1), core.opacity(0.85), .black.opacity(0.85)],
                                         center: UnitPoint(x: 0.38, y: 0.32), startRadius: 0, endRadius: 34 * s))
                    .padding(8 * s)
                    .shadow(color: core.opacity(0.8), radius: 8 * s)
                glyph().foregroundStyle(.white).shadow(color: .black.opacity(0.7), radius: 2 * s, y: 1 * s)
                // glass highlight
                Ellipse().fill(LinearGradient(colors: [.white.opacity(0.65), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 30 * s, height: 16 * s).offset(x: -9 * s, y: -17 * s)
            }
            .frame(width: 76 * s, height: 76 * s)
            .shadow(color: .black.opacity(0.6), radius: 6 * s, y: 3 * s)
            Text(label).font(.system(size: 12 * s, weight: .heavy, design: .rounded)).tracking(1 * s)
                .foregroundStyle(Color(red: 1, green: 0.88, blue: 0.55))
                .padding(.horizontal, 7 * s).padding(.vertical, 2 * s)
                .background(Capsule().fill(.black.opacity(0.6)))
        }
        .transition(.scale(scale: 0.5).combined(with: .opacity))
    }
}

/// The achievements panel over the game: progress, then every achievement (Steam's first when
/// signed in), the unlocked ones first; a window of rows moved with up / down.
struct AchievementsPanel: View {
    @ObservedObject var model: OverlayModel
    let scale: CGFloat
    struct Row: Identifiable { let id: String; let title: String; let detail: String; let got: Bool; let points: Int? }

    var rows: [Row] {
        var r: [Row] = []
        for a in model.steam.sorted(by: { ($0.got ? 0 : 1, $0.display) < ($1.got ? 0 : 1, $1.display) }) {
            r.append(Row(id: "s" + a.name, title: a.display, detail: SteamLink.shownDesc(a), got: a.got, points: nil))
        }
        for a in model.local.sorted(by: { ($0.unlocked != nil ? 0 : 1, $0.id) < ($1.unlocked != nil ? 0 : 1, $1.id) }) {
            r.append(Row(id: "l\(a.id)", title: a.title, detail: a.description, got: a.unlocked != nil, points: a.points))
        }
        return r
    }

    var body: some View {
        let s = max(scale, 0.55)
        let all = rows
        let visible = 9
        let start = min(max(0, model.scroll), max(0, all.count - visible))
        VStack(alignment: .leading, spacing: 14 * s) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "trophy.fill").foregroundStyle(Color(red: 0.91, green: 0.76, blue: 0.35))
                Text("Achievements").font(.system(size: 40 * s, weight: .bold))
                Spacer()
                if !model.steam.isEmpty {
                    Text("Steam \(model.steam.filter { $0.got }.count)/\(model.steam.count)").font(.system(size: 26 * s, weight: .semibold))
                }
                Text("ออฟไลน์ \(model.local.filter { $0.unlocked != nil }.count)/\(model.local.count) · \(model.local.filter { $0.unlocked != nil }.reduce(0) { $0 + $1.points }) แต้ม")
                    .font(.system(size: 26 * s, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
            }
            ForEach(all[start..<min(all.count, start + visible)]) { row in
                HStack(spacing: 16 * s) {
                    Image(systemName: row.got ? "trophy.fill" : "lock.fill").font(.system(size: 28 * s))
                        .foregroundStyle(row.got ? Color(red: 0.91, green: 0.76, blue: 0.35) : .white.opacity(0.4)).frame(width: 40 * s)
                    VStack(alignment: .leading, spacing: 2 * s) {
                        Text(row.title).font(.system(size: 28 * s, weight: .semibold))
                        Text(row.detail).font(.system(size: 20 * s)).foregroundStyle(.white.opacity(0.65)).lineLimit(2)
                    }
                    Spacer()
                    if let p = row.points { Text("\(p)").font(.system(size: 24 * s).monospacedDigit()).foregroundStyle(.white.opacity(0.7)) }
                }
                .opacity(row.got ? 1 : 0.6)
            }
            if all.isEmpty { Text("ยังไม่มีข้อมูล achievement").font(.system(size: 26 * s)) }
            Text("▲▼ เลื่อน   ·   F1 หรือ Select+△ หรือ × ปิด   ·   \(all.isEmpty ? 0 : start + 1)–\(min(all.count, start + visible)) จาก \(all.count)")
                .font(.system(size: 20 * s)).foregroundStyle(.white.opacity(0.6))
        }
        .foregroundStyle(.white)
        .padding(36 * s)
        .frame(width: 1100 * s)
        .background(RoundedRectangle(cornerRadius: 26 * s).fill(Color(red: 0.06, green: 0.08, blue: 0.16).opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 26 * s).stroke(Color(red: 0.91, green: 0.76, blue: 0.35).opacity(0.8), lineWidth: 2.5 * s))
    }
}

#if os(macOS)
private var overlayModel: OverlayModel?

/// F1 / Select+Triangle (src/mac/ff7_mac_main.mm): open or close the achievements panel.
@_cdecl("ff7_overlay_set_achievements")
public func ff7_overlay_set_achievements(_ open: Int32) {
    MainActor.assumeIsolated {
        guard let m = overlayModel else { return }
        if open != 0 { m.reloadLists(); m.scroll = 0 }
        m.panelOpen = open != 0
    }
}

@_cdecl("ff7_overlay_scroll")
public func ff7_overlay_scroll(_ by: Int32) {
    MainActor.assumeIsolated { overlayModel?.scroll = max(0, (overlayModel?.scroll ?? 0) + Int(by)) }
}

/// The achievements in a window of their own (the app menu's Achievements…): the game keeps running.
private var achWindow: NSWindow?
@_cdecl("ff7_achievements_window")
public func ff7_achievements_window() {
    MainActor.assumeIsolated {
        if let w = achWindow { w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "Achievements"
        w.isReleasedWhenClosed = false
        w.contentViewController = NSHostingController(rootView: AchievementsView(steam: SteamLink()).frame(minWidth: 520, minHeight: 500))
        w.center()
        w.makeKeyAndOrderFront(nil)
        achWindow = w
    }
}

/// Put the overlay over the game's view (src/mac/ff7_mac_main.mm, when the game window opens).
@_cdecl("ff7_overlay_attach")
public func ff7_overlay_attach(_ view: UnsafeMutableRawPointer) {
    MainActor.assumeIsolated {
        let host = Unmanaged<NSView>.fromOpaque(view).takeUnretainedValue()
        let m = OverlayModel()
        overlayModel = m
        let v = NSHostingView(rootView: GameOverlayView(model: m))
        v.frame = host.bounds
        v.autoresizingMask = [.width, .height]
        host.addSubview(v)
    }
}
#endif
