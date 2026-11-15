// Mods.swift - the mod library (mods/profile.xml, src/mods/mods.h), installing a download
// (.7z / .iro / .zip / folder, as the Android launcher does), the 7th Heaven catalogs, and
// downloads with progress.
import Foundation
import SwiftUI
import CryptoKit

// MARK: mod info (ff7_launcher_mod_info JSON)

struct ModInfo: Decodable {
    struct Value: Decodable, Hashable { let value: Int; let name: String }
    struct Option: Decodable, Identifiable {
        let id: String; let name: String; let type: String; let `default`: Int; let description: String; let values: [Value]
    }
    struct FFNx: Decodable { let key: String; let value: String; let when: String }
    struct Need: Decodable { let id: String; let why: String }
    var kind: String = ""
    var error: String?
    var id: String = ""
    var name: String = ""
    var author: String = ""
    var version: String = ""
    var category: String = ""
    var description: String = ""
    var link: String = ""
    var options: [Option] = []
    var ffnx: [FFNx] = []
    var requires: [Need] = []
    var forbids: [Need] = []
    var unsupported: [String] = []

    enum CodingKeys: String, CodingKey {
        case kind, error, id, name, author, version, category, description, link, options, ffnx, requires, forbids, unsupported
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? ""
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        link = try c.decodeIfPresent(String.self, forKey: .link) ?? ""
        options = try c.decodeIfPresent([Option].self, forKey: .options) ?? []
        ffnx = try c.decodeIfPresent([FFNx].self, forKey: .ffnx) ?? []
        requires = try c.decodeIfPresent([Need].self, forKey: .requires) ?? []
        forbids = try c.decodeIfPresent([Need].self, forKey: .forbids) ?? []
        unsupported = try c.decodeIfPresent([String].self, forKey: .unsupported) ?? []
    }

    static func read(_ url: URL) -> ModInfo? {
        let json = url.path.withCString { takeCString(c_mod_info($0)) }
        return try? JSONDecoder().decode(ModInfo.self, from: Data(json.utf8))
    }
}

final class InstalledMod: ObservableObject, Identifiable {
    let path: String                  // as in profile.xml (relative to mods/ or absolute)
    @Published var enabled: Bool
    @Published var options: [String: Int]
    let info: ModInfo?
    var id: String { path }
    var url: URL { path.hasPrefix("/") ? URL(fileURLWithPath: path) : Paths.mods.appendingPathComponent(path) }
    var title: String { (info?.name.isEmpty == false ? info!.name : (path as NSString).deletingPathExtension) }

    init(path: String, enabled: Bool, options: [String: Int]) {
        self.path = path; self.enabled = enabled; self.options = options
        let u = path.hasPrefix("/") ? URL(fileURLWithPath: path) : Paths.mods.appendingPathComponent(path)
        info = ModInfo.read(u)
    }

    func value(of o: ModInfo.Option) -> Int { options[o.id.lowercased()] ?? o.default }
    lazy var extras: ModExtras = ModExtras.load(self)

    /// An FFNxConfig entry's conditions ("id=v;id=v") all hold with this mod's options.
    func conditionsHold(_ when: String) -> Bool {
        for part in when.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2 else { continue }
            let opt = info?.options.first { $0.id.lowercased() == kv[0].lowercased() }
            let cur = options[kv[0].lowercased()] ?? opt?.default ?? 0
            if String(cur) != kv[1] { return false }
        }
        return true
    }
}

// MARK: what 7th Heaven's Configure Mod window shows: previews, readme, release notes

struct ModExtras {
    var preview: URL?                         // the mod's <PreviewFile>
    var optionPreview: [String: URL] = [:]    // "optionid" or "optionid=value" -> image
    var readme: String?
    var releaseNotes = "", releaseDate = ""

    static func load(_ m: InstalledMod) -> ModExtras {
        var e = ModExtras()
        guard let xmlURL = file(m, "mod.xml"), let d = try? Data(contentsOf: xmlURL), let root = XMLReader.parse(d) else {
            e.readme = readme(m); return e
        }
        e.releaseNotes = root.value("ReleaseNotes")
        e.releaseDate = root.value("ReleaseDate")
        if !root.value("PreviewFile").isEmpty { e.preview = file(m, root.value("PreviewFile")) }
        for o in root.descendants("ConfigOption") {
            let id = o.value("ID").lowercased()
            if let pf = o.attr("PreviewFile") ?? (o.value("PreviewFile").isEmpty ? nil : o.value("PreviewFile")), let u = file(m, pf) {
                e.optionPreview[id] = u
            }
            for v in o.all("Option") {
                if let pf = v.attr("PreviewFile"), let u = file(m, pf) { e.optionPreview["\(id)=\(v.attr("Value") ?? "")"] = u }
            }
        }
        e.readme = readme(m)
        return e
    }

