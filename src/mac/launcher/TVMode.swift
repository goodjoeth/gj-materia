// TVMode.swift - the launcher for a controller (on a TV, an AirPlay display, the couch): big
// tiles moved through with the D-pad, values changed with left / right, A to choose, B to leave,
// Start to play. Opens by itself when a controller button is pressed in the launcher.
// GameController + SwiftUI only, so an iPad (or Apple TV) build uses it as it is.
import SwiftUI
import GameController
#if os(macOS)
import AppKit
#endif

@MainActor
final class PadInput: ObservableObject {
    enum Button { case up, down, left, right, a, b, start, lb, rb }
    var onPress: ((Button) -> Void)?
    static var suspended = false   // iPhone / iPad: the game runs (LauncherIOS.swift)
    private var timer: Timer?
    private var held: Set<Button> = []
    private var repeatAt: [Button: Date] = [:]

    init() {
        GCController.shouldMonitorBackgroundEvents = false
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    /// Edge-triggered presses, with auto-repeat for the D-pad.
    private func poll() {
        if Self.suspended { held = []; return }
        var now: Set<Button> = []
        for c in GCController.controllers() {
            guard let g = c.extendedGamepad else { continue }
            if g.dpad.up.isPressed || g.leftThumbstick.yAxis.value > 0.6 { now.insert(.up) }
            if g.dpad.down.isPressed || g.leftThumbstick.yAxis.value < -0.6 { now.insert(.down) }
            if g.dpad.left.isPressed || g.leftThumbstick.xAxis.value < -0.6 { now.insert(.left) }
            if g.dpad.right.isPressed || g.leftThumbstick.xAxis.value > 0.6 { now.insert(.right) }
            if g.buttonA.isPressed { now.insert(.a) }
            if g.buttonB.isPressed { now.insert(.b) }
            if g.buttonMenu.isPressed { now.insert(.start) }
            if g.leftShoulder.isPressed { now.insert(.lb) }
            if g.rightShoulder.isPressed { now.insert(.rb) }
        }
        let t = Date()
        for b in now {
            if !held.contains(b) { onPress?(b); repeatAt[b] = t.addingTimeInterval(0.4) }
            else if [.up, .down, .left, .right].contains(b), let r = repeatAt[b], t >= r { onPress?(b); repeatAt[b] = t.addingTimeInterval(0.12) }
        }
        held = now
    }
}

struct TVModeView: View {
    @ObservedObject var state: LauncherState
    @ObservedObject var library: ModLibrary
    @ObservedObject var pad: PadInput
    let close: () -> Void
    @State private var focus = 0

    enum Row { case play(String, String, String), setting(String, () -> String, (Int) -> Void), mod(InstalledMod), leave }

    var rows: [Row] {
        var r: [Row] = [
            .play(L("เล่นต่อจากเซฟล่าสุด", "Continue from the last save"), "continue", "play.fill"),
            .play(L("เกมใหม่", "New game"), "newgame", "sparkles"),
            .play(L("หน้าไตเติล", "Title screen"), "title", "house"),
            .setting(L("อัตราส่วนจอ", "Aspect ratio"), { ["4:3", L("ยืด", "Stretch"), "16:9", "16:10", "21:9"][min(4, state.settings.aspect)] },
                     { d in state.settings.aspect = [0, 2, 3, 4, 1][((([0, 2, 3, 4, 1].firstIndex(of: state.settings.aspect) ?? 0) + d) % 5 + 5) % 5] }),
            .setting("Frame rate", { [L("ต้นฉบับ", "Original"), L("ต้นฉบับ (แก้จังหวะ)", "Original (fixed timing)"), L("ต่อสู้ 30", "Battles 30"), "60 FPS", "120 FPS"][state.settings.fps] },
                     { d in state.settings.fps = ((state.settings.fps + d) % 5 + 5) % 5 }),
            .setting(L("เต็มจอ", "Full screen"), { state.settings.fullscreen ? L("เปิด", "On") : L("ปิด", "Off") }, { _ in state.settings.fullscreen.toggle() }),
            .setting(L("การสั่นของจอย", "Controller rumble"), { [L("ปิด", "Off"), L("เบา", "Light"), L("แรง", "Strong")][state.settings.rumble] }, { d in state.settings.rumble = ((state.settings.rumble + d) % 3 + 3) % 3 }),
        ]
        #if os(macOS)
        let screens = [""] + NSScreen.screens.dropFirst().map { $0.localizedName }
        if screens.count > 1 {
            r.append(.setting(L("จอที่ใช้เล่น", "Display"), { state.settings.display.isEmpty ? L("จอหลัก", "Main display") : state.settings.display }, { d in
                let i = screens.firstIndex(of: state.settings.display) ?? 0
                state.settings.display = screens[((i + d) % screens.count + screens.count) % screens.count]
            }))
        }
        #endif
        r += library.mods.map { .mod($0) }
        r.append(.leave)
        return r
    }

