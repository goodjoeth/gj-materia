// Saves.swift - the game's save files (game/save/saveNN.ff7) and save states (savestates/slotNN.ff7s):
// list, import (PC saves from the 1998 / 2013 Steam releases and 7th Heaven; PlayStation memory
// cards from DuckStation .mcd, ePSXe .mcr, RetroArch .srm, DexDrive .gme, PSP .vmp), export (a PC
// save file, or a PlayStation memory card for an emulator), delete. Foundation only (iPad too).
// Layout as src/android PsxSaves.java (after ff7tk / Black Chocobo).
import Foundation

struct SaveError: Error { let message: String }

enum FF7Save {
    static let slot = 0x10F4, pcHeader = 9, pcSize = 9 + 15 * 0x10F4, files = 10
    static let regions: Set<String> = ["94163", "00867", "00868", "00869", "00900", "00700", "01057"]

    struct SlotInfo: Identifiable {
        let id: Int
        let leader: String, location: String
        let level: Int, gil: Int, playSeconds: Int
        var playTime: String { String(format: "%d:%02d", playSeconds / 3600, playSeconds / 60 % 60) }
    }
    struct File: Identifiable {
        let id: Int            // saveNN number (0-based); "Save N" = id + 1
        let url: URL
        let slots: [SlotInfo]
        let modified: Date
    }

    static func url(_ n: Int) -> URL { Paths.saves.appendingPathComponent(String(format: "save%02d.ff7", n)) }

    static func list() -> [File] {
        (0..<files).compactMap { n in
            let u = url(n)
            guard let d = try? Data(contentsOf: u), isPC([UInt8](d)) else { return nil }
            let b = [UInt8](d)
            let mod = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            return File(id: n, url: u, slots: (0..<15).compactMap { info(b, $0) }, modified: mod)
        }
    }

    static func isPC(_ d: [UInt8]) -> Bool { d.count == pcSize && d[0] == 0x71 && d[1] == 0x73 && d[2] == 0x27 && d[3] == 0x06 }

    static func used(_ pc: [UInt8], _ s: Int) -> Bool {
        let at = pcHeader + s * slot
        if (Int(pc[at]) | Int(pc[at + 1]) << 8) == 0x4D1D { return false }
        return pc[at..<(at + slot)].contains { $0 != 0 }
    }

    /// The slot's preview (the save menu's line): leader name, level, location, gil, time.
    static func info(_ pc: [UInt8], _ s: Int) -> SlotInfo? {
        guard used(pc, s) else { return nil }
        let at = pcHeader + s * slot
        func u32(_ o: Int) -> Int { Int(pc[at + o]) | Int(pc[at + o + 1]) << 8 | Int(pc[at + o + 2]) << 16 | Int(pc[at + o + 3]) << 24 }
        return SlotInfo(id: s, leader: ff7Text(Array(pc[(at + 0x08)..<(at + 0x08 + 16)])), location: ff7Text(Array(pc[(at + 0x28)..<(at + 0x28 + 32)])),
                        level: Int(pc[at + 0x04]), gil: u32(0x20), playSeconds: u32(0x24))
    }