    static func readme(_ m: InstalledMod) -> String? {
        for n in ["readme.txt", "Readme.txt", "README.txt", "readme.md", "README.md"] {
            if let u = file(m, n), let s = try? String(contentsOf: u, encoding: .utf8) ?? String(contentsOf: u, encoding: .isoLatin1) { return s }
        }
        return nil
    }

    /// A file inside the mod (folder or IRO, any case, either slash), as a local file.
    static func file(_ m: InstalledMod, _ name: String) -> URL? {
        let rel = name.replacingOccurrences(of: "\\", with: "/")
        var isDir: ObjCBool = false
        guard Paths.fm.fileExists(atPath: m.url.path, isDirectory: &isDir) else { return nil }
        if isDir.boolValue {
            var u = m.url
            for part in rel.split(separator: "/") {
                let items = (try? Paths.fm.contentsOfDirectory(atPath: u.path)) ?? []
                guard let hit = items.first(where: { $0.caseInsensitiveCompare(String(part)) == .orderedSame }) else { return nil }
                u.appendPathComponent(hit)
            }
            return u
        }
        let key = SHA256.hash(data: Data(m.url.path.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        let out = Paths.cache.appendingPathComponent("mod-\(key)").appendingPathComponent(rel)
        if Paths.fm.fileExists(atPath: out.path) { return out }
        try? Paths.fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        let rc = m.url.path.withCString { a in name.withCString { b in out.path.withCString { c in c_mod_file(a, b, c) } } }
        return rc == 0 ? out : nil
    }
}

// MARK: library

@MainActor
final class ModLibrary: ObservableObject {
    @Published var mods: [InstalledMod] = []
    @Published var busy: String?           // what is being done now (installing ...)
    @Published var lastError: String?
    var installedCatalog: [String: [String: String]] = [:]   // catalog mod ID -> {file, version}

    static let fixesPath = Paths.fixes.path

    init() { reload() }

    func reload() {
        Paths.ensure()
        var list: [InstalledMod] = []
        if let d = try? Data(contentsOf: Paths.profile), let root = XMLReader.parse(d) {
            for m in root.all("Mod") {
                guard let p = m.attr("Path"), p != Self.fixesPath else { continue }
                var opts: [String: Int] = [:]
                for o in m.all("Option") { if let id = o.attr("ID") { opts[id.lowercased()] = Int(o.attr("Value") ?? "") ?? 0 } }
                list.append(InstalledMod(path: p, enabled: (m.attr("Enabled") ?? "true").lowercased() != "false", options: opts))
            }
        }
        mods = list
        if let d = try? Data(contentsOf: Paths.installed), let j = try? JSONDecoder().decode([String: [String: String]].self, from: d) {
            installedCatalog = j
        }
    }

    /// profile.xml: the mods in priority order, then the font fix at the lowest priority.
    func save() {
        var s = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<Profile Language=\"en\">\n"
        for m in mods {
            s += "  <Mod Path=\"\(xmlEscape(m.path))\"" + (m.enabled ? "" : " Enabled=\"false\"")
            if m.options.isEmpty { s += " />\n"; continue }
            s += ">\n"
            for (k, v) in m.options.sorted(by: { $0.key < $1.key }) { s += "    <Option ID=\"\(xmlEscape(k))\" Value=\"\(v)\" />\n" }
            s += "  </Mod>\n"
        }
        s += "  <Mod Path=\"\(xmlEscape(Self.fixesPath))\" />\n</Profile>\n"
        try? s.write(to: Paths.profile, atomically: true, encoding: .utf8)
        let e = JSONEncoder(); e.outputFormatting = .prettyPrinted
        try? e.encode(installedCatalog).write(to: Paths.installed, options: .atomic)
        let var7th = Bundle.main.url(forResource: "7thHeaven", withExtension: "var")
        let dst = Paths.mods.appendingPathComponent("7thHeaven.var")
        if let v = var7th, !Paths.fm.fileExists(atPath: dst.path) { try? Paths.fm.copyItem(at: v, to: dst) }
        objectWillChange.send()
    }

    func move(from: IndexSet, to: Int) { mods.move(fromOffsets: from, toOffset: to); save() }
    /// 7th Heaven's order buttons: -2 top, -1 up, +1 down, +2 bottom.
    func shift(_ m: InstalledMod, _ how: Int) {
        guard let i = mods.firstIndex(where: { $0.id == m.id }) else { return }
        let j = how == -2 ? 0 : how == 2 ? mods.count - 1 : max(0, min(mods.count - 1, i + how))
        let x = mods.remove(at: i); mods.insert(x, at: j); save()
    }
    func setAll(_ on: Bool) { for m in mods { m.enabled = on }; save() }
    func resetOptions(_ m: InstalledMod) { m.options = [:]; save() }
    func setEnabled(_ m: InstalledMod, _ on: Bool) { m.enabled = on; save() }
    func setOption(_ m: InstalledMod, _ id: String, _ v: Int) { m.options[id.lowercased()] = v; save() }

    func remove(_ m: InstalledMod) {
        mods.removeAll { $0.id == m.id }
        if !m.path.hasPrefix("/") { try? Paths.fm.removeItem(at: m.url) }
        installedCatalog = installedCatalog.filter { $0.value["file"] != m.path }
        save()
    }

    var conflictsSummary: String {
        let json = Paths.profile.path.withCString { takeCString(c_conflicts($0)) }
        guard let d = json.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return "" }
        var lines: [String] = []
        for o in (j["overlaps"] as? [[String: Any]] ?? []) {
            let w = o["winner"] as? String ?? "?", l = o["loser"] as? String ?? "?", n = o["files"] as? Int ?? 0
            lines.append("• \(w) ทับ \(l) (\(n) ไฟล์)")
        }
        for f in (j["forbids"] as? [[String: Any]] ?? []) {
            lines.append("• \(f["mod"] as? String ?? "?") ห้ามใช้กับ \(f["other"] as? String ?? "?")")
        }
        for r in (j["requires"] as? [[String: Any]] ?? []) {
            lines.append("• \(r["mod"] as? String ?? "?") ต้องมี \(r["why"] as? String ?? r["id"] as? String ?? "?")")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: install

    /// Install a downloaded or picked file/folder. New mods go to the top for User Interface
    /// mods (they must win over content mods' fonts), else to the bottom.
    func install(_ src: URL, catalogID: String? = nil, version: String? = nil, keepSource: Bool = true) async {
        busy = "กำลังติดตั้ง \(src.lastPathComponent)…"
        lastError = nil
        defer { busy = nil }
        let result = await Task.detached { Installer.install(src) }.value
        switch result {
        case .failure(let e): lastError = e.message
        case .success(let name):
            if !keepSource { try? Paths.fm.removeItem(at: src) }
            mods.removeAll { $0.path == name }
            let m = InstalledMod(path: name, enabled: true, options: [:])
            if m.info?.category.lowercased().contains("user interface") == true { mods.insert(m, at: 0) } else { mods.append(m) }
            if let id = catalogID { installedCatalog[id.lowercased()] = ["file": name, "version": version ?? ""] }
            save()
        }
    }
}

struct InstallError: Error { let message: String }

enum Installer {
    static func install(_ src: URL) -> Result<String, InstallError> {
        let fm = Paths.fm
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: src.path, isDirectory: &isDir) else { return .failure(.init(message: "ไม่พบไฟล์")) }
        let base = src.deletingPathExtension().lastPathComponent
        if isDir.boolValue { return place(src, as: src.lastPathComponent, copy: true) }
        let head = (try? FileHandle(forReadingFrom: src).readData(ofLength: 8)) ?? Data()
        let b = [UInt8](head)
        if b.starts(with: [0x37, 0x7A, 0xBC, 0xAF]) || b.starts(with: [0x50, 0x4B]) {
            let tmp = Paths.mods.appendingPathComponent(".unpack-\(UUID().uuidString)")
            try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: tmp) }
            if b[0] == 0x37 {
                var err = [CChar](repeating: 0, count: 512)
                let rc = src.path.withCString { a in tmp.path.withCString { o in c_un7z(a, o, &err, err.count) } }
                if rc != 0 { return .failure(.init(message: "แตกไฟล์ไม่ได้: " + String(cString: err))) }
            } else {
                #if os(macOS)
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                p.arguments = ["-x", "-k", src.path, tmp.path]
                try? p.run(); p.waitUntilExit()
                if p.terminationStatus != 0 { return .failure(.init(message: "แตกไฟล์ zip ไม่ได้")) }
                #else
                return .failure(.init(message: "ยังแตกไฟล์ .zip บนอุปกรณ์นี้ไม่ได้"))
                #endif
            }
            if let iro = first(in: tmp, where: { $0.pathExtension.lowercased() == "iro" }) {
                return place(iro, as: iro.lastPathComponent, copy: false)
            }
            if let mx = first(in: tmp, where: { $0.lastPathComponent.lowercased() == "mod.xml" }) {
                return place(mx.deletingLastPathComponent(), as: base, copy: false)
            }
            let items = (try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? []
            if items.count == 1, (try? items[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                return place(items[0], as: base, copy: false)
            }
            return place(tmp, as: base, copy: false)
        }
        // an IRO archive (or anything else the game's reader decides about)
        let name = src.pathExtension.lowercased() == "iro" ? src.lastPathComponent : base + ".iro"
        return place(src, as: name, copy: true)
    }

    static func first(in dir: URL, where ok: (URL) -> Bool) -> URL? {
        guard let e = Paths.fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { return nil }
        var found: [URL] = []
        for case let u as URL in e where ok(u) { found.append(u) }
        return found.sorted { $0.pathComponents.count < $1.pathComponents.count }.first
    }

    static func place(_ item: URL, as name: String, copy: Bool) -> Result<String, InstallError> {
        let dst = Paths.mods.appendingPathComponent(name)
        try? Paths.fm.removeItem(at: dst)
        do {
            if copy { try Paths.fm.copyItem(at: item, to: dst) } else { try Paths.fm.moveItem(at: item, to: dst) }
        } catch { return .failure(.init(message: "ติดตั้งไม่ได้: \(error.localizedDescription)")) }
        return .success(name)
    }
}

// MARK: catalogs

struct CatalogMod: Identifiable, Hashable {
    let id: String
    let name, author, category, description, link: String
    let version, preview, releaseNotes: String
    let links: [String]
    let sizeKB: Int
    let tags: [String]
    var sizeText: String {
        let mb = Double(sizeKB) / 1024
        return mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", max(mb, 1))
    }
}

@MainActor
final class Catalog: ObservableObject {
    static let sources: [(String, String)] = [
        ("Qhimm", "https://github.com/tsunamods-codes/7th-Heaven-Catalogs/releases/download/canary/qhimm.xml"),
        ("Sega", "https://github.com/tsunamods-codes/7th-Heaven-Catalogs/releases/download/canary/sega.xml"),
    ]
    @Published var mods: [CatalogMod] = []
    @Published var loading = false
    @Published var error: String?

    func load(force: Bool = false) async {
        if loading || (!mods.isEmpty && !force) { return }
        loading = true; error = nil
        defer { loading = false }
        var all: [CatalogMod] = []
        for (name, url) in Self.sources {
            let cache = Paths.cache.appendingPathComponent("catalog-\(name).xml")
            var data: Data?
            if let (d, r) = try? await URLSession.shared.data(from: URL(string: url)!), (r as? HTTPURLResponse)?.statusCode == 200 {
                data = d; try? d.write(to: cache)
            } else {
                data = try? Data(contentsOf: cache)
            }
            guard let d = data, let root = XMLReader.parse(d) else { error = "โหลด catalog \(name) ไม่ได้"; continue }
            for m in root.descendants("Mod") {
                guard let lv = m.child("LatestVersion") else { continue }
                all.append(CatalogMod(
                    id: m.value("ID").lowercased(), name: m.value("Name"), author: m.value("Author"),
                    category: m.value("Category"), description: m.value("Description"), link: m.value("Link"),
                    version: lv.value("Version"), preview: lv.value("PreviewImage"), releaseNotes: lv.value("ReleaseNotes"),
                    links: lv.all("Link").map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) },
                    sizeKB: Int(lv.value("DownloadSize")) ?? 0,
                    tags: m.child("Tags")?.all("string").map { $0.text } ?? []))
            }
        }
        var seen = Set<String>()
        mods = all.filter { seen.insert($0.id).inserted }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var categories: [String] { Array(Set(mods.map { $0.category })).filter { !$0.isEmpty }.sorted() }

    /// iros:// links to plain URLs; nil for links that need a browser (Mega, web pages).
    static func resolve(_ link: String) -> URL? {
        let l = link.lowercased()
        if l.hasPrefix("iros://url/") {
            var rest = String(link.dropFirst("iros://Url/".count))
            if !rest.contains("://") { rest = rest.replacingOccurrences(of: "$", with: "://", options: [], range: rest.range(of: "$")) }
            return URL(string: rest) ?? URL(string: rest.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
        }
        if l.hasPrefix("iros://gdrive/") {
            let id = String(link.dropFirst("iros://GDrive/".count))
            return URL(string: "https://drive.usercontent.google.com/download?id=\(id)&export=download&confirm=t")
        }
        if l.hasPrefix("http://") || l.hasPrefix("https://") { return URL(string: link) }
        return nil
    }

    static func browserLink(_ m: CatalogMod) -> URL? {
        for l in m.links where l.lowercased().hasPrefix("iros://externalurl/") || l.lowercased().hasPrefix("iros://mega/") {
            var rest = String(l.split(separator: "/", maxSplits: 3, omittingEmptySubsequences: false).last ?? "")
            rest = rest.replacingOccurrences(of: "$", with: "://")
            if let u = URL(string: rest) { return u }
        }
        return URL(string: m.link)
    }
}

// MARK: downloads

@MainActor
final class Downloads: NSObject, ObservableObject, URLSessionDownloadDelegate {
    struct Job { var progress: Double; var status: String; var task: URLSessionDownloadTask?; var mod: CatalogMod
                 var bytes: Int64 = 0, total: Int64 = 0, started = Date() }
    struct Done: Identifiable { let id = UUID(); let name: String; let ok: Bool; let status: String; let at: Date }
    @Published var jobs: [String: Job] = [:]
    @Published var history: [Done] = []
    var active: Int { jobs.values.filter { $0.task != nil }.count }
    func finish(_ id: String, ok: Bool, _ status: String) {
        if let j = jobs[id] { history.insert(Done(name: j.mod.name, ok: ok, status: status, at: Date()), at: 0) }
    }
    weak var library: ModLibrary?
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)

    func start(_ m: CatalogMod) {
        guard jobs[m.id] == nil else { return }
        guard let url = m.links.lazy.compactMap(Catalog.resolve).first else {
            jobs[m.id] = Job(progress: 0, status: "ต้องดาวน์โหลดผ่านเบราว์เซอร์", task: nil, mod: m)
            return
        }
        let t = session.downloadTask(with: url)
        t.taskDescription = m.id
        jobs[m.id] = Job(progress: 0, status: "กำลังดาวน์โหลด…", task: t, mod: m)
        t.resume()
    }

    func cancel(_ id: String) { jobs[id]?.task?.cancel(); jobs[id] = nil }

    nonisolated func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite e: Int64) {
        let id = t.taskDescription ?? ""
        MainActor.assumeIsolated {
            guard var j = jobs[id] else { return }
            let total = e > 0 ? e : Int64(j.mod.sizeKB) * 1024
            j.progress = total > 0 ? min(1, Double(w) / Double(total)) : 0
            j.bytes = w; j.total = total
            j.status = String(format: "กำลังดาวน์โหลด %.0f / %.0f MB", Double(w) / 1_048_576, Double(total) / 1_048_576)
            jobs[id] = j
        }
    }

