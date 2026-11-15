// Keymap.swift - the keyboard's buttons, changed on the Controls page. Saved as keymap.txt beside
// the game folder ("name keycode keycode ..."), which src/mac/ff7_mac_main.mm load_keymap reads
// when the game starts. Key codes are macOS virtual key codes (Carbon kVK_*).
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct Keymap: Equatable {
    struct Button { let name: String; let title: String; let defaults: [UInt16] }
    static let buttons: [Button] = [
        Button(name: "up", title: "ขึ้น", defaults: [126]),
        Button(name: "down", title: "ลง", defaults: [125]),
        Button(name: "left", title: "ซ้าย", defaults: [123]),
        Button(name: "right", title: "ขวา", defaults: [124]),
        Button(name: "ok", title: "ตกลง (○)", defaults: [36, 76, 40]),
        Button(name: "cancel", title: "ยกเลิก (×)", defaults: [51, 38]),
        Button(name: "menu", title: "เมนู (△)", defaults: [49, 34]),
        Button(name: "square", title: "□", defaults: [56, 60, 32]),
        Button(name: "l1", title: "L1", defaults: [12]),
        Button(name: "r1", title: "R1", defaults: [13]),
        Button(name: "l2", title: "L2", defaults: [18]),
        Button(name: "r2", title: "R2", defaults: [19]),
        Button(name: "select", title: "Select", defaults: [48]),
        Button(name: "start", title: "Start", defaults: [35]),
        Button(name: "l3", title: "L3 (โหมด shortcut)", defaults: [37]),
        Button(name: "r3", title: "R3", defaults: [15]),
    ]
    var keys: [String: [UInt16]]

    static var file: URL { Paths.base.appendingPathComponent("keymap.txt") }
    static var standard: Keymap { Keymap(keys: Dictionary(uniqueKeysWithValues: buttons.map { ($0.name, $0.defaults) })) }

    static func load() -> Keymap {
        var m = standard
        guard let s = try? String(contentsOf: file, encoding: .utf8) else { return m }
        var read: [String: [UInt16]] = [:]
        for l in s.split(separator: "\n") {
            let f = l.split(separator: " ")
            guard let n = f.first.map(String.init), buttons.contains(where: { $0.name == n }) else { continue }
            read[n] = f.dropFirst().compactMap { UInt16($0) }
        }
        if !read.isEmpty { m.keys = Dictionary(uniqueKeysWithValues: buttons.map { ($0.name, read[$0.name] ?? []) }) }
        return m
    }

    func save() {
        if self == Self.standard { try? Paths.fm.removeItem(at: Self.file); return }
        let s = Self.buttons.map { b in ([b.name] + (keys[b.name] ?? []).map(String.init)).joined(separator: " ") }.joined(separator: "\n") + "\n"
        try? s.write(to: Self.file, atomically: true, encoding: .utf8)
    }

    /// Give `key` to `button` (taken from whichever button had it).
    mutating func assign(_ key: UInt16, to button: String) {
        for k in keys.keys { keys[k]?.removeAll { $0 == key } }
        keys[button, default: []].append(key)
    }

    /// The keys the game keeps for itself (F1: achievements; Escape closes the panel).
    static let reserved: Set<UInt16> = [122, 53]

    static func keyName(_ k: UInt16) -> String {
        let named: [UInt16: String] = [
            126: "↑", 125: "↓", 123: "←", 124: "→", 36: "Return", 76: "Enter (keypad)", 51: "Delete", 117: "Del ⌦",
            49: "Space", 48: "Tab", 53: "Esc", 56: "Shift", 60: "Shift ขวา", 59: "Control", 62: "Control ขวา",
            58: "Option", 61: "Option ขวา", 57: "Caps Lock", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            82: "0 (keypad)", 83: "1 (keypad)", 84: "2 (keypad)", 85: "3 (keypad)", 86: "4 (keypad)", 87: "5 (keypad)",
            88: "6 (keypad)", 89: "7 (keypad)", 91: "8 (keypad)", 92: "9 (keypad)", 65: ". (keypad)", 67: "* (keypad)",
            69: "+ (keypad)", 78: "- (keypad)", 75: "/ (keypad)",
        ]
        if let n = named[k] { return n }
        let letters: [UInt16: String] = [
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L", 46: "M",
            45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
            27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 50: "`",
        ]
        return letters[k] ?? "คีย์ \(k)"
    }

    func text(_ button: String) -> String {
        let k = keys[button] ?? []
        return k.isEmpty ? "—" : k.map(Self.keyName).joined(separator: " หรือ ")
    }
}

