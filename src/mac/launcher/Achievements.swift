// Achievements.swift - the offline achievement set (src/ffnx_port/achievements.cpp evaluates it
// with rcheevos while the game runs): achievements/ff7-local.txt (RetroAchievements' local format)
// and achievements/unlocks.txt ("id<TAB>unix time<TAB>title"). Foundation + SwiftUI (iPad too).
import Foundation
import SwiftUI

struct Achievement: Identifiable {
    let id: UInt32
    let title, description: String
    let points: Int
    var unlocked: Date?
}

enum Achievements {
    static var dir: URL { Paths.base.appendingPathComponent("achievements") }

    static func load() -> [Achievement] {
        var unlocks: [UInt32: Date] = [:]
        if let t = try? String(contentsOf: dir.appendingPathComponent("unlocks.txt"), encoding: .utf8) {
            for line in t.split(separator: "\n") {
                let f = line.split(separator: "\t")
                if f.count >= 2, let id = UInt32(f[0]), let ts = Double(f[1]) { unlocks[id] = Date(timeIntervalSince1970: ts) }
            }
        }
        var out: [Achievement] = []
        for file in ["ff7-local.txt", "ff7-custom.txt"] {
            guard let t = try? String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8) else { continue }
            for line in t.split(separator: "\n") {
                // id:"memaddr":"title":"description":progress:max:format:author:points:...
                let parts = line.components(separatedBy: "\"")
                guard parts.count >= 7, let id = UInt32(parts[0].trimmingCharacters(in: CharacterSet(charactersIn: ":"))) else { continue }
                let rest = parts[6].split(separator: ":", omittingEmptySubsequences: false)
                let points = rest.count > 5 ? Int(rest[5]) ?? 0 : 0
                out.append(Achievement(id: id, title: parts[3], description: parts[5], points: points, unlocked: unlocks[id]))
            }
        }
        return out
    }
}

struct AchievementsView: View {
    @ObservedObject var steam: SteamLink
    @State private var tab = 0
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Steam").tag(0)
                Text("ชุดออฟไลน์ (RetroAchievements)").tag(1)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 420).padding(10)
            if tab == 0 { SteamView(steam: steam) } else { LocalAchievementsView() }
        }
        .navigationTitle("Achievements")
    }
}

