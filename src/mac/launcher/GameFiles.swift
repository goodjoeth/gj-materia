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
    nonisolated static var expectedSHA1: String? {
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

    nonisolated static func sha1(_ d: Data) -> String { Insecure.SHA1.hash(data: d).map { String(format: "%02x", $0) }.joined() }

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
        busy = L("กำลังตรวจไฟล์เกม…", "Checking the game files…"); message = nil; progress = 0
        defer { busy = nil }
        let fm = Paths.fm
        let roots = [picked, picked.appendingPathComponent("FINAL FANTASY VII Steam Edition"), picked.deletingLastPathComponent()]
        guard let root = roots.first(where: { fm.fileExists(atPath: $0.appendingPathComponent("ff7/resources/ff7_1.02/ff7_en").path) }) else {
            message = L("ไม่พบไฟล์เกมในโฟลเดอร์นี้ ให้เลือกโฟลเดอร์ “FINAL FANTASY VII Steam Edition” (ที่มีโฟลเดอร์ ff7 อยู่ข้างใน)", "No game files in this folder. Choose the “FINAL FANTASY VII Steam Edition” folder (the one with the ff7 folder inside)."); return
        }
        let exe = root.appendingPathComponent("ff7/resources/ff7_1.02/ff7_en")
        let data = root.appendingPathComponent("ff7/workingdir/data")
        guard let exeData = try? Data(contentsOf: exe) else { message = L("อ่าน ff7_en ไม่ได้", "Can't read ff7_en"); return }
        if let want = Self.expectedSHA1, Self.sha1(exeData) != want {
            message = L("ไฟล์เกมนี้ต่างจากที่แอปนี้ถูก build มา (ต้อง build แอปใหม่จากโฟลเดอร์นี้ด้วย tools/build_mac.sh)", "These game files differ from the ones this app was built from (rebuild the app from this folder with tools/build_mac.sh)"); return
        }
        busy = L("กำลังก๊อปไฟล์เกม…", "Copying the game files…")
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
        if let e = ok { message = L("นำเข้าไม่สำเร็จ: \(e)", "Import failed: \(e)"); return }
        Self.installRuntime()
        message = L("นำเข้าไฟล์เกมแล้ว (เก็บไว้ในเครื่องนี้ ไม่ขึ้นกับโฟลเดอร์ต้นทางแล้ว)", "The game files are imported (kept on this Mac, no longer tied to the source folder)")
        objectWillChange.send()
    }

    // MARK: finding FF7 on this Mac

    struct Found: Identifiable, Hashable { let url: URL; let matches: Bool?; var id: String { url.path } }
    @Published var found: [Found] = []
    @Published var searching = false

    /// An install folder (the one with ff7/ inside), or nil.
    nonisolated static func installRoot(_ u: URL) -> URL? {
        let fm = FileManager.default
        for r in [u, u.appendingPathComponent("FINAL FANTASY VII Steam Edition"), u.appendingPathComponent("FINAL FANTASY VII")]
            where fm.fileExists(atPath: r.appendingPathComponent("ff7/resources/ff7_1.02/ff7_en").path)
            && fm.fileExists(atPath: r.appendingPathComponent("ff7/workingdir/data").path) { return r }
        return nil
    }

    /// Where FF7's Steam folder usually ends up on a Mac: Steam / steamcmd's library, Windows
    /// Steam inside CrossOver or Whisky, a copy in the home folders or on an external drive; then
    /// Spotlight for the exe itself.
    nonisolated static func search() -> [URL] {
        let fm = FileManager.default
        let home = URL(fileURLWithPath: NSHomeDirectory())
        var roots: [URL] = []
        let steamLibs = ["Library/Application Support/Steam/steamapps/common", "Library/Application Support/Steam/SteamApps/common"]
        for l in steamLibs { roots.append(home.appendingPathComponent(l)) }
        func bottles(_ base: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []).flatMap { b in
                ["Program Files (x86)", "Program Files"].map { b.appendingPathComponent("drive_c/\($0)/Steam/steamapps/common") }
            }
        }
        roots += bottles(home.appendingPathComponent("Library/Application Support/CrossOver/Bottles"))
        roots += bottles(home.appendingPathComponent("Library/Containers/com.isaacmarovitz.Whisky/Bottles"))
        for d in ["FF7", "Games", "Downloads", "Desktop", "Documents", ""] { roots.append(home.appendingPathComponent(d)) }
        for v in (try? fm.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"), includingPropertiesForKeys: nil)) ?? [] {
            roots.append(v)
            for sub in (try? fm.contentsOfDirectory(at: v, includingPropertiesForKeys: [.isDirectoryKey])) ?? [] { roots.append(sub) }
        }
        var out: [URL] = []
        func add(_ u: URL) { if let r = installRoot(u), !out.contains(where: { $0.standardizedFileURL == r.standardizedFileURL }) { out.append(r) } }
        for r in roots {
            add(r)
            for c in (try? fm.contentsOfDirectory(at: r, includingPropertiesForKeys: nil)) ?? []
                where c.lastPathComponent.localizedCaseInsensitiveContains("final fantasy vii") || c.lastPathComponent.lowercased().hasPrefix("ff7") { add(c) }
        }
        #if os(macOS)
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        p.arguments = ["kMDItemFSName == 'ff7_en'"]
        p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        if (try? p.run()) != nil {
            let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            for line in String(decoding: d, as: UTF8.self).split(separator: "\n") where line.hasSuffix("/ff7/resources/ff7_1.02/ff7_en") {
                add(URL(fileURLWithPath: String(line)).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
            }
        }
        #endif
        return out.filter { !$0.path.hasPrefix(Paths.base.path) }
    }

    func findGame() async {
        searching = true; defer { searching = false }
        let want = Self.expectedSHA1
        found = await Task.detached { () -> [Found] in
            Self.search().map { r in
                let d = try? Data(contentsOf: r.appendingPathComponent("ff7/resources/ff7_1.02/ff7_en"))
                return Found(url: r, matches: want == nil || d == nil ? nil : Self.sha1(d!) == want)
            }
        }.value
        if found.isEmpty { message = L("ไม่พบ FINAL FANTASY VII ในเครื่องนี้ ดู “วิธีได้ไฟล์เกม” ด้านล่าง", "FINAL FANTASY VII wasn't found on this Mac. See “How to get the game files” below.") }
    }

    #if os(macOS)
    /// tools/relift_mods_mac.sh: the enabled mods' code patches lifted into the app (needs the
    /// source tree this app was built from, with its tools). The app must restart afterwards.
    func reliftMods() {
        guard busy == nil, let tree = Self.sourceTree,
              Paths.fm.fileExists(atPath: tree.appendingPathComponent("tools/relift_mods_mac.sh").path) else {
            message = L("ไม่พบโฟลเดอร์ซอร์สที่ใช้ build แอปนี้", "Can't find the source folder this app was built from"); return
        }
        busy = L("กำลัง lift โค้ดของม็อด (ประมาณ 5–10 นาที)…", "Lifting the mods' code (about 5–10 minutes)…"); log = []; message = nil
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
                self.message = pr.terminationStatus == 0 ? L("เสร็จแล้ว ปิดแล้วเปิดแอปใหม่เพื่อใช้โค้ดที่ lift ใหม่", "Done. Quit and reopen the app to use the newly lifted code.") : L("lift ไม่สำเร็จ (ดูรายละเอียดด้านล่าง)", "The lift failed (details below)")
            }
        }
        do { try p.run() } catch { busy = nil; message = error.localizedDescription }
    }
    #endif
}
