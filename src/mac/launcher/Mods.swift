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
            lines.append(L("• \(w) ทับ \(l) (\(n) ไฟล์)", "• \(w) overrides \(l) (\(n) files)"))
        }
        for f in (j["forbids"] as? [[String: Any]] ?? []) {
            let fm = f["mod"] as? String ?? "?", fo = f["other"] as? String ?? "?"
                lines.append(L("• \(fm) ห้ามใช้กับ \(fo)", "• \(fm) can't be used with \(fo)"))
        }
        for r in (j["requires"] as? [[String: Any]] ?? []) {
            let rm = r["mod"] as? String ?? "?", rw = r["why"] as? String ?? r["id"] as? String ?? "?"
                lines.append(L("• \(rm) ต้องมี \(rw)", "• \(rm) needs \(rw)"))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: install

    /// Install a downloaded or picked file/folder. New mods go to the top for User Interface
    /// mods (they must win over content mods' fonts), else to the bottom.
    func install(_ src: URL, catalogID: String? = nil, version: String? = nil, keepSource: Bool = true) async {
        busy = L("กำลังติดตั้ง \(src.lastPathComponent)…", "Installing \(src.lastPathComponent)…")
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
        guard fm.fileExists(atPath: src.path, isDirectory: &isDir) else { return .failure(.init(message: L("ไม่พบไฟล์", "File not found"))) }
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
                if rc != 0 { return .failure(.init(message: L("แตกไฟล์ไม่ได้: ", "Can't unpack: ") + String(cString: err))) }
            } else {
                #if os(macOS)
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                p.arguments = ["-x", "-k", src.path, tmp.path]
                try? p.run(); p.waitUntilExit()
                if p.terminationStatus != 0 { return .failure(.init(message: L("แตกไฟล์ zip ไม่ได้", "Can't unpack the zip"))) }
                #else
                return .failure(.init(message: L("ยังแตกไฟล์ .zip บนอุปกรณ์นี้ไม่ได้", "Can't unpack .zip files on this device yet")))
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
        } catch { return .failure(.init(message: L("ติดตั้งไม่ได้: \(error.localizedDescription)", "Could not install: \(error.localizedDescription)"))) }
        return .success(name)
    }
}

// MARK: catalogs

struct CatalogMod: Identifiable, Hashable, Codable {
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
            guard let d = data, let root = XMLReader.parse(d) else { error = L("โหลด catalog \(name) ไม่ได้", "Can't load the \(name) catalog"); continue }
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

    /// The installed version of a catalog mod (installed from the catalog, or a mod whose mod.xml
    /// carries the catalog's ID); nil when it is not installed.
    static func installedVersion(_ m: CatalogMod, _ library: ModLibrary) -> String? {
        if let v = library.installedCatalog[m.id]?["version"] { return v }
        return library.mods.first { $0.info?.id.lowercased() == m.id }.map { $0.info?.version ?? "" }
    }

    /// Whether the catalog's version is newer: as decimals ("2.968"), else number by number ("1.2.10" > "1.2.9");
    /// versions that are not numbers count as newer when they differ.
    static func isNewer(_ catalog: String, than installed: String) -> Bool {
        let a = catalog.trimmingCharacters(in: .whitespaces), b = installed.trimmingCharacters(in: .whitespaces)
        if a.isEmpty || b.isEmpty || a == b { return false }   // no installed version: unknown, not "new"
        // 7th Heaven's versions are decimal numbers ("2.968" > "2.97" is false, as there)
        if a.filter({ $0 == "." }).count <= 1, b.filter({ $0 == "." }).count <= 1, let x = Double(a), let y = Double(b) { return x > y }
        func nums(_ s: String) -> [Int]? {
            let parts = s.lowercased().drop { $0 == "v" }.split(separator: ".")
            let n = parts.compactMap { Int($0) }
            return n.count == parts.count && !n.isEmpty ? n : nil
        }
        guard let x = nums(a), let y = nums(b) else { return true }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    /// Installed mods with a newer version in the catalog.
    func updates(_ library: ModLibrary) -> [CatalogMod] {
        mods.filter { m in Self.installedVersion(m, library).map { Self.isNewer(m.version, than: $0) } ?? false }
    }

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

/// Mod downloads. A download that stops (the network drops, the launcher quits, the game
/// starts and ends, or the user pauses it) keeps what it has in downloads/.partial and goes on
/// from there: by itself when the launcher opens again, or with the resume button.
@MainActor
final class Downloads: NSObject, ObservableObject, URLSessionDownloadDelegate {
    struct Job { var progress: Double; var status: String; var task: URLSessionDownloadTask?; var mod: CatalogMod
                 var bytes: Int64 = 0, total: Int64 = 0, started = Date(), startBytes: Int64 = 0
                 var paused = false, retries = 0 }
    struct Done: Identifiable { let id = UUID(); let name: String; let ok: Bool; let status: String; let at: Date }
    struct Partial: Codable { let mod: CatalogMod; var byUser: Bool; var bytes: Int64; var total: Int64 }
    @Published var jobs: [String: Job] = [:]
    @Published var history: [Done] = []
    var active: Int { jobs.values.filter { $0.task != nil }.count }
    func finish(_ id: String, ok: Bool, _ status: String) {
        if let j = jobs[id] { history.insert(Done(name: j.mod.name, ok: ok, status: status, at: Date()), at: 0) }
    }
    weak var library: ModLibrary?
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)

    static var partialDir: URL { Paths.downloads.appendingPathComponent(".partial") }
    static func safe(_ id: String) -> String { id.replacingOccurrences(of: "/", with: "_") }
    static func resumeFile(_ id: String) -> URL { partialDir.appendingPathComponent(safe(id) + ".resume") }
    static func infoFile(_ id: String) -> URL { partialDir.appendingPathComponent(safe(id) + ".json") }

    override init() {
        super.init()
        // the downloads that stopped last time: paused ones wait, the others go on
        for f in (try? Paths.fm.contentsOfDirectory(at: Self.partialDir, includingPropertiesForKeys: nil)) ?? [] where f.pathExtension == "json" {
            guard let d = try? Data(contentsOf: f), let p = try? JSONDecoder().decode(Partial.self, from: d) else { continue }
            let mb = { (b: Int64) in String(format: "%.0f", Double(b) / 1_048_576) }
            jobs[p.mod.id] = Job(progress: p.total > 0 ? Double(p.bytes) / Double(p.total) : 0,
                                 status: L("หยุดไว้ที่ \(mb(p.bytes)) / \(mb(p.total)) MB", "Paused at \(mb(p.bytes)) / \(mb(p.total)) MB"), task: nil, mod: p.mod,
                                 bytes: p.bytes, total: p.total, paused: true)
            if !p.byUser { resume(p.mod.id) }
        }
        #if os(macOS)
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated { Downloads.shared?.keepAllBlocking() }
        }
        #endif
        Downloads.shared = self
    }
    static weak var shared: Downloads?

