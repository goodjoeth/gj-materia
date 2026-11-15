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
    @Published var banner: (title: String, points: Int)?
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
                HStack(spacing: 12 * s) {
                    Spacer()
                    if model.speed > 1 {
                        badge(Color(red: 0.18, green: 0.54, blue: 0.34), s) {
                            VStack(spacing: 0) {
                                Image(systemName: "forward.fill").font(.system(size: 24 * s, weight: .bold))
                                Text("\(model.speed)×").font(.system(size: 22 * s, weight: .heavy))
                            }
                        }
                    }
                    if model.noBattles {
                        badge(Color(red: 0.18, green: 0.37, blue: 0.66), s) {
                            ZStack {
                                Image(systemName: "exclamationmark").font(.system(size: 34 * s, weight: .heavy))
                                Rectangle().frame(width: 44 * s, height: 5 * s).rotationEffect(.degrees(-45))
                            }
                        }
                    }
                    if model.battlePlus {
                        badge(Color(red: 0.69, green: 0.19, blue: 0.29), s) {
                            Image(systemName: "heart.fill").font(.system(size: 30 * s, weight: .bold))
                                .overlay(Image(systemName: "plus").font(.system(size: 16 * s, weight: .heavy)).foregroundStyle(Color(red: 0.69, green: 0.19, blue: 0.29)))
                        }
                    }
                }
                .padding(.top, 22 * s).padding(.trailing, 22 * s)
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
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.25), value: model.banner?.title)
    }

    func badge<C: View>(_ color: Color, _ s: CGFloat, @ViewBuilder _ content: () -> C) -> some View {
        content().foregroundStyle(.white)
            .frame(width: 64 * s, height: 64 * s)
            .background(RoundedRectangle(cornerRadius: 14 * s).fill(color.opacity(0.8)))
            .overlay(RoundedRectangle(cornerRadius: 14 * s).stroke(.white.opacity(0.7), lineWidth: 2.5 * s))
    }
}

#if os(macOS)
private var overlayModel: OverlayModel?

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