    /// FF7's text encoding: 0x00 space, 0x01.. = '!'.., 0xFF end.
    static func ff7Text(_ b: [UInt8]) -> String {
        var s = ""
        for c in b { if c == 0xFF { break }; s.append(c < 0x60 ? Character(UnicodeScalar(c + 0x20)) : "?") }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// FF7's slot checksum: CRC-16/CCITT over bytes 4..0x10F4 of the slot, inverted.
    static func crc(_ b: [UInt8], _ start: Int) -> Int {
        var r = 0xFFFF
        for i in (start + 4)..<(start + slot) {
            r ^= Int(b[i]) << 8
            for _ in 0..<8 { r = r & 0x8000 != 0 ? ((r << 1) ^ 0x1021) & 0xFFFF : (r << 1) & 0xFFFF }
        }
        return r ^ 0xFFFF
    }

    // MARK: import

    /// A PC save copied as is, or a memory card's FF7 saves converted, into the first free saveNN.ff7.
    /// Returns ("Save N", number of saves).
    static func importFile(_ src: URL) throws -> (Int, Int) {
        let d = [UInt8](try Data(contentsOf: src))
        if isPC(d) {
            let n = (0..<15).filter { used(d, $0) }.count
            if n == 0 { throw SaveError(message: "ไฟล์เซฟนี้ว่างเปล่า") }
            return (try writeFree(d), n)
        }
        var pc = [UInt8](repeating: 0, count: pcSize)
        pc[0] = 0x71; pc[1] = 0x73; pc[2] = 0x27; pc[3] = 0x06
        var count = 0
        if let card = rawCard(d) {
            for i in 1..<16 {
                let f = 0x80 * i
                guard card[f] == 0x51 else { continue }
                let name = String(bytes: card[(f + 0x0A)..<(f + 0x0A + 20)], encoding: .ascii) ?? ""
                guard let m = name.range(of: #"^B[A-Z]{5}-(\d{5})FF7-S(\d\d)"#, options: .regularExpression) else { continue }
                let hit = String(name[m])
                let region = String(hit.dropFirst(7).prefix(5)), num = Int(hit.suffix(2)) ?? 0
                guard regions.contains(region), num >= 1, num <= 15 else { continue }
                put(&pc, num - 1, card, 0x2000 * i + 0x200)
                count += 1
            }
        } else if d.count == 0x2000, d[0] == 0x53, d[1] == 0x43 {   // one exported block ("SC")
            put(&pc, 0, d, 0x200); count = 1
        } else {
            throw SaveError(message: "ไฟล์นี้ไม่ใช่เซฟ FF7 PC (saveNN.ff7) หรือ memory card ของ PlayStation")
        }
        if count == 0 { throw SaveError(message: "ไม่พบเซฟ FINAL FANTASY VII ใน memory card นี้") }
        var u5 = 0, u6 = 0
        for s in 0..<15 where used(pc, s) { if s < 8 { u5 |= 1 << s } else { u6 |= 1 << (s - 8) } }
        pc[5] = UInt8(u5); pc[6] = UInt8(u6)
        return (try writeFree(pc), count)
    }

    static func put(_ pc: inout [UInt8], _ s: Int, _ src: [UInt8], _ at: Int) {
        let dst = pcHeader + s * slot
        pc.replaceSubrange(dst..<(dst + slot), with: src[at..<(at + slot)])
        pc[dst + 0x10DA] &= ~UInt8(1 << 2)          // normal (not custom) controls, as Black Chocobo
        let c = crc(pc, dst)
        pc[dst] = UInt8(c & 0xFF); pc[dst + 1] = UInt8(c >> 8)
    }

    static func rawCard(_ d: [UInt8]) -> [UInt8]? {
        for off in [0, 0x0F40, 0x80, 0x40] where d.count >= off + 0x20000 && d[off] == 0x4D && d[off + 1] == 0x43 {
            return Array(d[off..<(off + 0x20000)])
        }
        return nil
    }

    static func writeFree(_ pc: [UInt8]) throws -> Int {
        try Paths.fm.createDirectory(at: Paths.saves, withIntermediateDirectories: true)
        for n in 0..<files where !Paths.fm.fileExists(atPath: url(n).path) {
            try Data(pc).write(to: url(n))
            return n + 1
        }
        throw SaveError(message: "ช่องเซฟทั้ง \(files) ไฟล์ (Save 1-10) เต็มแล้ว ลบไฟล์ใดไฟล์หนึ่งก่อน")
    }

    // MARK: export

    /// A 128 KiB PlayStation memory card (DuckStation .mcd / RetroArch .srm / ePSXe .mcr) with the
    /// file's saves as the US release's blocks (BASCUS-94163FF7-Snn).
    static func memoryCard(from pcFile: URL) throws -> Data {
        let pc = [UInt8](try Data(contentsOf: pcFile))
        guard isPC(pc) else { throw SaveError(message: "ไฟล์เซฟเสีย") }
        var card = [UInt8](repeating: 0, count: 0x20000)
        card[0] = 0x4D; card[1] = 0x43; card[0x7F] = 0x0E                 // "MC" header frame (xor checksum)
        for i in 1..<16 {                                                  // free directory frames
            let f = 0x80 * i
            card[f] = 0xA0; card[f + 8] = 0xFF; card[f + 9] = 0xFF
            card[f + 0x7F] = frameXor(card, f)
        }
        for i in 16..<36 { let f = 0x80 * i; for k in 0..<4 { card[f + k] = 0xFF }; card[f + 8] = 0xFF; card[f + 9] = 0xFF }
        var block = 1
        for s in 0..<15 where used(pc, s) && block < 16 {
            let f = 0x80 * block
            card[f] = 0x51
            card[f + 4] = 0x00; card[f + 5] = 0x20                         // 0x2000 bytes
            card[f + 8] = 0xFF; card[f + 9] = 0xFF
            let name = Array(String(format: "BASCUS-94163FF7-S%02d", s + 1).utf8)
            for (k, c) in name.enumerated() { card[f + 0x0A + k] = c }
            card[f + 0x7F] = frameXor(card, f)
            let b = 0x2000 * block
            card[b] = 0x53; card[b + 1] = 0x43; card[b + 2] = 0x11; card[b + 3] = 0x01   // "SC", 1 icon frame, 1 block
            let title = Array("FF7 Save \(s + 1)".utf8)                       // ASCII in the Shift-JIS title
            for (k, c) in title.enumerated() { card[b + 4 + k] = c }
            let src = pcHeader + s * slot
            card.replaceSubrange((b + 0x200)..<(b + 0x200 + slot), with: pc[src..<(src + slot)])
            block += 1
        }
        if block == 1 { throw SaveError(message: "ไฟล์เซฟนี้ว่างเปล่า") }
        return Data(card)
    }

    static func frameXor(_ c: [UInt8], _ f: Int) -> UInt8 { (0..<0x7F).reduce(0) { $0 ^ c[f + $1] } }
}

// MARK: save states

enum SaveStates {
    static let slots = 10
    struct Slot: Identifiable {
        let id: Int
        let exists: Bool
        var location = "", when: Date?, playSeconds = 0, size = 0
        var url: URL { SaveStates.url(id) }
        var playTime: String { String(format: "%d:%02d:%02d", playSeconds / 3600, playSeconds / 60 % 60, playSeconds % 60) }
    }

    static func url(_ n: Int) -> URL { Paths.savestates.appendingPathComponent(String(format: "slot%02d.ff7s", n)) }

    /* ss_header (src/host/ff7_savestate.c): magic[8], version u32, header_size u32, build[64],
     * saved_at i64, mode i32, raw_size u32, label[64], location[48], play_seconds u32 (216 bytes, v3). */
    static func read(_ n: Int) -> Slot {
        guard let h = try? FileHandle(forReadingFrom: url(n)) else { return Slot(id: n, exists: false) }
        defer { try? h.close() }
        let b = [UInt8](h.readData(ofLength: 216))
        let size = (try? url(n).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        var s = Slot(id: n, exists: true, size: size)
        guard b.count == 216, b[0] == 0x46, b[1] == 0x46, b[2] == 0x37 else { return s }
        func u32(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24 }
        guard u32(8) == 3, u32(12) == 216 else { return s }
        s.when = Date(timeIntervalSince1970: TimeInterval(u32(80)))
        let loc = b[160..<208].prefix { $0 != 0 }
        s.location = String(decoding: loc, as: UTF8.self)
        s.playSeconds = u32(208)
        return s
    }

    static func all() -> [Slot] { (1...slots).map(read) }

    static var current: Int {
        get {
            let t = (try? String(contentsOf: Paths.savestates.appendingPathComponent("current.txt"), encoding: .ascii)) ?? "1"
            let k = Int(t.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1
            return (1...slots).contains(k) ? k : 1
        }
        set {
            try? Paths.fm.createDirectory(at: Paths.savestates, withIntermediateDirectories: true)
            try? String(newValue).write(to: Paths.savestates.appendingPathComponent("current.txt"), atomically: true, encoding: .ascii)
        }
    }

    static func delete(_ n: Int) {
        try? Paths.fm.removeItem(at: url(n))
        try? Paths.fm.removeItem(at: URL(fileURLWithPath: url(n).path + ".bak"))
    }

    /// A .ff7s file from elsewhere into slot n (checked: it is a save state of this game build).
    static func importState(_ src: URL, into n: Int) throws {
        let h = try FileHandle(forReadingFrom: src)
        let b = [UInt8](h.readData(ofLength: 8)); try? h.close()
        guard b.count == 8, b[0] == 0x46, b[1] == 0x46, b[2] == 0x37 else {
            throw SaveError(message: "ไฟล์นี้ไม่ใช่ save state ของ GJ Materia / FF7Recomp (.ff7s) — save state ของ DuckStation/RetroArch ใช้กับเวอร์ชัน PC ไม่ได้")
        }
        try Paths.fm.createDirectory(at: Paths.savestates, withIntermediateDirectories: true)
        try? Paths.fm.removeItem(at: url(n))
        try Paths.fm.copyItem(at: src, to: url(n))
    }
}