    func start(_ m: CatalogMod) {
        if let j = jobs[m.id] { if j.paused { resume(m.id) }; return }
        guard let url = m.links.lazy.compactMap(Catalog.resolve).first else {
            jobs[m.id] = Job(progress: 0, status: L("ต้องดาวน์โหลดผ่านเบราว์เซอร์", "Has to be downloaded in a browser"), task: nil, mod: m)
            return
        }
        let t = session.downloadTask(with: url)
        t.taskDescription = m.id
        jobs[m.id] = Job(progress: 0, status: L("กำลังดาวน์โหลด…", "Downloading…"), task: t, mod: m)
        t.resume()
    }

    /// Go on from where it stopped (from the start when the server cannot).
    func resume(_ id: String) {
        guard var j = jobs[id], j.task == nil else { return }
        let t: URLSessionDownloadTask
        if let d = try? Data(contentsOf: Self.resumeFile(id)) {
            t = session.downloadTask(withResumeData: d)
        } else if let url = j.mod.links.lazy.compactMap(Catalog.resolve).first {
            t = session.downloadTask(with: url); j.bytes = 0
        } else { return }
        t.taskDescription = id
        j.task = t; j.paused = false; j.status = L("กำลังดาวน์โหลดต่อ…", "Resuming the download…"); j.started = Date(); j.startBytes = j.bytes
        jobs[id] = j
        t.resume()
    }

    /// Pause: what it has is kept for later.
    func pause(_ id: String) {
        guard let t = jobs[id]?.task else { return }
        jobs[id]?.task = nil; jobs[id]?.paused = true; jobs[id]?.status = L("กำลังหยุด…", "Pausing…")
        t.cancel { data in
            Task { @MainActor in self.keep(id, data, byUser: true) }
        }
    }

    func cancel(_ id: String) {
        jobs[id]?.task?.cancel(); jobs[id] = nil
        try? Paths.fm.removeItem(at: Self.resumeFile(id)); try? Paths.fm.removeItem(at: Self.infoFile(id))
    }

    private func keep(_ id: String, _ data: Data?, byUser: Bool) {
        guard var j = jobs[id] else { return }
        try? Paths.fm.createDirectory(at: Self.partialDir, withIntermediateDirectories: true)
        if let data { try? data.write(to: Self.resumeFile(id)) } else { try? Paths.fm.removeItem(at: Self.resumeFile(id)); j.bytes = 0 }
        if let d = try? JSONEncoder().encode(Partial(mod: j.mod, byUser: byUser, bytes: j.bytes, total: j.total)) { try? d.write(to: Self.infoFile(id)) }
        j.task = nil; j.paused = true
        j.status = data == nil ? L("หยุดไว้ (เซิร์ฟเวอร์นี้ต่อไม่ได้ จะเริ่มใหม่)", "Paused (this server can't resume; it will start over)")
                               : String(format: L("หยุดไว้ที่ %.0f / %.0f MB", "Paused at %.0f / %.0f MB"), Double(j.bytes) / 1_048_576, Double(j.total) / 1_048_576)
        jobs[id] = j
    }

