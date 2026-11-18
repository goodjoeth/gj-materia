// CloudSaves.swift - the game's saves and save states in iCloud Drive (iCloud Drive/FF7Recomp/),
// so every Mac on the Apple ID (and later an iPad, through the Files app) continues the same game.
//
// The game folder's save/ and savestates/ become links to the folders in iCloud Drive; the game
// itself writes through them as before. iCloud Drive is a plain folder to an app, so no iCloud
// entitlement (paid developer account) is needed. Safety: before each Play the saves are copied
// to save-backups/ (the last 20 kept), files iCloud has not downloaded yet are fetched first,
// and a note in iCloud Drive says which Mac is playing, so another one warns before it starts.
import Foundation
#if os(iOS)
import UIKit
#endif

@MainActor
final class CloudSaves: ObservableObject {
    @Published var status: String?
    @Published var busy = false

    #if os(iOS)
    // iPhone / iPad: an app can't reach iCloud Drive by its path (a sideloaded one has no iCloud
    // entitlement either), so the player picks the folder once in Files (iCloud Drive itself, or
    // its FF7Recomp folder, the Macs' one) and the app keeps that permission as a bookmark. The
    // saves stay real files in the game folder and are synced both ways, newer file wins: when
    // the launcher opens, before Play and when the game ends.
    nonisolated static let bookmarkKey = "iCloudFolderBookmark"
    nonisolated static let resolvedFolder: URL? = {
        guard let d = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let u = try? URL(resolvingBookmarkData: d, bookmarkDataIsStale: &stale) else { return nil }
        _ = u.startAccessingSecurityScopedResource()       // for as long as the app runs
        if stale, let fresh = try? u.bookmarkData() { UserDefaults.standard.set(fresh, forKey: bookmarkKey) }
        return u
    }()
    nonisolated static var iCloudDrive: URL { resolvedFolder ?? URL(fileURLWithPath: "/nonexistent-icloud") }
    nonisolated static var root: URL {
        iCloudDrive.lastPathComponent == "FF7Recomp" ? iCloudDrive : iCloudDrive.appendingPathComponent("FF7Recomp")
    }
    /// The folder picked in Files: kept, then the saves go in.
    func choose(_ u: URL) {
        _ = u.startAccessingSecurityScopedResource()
        guard let d = try? u.bookmarkData() else { status = L("จำโฟลเดอร์นี้ไม่ได้", "Can't keep access to this folder"); return }
        UserDefaults.standard.set(d, forKey: Self.bookmarkKey)
        UserDefaults.standard.set(true, forKey: "iCloudSync")
        status = L("เลือกโฟลเดอร์แล้ว: ปิดแล้วเปิดแอปใหม่ แล้วเปิดสวิตช์นี้อีกครั้ง", "Folder chosen: close and reopen the app, then turn this on again")
        if Self.resolvedFolder != nil { Self.sync(); status = L("เซฟซิงก์กับ iCloud Drive แล้ว", "The saves are synced with iCloud Drive") }
        objectWillChange.send()
    }
    /// Both ways, the newer file wins (the older one goes to save-backups/ first).
    nonisolated static func sync() {
        guard enabled else { return }
        let fm = FileManager.default
        let backup = backups.appendingPathComponent(stamp() + "-sync")
        func date(_ u: URL) -> Date { (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast }
        for (local, cloud) in pairs {
            try? fm.createDirectory(at: local, withIntermediateDirectories: true)
            try? fm.createDirectory(at: cloud, withIntermediateDirectories: true)
            download(cloud)
            let names = Set(((try? fm.contentsOfDirectory(atPath: local.path)) ?? []) + ((try? fm.contentsOfDirectory(atPath: cloud.path)) ?? []))
                .filter { !$0.hasPrefix(".") }
            for n in names {
                let l = local.appendingPathComponent(n), c = cloud.appendingPathComponent(n)
                let hasL = fm.fileExists(atPath: l.path), hasC = fm.fileExists(atPath: c.path)
                let (from, to): (URL, URL)
                if hasL && (!hasC || date(l) > date(c).addingTimeInterval(1)) { (from, to) = (l, c) }
                else if hasC && (!hasL || date(c) > date(l).addingTimeInterval(1)) { (from, to) = (c, l) }
                else { continue }
                if fm.fileExists(atPath: to.path) {
                    try? fm.createDirectory(at: backup.appendingPathComponent(local.lastPathComponent), withIntermediateDirectories: true)
                    try? fm.copyItem(at: to, to: backup.appendingPathComponent(local.lastPathComponent).appendingPathComponent(n))
                    try? fm.removeItem(at: to)
                }
                try? fm.copyItem(at: from, to: to)
            }
        }
    }
    #else
    nonisolated static var iCloudDrive: URL {
        if let e = ProcessInfo.processInfo.environment["FF7_ICLOUD_DRIVE"] { return URL(fileURLWithPath: e) }   // tests
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
    }
    nonisolated static var root: URL { iCloudDrive.appendingPathComponent("FF7Recomp") }
    #endif
    nonisolated static var lock: URL { root.appendingPathComponent("playing.json") }
    nonisolated static var available: Bool { FileManager.default.fileExists(atPath: iCloudDrive.path) }
    nonisolated static var backups: URL { Paths.base.appendingPathComponent("save-backups") }

    /// The local folders and their iCloud Drive counterparts.
    nonisolated static var pairs: [(local: URL, cloud: URL)] {
        [(Paths.saves, root.appendingPathComponent("save")), (Paths.savestates, root.appendingPathComponent("savestates"))]
    }

    #if os(iOS)
    nonisolated static var enabled: Bool { UserDefaults.standard.bool(forKey: "iCloudSync") && available }
    #else
    static var enabled: Bool {
        pairs.allSatisfy { (try? Paths.fm.destinationOfSymbolicLink(atPath: $0.local.path)) == $0.cloud.path }
    }
    #endif

    /// The name the other devices show ("Joe's MacBook Pro", "iPad"): iOS gives apps only the model.
    nonisolated static var deviceName: String {
        #if os(macOS)
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }

    /// This install's own id: two iPads both called "iPad" are still told apart.
    nonisolated static var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: "deviceID") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "deviceID")
        return id
    }

    // MARK: on / off

    func enable() {
        #if os(iOS)
        guard Self.available else { status = L("เลือกโฟลเดอร์ iCloud Drive ก่อน", "Choose the iCloud Drive folder first"); return }
        UserDefaults.standard.set(true, forKey: "iCloudSync")
        Self.sync()
        status = L("เซฟซิงก์กับ iCloud Drive แล้ว", "The saves are synced with iCloud Drive")
        objectWillChange.send()
        return
        #endif
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
        #if os(iOS)
        UserDefaults.standard.set(false, forKey: "iCloudSync")
        status = L("หยุดซิงก์แล้ว (เซฟยังอยู่ทั้งในเครื่องและใน iCloud Drive)", "Syncing stopped (the saves stay on this device and in iCloud Drive)")
        objectWillChange.send()
        return
        #endif
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

    /// `id` and `beat` are newer than the first notes: a note with a heartbeat is renewed every
    /// minute while the game runs, so one left by a device that was switched off or had the app
    /// closed is old after five minutes (one without, after eight hours).
    struct Playing: Codable {
        let device: String; let since: Date
        var id: String? = nil; var beat: Date? = nil
        nonisolated var mine: Bool { id.map { $0 == CloudSaves.deviceID } ?? (device == CloudSaves.deviceName) }
        nonisolated var stale: Bool {
            if let b = beat { return Date().timeIntervalSince(b) > 5 * 60 }
            return Date().timeIntervalSince(since) > 8 * 3600
        }
    }
    nonisolated static func note() -> Playing? {
        guard let d = try? Data(contentsOf: lock) else { return nil }
        return try? JSONDecoder().decode(Playing.self, from: d)
    }
    nonisolated static func writeNote(since: Date) {
        if let d = try? JSONEncoder().encode(Playing(device: deviceName, since: since, id: deviceID, beat: Date())) { try? d.write(to: lock) }
    }
    nonisolated(unsafe) static var heartbeat: Timer?

    /// Another device's note that it is playing, if recent (it is removed when the game ends there).
    static func otherDevicePlaying() -> Playing? {
        guard enabled, let p = note(), !p.mine, !p.stale else { return nil }
        return p
    }

    /// Before Play: the saves downloaded and backed up, and the note that this Mac is playing.
    static func beforePlay() {
        let fm = Paths.fm
        if enabled { for (_, cloud) in pairs { download(cloud) } }
        #if os(iOS)
        sync()
        #endif
        let to = backups.appendingPathComponent(stamp())
        for (local, _) in pairs where fm.fileExists(atPath: local.path) {
            try? fm.createDirectory(at: to, withIntermediateDirectories: true)
            try? fm.copyItem(at: local.resolvingSymlinksInPath(), to: to.appendingPathComponent(local.lastPathComponent))
        }
        // the last 20 backups
        let all = ((try? fm.contentsOfDirectory(atPath: backups.path)) ?? []).filter { !$0.hasSuffix("-merge") && !$0.hasSuffix("-local") }.sorted()
        for old in all.dropLast(20) { try? fm.removeItem(at: backups.appendingPathComponent(old)) }
        if enabled {
            let since = Date()
            writeNote(since: since)
            heartbeat?.invalidate()
            heartbeat = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                if let p = note(), !p.mine { return }      // another device took over: leave its note
                writeNote(since: since)
            }
        }
    }

    /// The game ended (src/mac/ff7_mac_main.mm): this Mac no longer plays.
    nonisolated static func afterPlay() {
        #if os(iOS)
        sync()                                   // the game's new saves up to iCloud Drive
        #endif
        DispatchQueue.main.async { heartbeat?.invalidate(); heartbeat = nil }
        guard let p = note(), p.mine else { return }
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
