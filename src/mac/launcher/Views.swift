// Views.swift - the launcher: Play, Settings, My mods (7th Heaven's library and Configure Mod),
// Get mods (catalogs), Downloads, Saves, Controls. SwiftUI only (fileImporter / fileExporter /
// openURL), so the same views can run on iPad; the window bridge at the end is macOS's.
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
final class LauncherState: ObservableObject {
    @Published var settings = Settings.load() { didSet { settings.save() } }
    let library = ModLibrary()
    let catalog = Catalog()
    let downloads = Downloads()
    let steam = SteamLink()
    let gameFiles = GameFiles()
    let pad = PadInput()
    let cloud = CloudSaves()
    @Published var otherPlaying: CloudSaves.Playing?
    private var steamLoop: Task<Void, Never>?
    #if os(macOS)
    weak var window: NSWindow?
    #endif
    init() {
        downloads.library = library
        GameFiles.installRuntime()          // this build's shaders and FFNx tables into the game folder
        if steam.signedIn { Task { await steam.sync() } }   // unlocks from the last session, fresh state
        Task {
            await catalog.load()                             // for the "new version" notices
            // tests: FF7_TEST_DOWNLOAD="<catalog mod ID>" downloads it, pauses after 1 s, goes on 2 s later
            if let id = ProcessInfo.processInfo.environment["FF7_TEST_DOWNLOAD"], let m = catalog.mods.first(where: { $0.id == id }) {
                downloads.start(m)
                try? await Task.sleep(nanoseconds: 1_000_000_000); downloads.pause(id)
                try? await Task.sleep(nanoseconds: 2_000_000_000); NSLog("[test] paused: %@", downloads.jobs[id]?.status ?? "-"); downloads.resume(id)
            }
        }
    }

    /// Play, unless another Mac has a recent note that it is playing (then the launcher asks).
    func play() {
        if otherPlaying == nil, let p = CloudSaves.otherDevicePlaying() { otherPlaying = p; return }
        otherPlaying = nil
        playNow()
    }

    func playNow() {
        otherPlaying = nil
        CloudSaves.beforePlay()
        Paths.ensure()
        FontFix.apply()
        library.save()
        settings.writeBoosters()
        do { try Toml.write(settings, mods: library.mods, steam: steam.active) } catch {
            library.lastError = "เขียน FFNx.toml ไม่ได้: \(error.localizedDescription)"; return
        }
        if settings.start == "title" { try? Paths.fm.removeItem(at: Paths.quickboot) }
        else { try? settings.start.write(to: Paths.quickboot, atomically: true, encoding: .utf8) }
        // while the game runs: achievements it unlocks go to Steam within a minute
        if steam.active {
            steamLoop = Task { [steam] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                    if steam.waiting > 0 { await steam.sync() }
                }
            }
        }
        #if os(macOS)
        window?.orderOut(nil)
        settings.display.withCString { c_start_game(Int32(settings.aspect), settings.fullscreen ? 1 : 0, $0) }
        window?.close()
        #endif
    }
}

enum Pane: String, CaseIterable, Identifiable {
    case play = "เล่น", settings = "ตั้งค่า", mods = "ม็อดของฉัน", catalog = "ค้นหาม็อด"
    case downloads = "ดาวน์โหลด", saves = "เซฟเกม", achievements = "Achievements", controls = "ปุ่มควบคุม"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .play: return "play.circle"
        case .settings: return "slider.horizontal.3"
        case .mods: return "shippingbox"
        case .catalog: return "magnifyingglass"
        case .downloads: return "arrow.down.circle"
        case .saves: return "externaldrive"
        case .achievements: return "trophy"
        case .controls: return "gamecontroller"
        }
    }
}

/// A picture from a local file (mod previews).
struct LocalImage: View {
    let url: URL?
    var body: some View {
        #if os(macOS)
        if let u = url, let i = NSImage(contentsOf: u) { Image(nsImage: i).resizable().scaledToFit() } else { placeholder }
        #else
        if let u = url, let i = UIImage(contentsOfFile: u.path) { Image(uiImage: i).resizable().scaledToFit() } else { placeholder }
        #endif
    }
    var placeholder: some View {
        RoundedRectangle(cornerRadius: 6).fill(.quaternary).overlay(Image(systemName: "photo").foregroundStyle(.secondary))
    }
}

/// Bytes for fileExporter.
struct BytesDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    static var writableContentTypes: [UTType] { [.data, .zip] }
    var data: Data
    init(_ d: Data) { data = d }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct LauncherView: View {
    @ObservedObject var state: LauncherState
    @ObservedObject var downloads: Downloads
    @State private var pane: Pane? = Pane.allCases.first { $0.icon == ProcessInfo.processInfo.environment["FF7_LAUNCHER_PANE"] } ?? .play
    @State private var tvMode = ProcessInfo.processInfo.environment["FF7_LAUNCHER_TV"] != nil

    var body: some View {
        ZStack {
            if !tvMode { normal }
            if tvMode { TVModeView(state: state, library: state.library, pad: state.pad) { tvMode = false }.transition(.opacity) }
        }
        .animation(.easeInOut(duration: 0.2), value: tvMode)
        .onAppear(perform: armPad)
        .onChange(of: tvMode) { _ in armPad() }
    }

    /// Outside TV mode, any controller button opens it.
    func armPad() { if !tvMode { state.pad.onPress = { _ in tvMode = true } } }

    var normal: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { p in
                HStack {
                    Label(p.rawValue, systemImage: p.icon)
                    if p == .catalog { UpdatesBadge(catalog: state.catalog, library: state.library) }
                    if p == .downloads, downloads.active > 0 {
                        Spacer()
                        Text("\(downloads.active)").font(.caption.bold()).padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(.blue)).foregroundStyle(.white)
                    }
                }
                .tag(p)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            switch pane ?? .play {
            case .play: PlayView(state: state, library: state.library)
            case .settings: SettingsView(state: state)
            case .mods: MyModsView(library: state.library, gameFiles: state.gameFiles)
            case .catalog: CatalogView(catalog: state.catalog, downloads: state.downloads, library: state.library)
            case .downloads: DownloadsView(downloads: state.downloads)
            case .saves: SavesView(cloud: state.cloud)
            case .achievements: AchievementsView(steam: state.steam)
            case .controls: ControlsView()
            }
        }
        .frame(minWidth: 980, minHeight: 640)
    }
}

// MARK: Play

/// The number of installed mods with a new version, beside "ค้นหาม็อด" in the sidebar.
struct UpdatesBadge: View {
    @ObservedObject var catalog: Catalog
    @ObservedObject var library: ModLibrary
    var body: some View {
        let n = catalog.updates(library).count
        if n > 0 {
            Spacer()
            Text("\(n)").font(.caption.bold()).padding(.horizontal, 6).padding(.vertical, 1)
                .background(Capsule().fill(.orange)).foregroundStyle(.white).help("ม็อดที่มีเวอร์ชันใหม่")
        }
    }
}

