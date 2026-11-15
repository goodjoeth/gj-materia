// Core.swift - the launcher's model: folders, settings (written into FFNx.toml before Play),
// the font-width fix, a small XML reader, and the native helpers (src/mac/ff7_launcher_native.cpp,
// src/android/un7z.c, src/mac/ff7_mac_main.mm).
import Foundation
import Compression

// MARK: native

@_silgen_name("ff7_launcher_mod_info") func c_mod_info(_ path: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
@_silgen_name("ff7_launcher_mod_file") func c_mod_file(_ mod: UnsafePointer<CChar>, _ name: UnsafePointer<CChar>, _ out: UnsafePointer<CChar>) -> Int32
@_silgen_name("ff7_launcher_conflicts") func c_conflicts(_ profile: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
@_silgen_name("ff7_launcher_free") func c_free(_ p: UnsafeMutablePointer<CChar>?)
@_silgen_name("ff7_un7z") func c_un7z(_ archive: UnsafePointer<CChar>, _ out: UnsafePointer<CChar>, _ err: UnsafeMutablePointer<CChar>, _ n: Int) -> Int32
@_silgen_name("ff7_un7z_progress") func c_un7z_progress(_ done: UnsafeMutablePointer<UInt64>, _ total: UnsafeMutablePointer<UInt64>)
@_silgen_name("ff7_mac_start_game") func c_start_game(_ aspect: Int32, _ fullscreen: Int32, _ screen: UnsafePointer<CChar>)

func takeCString(_ p: UnsafeMutablePointer<CChar>?) -> String {
    guard let p else { return "" }
    let s = String(cString: p)
    c_free(p)
    return s
}

// MARK: folders

enum Paths {
    static let fm = FileManager.default
    static let base: URL = {
        if let e = ProcessInfo.processInfo.environment["FF7_HOME"] { return URL(fileURLWithPath: e) }
        return fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FF7Recomp")
    }()
    static var game: URL { base.appendingPathComponent("game") }
    static var mods: URL { base.appendingPathComponent("mods") }
    static var profile: URL { mods.appendingPathComponent("profile.xml") }
    static var downloads: URL { base.appendingPathComponent("downloads") }
    static var fixes: URL { base.appendingPathComponent("fixes") }
    static var cache: URL { base.appendingPathComponent("launcher-cache") }
    static var settings: URL { base.appendingPathComponent("launcher.json") }
    static var installed: URL { mods.appendingPathComponent("installed.json") }
    static var quickboot: URL { base.appendingPathComponent("quickboot.txt") }
    static var log: URL { base.appendingPathComponent("ff7.log") }
    static var boosters: URL { base.appendingPathComponent("boosters.txt") }
    static var saves: URL { game.appendingPathComponent("save") }
    static var savestates: URL { base.appendingPathComponent("savestates") }

    static func ensure() {
        for u in [base, mods, downloads, fixes, cache] { try? fm.createDirectory(at: u, withIntermediateDirectories: true) }
    }
    static var gameReady: Bool { fm.fileExists(atPath: game.appendingPathComponent("ff7_en.exe").path) }
}

// MARK: settings

struct Settings: Codable, Equatable {
    var fps = 3                // FFNx ff7_fps_limiter: 0 original, 1 fixed, 2 30 FPS battles, 3 60, 4 120
    var aspect = 0             // FFNx aspect_ratio: 0 4:3, 1 stretched, 2 16:9 (with uncrop), 3 16:10, 4 21:9 (an FF7Recomp mode)
    var fullscreen = false
    var vsync = true
    var showFps = false
    var crt = false
    var bilinear = false
    var antialiasing = 0       // 0, 2, 4, 8
    var resolutionScale = 0    // 0 automatic, 1-4 x 640x480
    var analog = false         // analogue controls + auto run
    var musicVolume = 100
    var sfxVolume = 100
    var language = 1           // FFNx game_language: 1 en, 2 fr, 3 de, 4 es
    var speed2x = false
    var start = "title"        // title | newgame | continue
    var ntscj = false          // FFNx enable_ntscj_gamut_mode (the Japanese PlayStation's colours)
    var rumble = 2             // 0 off, 1 light, 2 strong (src/ffnx_port/rumble.cpp)
    var autofire = false       // hold OK to repeat it in battles
    var gilMult = 1, expMult = 1, apMult = 1
    var encounters = true
    var display = ""           // the screen to play on (macOS: NSScreen name; "" the main one)
    var battleHud = 0          // 21:9 battles, the status windows: 0 where 16:9 has them, 1 halfway out, 2 at the edge

    init() {}
    // Settings saved by an older launcher lack the newer keys: each falls back to its default.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: Keys.self)
        func v<T: Decodable>(_ k: String, _ def: T) -> T { (try? c.decodeIfPresent(T.self, forKey: Keys(k))) .flatMap { $0 } ?? def }
        let z = Settings()
        fps = v("fps", z.fps); aspect = v("aspect", z.aspect); fullscreen = v("fullscreen", z.fullscreen)
        vsync = v("vsync", z.vsync); showFps = v("showFps", z.showFps); crt = v("crt", z.crt)
        bilinear = v("bilinear", z.bilinear); antialiasing = v("antialiasing", z.antialiasing)
        resolutionScale = v("resolutionScale", z.resolutionScale); analog = v("analog", z.analog)
        musicVolume = v("musicVolume", z.musicVolume); sfxVolume = v("sfxVolume", z.sfxVolume)
        language = v("language", z.language); speed2x = v("speed2x", z.speed2x); start = v("start", z.start)
        ntscj = v("ntscj", z.ntscj); rumble = v("rumble", z.rumble); autofire = v("autofire", z.autofire)
        gilMult = v("gilMult", z.gilMult); expMult = v("expMult", z.expMult); apMult = v("apMult", z.apMult)
        encounters = v("encounters", z.encounters); display = v("display", z.display)
        battleHud = v("battleHud", z.battleHud)
    }
    struct Keys: CodingKey {
        var stringValue: String; var intValue: Int? { nil }
        init(_ s: String) { stringValue = s }
        init?(stringValue s: String) { stringValue = s }
        init?(intValue: Int) { nil }
    }

    /// boosters.txt beside the game folder (src/ffnx_port/boosters.cpp reads it at the first frame).
    func writeBoosters() {
        let s = "rumble=\(rumble)\nautofire=\(autofire ? "on" : "off")\ngil=\(gilMult)\nexp=\(expMult)\nap=\(apMult)\n"
            + "encounters=\(encounters ? "on" : "off")\nbattlehud=\(battleHud)\n"
        try? s.write(to: Paths.boosters, atomically: true, encoding: .utf8)
    }

    static func load() -> Settings {
        guard let d = try? Data(contentsOf: Paths.settings),
              let s = try? JSONDecoder().decode(Settings.self, from: d) else { return Settings() }
        return s
    }
    func save() {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? e.encode(self).write(to: Paths.settings, options: .atomic)
    }
}

enum Toml {
    /// `key = value` replaced (or appended).
    static func set(_ toml: String, _ key: String, _ value: String) -> String {
        var lines = toml.components(separatedBy: "\n")
        var found = false
        for i in lines.indices {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("#") { continue }
            if let eq = t.firstIndex(of: "="), t[..<eq].trimmingCharacters(in: .whitespaces) == key {
                lines[i] = "\(key) = \(value)"; found = true
            }
        }
        if !found { lines.append("\(key) = \(value)") }
        return lines.joined(separator: "\n")
    }

    /// A mod's FFNxConfig value as TOML: numbers and booleans bare, anything else quoted.
    static func value(_ v: String) -> String {
        let l = v.lowercased()
        if l == "true" || l == "false" || Double(v) != nil { return l == "true" || l == "false" ? l : v }
        if v.hasPrefix("\"") || v.hasPrefix("[") { return v }
        return "\"" + v.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// FFNx.toml from the template with the launcher's settings, then the enabled mods' FFNxConfig
    /// (lowest priority first, so the first mod's values win, as its files do).
    static func write(_ s: Settings, mods: [InstalledMod], steam: Bool = false) throws {
        let tpl = Paths.game.appendingPathComponent("FFNx.template.toml")
        var t = try String(contentsOf: tpl, encoding: .utf8)
        t = set(t, "fullscreen", "false")
        t = set(t, "show_version", "false")
        t = set(t, "show_renderer_backend", "false")
        t = set(t, "ff7_fps_limiter", String(s.speed2x && s.fps > 3 ? 3 : s.fps))
        t = set(t, "speedhack_min", s.speed2x ? "2.0" : "1.0")
        t = set(t, "aspect_ratio", String(s.aspect))
        t = set(t, "enable_uncrop", s.aspect != 0 ? "true" : "false")
        t = set(t, "enable_vsync", s.vsync ? "true" : "false")
        t = set(t, "show_fps", s.showFps ? "true" : "false")
        t = set(t, "crt_filter", s.crt ? "true" : "false")
        t = set(t, "enable_bilinear", s.bilinear ? "true" : "false")
        t = set(t, "enable_antialiasing", String(s.antialiasing))
        t = set(t, "enable_ntscj_gamut_mode", s.ntscj ? "true" : "false")
        // Steam achievements (src/ffnx_port/steam_android.cpp + the launcher's SteamLink): on once signed in
        t = set(t, "enable_steam_achievements", steam ? "true" : "false")
        t = set(t, "trace_achievement", steam ? "true" : "false")
        t = set(t, "external_music_volume", String(s.musicVolume))
        t = set(t, "external_sfx_volume", String(s.sfxVolume))
        let langs = ["", "en", "fr", "de", "es"]
        let hasLang = s.language < langs.count && Paths.fm.fileExists(atPath: Paths.game.appendingPathComponent("data/lang-\(langs[s.language])").path)
        t = set(t, "game_language", String(hasLang ? s.language : 1))
        if s.analog {
            t = set(t, "enable_analogue_controls", "true")
            t = set(t, "enable_auto_run", "true")
        }
        for m in mods.reversed() where m.enabled {
            for f in m.info?.ffnx ?? [] where m.conditionsHold(f.when) {
                t = set(t, f.key, value(f.value))
            }
        }
        if s.resolutionScale > 0 { t = set(t, "internal_resolution_scale", String(s.resolutionScale)) }
        try t.write(to: Paths.game.appendingPathComponent("FFNx.toml"), atomically: true, encoding: .utf8)
    }
}

// MARK: the font-width fix

/// The current Steam release's kernel/window.bin gives m, M, w and W 8 pixels where the classic
/// game's font draws them 11 wide ("newcorner", "Followme"). The fixed files go into a folder the
/// game reads as a mod of lowest priority (Paths.fixes), so the install itself is never changed
/// and any font mod still wins. (src/android: GameInstall.fixFontWidths.)
enum FontFix {
    static let wide: [Int] = [0x2D, 0x37, 0x4D, 0x57]   // M, W, m, w

    static func apply() {
        for l in ["en", "fr", "de", "es"] {
            let src = Paths.game.appendingPathComponent("data/lang-\(l)/kernel/window.bin")
            let dst = Paths.fixes.appendingPathComponent("data/lang-\(l)/kernel/window.bin")
            guard let d = try? Data(contentsOf: src), let fixed = fix(d) else { continue }
            try? Paths.fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fixed.write(to: dst, options: .atomic)
        }
    }

    static func fix(_ d: Data) -> Data? {
        let b = [UInt8](d)
        func u16(_ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
        var at = 0
        for _ in 0..<2 { guard at + 6 <= b.count else { return nil }; at += 6 + u16(at) }
        guard at + 6 <= b.count else { return nil }
        let csize = u16(at)
        guard at + 6 + csize <= b.count, var widths = Gzip.inflate(Data(b[(at + 6)..<(at + 6 + csize)])) else { return nil }
        var changed = false
        for c in wide where c < widths.count && widths[c] & 31 == 8 {
            widths[c] = (widths[c] & 0xE0) | 11; changed = true
        }
        guard changed, let packed = Gzip.deflate(Data(widths)), packed.count <= 0xFFFF else { return nil }
        var o = Data(b[0..<at])
        o.append(UInt8(packed.count & 0xFF)); o.append(UInt8(packed.count >> 8))
        o.append(contentsOf: b[(at + 2)..<(at + 6)])
        o.append(packed)
        o.append(contentsOf: b[(at + 6 + csize)...])
        return o
    }
}

/// gzip with the Compression framework (raw deflate) and a CRC-32: no external tools, so it
/// works the same on iPad.
enum Gzip {
    static func inflate(_ d: Data) -> [UInt8]? {
        let b = [UInt8](d)
        guard b.count > 18, b[0] == 0x1F, b[1] == 0x8B, b[2] == 8 else { return nil }
        let flg = b[3]
        var at = 10
        if flg & 4 != 0 { at += 2 + (Int(b[at]) | Int(b[at + 1]) << 8) }
        if flg & 8 != 0 { while at < b.count && b[at] != 0 { at += 1 }; at += 1 }
        if flg & 16 != 0 { while at < b.count && b[at] != 0 { at += 1 }; at += 1 }
        if flg & 2 != 0 { at += 2 }
        let n = b.count
        let size = Int(b[n - 4]) | Int(b[n - 3]) << 8 | Int(b[n - 2]) << 16 | Int(b[n - 1]) << 24
        guard at < n - 8, size > 0, size < 64 << 20 else { return nil }
        var out = [UInt8](repeating: 0, count: size)
        let got = b.withUnsafeBufferPointer { src in
            compression_decode_buffer(&out, size, src.baseAddress! + at, n - 8 - at, nil, COMPRESSION_ZLIB)
        }
        return got == size ? out : nil
    }

    static func deflate(_ d: Data) -> Data? {
        let src = [UInt8](d)
        var dst = [UInt8](repeating: 0, count: src.count + 1024)
        let n = compression_encode_buffer(&dst, dst.count, src, src.count, nil, COMPRESSION_ZLIB)
        guard n > 0 else { return nil }
        var o = Data([0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 3])
        o.append(contentsOf: dst[0..<n])
        let c = crc32(src), len = UInt32(truncatingIfNeeded: src.count)
        for v in [c, len] { for k in 0..<4 { o.append(UInt8((v >> (8 * UInt32(k))) & 0xFF)) } }
        return o
    }

    static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }
    static func crc32(_ b: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for x in b { c = table[Int((c ^ UInt32(x)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }
}

// MARK: XML

final class XNode {
    let name: String
    var attrs: [String: String]
    var children: [XNode] = []
    var text = ""
    init(_ n: String, _ a: [String: String]) { name = n; attrs = a }

    func child(_ n: String) -> XNode? { children.first { $0.name.caseInsensitiveCompare(n) == .orderedSame } }
    func all(_ n: String) -> [XNode] { children.filter { $0.name.caseInsensitiveCompare(n) == .orderedSame } }
    func value(_ n: String) -> String { child(n)?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    func attr(_ n: String) -> String? { attrs.first { $0.key.caseInsensitiveCompare(n) == .orderedSame }?.value }
    func descendants(_ n: String) -> [XNode] { all(n) + children.flatMap { $0.descendants(n) } }
}

final class XMLReader: NSObject, XMLParserDelegate {
    private var stack: [XNode] = []
    private var root: XNode?

    static func parse(_ d: Data) -> XNode? {
        let r = XMLReader()
        let p = XMLParser(data: d)
        p.delegate = r
        _ = p.parse()
        return r.root
    }
    func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        let n = XNode(e, a)
        stack.last?.children.append(n)
        if root == nil { root = n }
        stack.append(n)
    }
    func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) { _ = stack.popLast() }
    func parser(_ p: XMLParser, foundCharacters s: String) { stack.last?.text += s }
}

func xmlEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
}
