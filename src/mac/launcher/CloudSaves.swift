// CloudSaves.swift - the game's saves and save states in iCloud Drive (iCloud Drive/FF7Recomp/),
// so every Mac on the Apple ID (and later an iPad, through the Files app) continues the same game.
//
// The game folder's save/ and savestates/ become links to the folders in iCloud Drive; the game
// itself writes through them as before. iCloud Drive is a plain folder to an app, so no iCloud
// entitlement (paid developer account) is needed. Safety: before each Play the saves are copied
// to save-backups/ (the last 20 kept), files iCloud has not downloaded yet are fetched first,
// and a note in iCloud Drive says which Mac is playing, so another one warns before it starts.
import Foundation

@MainActor
final class CloudSaves: ObservableObject {
    @Published var status: String?
    @Published var busy = false

    nonisolated static var iCloudDrive: URL {
        if let e = ProcessInfo.processInfo.environment["FF7_ICLOUD_DRIVE"] { return URL(fileURLWithPath: e) }   // tests
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
    }
    nonisolated static var root: URL { iCloudDrive.appendingPathComponent("FF7Recomp") }
    nonisolated static var lock: URL { root.appendingPathComponent("playing.json") }
    static var available: Bool { Paths.fm.fileExists(atPath: iCloudDrive.path) }
    static var backups: URL { Paths.base.appendingPathComponent("save-backups") }

    /// The local folders and their iCloud Drive counterparts.
    static var pairs: [(local: URL, cloud: URL)] {
        [(Paths.saves, root.appendingPathComponent("save")), (Paths.savestates, root.appendingPathComponent("savestates"))]
    }

    static var enabled: Bool {
        pairs.allSatisfy { (try? Paths.fm.destinationOfSymbolicLink(atPath: $0.local.path)) == $0.cloud.path }
    }

    static var deviceName: String { Host.current().localizedName ?? ProcessInfo.processInfo.hostName }

    // MARK: on / off