/// On the Play page: installed mods with a new version in the catalog, and updating them all.
struct UpdatesBanner: View {
    @ObservedObject var catalog: Catalog
    @ObservedObject var library: ModLibrary
    @ObservedObject var downloads: Downloads
    @State private var open = false
    var body: some View {
        let ups = catalog.updates(library).filter { downloads.jobs[$0.id] == nil }
        if !ups.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(.orange)
                    Text("ม็อดมีเวอร์ชันใหม่ \(ups.count) ตัว").fontWeight(.semibold)
                    Spacer()
                    Button(open ? "ซ่อน" : "ดู") { open.toggle() }.buttonStyle(.link)
                    Button("อัปเดตทั้งหมด") { ups.forEach(downloads.start) }.controlSize(.small)
                }
                if open {
                    ForEach(ups) { m in
                        HStack {
                            Text(m.name).lineLimit(1)
                            Spacer()
                            Text("\(Catalog.installedVersion(m, library) ?? "") → \(m.version)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            Button("อัปเดต") { downloads.start(m) }.controlSize(.small)
                        }
                    }
                }
            }
            .padding(12).frame(width: 520)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
        }
    }
}

struct PlayView: View {
    @ObservedObject var state: LauncherState
    @ObservedObject var library: ModLibrary
    @Environment(\.openURL) private var openURL
    @State private var reportDoc: BytesDocument?
    @State private var reportError: String?

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Text("FINAL FANTASY VII").font(.system(size: 40, weight: .bold, design: .serif))
            Text("FF7Recomp").foregroundStyle(.secondary)
            if !Paths.gameReady || state.gameFiles.dataLinkedTo != nil || !state.gameFiles.exeMatches {
                GameFilesBox(files: state.gameFiles)
            }
            Picker("เริ่มที่", selection: $state.settings.start) {
                Text("หน้าไตเติล").tag("title")
                Text("เกมใหม่ทันที").tag("newgame")
                Text("เล่นต่อจากเซฟล่าสุด").tag("continue")
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 420)
            Button(action: state.play) {
                Label("เล่น", systemImage: "play.fill").font(.title2).frame(width: 200, height: 36)
            }
            .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            .disabled(!Paths.gameReady || !state.gameFiles.exeMatches)
            let on = library.mods.filter { $0.enabled }
            Text(on.isEmpty ? "ไม่มีม็อดที่เปิดใช้" : "ม็อดที่เปิดใช้ \(on.count) ตัว: " + on.prefix(4).map { $0.title }.joined(separator: ", ") + (on.count > 4 ? " …" : ""))
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 560)
            if let e = library.lastError { Text(e).foregroundStyle(.red) }
            UpdatesBanner(catalog: state.catalog, library: library, downloads: state.downloads)
            Spacer()
            Text("มีจอย? กดปุ่มใดก็ได้บนจอยเพื่อเข้าโหมดทีวี").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("เปิดโฟลเดอร์เกม") { openURL(Paths.base) }
                Button("เปิด log ล่าสุด") { openURL(Paths.log) }
                Button("รายงานปัญหา…") {
                    do { reportDoc = BytesDocument(try Data(contentsOf: Report.build())) }
                    catch { reportError = error.localizedDescription }
                }
                .help("รวม log ตั้งค่า และรายการม็อดเป็นไฟล์ .zip ไฟล์เดียว (ไม่มีไฟล์เกมและข้อมูลบัญชี Steam) แนบไปกับรายงานบั๊กได้เลย")
            }
            .buttonStyle(.link).padding(.bottom)
            .fileExporter(isPresented: Binding(get: { reportDoc != nil }, set: { if !$0 { reportDoc = nil } }), document: reportDoc,
                          contentType: .zip, defaultFilename: "FF7Recomp-report.zip") { _ in reportDoc = nil }
            .alert("กำลังเล่นอยู่ที่เครื่องอื่น?", isPresented: Binding(get: { state.otherPlaying != nil }, set: { if !$0 { state.otherPlaying = nil } })) {
                Button("เล่นต่อที่เครื่องนี้") { state.playNow() }
                Button("ยกเลิก", role: .cancel) { state.otherPlaying = nil }
            } message: {
                Text("“\(state.otherPlaying?.device ?? "")” เริ่มเล่นไว้เมื่อ \(state.otherPlaying?.since.formatted(date: .omitted, time: .shortened) ?? "") และยังไม่ได้ปิดเกม ถ้าเล่นพร้อมกันสองเครื่อง เครื่องที่เซฟทีหลังจะทับอีกเครื่อง (เซฟก่อนหน้าสำรองไว้ใน save-backups ทุกครั้งที่กดเล่น)")
            }
            .alert("สร้างไฟล์รายงานไม่ได้", isPresented: Binding(get: { reportError != nil }, set: { if !$0 { reportError = nil } })) {
                Button("ตกลง") { reportError = nil }
            } message: { Text(reportError ?? "") }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("เล่น")
    }
}

// MARK: Game files