/// The Controls page's keyboard section: each button's keys; "เปลี่ยน" waits for the next key.
struct KeymapEditor: View {
    @Binding var map: Keymap
    @State private var waiting: String?
    @State private var note: String?
    #if os(macOS)
    @State private var monitor: Any?
    #endif

    var body: some View {
        Section {
            ForEach(Keymap.buttons, id: \.name) { b in
                HStack {
                    Text(b.title).frame(width: 170, alignment: .leading)
                    Text(waiting == b.name ? "กดปุ่มที่ต้องการ… (Esc ยกเลิก)" : map.text(b.name))
                        .monospaced().foregroundStyle(waiting == b.name ? Color.accentColor : .primary)
                    Spacer()
                    if map.keys[b.name] != b.defaults {
                        Button("ค่าเดิม") { map.keys[b.name] = []; for k in b.defaults { map.assign(k, to: b.name) }; map.save() }
                            .buttonStyle(.borderless)
                    }
                    Button(waiting == b.name ? "ยกเลิก" : "เปลี่ยน") { waiting == b.name ? stop() : listen(b.name, add: false) }
                    Button("เพิ่ม") { listen(b.name, add: true) }.disabled(waiting != nil)
                }
            }
            HStack {
                if let n = note { Text(n).font(.footnote).foregroundStyle(.secondary) }
                Spacer()
                Button("คืนค่าเริ่มต้นทั้งหมด") { map = .standard; map.save(); note = nil }.disabled(map == .standard)
            }
        } header: { Text("ปุ่มคีย์บอร์ด") } footer: {
            Text("มีผลตอนเริ่มเกมครั้งถัดไป F1 (achievement), Esc และปุ่มที่กดพร้อม Cmd เป็นของแอป ใช้แทนปุ่มเกมไม่ได้ ปุ่มจอยเปลี่ยนในเกมที่ Config > Controller")
                .font(.footnote)
        }
        .onDisappear { stop() }
    }

    func listen(_ button: String, add: Bool) {
        #if os(macOS)
        stop()
        waiting = button
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { e in
            let k = e.keyCode
            if e.type == .flagsChanged {
                // a modifier counts when it goes down
                let down: Bool
                switch k {
                case 56, 60: down = e.modifierFlags.contains(.shift)
                case 59, 62: down = e.modifierFlags.contains(.control)
                case 58, 61: down = e.modifierFlags.contains(.option)
                case 57: down = e.modifierFlags.contains(.capsLock)
                default: return e
                }
                if !down { return nil }
            } else if e.modifierFlags.contains(.command) {
                return e
            }
            if k == 53 { stop(); return nil }
            if Keymap.reserved.contains(k) || k >= 128 { note = "\(Keymap.keyName(k)) ใช้ไม่ได้ (แอปใช้อยู่)"; return nil }
            let had = Keymap.buttons.first { map.keys[$0.name]?.contains(k) == true && $0.name != button }
            if !add { map.keys[button] = [] }
            map.assign(k, to: button)
            map.save()
            note = had.map { "\(Keymap.keyName(k)) ย้ายมาจาก \($0.title) แล้ว" }
            stop()
            return nil
        }
        #endif
    }

    func stop() {
        #if os(macOS)
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        #endif
        waiting = nil
    }
}