struct SteamView: View {
    @ObservedObject var steam: SteamLink
    @State private var revealHidden = false
    var body: some View {
        List {
            Section {
                if steam.signedIn {
                    LabeledContent("บัญชี", value: steam.info.account)
                    LabeledContent("เกม", value: steam.info.appid == SteamLink.app2013 ? "FINAL FANTASY VII (2013)" : steam.info.appid == 0 ? "ยังไม่ทราบ" : "FINAL FANTASY VII (2026)")
                    if !steam.achievements.isEmpty {
                        LabeledContent("ปลดล็อกบน Steam", value: "\(steam.achievements.filter { $0.got }.count) / \(steam.achievements.count)")
                    }
                    if steam.waiting > 0 { LabeledContent("รอส่งขึ้น Steam", value: "\(steam.waiting)") }
                    HStack {
                        Button { Task { await steam.sync() } } label: { Label("Sync ตอนนี้", systemImage: "arrow.triangle.2.circlepath") }
                            .disabled(steam.busy)
                        Spacer()
                        Button("ออกจากระบบ", role: .destructive) { steam.signOut() }.disabled(steam.busy)
                    }
                } else if let u = steam.qrURL {
                    HStack(alignment: .top, spacing: 20) {
                        if let img = SteamLink.qrImage(u) {
                            Image(decorative: img, scale: 1).interpolation(.none).resizable().frame(width: 220, height: 220)
                                .padding(8).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("สแกนด้วยแอป Steam บนมือถือ").font(.headline)
                            Text("เปิดแอป Steam → ไอคอน Steam Guard (โล่) → สแกน QR code แล้วกดอนุมัติ\nไม่ต้องพิมพ์รหัสผ่านในแอปนี้")
                                .foregroundStyle(.secondary)
                            Button("ยกเลิก") { steam.cancelSignIn() }
                        }
                    }
                    .padding(.vertical, 6)
                } else {
                    Text("ลงชื่อเข้าใช้ Steam เพื่อให้ achievement ที่ได้ในเกมขึ้นบนบัญชี Steam ของคุณ (ต้องเป็นบัญชีที่มี FINAL FANTASY VII)")
                    Button { steam.signIn() } label: { Label("ลงชื่อเข้าใช้ด้วย QR code", systemImage: "qrcode") }
                        .disabled(steam.busy)
                }
                if steam.busy && steam.qrURL == nil { ProgressView().controlSize(.small) }
                if let s = steam.status { Text(s).font(.callout).foregroundStyle(.secondary) }
            } header: { Text("Steam") } footer: {
                Text("FFNx เป็นตัวตัดสินว่าได้ achievement เมื่อไร แล้ว launcher ส่งขึ้น Steam (ระหว่างเล่นทุก 1 นาที และตอนเปิด launcher) token ของ Steam เก็บเป็นไฟล์ที่อ่านได้เฉพาะบัญชีผู้ใช้นี้")
                    .font(.caption)
            }
            if !steam.achievements.isEmpty {
                Section("Achievement บน Steam") {
                    ForEach(steam.achievements) { a in
                        HStack(alignment: .top) {
                            Image(systemName: a.got ? "trophy.fill" : "lock.fill").foregroundStyle(a.got ? .yellow : .secondary).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.display)
                                let d = SteamLink.shownDesc(a, reveal: revealHidden)
                                if !d.isEmpty { Text(d).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                            }
                        }
                        .opacity(a.got ? 1 : 0.6)
                    }
                    if steam.achievements.contains(where: { $0.hidden && !$0.got }) {
                        Toggle("แสดงรายละเอียดของ achievement ลับ (สปอยล์)", isOn: $revealHidden)
                    }
                }
            }
        }
    }
}

struct LocalAchievementsView: View {
    @State private var list = Achievements.load()
    var body: some View {
        let got = list.filter { $0.unlocked != nil }
        List {
            Section {
                HStack {
                    Text("ปลดล็อกแล้ว \(got.count) / \(list.count)").font(.headline)
                    Spacer()
                    Text("\(got.reduce(0) { $0 + $1.points }) / \(list.reduce(0) { $0 + $1.points }) แต้ม").foregroundStyle(.secondary)
                }
                ProgressView(value: Double(got.count), total: Double(max(list.count, 1)))
            } footer: {
                Text("ชุด achievement แบบออฟไลน์ (รูปแบบเดียวกับ RetroAchievements) ตรวจในเครื่องระหว่างเล่น ยังไม่ส่งขึ้นบัญชี RetroAchievements เพราะ RA ยังไม่อนุมัติโปรแกรมนี้ ถ้ายังไม่มีรายการ ให้เข้าเกมหนึ่งครั้ง")
                    .font(.caption)
            }
            ForEach(list.sorted { ($0.unlocked != nil ? 0 : 1, $0.id) < ($1.unlocked != nil ? 0 : 1, $1.id) }) { a in
                HStack(spacing: 12) {
                    Image(systemName: a.unlocked != nil ? "trophy.fill" : "lock.fill")
                        .foregroundStyle(a.unlocked != nil ? .yellow : .secondary).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.title).fontWeight(.medium)
                        Text(a.description).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let d = a.unlocked { Text(d.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary) }
                    Text("\(a.points)").monospacedDigit().foregroundStyle(.secondary).frame(width: 32, alignment: .trailing)
                }
                .opacity(a.unlocked != nil ? 1 : 0.6)
            }
        }
        .onAppear { list = Achievements.load() }
    }
}