struct GameFilesBox: View {
    @ObservedObject var files: GameFiles
    @State private var picking = false
    @State private var showGuide = ProcessInfo.processInfo.environment["FF7_LAUNCHER_GUIDE"] != nil   // tests
    var body: some View {
        VStack(spacing: 10) {
            if !Paths.gameReady {
                Text("ยังไม่มีไฟล์เกม: ต้องมี FINAL FANTASY VII เวอร์ชัน Steam ของคุณเอง").font(.headline).foregroundStyle(.orange)
            } else if !files.exeMatches {
                Text("ไฟล์เกมในเครื่องไม่ตรงกับที่แอปนี้ถูก build มา").foregroundStyle(.orange)
            } else if let l = files.dataLinkedTo {
                Text("ข้อมูลเกมยังลิงก์ไปที่ \(l.replacingOccurrences(of: NSHomeDirectory(), with: "~"))\nถ้าย้ายหรือลบโฟลเดอร์นั้นเกมจะเปิดไม่ได้ กด “ค้นหา FF7 ในเครื่อง” แล้ว “นำเข้า” เพื่อก๊อปมาเก็บในแอป")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if let b = files.busy {
                ProgressView(value: files.progress) { Text(b).font(.caption) }.frame(width: 360)
            } else {
                HStack {
                    Button { Task { await files.findGame() } } label: { Label("ค้นหา FF7 ในเครื่อง", systemImage: "magnifyingglass") }
                        .buttonStyle(.borderedProminent).disabled(files.searching)
                    Button { picking = true } label: { Label("เลือกโฟลเดอร์เอง…", systemImage: "folder") }
                    Button { showGuide = true } label: { Label("วิธีได้ไฟล์เกม", systemImage: "questionmark.circle") }
                }
                if files.searching { ProgressView().controlSize(.small) }
                ForEach(files.found) { f in
                    HStack {
                        Image(systemName: f.matches == false ? "exclamationmark.triangle" : "checkmark.seal").foregroundStyle(f.matches == false ? .orange : .green)
                        Text(f.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.callout).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        if f.matches == false { Text("เวอร์ชันไม่ตรงกับแอป").font(.caption).foregroundStyle(.orange) }
                        else { Button("นำเข้า") { Task { await files.importGame(from: f.url) } } }
                    }
                    .frame(maxWidth: 560)
                }
            }
            if let m = files.message { Text(m).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center) }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { r in
            guard let u = try? r.get() else { return }
            let ok = u.startAccessingSecurityScopedResource()
            Task { await files.importGame(from: u); if ok { u.stopAccessingSecurityScopedResource() } }
        }
        .sheet(isPresented: $showGuide) { GameGuideView { showGuide = false } }
    }
}

/// How to get the game's files onto this Mac: they must come from the player's own Steam copy.
struct GameGuideView: View {
    let close: () -> Void
    let steamcmd = """
    mkdir -p ~/steamcmd && cd ~/steamcmd
    curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz" | tar zxf -
    ./steamcmd.sh +@sSteamCmdForcePlatformType windows +force_install_dir ~/FF7 +login ชื่อบัญชีSteam +app_update 3837340 validate +quit
    """
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("วิธีได้ไฟล์เกม (ต้องทำก่อนเล่น)").font(.title2.bold())
                Text("แอปนี้ไม่มีไฟล์เกม ต้องใช้ FINAL FANTASY VII ที่คุณซื้อบน Steam เท่านั้น (เวอร์ชันที่ขายอยู่ปัจจุบัน) ไฟล์เกมที่ใช้คือเวอร์ชัน Windows")
                step("1", "ซื้อ FINAL FANTASY VII บน Steam", "ใช้บัญชี Steam ของคุณเอง เวอร์ชันอื่น (เช่น 7th Heaven 1998, GOG, App Store, PlayStation) ยังใช้ไม่ได้")
                step("2", "โหลดไฟล์เกม เลือกวิธีใดวิธีหนึ่ง", nil)
                VStack(alignment: .leading, spacing: 10) {
                    option("ก. มีคอม Windows", "ติดตั้งเกมใน Steam → คลิกขวาที่เกม → Manage → Browse local files → ก๊อปโฟลเดอร์ “FINAL FANTASY VII Steam Edition” ทั้งโฟลเดอร์ (ประมาณ 3.5 GB) มาไว้ใน Mac ผ่านไดรฟ์ภายนอกหรือแชร์ไฟล์ จะวางไว้ที่ Downloads หรือในไดรฟ์ภายนอกก็ได้")
                    option("ข. บน Mac ด้วย CrossOver หรือ Whisky", "ติดตั้ง Steam เวอร์ชัน Windows ใน bottle แล้วติดตั้ง FINAL FANTASY VII ตามปกติ ไม่ต้องเปิดเล่น แค่ให้โหลดเสร็จ")
                    VStack(alignment: .leading, spacing: 6) {
                        option("ค. บน Mac ด้วย steamcmd (เครื่องมือของ Valve ใน Terminal)", "เปิด Terminal แล้ววางคำสั่งนี้ (เปลี่ยน ชื่อบัญชีSteam เป็นชื่อล็อกอินของคุณ) จะถามรหัสผ่านและรหัส Steam Guard ใน Terminal ไฟล์เกมจะไปอยู่ที่ ~/FF7")
                        Text(steamcmd).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            .padding(8).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                        Button("ก๊อปคำสั่ง") {
                            #if os(macOS)
                            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(steamcmd, forType: .string)
                            #endif
                        }
                    }
                }
                .padding(.leading, 34)
                step("3", "กด “ค้นหา FF7 ในเครื่อง” แล้วกด “นำเข้า”", "แอปจะค้นใน Steam, CrossOver, Whisky, ~/FF7, Downloads, Desktop, Documents และไดรฟ์ภายนอกที่เสียบอยู่ (macOS อาจถามสิทธิ์เข้าถึงโฟลเดอร์ ให้กดอนุญาต) ไฟล์จะถูกก๊อปมาเก็บในแอป หลังนำเข้าแล้วลบโฟลเดอร์ต้นทางได้")
                Divider()
                Text("ห้ามแชร์ไฟล์เกมหรือแอปที่ build แล้วให้คนอื่น ทุกคนต้องใช้เกมที่ซื้อเอง").font(.callout).foregroundStyle(.secondary)
                HStack { Spacer(); Button("ปิด", action: close).keyboardShortcut(.defaultAction) }
            }
            .padding(24)
        }
        .frame(width: 700, height: 640)
    }

    func step(_ n: String, _ title: String, _ detail: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(n).font(.headline).frame(width: 22, height: 22).background(Circle().fill(.blue)).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                if let d = detail { Text(d).foregroundStyle(.secondary) }
            }
        }
    }
    func option(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(title).fontWeight(.semibold); Text(detail).foregroundStyle(.secondary).font(.callout) }
    }
}

#if os(macOS)
struct ReliftView: View {
    @ObservedObject var files: GameFiles
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ทำให้ม็อดเร็วขึ้น").font(.title2.bold())
            Text("ม็อดบางตัว (เช่น Enhanced Stock UI) แก้โค้ดของเกม โค้ดส่วนนั้นจะรันผ่าน interpreter ซึ่งช้ากว่า ปุ่มนี้จะ lift โค้ดของชุดม็อดที่เปิดอยู่เข้าไปในแอปให้รันแบบ native ใช้เวลาประมาณ 5–10 นาที ทำใหม่ทุกครั้งที่เปลี่ยนชุดม็อดหรือตัวเลือกของม็อด เสร็จแล้วต้องเปิดแอปใหม่")
                .foregroundStyle(.secondary)
            ScrollView {
                Text(files.log.joined(separator: "\n")).font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            .frame(height: 200).padding(6).background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
            if let m = files.message { Text(m).font(.callout) }
            HStack {
                if files.busy != nil { ProgressView().controlSize(.small); Text(files.busy ?? "").font(.caption) }
                Spacer()
                Button("ปิด", action: close)
                Button("เริ่ม") { files.reliftMods() }.buttonStyle(.borderedProminent).disabled(files.busy != nil)
                if files.message?.contains("เปิดแอปใหม่") == true { Button("ปิดแอป") { NSApp.terminate(nil) } }
            }
        }
        .padding(20).frame(width: 640)
    }
}
#endif

// MARK: Settings

struct SettingsView: View {
    @ObservedObject var state: LauncherState
    let mults = [1, 2, 3, 5, 10]