    nonisolated func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didFinishDownloadingTo loc: URL) {
        let id = t.taskDescription ?? ""
        let name = t.response?.suggestedFilename ?? t.originalRequest?.url?.lastPathComponent ?? "mod"
        let dst = Paths.downloads.appendingPathComponent(name)
        try? Paths.fm.removeItem(at: dst)
        let moved = (try? Paths.fm.moveItem(at: loc, to: dst)) != nil
        let html = (t.response?.mimeType ?? "").contains("html")
        MainActor.assumeIsolated {
            guard var j = jobs[id] else { return }
            if !moved || html || (t.response as? HTTPURLResponse).map({ $0.statusCode >= 400 }) == true {
                j.status = "ดาวน์โหลดไม่สำเร็จ (ลองเปิดผ่านเบราว์เซอร์)"; j.task = nil; jobs[id] = j
                finish(id, ok: false, j.status)
                return
            }
            j.status = "กำลังติดตั้ง…"; j.progress = 1; jobs[id] = j
            let mod = j.mod
            Task { @MainActor in
                await self.library?.install(dst, catalogID: mod.id, version: mod.version, keepSource: false)
                if let e = self.library?.lastError { self.jobs[id]?.status = e; self.jobs[id]?.task = nil; self.finish(id, ok: false, e) }
                else { self.finish(id, ok: true, "ติดตั้งแล้ว"); self.jobs[id] = nil }
            }
        }
    }

    nonisolated func urlSession(_ s: URLSession, task t: URLSessionTask, didCompleteWithError e: Error?) {
        guard let e, (e as NSError).code != NSURLErrorCancelled else { return }
        let id = t.taskDescription ?? ""
        MainActor.assumeIsolated {
            jobs[id]?.status = "ดาวน์โหลดไม่สำเร็จ: \(e.localizedDescription)"
            jobs[id]?.task = nil
            finish(id, ok: false, jobs[id]?.status ?? "")
        }
    }
}
