// GameFiles.swift - the game folder (~/Library/Application Support/FF7Recomp/game): importing the
// player's own FINAL FANTASY VII (Steam) into it, and the run-time files this app carries
// (FFNx's settings and tables, Metal shaders, NTSC-J LUTs: Resources/ffnx). Only the exe this
// app was lifted from is accepted (Resources/ff7_en.sha1), as the game's code is built into it.
// Also, on macOS, re-lifting for the enabled mods' code patches (tools/relift_mods_mac.sh).
import Foundation
import CryptoKit

@MainActor
final class GameFiles: ObservableObject {
    @Published var busy: String?
    @Published var progress: Double = 0
    @Published var message: String?
    @Published var log: [String] = []

    static var bundled: URL? { Bundle.main.resourceURL?.appendingPathComponent("ffnx") }
    static var expectedSHA1: String? {
        (try? String(contentsOf: Bundle.main.resourceURL!.appendingPathComponent("ff7_en.sha1"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static var sourceTree: URL? {
        guard let s = try? String(contentsOf: Bundle.main.resourceURL!.appendingPathComponent("source-tree.txt"), encoding: .utf8) else { return nil }
        return URL(fileURLWithPath: s.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var dataURL: URL { Paths.game.appendingPathComponent("data") }
    /// game/data is a link to another folder (the install itself): it breaks if that folder moves.
    var dataLinkedTo: String? { try? Paths.fm.destinationOfSymbolicLink(atPath: dataURL.path) }
    var exeMatches: Bool {
        guard let want = Self.expectedSHA1, let d = try? Data(contentsOf: Paths.game.appendingPathComponent("ff7_en.exe")) else { return false }
        return Self.sha1(d) == want
    }

    static func sha1(_ d: Data) -> String { Insecure.SHA1.hash(data: d).map { String(format: "%02x", $0) }.joined() }

    /// FFNx's run-time files from the app into the game folder (at each launch: a rebuilt app's
    /// shaders replace the old ones). FFNx.toml stays the launcher's; the default is the template.
    static func installRuntime() {
        guard let src = bundled, Paths.fm.fileExists(atPath: src.path) else { return }
        let fm = Paths.fm
        try? fm.createDirectory(at: Paths.game.appendingPathComponent("save"), withIntermediateDirectories: true)
        for f in (try? fm.contentsOfDirectory(atPath: src.path)) ?? [] where f.hasSuffix(".toml") {
            let to = Paths.game.appendingPathComponent(f == "FFNx.toml" ? "FFNx.template.toml" : f)
            try? fm.removeItem(at: to)
            try? fm.copyItem(at: src.appendingPathComponent(f), to: to)
        }
        let toml = Paths.game.appendingPathComponent("FFNx.toml")
        if !fm.fileExists(atPath: toml.path) { try? fm.copyItem(at: src.appendingPathComponent("FFNx.toml"), to: toml) }
        let shaders = Paths.game.appendingPathComponent("shaders")
        try? fm.removeItem(at: shaders)
        try? fm.copyItem(at: src.appendingPathComponent("shaders"), to: shaders)
    }

    /// Import from the FF7 install folder (the one with ff7/ inside), or ff7/ itself.
    func importGame(from picked: URL) async {
        busy = "กำลังตรวจไฟล์เกม…"; message = nil; progress = 0
        defer { busy = nil }
        let fm = Paths.fm
        let roots = [picked, picked.appendingPathComponent("FINAL FANTASY VII Steam Edition"), picked.deletingLastPathComponent()]
        guard let root = roots.first(where: { fm.fileExists(atPath: $0.appendingPathComponent("ff7/resources/ff7_1.02/ff7_en").path) }) else {
            message = "ไม่พบไฟล์เกมในโฟลเดอร์นี้ ให้เลือกโฟลเดอร์ “FINAL FANTASY VII Steam Edition” (ที่มีโฟลเดอร์ ff7 อยู่ข้างใน)"; return
        }
        let exe = root.appendingPathComponent("ff7/resources/ff7_1.02/ff7_en")
        let data = root.appendingPathComponent("ff7/workingdir/data")
        guard let exeData = try? Data(contentsOf: exe) else { message = "อ่าน ff7_en ไม่ได้"; return }
        if let want = Self.expectedSHA1, Self.sha1(exeData) != want {
            message = "ไฟล์เกมนี้ต่างจากที่แอปนี้ถูก build มา (ต้อง build แอปใหม่จากโฟลเดอร์นี้ด้วย tools/build_mac.sh)"; return
        }
        busy = "กำลังก๊อปไฟล์เกม…"
        let ok = await Task.detached { () -> String? in
            do {
                try fm.createDirectory(at: Paths.game, withIntermediateDirectories: true)
                let tmp = Paths.game.appendingPathComponent("data.importing")
                try? fm.removeItem(at: tmp)
                let files = (fm.enumerator(at: data, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey])?.allObjects as? [URL]) ?? []
                let total = files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
                var done = 0
                for f in files {
                    let rel = f.path.dropFirst(data.path.count + 1)
                    let to = tmp.appendingPathComponent(String(rel))
                    if (try? f.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                        try fm.createDirectory(at: to, withIntermediateDirectories: true); continue
                    }
                    try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.copyItem(at: f, to: to)
                    done += (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    let p = total > 0 ? Double(done) / Double(total) : 1
                    await MainActor.run { self.progress = p }
                }
                let dst = Paths.game.appendingPathComponent("data")
                try? fm.removeItem(at: dst)                      // a link: only the link goes
                try fm.moveItem(at: tmp, to: dst)
                let exeTo = Paths.game.appendingPathComponent("ff7_en.exe")
                try? fm.removeItem(at: exeTo)
                try exeData.write(to: exeTo)
                let cfg = root.appendingPathComponent("ff7/workingdir/ff7input.cfg")
                let cfgTo = Paths.game.appendingPathComponent("ff7input.cfg")
                if fm.fileExists(atPath: cfg.path) && !fm.fileExists(atPath: cfgTo.path) { try? fm.copyItem(at: cfg, to: cfgTo) }
                return nil
            } catch { return error.localizedDescription }
        }.value
        if let e = ok { message = "นำเข้าไม่สำเร็จ: \(e)"; return }
        Self.installRuntime()
        message = "นำเข้าไฟล์เกมแล้ว (เก็บไว้ในเครื่องนี้ ไม่ขึ้นกับโฟลเดอร์ต้นทางแล้ว)"
        objectWillChange.send()
    }

    #if os(macOS)
    /// tools/relift_mods_mac.sh: the enabled mods' code patches lifted into the app (needs the
    /// source tree this app was built from, with its tools). The app must restart afterwards.
    func reliftMods() {
        guard busy == nil, let tree = Self.sourceTree,
              Paths.fm.fileExists(atPath: tree.appendingPathComponent("tools/relift_mods_mac.sh").path) else {
            message = "ไม่พบโฟลเดอร์ซอร์สที่ใช้ build แอปนี้"; return
        }
        busy = "กำลัง lift โค้ดของม็อด (ประมาณ 5–10 นาที)…"; log = []; message = nil
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-lc", "bash \"\(tree.path)/tools/relift_mods_mac.sh\" \"\(Paths.profile.path)\" 2>&1"]
        let pipe = Pipe()
        p.standardOutput = pipe
        pipe.fileHandleForReading.readabilityHandler = { h in
            let s = String(decoding: h.availableData, as: UTF8.self)
            guard !s.isEmpty else { return }
            Task { @MainActor in self.log.append(contentsOf: s.split(separator: "\n").map(String.init)); if self.log.count > 200 { self.log.removeFirst(self.log.count - 200) } }
        }
        p.terminationHandler = { pr in
            Task { @MainActor in
                pipe.fileHandleForReading.readabilityHandler = nil
                self.busy = nil
                self.message = pr.terminationStatus == 0 ? "เสร็จแล้ว ปิดแล้วเปิดแอปใหม่เพื่อใช้โค้ดที่ lift ใหม่" : "lift ไม่สำเร็จ (ดูรายละเอียดด้านล่าง)"
            }
        }
        do { try p.run() } catch { busy = nil; message = error.localizedDescription }
    }
    #endif
}