    var body: some View {
        Form {
            Section("ไฟล์เกม") { GameFilesBox(files: state.gameFiles).frame(maxWidth: .infinity) }
            Section {
                Picker("อัตราส่วนจอ", selection: $state.settings.aspect) {
                    Text("4:3 (ต้นฉบับ)").tag(0)
                    Text("16:9 Widescreen").tag(2)
                    Text("16:10").tag(3)
                    Text("21:9 Ultrawide").tag(4)
                    Text("ยืดเต็มหน้าต่าง").tag(1)
                }
                if state.settings.aspect == 4 {
                    Picker("แถบสถานะฉากต่อสู้ (21:9)", selection: $state.settings.battleHud) {
                        Text("ตำแหน่งแบบ 16:9 (มองง่าย)").tag(0)
                        Text("ขยับออกครึ่งทาง").tag(1)
                        Text("ชิดขอบจอ").tag(2)
                    }
                    .help("ม็อด UI จัดหน้าต่างฉากต่อสู้ไว้สำหรับ 16:9 เลือกได้ว่าจะให้แถบ HP/MP อยู่ตรงนั้น หรือขยับไปทางขอบขวาของจอ 21:9")
                }
                Toggle("เต็มจอเมื่อเริ่มเกม", isOn: $state.settings.fullscreen)
                #if os(macOS)
                Picker("จอที่ใช้เล่น", selection: $state.settings.display) {
                    Text("จอหลัก").tag("")
                    ForEach(NSScreen.screens.dropFirst().map { $0.localizedName }, id: \.self) { Text($0).tag($0) }
                }
                #endif
                Picker("ความละเอียดภายใน", selection: $state.settings.resolutionScale) {
                    Text("อัตโนมัติ").tag(0)
                    ForEach(1...4, id: \.self) { Text("\($0)× (" + String(640 * $0) + "×" + String(480 * $0) + ")").tag($0) }
                }
                Picker("Anti-aliasing", selection: $state.settings.antialiasing) {
                    Text("ปิด").tag(0); Text("2×").tag(2); Text("4×").tag(4); Text("8×").tag(8)
                }
                Toggle("Bilinear filtering (ภาพนุ่มขึ้น)", isOn: $state.settings.bilinear)
                Toggle("ฟิลเตอร์ CRT (เส้นสแกนแบบจอทีวี)", isOn: $state.settings.crt)
                Toggle("สีแบบ NTSC-J (สีของ PlayStation ญี่ปุ่น)", isOn: $state.settings.ntscj)
                Toggle("VSync", isOn: $state.settings.vsync)
                Toggle("แสดง FPS", isOn: $state.settings.showFps)
            } header: { Text("ภาพ") } footer: {
                Text("AirPlay: เปิด AirPlay ไปที่ Apple TV/ทีวีจากศูนย์ควบคุมของ Mac แล้วเลือก “ใช้เป็นจอแยก” (ไม่ใช่ mirror) จอนั้นจะขึ้นในรายการ “จอที่ใช้เล่น” เลือกแล้วเปิด “เต็มจอเมื่อเริ่มเกม”  21:9: ฉากต่อสู้ world map และฉากที่กว้างพอจะเต็มจอ ฉากที่ฉากหลังแคบกว่าจะมีขอบดำซ้ายขวา  NTSC-J เป็นฟีเจอร์ของ FFNx (7th Heaven แค่มีปุ่มเปิด)")
                    .font(.caption)
            }
            Section("ความเร็ว") {
                Picker("Frame rate", selection: $state.settings.fps) {
                    Text("ต้นฉบับ").tag(0)
                    Text("ต้นฉบับ (แก้จังหวะเฟรม)").tag(1)
                    Text("ฉากต่อสู้ 30 FPS").tag(2)
                    Text("60 FPS ทั้งเกม").tag(3)
                    Text("120 FPS (ทดลอง)").tag(4)
                }
                Toggle("เร่งความเร็ว 2× ตั้งแต่เริ่ม", isOn: $state.settings.speed2x)
            }
            Section("เสียง") {
                LabeledContent("เพลง \(state.settings.musicVolume)%") {
                    Slider(value: Binding(get: { Double(state.settings.musicVolume) }, set: { state.settings.musicVolume = Int($0) }), in: 0...100, step: 5)
                }
                LabeledContent("เสียงเอฟเฟกต์ \(state.settings.sfxVolume)%") {
                    Slider(value: Binding(get: { Double(state.settings.sfxVolume) }, set: { state.settings.sfxVolume = Int($0) }), in: 0...100, step: 5)
                }
            }
            Section {
                Picker("การสั่นของจอย", selection: $state.settings.rumble) {
                    Text("ปิด").tag(0); Text("เบา").tag(1); Text("แรง").tag(2)
                }
                Toggle("Analog stick (เดิน/วิ่งตามแรงกด, หมุนกล้องตอนต่อสู้)", isOn: $state.settings.analog)
                Toggle("กดค้างปุ่มตกลงเพื่อกดรัว (ตอนต่อสู้)", isOn: $state.settings.autofire)
            } header: { Text("จอย") } footer: {
                Text("สั่นเมื่อโจมตีโดนหรือโดนโจมตี (เวทมนตร์ มนตร์อสูร และ Limit Break ที่แรงจะสั่นหนักกว่า) และเมื่อฉากสั่น  ใช้กับจอยที่รองรับการสั่นบน Mac (DualSense, DualShock 4, Xbox)")
                    .font(.caption)
            }
            Section("เกม") {
                Picker("ภาษา", selection: $state.settings.language) {
                    Text("English").tag(1); Text("Français").tag(2); Text("Deutsch").tag(3); Text("Español").tag(4)
                }
                Toggle("เจอศัตรูแบบสุ่ม", isOn: $state.settings.encounters)
                Picker("Gil ที่ได้", selection: $state.settings.gilMult) { ForEach(mults, id: \.self) { Text("\($0)×").tag($0) } }
                Picker("EXP ที่ได้", selection: $state.settings.expMult) { ForEach(mults, id: \.self) { Text("\($0)×").tag($0) } }
                Picker("AP ที่ได้", selection: $state.settings.apMult) { ForEach(mults, id: \.self) { Text("\($0)×").tag($0) } }
            }
            Section {
                Text("ค่าทั้งหมดจะถูกเขียนลง FFNx.toml ตอนกดเล่น ม็อดที่มีค่า FFNx ของตัวเองอาจทับบางค่า (ยกเว้นความละเอียดที่เลือกเอง)")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("คืนค่าเริ่มต้น") { state.settings = Settings() }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("ตั้งค่า")
    }
}

// MARK: My mods (7th Heaven's library)

struct MyModsView: View {
    @ObservedObject var library: ModLibrary
    var gameFiles: GameFiles? = nil
    @State private var reliftSheet = false
    @State private var selected: InstalledMod.ID? = ProcessInfo.processInfo.environment["FF7_LAUNCHER_MOD"]   // tests
    @State private var search = ""
    @State private var conflicts: String?
    @State private var importing = false
    @State private var confirmRemove = false

    var shown: [InstalledMod] {
        search.isEmpty ? library.mods : library.mods.filter {
            $0.title.localizedCaseInsensitiveContains(search) || ($0.info?.author ?? "").localizedCaseInsensitiveContains(search)
                || ($0.info?.category ?? "").localizedCaseInsensitiveContains(search)
        }
    }
    var current: InstalledMod? { library.mods.first { $0.id == selected } }

    var body: some View {
        VSplitView {
            VStack(spacing: 0) {
                HStack {
                    TextField("ค้นหาในม็อดของฉัน", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                    Spacer()
                    Button("เปิดทั้งหมด") { library.setAll(true) }
                    Button("ปิดทั้งหมด") { library.setAll(false) }
                    Button { conflicts = library.conflictsSummary } label: { Label("ตรวจม็อดชนกัน", systemImage: "exclamationmark.triangle") }
                    Button { importing = true } label: { Label("เพิ่มจากไฟล์…", systemImage: "plus") }
                    #if os(macOS)
                    Button { reliftSheet = true } label: { Label("ทำให้ม็อดเร็วขึ้น…", systemImage: "bolt") }
                        .help("lift โค้ดที่ม็อดแก้ให้รันแบบ native แทน interpreter (ทำหลังเปลี่ยนชุดม็อด)")
                    #endif
                }
                .padding(8)
                HStack(spacing: 0) {
                    Table(shown, selection: $selected) {
                        TableColumn("") { m in
                            Toggle("", isOn: Binding(get: { m.enabled }, set: { library.setEnabled(m, $0) })).labelsHidden()
                        }.width(28)
                        TableColumn("#") { m in Text("\((library.mods.firstIndex { $0.id == m.id } ?? 0) + 1)").foregroundStyle(.secondary) }.width(26)
                        TableColumn("ชื่อ") { m in
                            HStack {
                                Text(m.title).fontWeight(.medium)
                                if m.info?.error != nil { Image(systemName: "xmark.octagon").foregroundStyle(.red) }
                                else if m.info?.unsupported.isEmpty == false { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange) }
                            }.opacity(m.enabled ? 1 : 0.5)
                        }
                        TableColumn("ผู้สร้าง") { m in Text(m.info?.author ?? "").foregroundStyle(.secondary) }.width(min: 80, ideal: 140)
                        TableColumn("หมวด") { m in Text(m.info?.category ?? "") }.width(min: 80, ideal: 120)
                        TableColumn("เวอร์ชัน") { m in Text(m.info?.version ?? "").monospacedDigit() }.width(70)
                    }
                    .overlay {
                        if library.mods.isEmpty {
                            Text("ยังไม่มีม็อด\nลากไฟล์ .7z / .iro / .zip มาวางที่นี่ หรือไปที่ “ค้นหาม็อด”")
                                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        }
                    }
                    VStack(spacing: 8) {   // 7th Heaven's order buttons
                        orderButton("arrow.up.to.line", "ขึ้นบนสุด", -2)
                        orderButton("arrow.up", "ขึ้น", -1)
                        orderButton("arrow.down", "ลง", 1)
                        orderButton("arrow.down.to.line", "ลงล่างสุด", 2)
                        Divider().frame(width: 24)
                        Button { confirmRemove = true } label: { Image(systemName: "trash") }.help("ลบม็อด").disabled(current == nil)
                    }
                    .buttonStyle(.borderless).padding(8)
                }
                HStack {
                    if let b = library.busy { ProgressView().controlSize(.small); Text(b).font(.caption) }
                    if let e = library.lastError { Text(e).foregroundStyle(.red).font(.caption) }
                    Spacer()
                    Text("ม็อดที่อยู่บนชนะเมื่อแก้ไฟล์เดียวกัน · ม็อด User Interface ควรอยู่บนสุด").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
            }
            .frame(minHeight: 220, idealHeight: 340)
            Group {
                if let m = current { ModDetail(mod: m, library: library).id(m.id) }
                else { Text("เลือกม็อดเพื่อดูรายละเอียดและตั้งค่า").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
            .frame(minHeight: 260)
        }
        .navigationTitle("ม็อดของฉัน")
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { u, _ in if let u { Task { @MainActor in await library.install(u) } } }
            }
            return true
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item, .folder], allowsMultipleSelection: true) { r in
            for u in (try? r.get()) ?? [] {
                let ok = u.startAccessingSecurityScopedResource()
                Task { await library.install(u); if ok { u.stopAccessingSecurityScopedResource() } }
            }
        }
        .sheet(isPresented: $reliftSheet) { if let g = gameFiles { ReliftView(files: g) { reliftSheet = false } } }
        .alert("ม็อดชนกัน", isPresented: Binding(get: { conflicts != nil }, set: { if !$0 { conflicts = nil } })) {
            Button("ตกลง") { conflicts = nil }
        } message: { Text(conflicts?.isEmpty == false ? conflicts! : "ไม่พบม็อดที่แก้ไฟล์เดียวกัน") }
        .confirmationDialog("ลบ \(current?.title ?? "")?", isPresented: $confirmRemove) {
            Button("ลบ", role: .destructive) { if let m = current { library.remove(m); selected = nil } }
        } message: { Text("ไฟล์ม็อดจะถูกลบออกจากเครื่อง") }
    }

    func orderButton(_ icon: String, _ help: String, _ how: Int) -> some View {
        Button { if let m = current { library.shift(m, how) } } label: { Image(systemName: icon) }
            .help(help).disabled(current == nil || !search.isEmpty)
    }
}

/// The selected mod: Info / Configure (7th Heaven's Configure Mod window) / Readme.
struct ModDetail: View {
    @ObservedObject var mod: InstalledMod
    let library: ModLibrary
    @State private var tab = Int(ProcessInfo.processInfo.environment["FF7_LAUNCHER_TAB"] ?? "") ?? 0   // tests
    @State private var focus: String?          // the option the preview shows
    @Environment(\.openURL) private var openURL

    var body: some View {
        let ex = mod.extras
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(mod.title).font(.title3.bold())
                Text([mod.info?.author, mod.info?.version.isEmpty == false ? "v" + (mod.info?.version ?? "") : nil].compactMap { $0 }.joined(separator: " · "))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $tab) {
                    Text("ข้อมูล").tag(0)
                    Text("ตั้งค่าม็อด (\(mod.info?.options.count ?? 0))").tag(1)
                    if ex.readme != nil { Text("Readme").tag(2) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 330)
            }
            .padding(10)
            Divider()
            switch tab {
            case 1: configure(ex)
            case 2: ScrollView { Text(ex.readme ?? "").font(.system(.callout, design: .monospaced)).textSelection(.enabled).padding() }
            default: info(ex)
            }
        }
    }