    /// Before the process ends (quit, or the game ending): every running download kept, waiting
    /// up to 3 s for URLSession to hand over what it has. Main thread only.
    func keepAllBlocking() {
        let running = jobs.compactMap { id, j in j.task.map { (id, $0) } }
        guard !running.isEmpty else { return }
        var left = running.count
        for (id, t) in running {
            jobs[id]?.task = nil
            t.cancel { data in
                DispatchQueue.main.async { MainActor.assumeIsolated { self.keep(id, data, byUser: false); left -= 1 } }
            }
        }
        let until = Date().addingTimeInterval(3)
        while left > 0 && Date() < until { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
    }

    nonisolated func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite e: Int64) {
        let id = t.taskDescription ?? ""
        MainActor.assumeIsolated {
            guard var j = jobs[id], j.task === t else { return }
            let total = e > 0 ? e : Int64(j.mod.sizeKB) * 1024
            j.progress = total > 0 ? min(1, Double(w) / Double(total)) : 0
            j.bytes = w; j.total = total
            j.status = String(format: L("กำลังดาวน์โหลด %.0f / %.0f MB", "Downloading %.0f / %.0f MB"), Double(w) / 1_048_576, Double(total) / 1_048_576)
            jobs[id] = j
        }
    }

    nonisolated func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didResumeAtOffset o: Int64, expectedTotalBytes e: Int64) {
        let id = t.taskDescription ?? ""
        NSLog("[downloads] %@ goes on from %lld of %lld bytes", id, o, e)
        MainActor.assumeIsolated { jobs[id]?.startBytes = o; jobs[id]?.bytes = o }
    }

    nonisolated func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didFinishDownloadingTo loc: URL) {
        let id = t.taskDescription ?? ""
        let name = t.response?.suggestedFilename ?? t.originalRequest?.url?.lastPathComponent ?? "mod"
        let dst = Paths.downloads.appendingPathComponent(name)
        try? Paths.fm.removeItem(at: dst)
        let moved = (try? Paths.fm.moveItem(at: loc, to: dst)) != nil
        let html = (t.response?.mimeType ?? "").contains("html")
        MainActor.assumeIsolated {
            try? Paths.fm.removeItem(at: Self.resumeFile(id)); try? Paths.fm.removeItem(at: Self.infoFile(id))
            guard var j = jobs[id] else { return }
            if !moved || html || (t.response as? HTTPURLResponse).map({ $0.statusCode >= 400 }) == true {
                j.status = L("ดาวน์โหลดไม่สำเร็จ (ลองเปิดผ่านเบราว์เซอร์)", "Download failed (try opening it in a browser)"); j.task = nil; jobs[id] = j
                finish(id, ok: false, j.status)
                return
            }
            j.status = L("กำลังติดตั้ง…", "Installing…"); j.progress = 1; jobs[id] = j
            let mod = j.mod
            Task { @MainActor in
                await self.library?.install(dst, catalogID: mod.id, version: mod.version, keepSource: false)
                if let e = self.library?.lastError { self.jobs[id]?.status = e; self.jobs[id]?.task = nil; self.finish(id, ok: false, e) }
                else { self.finish(id, ok: true, L("ติดตั้งแล้ว", "Installed")); self.jobs[id] = nil }
            }
        }
    }

    nonisolated func urlSession(_ s: URLSession, task t: URLSessionTask, didCompleteWithError e: Error?) {
        guard let e = e as NSError?, e.code != NSURLErrorCancelled else { return }
        let id = t.taskDescription ?? ""
        let data = e.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        MainActor.assumeIsolated {
            guard let j = jobs[id], j.task === t else { return }
            // the network dropped: keep what came, and try again by itself a few times
            keep(id, data, byUser: false)
            if j.retries < 5 {
                jobs[id]?.retries = j.retries + 1
                jobs[id]?.status = L("เน็ตหลุด จะดาวน์โหลดต่อใน 10 วินาที (\(e.localizedDescription))", "Connection lost; resuming in 10 seconds (\(e.localizedDescription))")
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                    MainActor.assumeIsolated { if self?.jobs[id]?.paused == true && self?.jobs[id]?.task == nil { self?.resume(id) } }
                }
            } else {
                jobs[id]?.status = L("ดาวน์โหลดไม่สำเร็จ: \(e.localizedDescription) (กดดาวน์โหลดต่อเพื่อลองอีกครั้ง)", "Download failed: \(e.localizedDescription) (press Resume to try again)")
            }
        }
    }
}

/// The game ends (src/mac/ff7_mac_main.mm ff7_platform_exit, on the game thread): the downloads
/// are kept before the process goes.
@_cdecl("ff7_downloads_keep")
public func ff7_downloads_keep() {
    if Thread.isMainThread { MainActor.assumeIsolated { Downloads.shared?.keepAllBlocking() }; return }
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.main.async { MainActor.assumeIsolated { Downloads.shared?.keepAllBlocking() }; done.signal() }
    _ = done.wait(timeout: .now() + 5)
}