    func enable() {
        guard Self.available else { status = L("iCloud Drive ไม่ได้เปิดอยู่ (การตั้งค่าระบบ → Apple ID → iCloud → iCloud Drive)", "iCloud Drive is off (System Settings → Apple ID → iCloud → iCloud Drive)"); return }
        busy = true; defer { busy = false }
        let fm = Paths.fm
        var merged = 0, kept = 0
        do {
            let stamp = Self.stamp()
            for (local, cloud) in Self.pairs {
                try fm.createDirectory(at: cloud, withIntermediateDirectories: true)
                Self.download(cloud)
                if (try? fm.destinationOfSymbolicLink(atPath: local.path)) == cloud.path { continue }
                // what this Mac has goes in; where both have a file, the newer wins and the
                // other is kept in save-backups/
                for f in (try? fm.contentsOfDirectory(at: local, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
                    let to = cloud.appendingPathComponent(f.lastPathComponent)
                    if fm.fileExists(atPath: to.path) {
                        let a = (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                        let b = (try? to.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                        let loser = a > b ? to : f
                        let keep = Self.backups.appendingPathComponent("\(stamp)-merge/\(local.lastPathComponent)")
                        try fm.createDirectory(at: keep, withIntermediateDirectories: true)
                        try? fm.copyItem(at: loser, to: keep.appendingPathComponent(f.lastPathComponent))
                        if a > b { try fm.removeItem(at: to); try fm.copyItem(at: f, to: to) }
                        kept += 1
                    } else {
                        try fm.copyItem(at: f, to: to)
                    }
                    merged += 1
                }
                // the local folder is kept aside, then replaced by the link
                if fm.fileExists(atPath: local.path) {
                    let aside = Self.backups.appendingPathComponent("\(stamp)-local/\(local.lastPathComponent)")
                    try fm.createDirectory(at: aside.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.moveItem(at: local, to: aside)
                }
                try fm.createSymbolicLink(at: local, withDestinationURL: cloud)
            }
            let both = kept > 0 ? L(", \(kept) ไฟล์ที่มีทั้งสองที่: ใช้อันที่ใหม่กว่า อีกอันเก็บไว้ใน save-backups", ", \(kept) on both: the newer one is used, the other kept in save-backups") : ""
            status = L("เซฟอยู่ใน iCloud Drive แล้ว (\(merged) ไฟล์", "The saves are in iCloud Drive (\(merged) files") + both + ")"
        } catch {
            status = L("ย้ายไป iCloud ไม่สำเร็จ: \(error.localizedDescription)", "Could not move them to iCloud: \(error.localizedDescription)")
        }
        objectWillChange.send()
    }

    func disable() {
        busy = true; defer { busy = false }
        let fm = Paths.fm
        do {
            for (local, cloud) in Self.pairs where (try? fm.destinationOfSymbolicLink(atPath: local.path)) != nil {
                Self.download(cloud)
                try fm.removeItem(at: local)                       // the link
                try fm.copyItem(at: cloud, to: local)              // iCloud Drive keeps its copy
            }
            status = L("เซฟกลับมาอยู่ในเครื่องนี้แล้ว (สำเนาใน iCloud Drive ยังอยู่)", "The saves are back on this Mac (the copy in iCloud Drive stays)")
        } catch {
            status = L("ย้ายกลับไม่สำเร็จ: \(error.localizedDescription)", "Could not move them back: \(error.localizedDescription)")
        }
        objectWillChange.send()
    }

    // MARK: before and after playing

    struct Playing: Codable { let device: String; let since: Date }

    /// Another Mac's note that it is playing, if recent (it is removed when the game ends there).
    static func otherDevicePlaying() -> Playing? {
        guard enabled, let d = try? Data(contentsOf: lock), let p = try? JSONDecoder().decode(Playing.self, from: d) else { return nil }
        if p.device == deviceName || Date().timeIntervalSince(p.since) > 8 * 3600 { return nil }
        return p
    }

    /// Before Play: the saves downloaded and backed up, and the note that this Mac is playing.
    static func beforePlay() {
        let fm = Paths.fm
        if enabled { for (_, cloud) in pairs { download(cloud) } }
        let to = backups.appendingPathComponent(stamp())
        for (local, _) in pairs where fm.fileExists(atPath: local.path) {
            try? fm.createDirectory(at: to, withIntermediateDirectories: true)
            try? fm.copyItem(at: local.resolvingSymlinksInPath(), to: to.appendingPathComponent(local.lastPathComponent))
        }
        // the last 20 backups
        let all = ((try? fm.contentsOfDirectory(atPath: backups.path)) ?? []).filter { !$0.hasSuffix("-merge") && !$0.hasSuffix("-local") }.sorted()
        for old in all.dropLast(20) { try? fm.removeItem(at: backups.appendingPathComponent(old)) }
        if enabled, let d = try? JSONEncoder().encode(Playing(device: deviceName, since: Date())) { try? d.write(to: lock) }
    }

    /// The game ended (src/mac/ff7_mac_main.mm): this Mac no longer plays.
    nonisolated static func afterPlay() {
        guard let d = try? Data(contentsOf: lock), let p = try? JSONDecoder().decode(Playing.self, from: d),
              p.device == (Host.current().localizedName ?? ProcessInfo.processInfo.hostName) else { return }
        try? FileManager.default.removeItem(at: lock)
    }

    /// Files iCloud has not downloaded to this Mac yet (".name.icloud" placeholders): fetched,
    /// waiting up to 20 s.
    nonisolated static func download(_ dir: URL) {
        let fm = FileManager.default
        func pending() -> [URL] {
            ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [])) ?? [])
                .filter { $0.lastPathComponent.hasPrefix(".") && $0.pathExtension == "icloud" }
        }
        let missing = pending()
        guard !missing.isEmpty else { return }
        for p in missing {
            let real = dir.appendingPathComponent(String(p.deletingPathExtension().lastPathComponent.dropFirst()))
            try? fm.startDownloadingUbiquitousItem(at: real)
            #if os(macOS)
            let t = Process(); t.executableURL = URL(fileURLWithPath: "/usr/bin/brctl"); t.arguments = ["download", real.path]
            t.standardOutput = FileHandle.nullDevice; t.standardError = FileHandle.nullDevice
            try? t.run(); t.waitUntilExit()
            #endif
        }
        let until = Date().addingTimeInterval(20)
        while !pending().isEmpty && Date() < until { Thread.sleep(forTimeInterval: 0.25) }
    }

    nonisolated static func stamp() -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"; return f.string(from: Date())
    }
}

@_cdecl("ff7_launcher_game_exited")
public func ff7_launcher_game_exited() { CloudSaves.afterPlay() }