    func info(_ ex: ModExtras) -> some View {
        HStack(alignment: .top, spacing: 16) {
            LocalImage(url: ex.preview).frame(width: 300, height: 200)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let i = mod.info {
                        Text([i.category, ex.releaseDate.isEmpty ? "" : "ออกเมื่อ \(ex.releaseDate)"].filter { !$0.isEmpty }.joined(separator: " · "))
                            .foregroundStyle(.secondary)
                        if !i.description.isEmpty { Text(i.description).textSelection(.enabled) }
                        if !ex.releaseNotes.isEmpty { Text("มีอะไรใหม่").font(.headline); Text(ex.releaseNotes).font(.callout) }
                        if !i.requires.isEmpty { Label("ต้องใช้คู่กับ: " + i.requires.map { $0.why.isEmpty ? $0.id : $0.why }.joined(separator: "; "), systemImage: "link") }
                        if !i.forbids.isEmpty { Label("ใช้ร่วมไม่ได้กับ: " + i.forbids.map { $0.why.isEmpty ? $0.id : $0.why }.joined(separator: "; "), systemImage: "nosign") }
                        if !i.unsupported.isEmpty {
                            Label("ส่วนที่ใช้ไม่ได้ในเวอร์ชันนี้: " + i.unsupported.joined(separator: ", "), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        }
                        if let l = URL(string: i.link), !i.link.isEmpty { Button("หน้าเว็บของม็อด") { openURL(l) }.buttonStyle(.link) }
                    }
                    Text("ไฟล์: \(mod.path)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
    }

    func configure(_ ex: ModExtras) -> some View {
        let opts = mod.info?.options ?? []
        let f = focus ?? opts.first?.id
        let fo = opts.first { $0.id == f }
        let previewURL: URL? = fo.flatMap { o in ex.optionPreview["\(o.id.lowercased())=\(mod.value(of: o))"] ?? ex.optionPreview[o.id.lowercased()] } ?? ex.preview
        return Group {
            if opts.isEmpty {
                Text("ม็อดนี้ไม่มีตัวเลือกให้ตั้งค่า").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    List(opts, selection: Binding(get: { f }, set: { focus = $0 })) { o in
                        OptionRow(mod: mod, option: o, library: library).tag(o.id)
                    }
                    .frame(minWidth: 320)
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        LocalImage(url: previewURL).frame(maxWidth: .infinity, maxHeight: 260)
                        if let o = fo {
                            Text(o.name).font(.headline)
                            if !o.description.isEmpty { ScrollView { Text(o.description).font(.callout).frame(maxWidth: .infinity, alignment: .leading) } }
                        }
                        Spacer()
                        Button("คืนค่าเริ่มต้นของม็อดนี้") { library.resetOptions(mod) }
                    }
                    .padding().frame(minWidth: 280)
                }
            }
        }
    }
}

struct OptionRow: View {
    @ObservedObject var mod: InstalledMod
    let option: ModInfo.Option
    let library: ModLibrary
    var body: some View {
        let binding = Binding(get: { mod.value(of: option) }, set: { library.setOption(mod, option.id, $0) })
        if option.type.lowercased() == "bool" {
            Toggle(option.name, isOn: Binding(get: { binding.wrappedValue != 0 }, set: { binding.wrappedValue = $0 ? 1 : 0 }))
        } else {
            Picker(option.name, selection: binding) {
                ForEach(option.values, id: \.self) { v in Text(v.name.isEmpty ? String(v.value) : v.name).tag(v.value) }
            }
        }
    }
}

// MARK: Get mods

struct CatalogView: View {
    @ObservedObject var catalog: Catalog
    @ObservedObject var downloads: Downloads
    @ObservedObject var library: ModLibrary
    @State private var search = ""
    @State private var category = ""
    @State private var selected: String?
    @State private var onlyUpdates = false