    var body: some View {
        let list = rows
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.08, blue: 0.18), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("FINAL FANTASY VII").font(.system(size: 44, weight: .bold, design: .serif)).foregroundStyle(.white)
                    Spacer()
                    Text(L("Ⓐ เลือก   Ⓑ ออก   ◀▶ เปลี่ยนค่า   START เล่นต่อ", "Ⓐ select   Ⓑ back   ◀▶ change   START resume")).font(.title3).foregroundStyle(.white.opacity(0.6))
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(list.enumerated()), id: \.offset) { i, row in
                                tile(row, focused: i == focus).id(i)
                                if i == 2 { section(L("ตั้งค่า", "Settings")) }
                                if case .setting = row, i + 1 < list.count, case .mod = list[i + 1] { section(L("ม็อด", "Mods")) }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .onChange(of: focus) { f in withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(f, anchor: .center) } }
                }
            }
            .padding(48)
        }
        .onAppear { pad.onPress = { press($0) } }
    }

    func section(_ t: String) -> some View {
        Text(t).font(.title2.bold()).foregroundStyle(.white.opacity(0.5)).padding(.top, 14)
    }

    @ViewBuilder func tile(_ row: Row, focused: Bool) -> some View {
        HStack(spacing: 16) {
            switch row {
            case .play(let title, _, let icon):
                Image(systemName: icon).font(.title); Text(title).font(.title.bold()); Spacer()
            case .setting(let title, let value, _):
                Text(title).font(.title2); Spacer()
                Text("◀  \(value())  ▶").font(.title2.monospacedDigit()).foregroundStyle(focused ? .white : .white.opacity(0.7))
            case .mod(let m):
                Image(systemName: m.enabled ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(m.enabled ? .green : .white.opacity(0.5))
                Text(m.title).font(.title2); Spacer()
                Text(m.info?.category ?? "").foregroundStyle(.white.opacity(0.5))
            case .leave:
                Image(systemName: "xmark.circle"); Text(L("ออกจากโหมดทีวี", "Leave TV mode")).font(.title2); Spacer()
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14).fill(focused ? Color.blue.opacity(0.55) : Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(focused ? Color.white.opacity(0.9) : .clear, lineWidth: 2))
        .scaleEffect(focused ? 1.02 : 1)
        .animation(.easeOut(duration: 0.12), value: focused)
    }

    func press(_ b: PadInput.Button) {
        let list = rows
        switch b {
        case .up: focus = max(0, focus - 1)
        case .down: focus = min(list.count - 1, focus + 1)
        case .lb: focus = 0
        case .rb: focus = list.count - 1
        case .b: close()
        case .start: state.settings.start = "continue"; state.play()
        case .left, .right, .a:
            let d = b == .left ? -1 : 1
            switch list[focus] {
            case .play(_, let mode, _): if b == .a { state.settings.start = mode; state.play() }
            case .setting(_, _, let change): change(d)
            case .mod(let m): if b == .a { library.setEnabled(m, !m.enabled) }
            case .leave: if b == .a { close() }
            }
        }
    }
}