    var filtered: [CatalogMod] {
        let ups = onlyUpdates ? Set(catalog.updates(library).map { $0.id }) : []
        return catalog.mods.filter { m in
            (!onlyUpdates || ups.contains(m.id)) &&
            (category.isEmpty || m.category == category) &&
            (search.isEmpty || m.name.localizedCaseInsensitiveContains(search) || m.author.localizedCaseInsensitiveContains(search)
                || m.tags.contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    TextField("ค้นหาชื่อ ผู้สร้าง หรือแท็ก", text: $search).textFieldStyle(.roundedBorder)
                    Picker("", selection: $category) {
                        Text("ทุกหมวด").tag("")
                        ForEach(catalog.categories, id: \.self) { Text($0).tag($0) }
                    }
                    .frame(width: 170)
                    Toggle("มีอัปเดต", isOn: $onlyUpdates).toggleStyle(.button)
                    Button { Task { await catalog.load(force: true) } } label: { Image(systemName: "arrow.clockwise") }
                        .help("โหลด catalog ใหม่")
                }
                .padding(8)
                List(filtered, selection: $selected) { m in CatalogRow(mod: m, downloads: downloads, library: library).tag(m.id) }
                    .overlay {
                        if catalog.loading { ProgressView("กำลังโหลด catalog…") }
                        else if let e = catalog.error, catalog.mods.isEmpty { Text(e).foregroundStyle(.red) }
                    }
                Text("\(filtered.count) ม็อด · จาก catalog ของ 7th Heaven (Qhimm, Sega)").font(.caption).foregroundStyle(.secondary).padding(6)
            }
            .frame(minWidth: 420)
            Group {
                if let id = selected, let m = catalog.mods.first(where: { $0.id == id }) {
                    CatalogDetail(mod: m, downloads: downloads, library: library)
                } else {
                    Text("เลือกม็อดเพื่อดูรายละเอียด").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 320)
        }
        .navigationTitle("ค้นหาม็อด")
        .task { await catalog.load() }
    }
}

struct InstallButton: View {
    let mod: CatalogMod
    @ObservedObject var downloads: Downloads
    @ObservedObject var library: ModLibrary
    @Environment(\.openURL) private var openURL
    var body: some View {
        // installed from the catalog here, or a mod whose mod.xml carries the catalog's ID
        let inst = Catalog.installedVersion(mod, library)
        if let j = downloads.jobs[mod.id] {
            VStack(alignment: .trailing, spacing: 2) {
                if j.task != nil || j.paused { ProgressView(value: j.progress).frame(width: 120) }
                HStack(spacing: 4) {
                    Text(j.status).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    if j.task == nil, !j.paused, j.status.contains("เบราว์เซอร์"), let u = Catalog.browserLink(mod) {
                        Button("เปิด") { openURL(u); downloads.cancel(mod.id) }
                    } else {
                        DownloadControls(id: mod.id, job: j, downloads: downloads)
                    }
                }
            }
            .frame(width: 200, alignment: .trailing)
        } else if let inst, !Catalog.isNewer(mod.version, than: inst) {
            Label("ติดตั้งแล้ว", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
        } else if let inst {
            Button("อัปเดต \(inst.isEmpty ? "" : inst + " → ")\(mod.version)") { downloads.start(mod) }
                .controlSize(.small).tint(.orange)
        } else {
            Button("ดาวน์โหลด (\(mod.sizeText))") { downloads.start(mod) }
                .controlSize(.small)
        }
    }
}

/// Pause / go on / cancel for one download.
struct DownloadControls: View {
    let id: String
    let job: Downloads.Job
    @ObservedObject var downloads: Downloads
    var body: some View {
        HStack(spacing: 4) {
            if job.task != nil {
                Button { downloads.pause(id) } label: { Image(systemName: "pause.circle") }.buttonStyle(.borderless).help("หยุดไว้ก่อน (ดาวน์โหลดต่อทีหลังได้)")
            } else if job.paused {
                Button { downloads.resume(id) } label: { Image(systemName: "play.circle") }.buttonStyle(.borderless).help("ดาวน์โหลดต่อ")
            }
            Button { downloads.cancel(id) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless).help("ยกเลิก (ทิ้งส่วนที่โหลดมาแล้ว)")
        }
    }
}

struct CatalogRow: View {
    let mod: CatalogMod
    let downloads: Downloads
    let library: ModLibrary
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(mod.name).fontWeight(.medium).lineLimit(1)
                Text("\(mod.category) · \(mod.author)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            InstallButton(mod: mod, downloads: downloads, library: library)
        }
        .padding(.vertical, 2)
    }
}

struct CatalogDetail: View {
    let mod: CatalogMod
    @ObservedObject var downloads: Downloads
    @ObservedObject var library: ModLibrary
    @Environment(\.openURL) private var openURL
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let u = URL(string: mod.preview), !mod.preview.isEmpty {
                    AsyncImage(url: u) { img in img.resizable().scaledToFit() } placeholder: { Color.gray.opacity(0.15).frame(height: 180) }
                        .frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Text(mod.name).font(.title2.bold())
                Text("\(mod.author) · เวอร์ชัน \(mod.version) · \(mod.category) · \(mod.sizeText)").foregroundStyle(.secondary)
                InstallButton(mod: mod, downloads: downloads, library: library)
                Text(mod.description).textSelection(.enabled)
                if !mod.releaseNotes.isEmpty { Text("มีอะไรใหม่").font(.headline); Text(mod.releaseNotes).font(.callout) }
                if let l = URL(string: mod.link), !mod.link.isEmpty { Button("หน้าเว็บของม็อด") { openURL(l) }.buttonStyle(.link) }
                if !mod.tags.isEmpty { Text(mod.tags.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: Downloads

struct DownloadsView: View {
    @ObservedObject var downloads: Downloads
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section("กำลังดำเนินการ") {
                if downloads.jobs.isEmpty { Text("ไม่มีการดาวน์โหลด").foregroundStyle(.secondary) }
                ForEach(downloads.jobs.sorted { $0.value.started < $1.value.started }, id: \.key) { id, j in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(j.mod.name).fontWeight(.medium)
                            Spacer()
                            if j.task != nil {
                                let secs = max(1, Date().timeIntervalSince(j.started))
                                Text(String(format: "%.1f MB/s", Double(j.bytes - j.startBytes) / 1_048_576 / secs)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            }
                            DownloadControls(id: id, job: j, downloads: downloads)
                        }
                        if j.task != nil || j.paused { ProgressView(value: j.progress) }
                        Text(j.status).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            Section("ประวัติ") {
                if downloads.history.isEmpty { Text("ยังไม่มีประวัติ").foregroundStyle(.secondary) }
                ForEach(downloads.history) { d in
                    HStack {
                        Image(systemName: d.ok ? "checkmark.circle.fill" : "xmark.octagon.fill").foregroundStyle(d.ok ? .green : .red)
                        Text(d.name)
                        Spacer()
                        Text(d.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Text(d.at, style: .time).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .toolbar {
            Button("ล้างประวัติ") { downloads.history.removeAll() }.disabled(downloads.history.isEmpty)
            Button("เปิดโฟลเดอร์ดาวน์โหลด") { openURL(Paths.downloads) }
        }
        .navigationTitle("ดาวน์โหลด")
    }
}

// MARK: Saves

struct SavesView: View {
    @ObservedObject var cloud: CloudSaves
    @Environment(\.openURL) private var openURL
    @State private var files: [FF7Save.File] = FF7Save.list()
    @State private var states: [SaveStates.Slot] = SaveStates.all()
    @State private var current = SaveStates.current
    @State private var message: String?
    @State private var importing = false
    @State private var importingState: Int?
    @State private var exportDoc: BytesDocument?
    @State private var exportName = ""
    @State private var confirmDelete: (() -> Void)?

    var body: some View {
        Form {
            Section {
                Toggle("เก็บเซฟและ save state ใน iCloud Drive", isOn: Binding(get: { CloudSaves.enabled }, set: { on in
                    if on { cloud.enable() } else { cloud.disable() }
                    refresh()
                }))
                .disabled(cloud.busy || !CloudSaves.available)
                if let s = cloud.status { Text(s).font(.callout).foregroundStyle(.secondary) }
                HStack {
                    if CloudSaves.enabled { Button("เปิดโฟลเดอร์ใน iCloud Drive") { openURL(CloudSaves.root) } }
                    Button("เปิดเซฟสำรอง") { openURL(CloudSaves.backups) }
                }
                .buttonStyle(.link)
            } header: { Text("iCloud") } footer: {
                Text(CloudSaves.available
                     ? "ทุก Mac ที่ใช้ Apple ID เดียวกันจะเล่นต่อจากเซฟเดียวกันได้ (iPad ในอนาคตเปิดผ่านแอป Files) อย่าเล่นพร้อมกันสองเครื่อง ถ้ามีเครื่องอื่นเปิดเกมค้างไว้ แอปจะเตือนก่อน และสำรองเซฟไว้ทุกครั้งที่กดเล่น (เก็บ 20 ครั้งล่าสุด)"
                     : "iCloud Drive ไม่ได้เปิดอยู่: การตั้งค่าระบบ → [ชื่อคุณ] → iCloud → iCloud Drive")
                    .font(.caption)
            }
            Section {
                if files.isEmpty { Text("ยังไม่มีไฟล์เซฟ (เซฟในเกมแล้วจะขึ้นที่นี่)").foregroundStyle(.secondary) }
                ForEach(files) { f in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Save \(f.id + 1)").font(.headline)
                            Text("\(f.slots.count) ช่อง · แก้ไขล่าสุด \(f.modified.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(.secondary).font(.caption)
                            Spacer()
                            Menu("ส่งออก") {
                                Button("ไฟล์เซฟ PC (.ff7) — Steam 2013 / 7th Heaven") { export(f.url, name: "save" + String(format: "%02d", f.id) + ".ff7") }
                                Button("Memory card (.mcd) — DuckStation / RetroArch (ทดลอง)") { exportCard(f) }
                            }
                            .fixedSize()
                            Button(role: .destructive) { confirmDelete = { try? Paths.fm.removeItem(at: f.url); refresh() } } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                        }
                        ForEach(f.slots) { s in
                            Text("  ช่อง \(s.id + 1): \(s.leader) Lv \(s.level) · \(s.location) · \(s.playTime) · \(s.gil) Gil")
                                .font(.caption).monospacedDigit()
                        }
                    }
                    .padding(.vertical, 2)
                }
                Button { importing = true } label: { Label("นำเข้าเซฟ…", systemImage: "square.and.arrow.down") }
            } header: { Text("เซฟเกม (Continue ในเกม)") } footer: {
                Text("นำเข้าได้: ไฟล์เซฟ PC (save00.ff7…) จาก FF7 Steam 2013, PC 1998 หรือ 7th Heaven และ memory card ของ PlayStation จาก DuckStation (.mcd), RetroArch (.srm), ePSXe (.mcr), DexDrive (.gme), PSP (.vmp)  เซฟที่นำเข้าจะไปเป็นไฟล์ใหม่ ไม่ทับของเดิม  (เซฟของ Steam รุ่นปัจจุบันใช้รูปแบบอื่น ยังไม่รองรับ)")
                    .font(.caption)
            }
            Section {
                Picker("ช่องที่ปุ่มในเกมใช้", selection: $current) { ForEach(1...SaveStates.slots, id: \.self) { Text("ช่อง \($0)").tag($0) } }
                    .onChange(of: current) { SaveStates.current = $0 }
                ForEach(states) { s in
                    HStack {
                        Text("ช่อง \(s.id)").frame(width: 56, alignment: .leading)
                        if s.exists {
                            VStack(alignment: .leading) {
                                Text(s.location.isEmpty ? "(ไม่ทราบตำแหน่ง)" : s.location)
                                Text([s.when.map { $0.formatted(date: .abbreviated, time: .shortened) }, "เวลาเล่น \(s.playTime)"].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } else { Text("ว่าง").foregroundStyle(.secondary) }
                        Spacer()
                        Button("นำเข้า…") { importingState = s.id }
                        if s.exists {
                            Button("ส่งออก") { export(s.url, name: "FF7Recomp-slot" + String(format: "%02d", s.id) + ".ff7s") }
                            Button(role: .destructive) { confirmDelete = { SaveStates.delete(s.id); refresh() } } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            } header: { Text("Save states") } footer: {
                Text("ในเกม: Tab+Q (Select+L1) บันทึก · Tab+W (Select+R1) โหลด · Tab+←/→ เปลี่ยนช่อง  Save state ของ DuckStation/RetroArch เป็นภาพหน่วยความจำของเครื่อง PlayStation จึงแปลงมาใช้กับเวอร์ชัน PC ไม่ได้ ให้ใช้เซฟใน memory card แทน")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("เซฟเกม")
        .onAppear(perform: refresh)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { r in
            var lines: [String] = []
            for u in (try? r.get()) ?? [] {
                let ok = u.startAccessingSecurityScopedResource()
                defer { if ok { u.stopAccessingSecurityScopedResource() } }
                do { let (n, c) = try FF7Save.importFile(u); lines.append("\(u.lastPathComponent): \(c) เซฟ → Save \(n)") }
                catch { lines.append("\(u.lastPathComponent): \((error as? SaveError)?.message ?? error.localizedDescription)") }
            }
            message = lines.joined(separator: "\n"); refresh()
        }
        .fileImporter(isPresented: Binding(get: { importingState != nil }, set: { if !$0 { importingState = nil } }), allowedContentTypes: [.item]) { r in
            guard let n = importingState, let u = try? r.get() else { return }
            let ok = u.startAccessingSecurityScopedResource()
            defer { if ok { u.stopAccessingSecurityScopedResource() } }
            do { try SaveStates.importState(u, into: n); message = "นำเข้าไปที่ช่อง \(n) แล้ว" }
            catch { message = (error as? SaveError)?.message ?? error.localizedDescription }
            importingState = nil; refresh()
        }
        .fileExporter(isPresented: Binding(get: { exportDoc != nil }, set: { if !$0 { exportDoc = nil } }), document: exportDoc,
                      contentType: .data, defaultFilename: exportName) { r in
            if case .failure(let e) = r { message = e.localizedDescription }
            exportDoc = nil
        }
        .alert("เซฟเกม", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("ตกลง") { message = nil }
        } message: { Text(message ?? "") }
        .confirmationDialog("ลบไฟล์นี้?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("ลบ", role: .destructive) { confirmDelete?(); confirmDelete = nil }
        } message: { Text("ลบแล้วกู้คืนไม่ได้") }
    }

    func refresh() { files = FF7Save.list(); states = SaveStates.all(); current = SaveStates.current }
    func export(_ u: URL, name: String) {
        guard let d = try? Data(contentsOf: u) else { return }
        exportName = name; exportDoc = BytesDocument(d)
    }
    func exportCard(_ f: FF7Save.File) {
        do { exportName = "FF7-Save\(f.id + 1).mcd"; exportDoc = BytesDocument(try FF7Save.memoryCard(from: f.url)) }
        catch { message = (error as? SaveError)?.message ?? error.localizedDescription }
    }
}

// MARK: Controls

struct ControlsView: View {
    @State private var map = Keymap.load()
    var rows: [(String, String, String)] {
        let k = { (n: String) in map.text(n) }
        return [
        ("เดิน / เลื่อนเมนู", "\(k("up")) \(k("down")) \(k("left")) \(k("right"))", "D-pad / Stick ซ้าย"),
        ("ตกลง (○)", k("ok"), "B / ○"),
        ("ยกเลิก (×)", k("cancel"), "A / ×"),
        ("เปิดเมนู (△)", k("menu"), "Y / △"),
        ("□", k("square"), "X / □"),
        ("L1 / R1", "\(k("l1")) / \(k("r1"))", "LB / RB"),
        ("L2 / R2", "\(k("l2")) / \(k("r2"))", "LT / RT"),
        ("Select", k("select"), "View / Share"),
        ("Start (หยุดเกม)", k("start"), "Menu / Options"),
        ("L3 / R3", "\(k("l3")) / \(k("r3"))", "กดสติ๊กซ้าย / ขวา"),
        ("โหมด shortcut ของ FFNx", "\(k("l3")) แล้วตามด้วยปุ่ม", "L3 แล้วตามด้วยปุ่ม"),
        ("  → ความเร็ว + / −", "\(k("r1")) / \(k("l1"))", "R1 / L1"),
        ("  → เปิด/ปิดเร่งความเร็ว", "\(k("l2")) หรือ \(k("r2"))", "L2 หรือ R2"),
        ("  → เปิด/ปิดการเจอศัตรู", k("ok"), "○"),
        ("  → Battle enhancement", k("cancel"), "×"),
        ("  → ข้ามภาพยนตร์", k("square"), "□"),
        ("บันทึก / โหลด save state", "\(k("select"))+\(k("l1")) / \(k("select"))+\(k("r1"))", "Select+L1 / Select+R1"),
        ("เปลี่ยนช่อง save state", "\(k("select"))+← / \(k("select"))+→", "Select+← / Select+→"),
        ("กลับไปที่ launcher", "Cmd+L", "Select+Start ค้าง 2 วินาที"),
        ("ดู achievement (แผงทับเกม)", "F1", "Select+△"),
        ("ดู achievement (หน้าต่างแยก)", "Cmd+Shift+A", "-"),
        ("เต็มจอ", "Cmd+F", ""),
        ("ออกจากเกม", "Cmd+Q", ""),
        ]
    }
    var body: some View {
        Form {
            KeymapEditor(map: $map)
            Section("ปุ่มที่ใช้ในเกม") {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow { Text("หน้าที่").bold(); Text("คีย์บอร์ด").bold(); Text("จอย").bold() }
                    Divider()
                    ForEach(rows, id: \.0) { r in GridRow { Text(r.0); Text(r.1).monospaced(); Text(r.2) } }
                }
            }
            Section {
                Text("จอย Xbox, PlayStation และ MFi ที่เชื่อมต่อกับ Mac ใช้ได้ทันที การเปลี่ยนปุ่มจอยทำได้ในเกมที่ Config > Controller")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("ปุ่มควบคุม")
    }
}

// MARK: window (macOS)

#if os(macOS)
private var launcherWindow: NSWindow?
private var launcherState: LauncherState?

@_cdecl("ff7_launcher_show")
public func ff7_launcher_show() {
    MainActor.assumeIsolated {
        let s = LauncherState()
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = "FF7Recomp"
        w.contentViewController = NSHostingController(rootView: LauncherView(state: s, downloads: s.downloads))
        w.setContentSize(NSSize(width: 1080, height: 720))
        w.isReleasedWhenClosed = false
        w.center()
        w.makeKeyAndOrderFront(nil)
        s.window = w
        launcherWindow = w
        launcherState = s
        if ProcessInfo.processInfo.environment["FF7_LAUNCHER_AUTOPLAY"] != nil { s.play() }   // tests
    }
}
#endif
