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
            library.lastError = L("เขียน FFNx.toml ไม่ได้: \(error.localizedDescription)", "Can't write FFNx.toml: \(error.localizedDescription)"); return
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
    case play, settings, mods, catalog, downloads, saves, achievements, controls
    var id: String { rawValue }
    var title: String {
        switch self {
        case .play: return L("เล่น", "Play")
        case .settings: return L("ตั้งค่า", "Settings")
        case .mods: return L("ม็อดของฉัน", "My mods")
        case .catalog: return L("ค้นหาม็อด", "Get mods")
        case .downloads: return L("ดาวน์โหลด", "Downloads")
        case .saves: return L("เซฟเกม", "Saves")
        case .achievements: return "Achievements"
        case .controls: return L("ปุ่มควบคุม", "Controls")
        }
    }
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
                    Label(p.title, systemImage: p.icon)
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
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 2) {
                    GoodJoeLogo(height: 54)
                    Text("GJ Materia").font(.caption2.weight(.semibold)).foregroundStyle(Theme.gold.opacity(0.8))
                }
                .padding(.bottom, 12)
            }
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
        .scrollContentBackground(.hidden)
        .background { if pane != .play && pane != nil { StarField(dim: true) } }
        .frame(minWidth: 980, minHeight: 640)
        .tint(Theme.gold)
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
                .background(Capsule().fill(.orange)).foregroundStyle(.white).help(L("ม็อดที่มีเวอร์ชันใหม่", "Mods with a new version"))
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
                    Text(L("ม็อดมีเวอร์ชันใหม่ \(ups.count) ตัว", "\(ups.count) mods have a new version")).fontWeight(.semibold)
                    Spacer()
                    Button(open ? L("ซ่อน", "Hide") : L("ดู", "Show")) { open.toggle() }.buttonStyle(.link)
                    Button(L("อัปเดตทั้งหมด", "Update all")) { ups.forEach(downloads.start) }.controlSize(.small)
                }
                if open {
                    ForEach(ups) { m in
                        HStack {
                            Text(m.name).lineLimit(1)
                            Spacer()
                            Text("\(Catalog.installedVersion(m, library) ?? "") → \(m.version)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            Button(L("อัปเดต", "Update")) { downloads.start(m) }.controlSize(.small)
                        }
                    }
                }
            }
            .padding(12).frame(width: 520)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
        }
    }
}

/// Names as small gold-edged chips, wrapped onto lines.
struct FlowChips: View {
    let items: [String]
    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, t in
                Text(t).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .foregroundStyle(Theme.goldLight.opacity(0.9))
                    .background(Capsule().fill(.black.opacity(0.45)))
                    .overlay(Capsule().strokeBorder(Theme.gold.opacity(0.3), lineWidth: 1))
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? 600, subviews)
        return CGSize(width: proposal.width ?? rows.map { $0.width }.max() ?? 0, height: rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1)))
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = b.minY
        for row in arrange(b.width, subviews) {
            var x = b.minX + (b.width - row.width) / 2                    // each line centred
            for i in row.items {
                let sz = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += sz.width + spacing
            }
            y += row.height + spacing
        }
    }
    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], width: CGFloat, height: CGFloat)] = [([], 0, 0)]
        for i in subviews.indices {
            let sz = subviews[i].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty && rows[rows.count - 1].width + spacing + sz.width > width { rows.append(([], 0, 0)) }
            var r = rows[rows.count - 1]
            r.width += (r.items.isEmpty ? 0 : spacing) + sz.width; r.height = max(r.height, sz.height); r.items.append(i)
            rows[rows.count - 1] = r
        }
        return rows
    }
}

struct PlayView: View {
    @ObservedObject var state: LauncherState
    @ObservedObject var library: ModLibrary
    @Environment(\.openURL) private var openURL
    @State private var reportDoc: BytesDocument?
    @State private var reportError: String?

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 12)
            #if os(macOS)
            Image(nsImage: NSApp.applicationIconImage).resizable().interpolation(.high)
                .frame(width: 112, height: 112).shadow(color: .black.opacity(0.6), radius: 12, y: 6)
            #endif
            VStack(spacing: 6) {
                GoldText(text: "FINAL FANTASY VII", size: 42)
                HStack(spacing: 10) {
                    Text("GJ MATERIA  ·  BY").font(.system(size: 12, weight: .semibold)).tracking(3)
                        .foregroundStyle(Theme.goldLight.opacity(0.7))
                    GoodJoeLogo(height: 48)
                }
            }
            if !Paths.gameReady || state.gameFiles.dataLinkedTo != nil || !state.gameFiles.exeMatches {
                GameFilesBox(files: state.gameFiles).glassCard().frame(maxWidth: 640)
            }
            GoldChoice(selection: $state.settings.start, options: [("title", L("หน้าไตเติล", "Title screen")), ("newgame", L("เกมใหม่ทันที", "New game right away")), ("continue", L("เล่นต่อจากเซฟล่าสุด", "Continue from the last save"))])
            Button(action: state.play) {
                Label(L("เล่น", "Play"), systemImage: "play.fill")
            }
            .buttonStyle(CrimsonButtonStyle()).keyboardShortcut(.defaultAction)
            .disabled(!Paths.gameReady || !state.gameFiles.exeMatches)
            let on = library.mods.filter { $0.enabled }
            VStack(spacing: 8) {
                Text(on.isEmpty ? L("ไม่มีม็อดที่เปิดใช้", "No mods enabled") : L("ม็อดที่เปิดใช้ \(on.count) ตัว", "\(on.count) mods enabled")).font(.caption.weight(.semibold)).foregroundStyle(Theme.gold)
                if !on.isEmpty {
                    FlowChips(items: on.prefix(8).map { $0.title } + (on.count > 8 ? ["+\(on.count - 8)"] : []))
                }
            }
            .frame(maxWidth: 640)
            if let e = library.lastError { Text(e).foregroundStyle(.red) }
            UpdatesBanner(catalog: state.catalog, library: library, downloads: state.downloads)
            Spacer()
            Text(L("มีจอย? กดปุ่มใดก็ได้บนจอยเพื่อเข้าโหมดทีวี", "Got a controller? Press any button on it for TV mode")).font(.caption).foregroundStyle(Theme.goldLight.opacity(0.6))
            HStack {
                Button(L("เปิดโฟลเดอร์เกม", "Open the game folder")) { openURL(Paths.base) }
                Button(L("เปิด log ล่าสุด", "Open the latest log")) { openURL(Paths.log) }
                Button(L("รายงานปัญหา…", "Report a problem…")) {
                    do { reportDoc = BytesDocument(try Data(contentsOf: Report.build())) }
                    catch { reportError = error.localizedDescription }
                }
                .help(L("รวม log ตั้งค่า และรายการม็อดเป็นไฟล์ .zip ไฟล์เดียว (ไม่มีไฟล์เกมและข้อมูลบัญชี Steam) แนบไปกับรายงานบั๊กได้เลย", "Puts the logs, settings and mod list in one .zip (no game files, nothing of your Steam account) to attach to a bug report"))
            }
            .buttonStyle(.link).tint(Theme.goldLight).padding(.bottom)
            .fileExporter(isPresented: Binding(get: { reportDoc != nil }, set: { if !$0 { reportDoc = nil } }), document: reportDoc,
                          contentType: .zip, defaultFilename: "GJMateria-report.zip") { _ in reportDoc = nil }
            .alert(L("กำลังเล่นอยู่ที่เครื่องอื่น?", "Playing on another Mac?"), isPresented: Binding(get: { state.otherPlaying != nil }, set: { if !$0 { state.otherPlaying = nil } })) {
                Button(L("เล่นต่อที่เครื่องนี้", "Play on this Mac")) { state.playNow() }
                Button(L("ยกเลิก", "Cancel"), role: .cancel) { state.otherPlaying = nil }
            } message: {
                let dev = state.otherPlaying?.device ?? "", when = state.otherPlaying?.since.formatted(date: .omitted, time: .shortened) ?? ""
                Text(L("“\(dev)” เริ่มเล่นไว้เมื่อ \(when) และยังไม่ได้ปิดเกม ถ้าเล่นพร้อมกันสองเครื่อง เครื่องที่เซฟทีหลังจะทับอีกเครื่อง (เซฟก่อนหน้าสำรองไว้ใน save-backups ทุกครั้งที่กดเล่น)",
                       "“\(dev)” started playing at \(when) and hasn't closed the game. If two Macs play at once, the one that saves last overwrites the other (the saves before are backed up in save-backups each time you press Play)."))
            }
            .alert(L("สร้างไฟล์รายงานไม่ได้", "Could not make the report"), isPresented: Binding(get: { reportError != nil }, set: { if !$0 { reportError = nil } })) {
                Button(L("ตกลง", "OK")) { reportError = nil }
            } message: { Text(reportError ?? "") }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MeteorSky())
        .navigationTitle(L("เล่น", "Play"))
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
                Text(L("ยังไม่มีไฟล์เกม: ต้องมี FINAL FANTASY VII เวอร์ชัน Steam ของคุณเอง", "No game files yet: you need your own FINAL FANTASY VII from Steam")).font(.headline).foregroundStyle(.orange)
            } else if !files.exeMatches {
                Text(L("ไฟล์เกมในเครื่องไม่ตรงกับที่แอปนี้ถูก build มา", "The game files on this Mac don't match the ones this app was built from")).foregroundStyle(.orange)
            } else if let l = files.dataLinkedTo {
                let where_ = l.replacingOccurrences(of: NSHomeDirectory(), with: "~")
                Text(L("ข้อมูลเกมยังลิงก์ไปที่ \(where_)\nถ้าย้ายหรือลบโฟลเดอร์นั้นเกมจะเปิดไม่ได้ กด “ค้นหา FF7 ในเครื่อง” แล้ว “นำเข้า” เพื่อก๊อปมาเก็บในแอป",
                       "The game data is still linked to \(where_)\nIf that folder moves or is deleted the game won't start. Press “Find FF7 on this Mac”, then “Import”, to copy it into the app."))
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if let b = files.busy {
                ProgressView(value: files.progress) { Text(b).font(.caption) }.frame(width: 360)
            } else {
                HStack {
                    Button { Task { await files.findGame() } } label: { Label(L("ค้นหา FF7 ในเครื่อง", "Find FF7 on this Mac"), systemImage: "magnifyingglass") }
                        .buttonStyle(.borderedProminent).disabled(files.searching)
                    Button { picking = true } label: { Label(L("เลือกโฟลเดอร์เอง…", "Choose the folder…"), systemImage: "folder") }
                    Button { showGuide = true } label: { Label(L("วิธีได้ไฟล์เกม", "How to get the game files"), systemImage: "questionmark.circle") }
                }
                if files.searching { ProgressView().controlSize(.small) }
                ForEach(files.found) { f in
                    HStack {
                        Image(systemName: f.matches == false ? "exclamationmark.triangle" : "checkmark.seal").foregroundStyle(f.matches == false ? .orange : .green)
                        Text(f.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.callout).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        if f.matches == false { Text(L("เวอร์ชันไม่ตรงกับแอป", "Doesn't match this app's version")).font(.caption).foregroundStyle(.orange) }
                        else { Button(L("นำเข้า", "Import")) { Task { await files.importGame(from: f.url) } } }
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
    ./steamcmd.sh +@sSteamCmdForcePlatformType windows +force_install_dir ~/FF7 +login \(L("ชื่อบัญชีSteam", "YOUR_STEAM_LOGIN")) +app_update 3837340 validate +quit
    """
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L("วิธีได้ไฟล์เกม (ต้องทำก่อนเล่น)", "How to get the game files (needed before you play)")).font(.title2.bold())
                Text(L("แอปนี้ไม่มีไฟล์เกม ต้องใช้ FINAL FANTASY VII ที่คุณซื้อบน Steam เท่านั้น (เวอร์ชันที่ขายอยู่ปัจจุบัน) ไฟล์เกมที่ใช้คือเวอร์ชัน Windows", "This app has no game files. You need FINAL FANTASY VII bought on Steam (the release on sale today); it uses the Windows version's files."))
                step("1", L("ซื้อ FINAL FANTASY VII บน Steam", "Buy FINAL FANTASY VII on Steam"), L("ใช้บัญชี Steam ของคุณเอง เวอร์ชันอื่น (เช่น 7th Heaven 1998, GOG, App Store, PlayStation) ยังใช้ไม่ได้", "Use your own Steam account. Other releases (7th Heaven 1998, GOG, App Store, PlayStation) don't work yet."))
                step("2", L("โหลดไฟล์เกม เลือกวิธีใดวิธีหนึ่ง", "Get the game files one of these ways"), nil)
                VStack(alignment: .leading, spacing: 10) {
                    option(L("ก. มีคอม Windows", "A. With a Windows PC"), L("ติดตั้งเกมใน Steam → คลิกขวาที่เกม → Manage → Browse local files → ก๊อปโฟลเดอร์ “FINAL FANTASY VII Steam Edition” ทั้งโฟลเดอร์ (ประมาณ 3.5 GB) มาไว้ใน Mac ผ่านไดรฟ์ภายนอกหรือแชร์ไฟล์ จะวางไว้ที่ Downloads หรือในไดรฟ์ภายนอกก็ได้", "Install the game in Steam → right-click it → Manage → Browse local files → copy the whole “FINAL FANTASY VII Steam Edition” folder (about 3.5 GB) to the Mac over an external drive or file sharing. Downloads or an external drive are fine."))
                    option(L("ข. บน Mac ด้วย CrossOver หรือ Whisky", "B. On the Mac with CrossOver or Whisky"), L("ติดตั้ง Steam เวอร์ชัน Windows ใน bottle แล้วติดตั้ง FINAL FANTASY VII ตามปกติ ไม่ต้องเปิดเล่น แค่ให้โหลดเสร็จ", "Install the Windows version of Steam in a bottle, then install FINAL FANTASY VII as usual. No need to play it, just let it finish downloading."))
                    VStack(alignment: .leading, spacing: 6) {
                        option(L("ค. บน Mac ด้วย steamcmd (เครื่องมือของ Valve ใน Terminal)", "C. On the Mac with steamcmd (Valve's tool, in Terminal)"), L("เปิด Terminal แล้ววางคำสั่งนี้ (เปลี่ยน ชื่อบัญชีSteam เป็นชื่อล็อกอินของคุณ) จะถามรหัสผ่านและรหัส Steam Guard ใน Terminal ไฟล์เกมจะไปอยู่ที่ ~/FF7", "Open Terminal and paste this command (replace YOUR_STEAM_LOGIN with your login name). Terminal asks for your password and Steam Guard code; the game goes to ~/FF7."))
                        Text(steamcmd).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            .padding(8).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                        Button(L("ก๊อปคำสั่ง", "Copy the command")) {
                            #if os(macOS)
                            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(steamcmd, forType: .string)
                            #endif
                        }
                    }
                }
                .padding(.leading, 34)
                step("3", L("กด “ค้นหา FF7 ในเครื่อง” แล้วกด “นำเข้า”", "Press “Find FF7 on this Mac”, then “Import”"), L("แอปจะค้นใน Steam, CrossOver, Whisky, ~/FF7, Downloads, Desktop, Documents และไดรฟ์ภายนอกที่เสียบอยู่ (macOS อาจถามสิทธิ์เข้าถึงโฟลเดอร์ ให้กดอนุญาต) ไฟล์จะถูกก๊อปมาเก็บในแอป หลังนำเข้าแล้วลบโฟลเดอร์ต้นทางได้", "The app looks in Steam, CrossOver, Whisky, ~/FF7, Downloads, Desktop, Documents and connected external drives (macOS may ask for access to a folder; allow it). The files are copied into the app; you can delete the source folder afterwards."))
                Divider()
                Text(L("ห้ามแชร์ไฟล์เกมหรือแอปที่ build แล้วให้คนอื่น ทุกคนต้องใช้เกมที่ซื้อเอง", "Don't share the game files or the built app: everyone needs a game they bought")).font(.callout).foregroundStyle(.secondary)
                HStack { Spacer(); Button(L("ปิด", "Off"), action: close).keyboardShortcut(.defaultAction) }
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
            Text(L("ทำให้ม็อดเร็วขึ้น", "Make mods faster")).font(.title2.bold())
            Text(L("ม็อดบางตัว (เช่น Enhanced Stock UI) แก้โค้ดของเกม โค้ดส่วนนั้นจะรันผ่าน interpreter ซึ่งช้ากว่า ปุ่มนี้จะ lift โค้ดของชุดม็อดที่เปิดอยู่เข้าไปในแอปให้รันแบบ native ใช้เวลาประมาณ 5–10 นาที ทำใหม่ทุกครั้งที่เปลี่ยนชุดม็อดหรือตัวเลือกของม็อด เสร็จแล้วต้องเปิดแอปใหม่", "Some mods (such as Enhanced Stock UI) change the game's code, and that code then runs in an interpreter, which is slower. This lifts the code of the mods you have enabled into the app so it runs natively. It takes about 5–10 minutes; do it again whenever you change your mods or their options, then reopen the app."))
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
                Button(L("ปิด", "Off"), action: close)
                Button(L("เริ่ม", "Start at")) { files.reliftMods() }.buttonStyle(.borderedProminent).disabled(files.busy != nil)
                if files.message?.contains(L("เปิดแอปใหม่", "Reopen the app")) == true { Button(L("ปิดแอป", "Quit")) { NSApp.terminate(nil) } }
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
            Section {
                Picker("Language / ภาษา", selection: Binding(get: { Lang.thai }, set: { Lang.set(thai: $0) })) {
                    Text("English").tag(false)
                    Text("ไทย (Thai)").tag(true)
                }
            } footer: { Text("The app reopens in the language you choose. / แอปจะเปิดใหม่เป็นภาษาที่เลือก").font(.caption) }
            Section(L("ไฟล์เกม", "Game files")) { GameFilesBox(files: state.gameFiles).frame(maxWidth: .infinity) }
            Section {
                Picker(L("อัตราส่วนจอ", "Aspect ratio"), selection: $state.settings.aspect) {
                    Text(L("4:3 (ต้นฉบับ)", "4:3 (original)")).tag(0)
                    Text("16:9 Widescreen").tag(2)
                    Text("16:10").tag(3)
                    Text("21:9 Ultrawide").tag(4)
                    Text(L("ยืดเต็มหน้าต่าง", "Stretch to the window")).tag(1)
                }
                if state.settings.aspect == 4 {
                    Picker(L("แถบสถานะฉากต่อสู้ (21:9)", "Battle status bar (21:9)"), selection: $state.settings.battleHud) {
                        Text(L("ตำแหน่งแบบ 16:9 (มองง่าย)", "Where 16:9 has it (easy to see)")).tag(0)
                        Text(L("ขยับออกครึ่งทาง", "Halfway out")).tag(1)
                        Text(L("ชิดขอบจอ", "At the screen edge")).tag(2)
                    }
                    .help(L("ม็อด UI จัดหน้าต่างฉากต่อสู้ไว้สำหรับ 16:9 เลือกได้ว่าจะให้แถบ HP/MP อยู่ตรงนั้น หรือขยับไปทางขอบขวาของจอ 21:9", "UI mods lay the battle windows out for 16:9. Keep the HP/MP bar there, or move it toward the right edge of the 21:9 screen."))
                }
                Toggle(L("เต็มจอเมื่อเริ่มเกม", "Full screen at start"), isOn: $state.settings.fullscreen)
                #if os(macOS)
                Picker(L("จอที่ใช้เล่น", "Display"), selection: $state.settings.display) {
                    Text(L("จอหลัก", "Main display")).tag("")
                    ForEach(NSScreen.screens.dropFirst().map { $0.localizedName }, id: \.self) { Text($0).tag($0) }
                }
                #endif
                Picker(L("ความละเอียดภายใน", "Internal resolution"), selection: $state.settings.resolutionScale) {
                    Text(L("อัตโนมัติ", "Automatic")).tag(0)
                    ForEach(1...4, id: \.self) { Text("\($0)× (" + String(640 * $0) + "×" + String(480 * $0) + ")").tag($0) }
                }
                Picker("Anti-aliasing", selection: $state.settings.antialiasing) {
                    Text(L("ปิด", "Off")).tag(0); Text("2×").tag(2); Text("4×").tag(4); Text("8×").tag(8)
                }
                Toggle(L("Bilinear filtering (ภาพนุ่มขึ้น)", "Bilinear filtering (smoother image)"), isOn: $state.settings.bilinear)
                Toggle(L("ฟิลเตอร์ CRT (เส้นสแกนแบบจอทีวี)", "CRT filter (TV scanlines)"), isOn: $state.settings.crt)
                Toggle(L("สีแบบ NTSC-J (สีของ PlayStation ญี่ปุ่น)", "NTSC-J colours (the Japanese PlayStation's)"), isOn: $state.settings.ntscj)
                Toggle("VSync", isOn: $state.settings.vsync)
                Toggle(L("แสดง FPS", "Show FPS"), isOn: $state.settings.showFps)
            } header: { Text(L("ภาพ", "Graphics")) } footer: {
                Text(L("AirPlay: เปิด AirPlay ไปที่ Apple TV/ทีวีจากศูนย์ควบคุมของ Mac แล้วเลือก “ใช้เป็นจอแยก” (ไม่ใช่ mirror) จอนั้นจะขึ้นในรายการ “จอที่ใช้เล่น” เลือกแล้วเปิด “เต็มจอเมื่อเริ่มเกม”  21:9: ฉากต่อสู้ world map และฉากที่กว้างพอจะเต็มจอ ฉากที่ฉากหลังแคบกว่าจะมีขอบดำซ้ายขวา  NTSC-J เป็นฟีเจอร์ของ FFNx (7th Heaven แค่มีปุ่มเปิด)", "AirPlay: from the Mac's Control Center, AirPlay to the Apple TV/TV and choose “Use as Separate Display” (not mirroring); it then appears under “Display”. Pick it and turn on “Full screen at start”.  21:9: battles, the world map and wide enough scenes fill the screen; narrower backgrounds get black bars at the sides.  NTSC-J is an FFNx feature (7th Heaven only has the switch)."))
                    .font(.caption)
            }
            Section(L("ความเร็ว", "Speed")) {
                Picker("Frame rate", selection: $state.settings.fps) {
                    Text(L("ต้นฉบับ", "Original")).tag(0)
                    Text(L("ต้นฉบับ (แก้จังหวะเฟรม)", "Original (fixed frame pacing)")).tag(1)
                    Text(L("ฉากต่อสู้ 30 FPS", "Battles at 30 FPS")).tag(2)
                    Text(L("60 FPS ทั้งเกม", "60 FPS everywhere")).tag(3)
                    Text(L("120 FPS (ทดลอง)", "120 FPS (experimental)")).tag(4)
                }
                Toggle(L("เร่งความเร็ว 2× ตั้งแต่เริ่ม", "2× speed from the start"), isOn: $state.settings.speed2x)
            }
            Section(L("เสียง", "Sound")) {
                LabeledContent(L("เพลง \(state.settings.musicVolume)%", "Music \(state.settings.musicVolume)%")) {
                    Slider(value: Binding(get: { Double(state.settings.musicVolume) }, set: { state.settings.musicVolume = Int($0) }), in: 0...100, step: 5)
                }
                LabeledContent(L("เสียงเอฟเฟกต์ \(state.settings.sfxVolume)%", "Sound effects \(state.settings.sfxVolume)%")) {
                    Slider(value: Binding(get: { Double(state.settings.sfxVolume) }, set: { state.settings.sfxVolume = Int($0) }), in: 0...100, step: 5)
                }
            }
            Section {
                // each style as it looks over the game, all three modes on
                HStack(spacing: 10) {
                    ForEach(0..<BoosterIcons.styles.count, id: \.self) { i in
                        Button { state.settings.boosterIcons = i } label: {
                            VStack(spacing: 6) {
                                ZStack(alignment: .topTrailing) {
                                    LinearGradient(colors: [Color(red: 0.3, green: 0.36, blue: 0.24), Color(red: 0.1, green: 0.12, blue: 0.09)],
                                                   startPoint: .top, endPoint: .bottom)
                                    BoosterIcons(speed: 2, noBattles: true, battlePlus: true, style: i, s: 0.42)
                                    if i == 3 { Text("—").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
                                }
                                .frame(width: 150, height: 74)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(state.settings.boosterIcons == i ? Color.accentColor : .clear, lineWidth: 3))
                                Text(BoosterIcons.styles[i]).font(.caption)
                                    .foregroundStyle(state.settings.boosterIcons == i ? .primary : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: { Text(L("ไอคอนโหมดพิเศษ (มุมขวาบนระหว่างเล่น)", "Special-mode icons (top right while playing)")) } footer: {
                Text(L("ขึ้นเมื่อเปิดโหมดเร่งความเร็ว ปิดการเจอศัตรู หรือ Battle enhancement (กด L3 แล้วตามด้วยปุ่ม) มีผลตอนเริ่มเกมครั้งถัดไป", "Shown while speed-up, no random battles or Battle enhancement is on (L3, then a button). Takes effect the next time the game starts.")).font(.caption)
            }
            Section {
                Picker(L("การสั่นของจอย", "Controller rumble"), selection: $state.settings.rumble) {
                    Text(L("ปิด", "Off")).tag(0); Text(L("เบา", "Light")).tag(1); Text(L("แรง", "Strong")).tag(2)
                }
                Toggle(L("Analog stick (เดิน/วิ่งตามแรงกด, หมุนกล้องตอนต่อสู้)", "Analog stick (walk/run by how far you push, camera in battles)"), isOn: $state.settings.analog)
                Toggle(L("กดค้างปุ่มตกลงเพื่อกดรัว (ตอนต่อสู้)", "Hold OK to repeat it (in battles)"), isOn: $state.settings.autofire)
            } header: { Text(L("จอย", "Controller")) } footer: {
                Text(L("สั่นเมื่อโจมตีโดนหรือโดนโจมตี (เวทมนตร์ มนตร์อสูร และ Limit Break ที่แรงจะสั่นหนักกว่า) และเมื่อฉากสั่น  ใช้กับจอยที่รองรับการสั่นบน Mac (DualSense, DualShock 4, Xbox)", "Rumbles when you hit or get hit (strong magic, summons and Limit Breaks harder) and when the screen shakes. Works with controllers that rumble on the Mac (DualSense, DualShock 4, Xbox)."))
                    .font(.caption)
            }
            Section(L("เกม", "Game")) {
                Picker(L("ภาษา", "Language"), selection: $state.settings.language) {
                    Text("English").tag(1); Text("Français").tag(2); Text("Deutsch").tag(3); Text("Español").tag(4)
                }
                Toggle(L("เจอศัตรูแบบสุ่ม", "Random battles"), isOn: $state.settings.encounters)
                Picker(L("Gil ที่ได้", "Gil gained"), selection: $state.settings.gilMult) { ForEach(mults, id: \.self) { Text("\($0)×").tag($0) } }
                Picker(L("EXP ที่ได้", "EXP gained"), selection: $state.settings.expMult) { ForEach(mults, id: \.self) { Text("\($0)×").tag($0) } }
                Picker(L("AP ที่ได้", "AP gained"), selection: $state.settings.apMult) { ForEach(mults, id: \.self) { Text("\($0)×").tag($0) } }
            }
            Section {
                Text(L("ค่าทั้งหมดจะถูกเขียนลง FFNx.toml ตอนกดเล่น ม็อดที่มีค่า FFNx ของตัวเองอาจทับบางค่า (ยกเว้นความละเอียดที่เลือกเอง)", "Everything is written to FFNx.toml when you press Play. Mods with their own FFNx settings may override some of them (except a resolution you chose)."))
                    .font(.footnote).foregroundStyle(.secondary)
                Button(L("คืนค่าเริ่มต้น", "Reset to defaults")) { state.settings = Settings() }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(L("ตั้งค่า", "Settings"))
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
                    TextField(L("ค้นหาในม็อดของฉัน", "Search my mods"), text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                    Spacer()
                    Button(L("เปิดทั้งหมด", "Turn all on")) { library.setAll(true) }
                    Button(L("ปิดทั้งหมด", "Turn all off")) { library.setAll(false) }
                    Button { conflicts = library.conflictsSummary } label: { Label(L("ตรวจม็อดชนกัน", "Check for mod conflicts"), systemImage: "exclamationmark.triangle") }
                    Button { importing = true } label: { Label(L("เพิ่มจากไฟล์…", "Add from a file…"), systemImage: "plus") }
                    #if os(macOS)
                    Button { reliftSheet = true } label: { Label(L("ทำให้ม็อดเร็วขึ้น…", "Make mods faster…"), systemImage: "bolt") }
                        .help(L("lift โค้ดที่ม็อดแก้ให้รันแบบ native แทน interpreter (ทำหลังเปลี่ยนชุดม็อด)", "Lift the code the mods change so it runs natively instead of in the interpreter (do it after changing your mods)"))
                    #endif
                }
                .padding(8)
                HStack(spacing: 0) {
                    Table(shown, selection: $selected) {
                        TableColumn("") { m in
                            Toggle("", isOn: Binding(get: { m.enabled }, set: { library.setEnabled(m, $0) })).labelsHidden()
                        }.width(28)
                        TableColumn("#") { m in Text("\((library.mods.firstIndex { $0.id == m.id } ?? 0) + 1)").foregroundStyle(.secondary) }.width(26)
                        TableColumn(L("ชื่อ", "Name")) { m in
                            HStack {
                                Text(m.title).fontWeight(.medium)
                                if m.info?.error != nil { Image(systemName: "xmark.octagon").foregroundStyle(.red) }
                                else if m.info?.unsupported.isEmpty == false { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange) }
                            }.opacity(m.enabled ? 1 : 0.5)
                        }
                        TableColumn(L("ผู้สร้าง", "Author")) { m in Text(m.info?.author ?? "").foregroundStyle(.secondary) }.width(min: 80, ideal: 140)
                        TableColumn(L("หมวด", "Category")) { m in Text(m.info?.category ?? "") }.width(min: 80, ideal: 120)
                        TableColumn(L("เวอร์ชัน", "Version")) { m in Text(m.info?.version ?? "").monospacedDigit() }.width(70)
                    }
                    .overlay {
                        if library.mods.isEmpty {
                            Text(L("ยังไม่มีม็อด\nลากไฟล์ .7z / .iro / .zip มาวางที่นี่ หรือไปที่ “ค้นหาม็อด”", "No mods yet\nDrop .7z / .iro / .zip files here, or go to “Get mods”"))
                                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        }
                    }
                    VStack(spacing: 8) {   // 7th Heaven's order buttons
                        orderButton("arrow.up.to.line", L("ขึ้นบนสุด", "Move to the top"), -2)
                        orderButton("arrow.up", L("ขึ้น", "Up"), -1)
                        orderButton("arrow.down", L("ลง", "Down"), 1)
                        orderButton("arrow.down.to.line", L("ลงล่างสุด", "Move to the bottom"), 2)
                        Divider().frame(width: 24)
                        Button { confirmRemove = true } label: { Image(systemName: "trash") }.help(L("ลบม็อด", "Delete mod")).disabled(current == nil)
                    }
                    .buttonStyle(.borderless).padding(8)
                }
                HStack {
                    if let b = library.busy { ProgressView().controlSize(.small); Text(b).font(.caption) }
                    if let e = library.lastError { Text(e).foregroundStyle(.red).font(.caption) }
                    Spacer()
                    Text(L("ม็อดที่อยู่บนชนะเมื่อแก้ไฟล์เดียวกัน · ม็อด User Interface ควรอยู่บนสุด", "The higher mod wins when two change the same file · User Interface mods belong at the top")).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
            }
            .frame(minHeight: 220, idealHeight: 340)
            Group {
                if let m = current { ModDetail(mod: m, library: library).id(m.id) }
                else { Text(L("เลือกม็อดเพื่อดูรายละเอียดและตั้งค่า", "Pick a mod to see its details and options")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
            .frame(minHeight: 260)
        }
        .navigationTitle(L("ม็อดของฉัน", "My mods"))
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
        .alert(L("ม็อดชนกัน", "Mod conflicts"), isPresented: Binding(get: { conflicts != nil }, set: { if !$0 { conflicts = nil } })) {
            Button(L("ตกลง", "OK")) { conflicts = nil }
        } message: { Text(conflicts?.isEmpty == false ? conflicts! : L("ไม่พบม็อดที่แก้ไฟล์เดียวกัน", "No two mods change the same file")) }
        .confirmationDialog(L("ลบ \(current?.title ?? "-")?", "Delete \(current?.title ?? "-")?"), isPresented: $confirmRemove) {
            Button(L("ลบ", "Delete"), role: .destructive) { if let m = current { library.remove(m); selected = nil } }
        } message: { Text(L("ไฟล์ม็อดจะถูกลบออกจากเครื่อง", "The mod's files will be deleted from this Mac")) }
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
                    Text(L("ข้อมูล", "Info")).tag(0)
                    Text(L("ตั้งค่าม็อด (\(mod.info?.options.count ?? 0))", "Mod options (\(mod.info?.options.count ?? 0))")).tag(1)
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
                        Text([i.category, ex.releaseDate.isEmpty ? "" : L("ออกเมื่อ \(ex.releaseDate)", "Released \(ex.releaseDate)")].filter { !$0.isEmpty }.joined(separator: " · "))
                            .foregroundStyle(.secondary)
                        if !i.description.isEmpty { Text(i.description).textSelection(.enabled) }
                        if !ex.releaseNotes.isEmpty { Text(L("มีอะไรใหม่", "What's new")).font(.headline); Text(ex.releaseNotes).font(.callout) }
                        if !i.requires.isEmpty { Label(L("ต้องใช้คู่กับ: ", "Needs: ") + i.requires.map { $0.why.isEmpty ? $0.id : $0.why }.joined(separator: "; "), systemImage: "link") }
                        if !i.forbids.isEmpty { Label(L("ใช้ร่วมไม่ได้กับ: ", "Doesn't work with: ") + i.forbids.map { $0.why.isEmpty ? $0.id : $0.why }.joined(separator: "; "), systemImage: "nosign") }
                        if !i.unsupported.isEmpty {
                            Label(L("ส่วนที่ใช้ไม่ได้ในเวอร์ชันนี้: ", "Not supported in this version: ") + i.unsupported.joined(separator: ", "), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        }
                        if let l = URL(string: i.link), !i.link.isEmpty { Button(L("หน้าเว็บของม็อด", "Mod's web page")) { openURL(l) }.buttonStyle(.link) }
                    }
                    Text(L("ไฟล์: \(mod.path)", "File: \(mod.path)")).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
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
                Text(L("ม็อดนี้ไม่มีตัวเลือกให้ตั้งค่า", "This mod has no options")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        Button(L("คืนค่าเริ่มต้นของม็อดนี้", "Reset this mod's options")) { library.resetOptions(mod) }
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
                    TextField(L("ค้นหาชื่อ ผู้สร้าง หรือแท็ก", "Search names, authors or tags"), text: $search).textFieldStyle(.roundedBorder)
                    Picker("", selection: $category) {
                        Text(L("ทุกหมวด", "All categories")).tag("")
                        ForEach(catalog.categories, id: \.self) { Text($0).tag($0) }
                    }
                    .frame(width: 170)
                    Toggle(L("มีอัปเดต", "Updates"), isOn: $onlyUpdates).toggleStyle(.button)
                    Button { Task { await catalog.load(force: true) } } label: { Image(systemName: "arrow.clockwise") }
                        .help(L("โหลด catalog ใหม่", "Reload the catalogs"))
                }
                .padding(8)
                List(filtered, selection: $selected) { m in CatalogRow(mod: m, downloads: downloads, library: library).tag(m.id) }
                    .overlay {
                        if catalog.loading { ProgressView(L("กำลังโหลด catalog…", "Loading the catalog…")) }
                        else if let e = catalog.error, catalog.mods.isEmpty { Text(e).foregroundStyle(.red) }
                    }
                Text(L("\(filtered.count) ม็อด · จาก catalog ของ 7th Heaven (Qhimm, Sega)", "\(filtered.count) mods · from the 7th Heaven catalogs (Qhimm, Sega)")).font(.caption).foregroundStyle(.secondary).padding(6)
            }
            .frame(minWidth: 420)
            Group {
                if let id = selected, let m = catalog.mods.first(where: { $0.id == id }) {
                    CatalogDetail(mod: m, downloads: downloads, library: library)
                } else {
                    Text(L("เลือกม็อดเพื่อดูรายละเอียด", "Pick a mod to see its details")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 320)
        }
        .navigationTitle(L("ค้นหาม็อด", "Get mods"))
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
                    if j.task == nil, !j.paused, j.status.contains(L("เบราว์เซอร์", "Browser")), let u = Catalog.browserLink(mod) {
                        Button(L("เปิด", "Open")) { openURL(u); downloads.cancel(mod.id) }
                    } else {
                        DownloadControls(id: mod.id, job: j, downloads: downloads)
                    }
                }
            }
            .frame(width: 200, alignment: .trailing)
        } else if let inst, !Catalog.isNewer(mod.version, than: inst) {
            Label(L("ติดตั้งแล้ว", "Installed"), systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
        } else if let inst {
            Button(L("อัปเดต ", "Update ") + (inst.isEmpty ? "" : inst + " → ") + mod.version) { downloads.start(mod) }
                .controlSize(.small).tint(.orange)
        } else {
            Button(L("ดาวน์โหลด (\(mod.sizeText))", "Download (\(mod.sizeText))")) { downloads.start(mod) }
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
                Button { downloads.pause(id) } label: { Image(systemName: "pause.circle") }.buttonStyle(.borderless).help(L("หยุดไว้ก่อน (ดาวน์โหลดต่อทีหลังได้)", "Pause (resume later)"))
            } else if job.paused {
                Button { downloads.resume(id) } label: { Image(systemName: "play.circle") }.buttonStyle(.borderless).help(L("ดาวน์โหลดต่อ", "Resume download"))
            }
            Button { downloads.cancel(id) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless).help(L("ยกเลิก (ทิ้งส่วนที่โหลดมาแล้ว)", "Cancel (drop what was downloaded)"))
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
                Text(L("\(mod.author) · เวอร์ชัน \(mod.version) · \(mod.category) · \(mod.sizeText)", "\(mod.author) · version \(mod.version) · \(mod.category) · \(mod.sizeText)")).foregroundStyle(.secondary)
                InstallButton(mod: mod, downloads: downloads, library: library)
                Text(mod.description).textSelection(.enabled)
                if !mod.releaseNotes.isEmpty { Text(L("มีอะไรใหม่", "What's new")).font(.headline); Text(mod.releaseNotes).font(.callout) }
                if let l = URL(string: mod.link), !mod.link.isEmpty { Button(L("หน้าเว็บของม็อด", "Mod's web page")) { openURL(l) }.buttonStyle(.link) }
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
            Section(L("กำลังดำเนินการ", "In progress")) {
                if downloads.jobs.isEmpty { Text(L("ไม่มีการดาวน์โหลด", "No downloads")).foregroundStyle(.secondary) }
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
            Section(L("ประวัติ", "History")) {
                if downloads.history.isEmpty { Text(L("ยังไม่มีประวัติ", "No history yet")).foregroundStyle(.secondary) }
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
            Button(L("ล้างประวัติ", "Clear history")) { downloads.history.removeAll() }.disabled(downloads.history.isEmpty)
            Button(L("เปิดโฟลเดอร์ดาวน์โหลด", "Open the downloads folder")) { openURL(Paths.downloads) }
        }
        .navigationTitle(L("ดาวน์โหลด", "Downloads"))
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
                Toggle(L("เก็บเซฟและ save state ใน iCloud Drive", "Keep saves and save states in iCloud Drive"), isOn: Binding(get: { CloudSaves.enabled }, set: { on in
                    if on { cloud.enable() } else { cloud.disable() }
                    refresh()
                }))
                .disabled(cloud.busy || !CloudSaves.available)
                if let s = cloud.status { Text(s).font(.callout).foregroundStyle(.secondary) }
                HStack {
                    if CloudSaves.enabled { Button(L("เปิดโฟลเดอร์ใน iCloud Drive", "Open the folder in iCloud Drive")) { openURL(CloudSaves.root) } }
                    Button(L("เปิดเซฟสำรอง", "Open backups")) { openURL(CloudSaves.backups) }
                }
                .buttonStyle(.link)
            } header: { Text("iCloud") } footer: {
                Text(CloudSaves.available
                     ? L("ทุก Mac ที่ใช้ Apple ID เดียวกันจะเล่นต่อจากเซฟเดียวกันได้ (iPad ในอนาคตเปิดผ่านแอป Files) อย่าเล่นพร้อมกันสองเครื่อง ถ้ามีเครื่องอื่นเปิดเกมค้างไว้ แอปจะเตือนก่อน และสำรองเซฟไว้ทุกครั้งที่กดเล่น (เก็บ 20 ครั้งล่าสุด)", "Every Mac on the same Apple ID continues from the same saves (an iPad later, through the Files app). Don't play on two at once: if another Mac left the game open, the app warns you first, and the saves are backed up each time you press Play (the last 20 are kept).")
                     : L("iCloud Drive ไม่ได้เปิดอยู่: การตั้งค่าระบบ → [ชื่อคุณ] → iCloud → iCloud Drive", "iCloud Drive is off: System Settings → [your name] → iCloud → iCloud Drive"))
                    .font(.caption)
            }
            Section {
                if files.isEmpty { Text(L("ยังไม่มีไฟล์เซฟ (เซฟในเกมแล้วจะขึ้นที่นี่)", "No save files yet (they show up here once you save in the game)")).foregroundStyle(.secondary) }
                ForEach(files) { f in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Save \(f.id + 1)").font(.headline)
                            Text(L("\(f.slots.count) ช่อง · แก้ไขล่าสุด \(f.modified.formatted(date: .abbreviated, time: .shortened))", "\(f.slots.count) slots · last changed \(f.modified.formatted(date: .abbreviated, time: .shortened))")).foregroundStyle(.secondary).font(.caption)
                            Spacer()
                            Menu(L("ส่งออก", "Export")) {
                                Button(L("ไฟล์เซฟ PC (.ff7) — Steam 2013 / 7th Heaven", "PC save file (.ff7) — Steam 2013 / 7th Heaven")) { export(f.url, name: "save" + String(format: "%02d", f.id) + ".ff7") }
                                Button(L("Memory card (.mcd) — DuckStation / RetroArch (ทดลอง)", "Memory card (.mcd) — DuckStation / RetroArch (experimental)")) { exportCard(f) }
                            }
                            .fixedSize()
                            Button(role: .destructive) { confirmDelete = { try? Paths.fm.removeItem(at: f.url); refresh() } } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                        }
                        ForEach(f.slots) { s in
                            Text(L("  ช่อง \(s.id + 1): \(s.leader) Lv \(s.level) · \(s.location) · \(s.playTime) · \(s.gil) Gil", "  Slot \(s.id + 1): \(s.leader) Lv \(s.level) · \(s.location) · \(s.playTime) · \(s.gil) Gil"))
                                .font(.caption).monospacedDigit()
                        }
                    }
                    .padding(.vertical, 2)
                }
                Button { importing = true } label: { Label(L("นำเข้าเซฟ…", "Import saves…"), systemImage: "square.and.arrow.down") }
            } header: { Text(L("เซฟเกม (Continue ในเกม)", "Game saves (Continue in the game)")) } footer: {
                Text(L("นำเข้าได้: ไฟล์เซฟ PC (save00.ff7…) จาก FF7 Steam 2013, PC 1998 หรือ 7th Heaven และ memory card ของ PlayStation จาก DuckStation (.mcd), RetroArch (.srm), ePSXe (.mcr), DexDrive (.gme), PSP (.vmp)  เซฟที่นำเข้าจะไปเป็นไฟล์ใหม่ ไม่ทับของเดิม  (เซฟของ Steam รุ่นปัจจุบันใช้รูปแบบอื่น ยังไม่รองรับ)", "You can import: PC save files (save00.ff7…) from FF7 Steam 2013, PC 1998 or 7th Heaven, and PlayStation memory cards from DuckStation (.mcd), RetroArch (.srm), ePSXe (.mcr), DexDrive (.gme), PSP (.vmp).  Imported saves go into a new file and never replace yours.  (Saves of today's Steam release use another format, not supported yet.)"))
                    .font(.caption)
            }
            Section {
                Picker(L("ช่องที่ปุ่มในเกมใช้", "The slot the in-game keys use"), selection: $current) { ForEach(1...SaveStates.slots, id: \.self) { Text(L("ช่อง \($0)", "Slot \($0)")).tag($0) } }
                    .onChange(of: current) { SaveStates.current = $0 }
                ForEach(states) { s in
                    HStack {
                        Text(L("ช่อง \(s.id)", "Slot \(s.id)")).frame(width: 56, alignment: .leading)
                        if s.exists {
                            VStack(alignment: .leading) {
                                Text(s.location.isEmpty ? L("(ไม่ทราบตำแหน่ง)", "(location unknown)") : s.location)
                                Text([s.when.map { $0.formatted(date: .abbreviated, time: .shortened) }, L("เวลาเล่น \(s.playTime)", "Play time \(s.playTime)")].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } else { Text(L("ว่าง", "Empty")).foregroundStyle(.secondary) }
                        Spacer()
                        Button(L("นำเข้า…", "Import…")) { importingState = s.id }
                        if s.exists {
                            Button(L("ส่งออก", "Export")) { export(s.url, name: "GJMateria-slot" + String(format: "%02d", s.id) + ".ff7s") }
                            Button(role: .destructive) { confirmDelete = { SaveStates.delete(s.id); refresh() } } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            } header: { Text("Save states") } footer: {
                Text(L("ในเกม: Tab+Q (Select+L1) บันทึก · Tab+W (Select+R1) โหลด · Tab+←/→ เปลี่ยนช่อง  Save state ของ DuckStation/RetroArch เป็นภาพหน่วยความจำของเครื่อง PlayStation จึงแปลงมาใช้กับเวอร์ชัน PC ไม่ได้ ให้ใช้เซฟใน memory card แทน", "In the game: Tab+Q (Select+L1) saves · Tab+W (Select+R1) loads · Tab+←/→ changes the slot.  DuckStation/RetroArch save states are snapshots of a PlayStation's memory, so they can't be used by the PC version; use memory card saves instead."))
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(L("เซฟเกม", "Saves"))
        .onAppear(perform: refresh)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { r in
            var lines: [String] = []
            for u in (try? r.get()) ?? [] {
                let ok = u.startAccessingSecurityScopedResource()
                defer { if ok { u.stopAccessingSecurityScopedResource() } }
                do { let (n, c) = try FF7Save.importFile(u); lines.append(L("\(u.lastPathComponent): \(c) เซฟ → Save \(n)", "\(u.lastPathComponent): \(c) save(s) → Save \(n)")) }
                catch { lines.append("\(u.lastPathComponent): \((error as? SaveError)?.message ?? error.localizedDescription)") }
            }
            message = lines.joined(separator: "\n"); refresh()
        }
        .fileImporter(isPresented: Binding(get: { importingState != nil }, set: { if !$0 { importingState = nil } }), allowedContentTypes: [.item]) { r in
            guard let n = importingState, let u = try? r.get() else { return }
            let ok = u.startAccessingSecurityScopedResource()
            defer { if ok { u.stopAccessingSecurityScopedResource() } }
            do { try SaveStates.importState(u, into: n); message = L("นำเข้าไปที่ช่อง \(n) แล้ว", "Imported into slot \(n)") }
            catch { message = (error as? SaveError)?.message ?? error.localizedDescription }
            importingState = nil; refresh()
        }
        .fileExporter(isPresented: Binding(get: { exportDoc != nil }, set: { if !$0 { exportDoc = nil } }), document: exportDoc,
                      contentType: .data, defaultFilename: exportName) { r in
            if case .failure(let e) = r { message = e.localizedDescription }
            exportDoc = nil
        }
        .alert(L("เซฟเกม", "Saves"), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(L("ตกลง", "OK")) { message = nil }
        } message: { Text(message ?? "") }
        .confirmationDialog(L("ลบไฟล์นี้?", "Delete this file?"), isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button(L("ลบ", "Delete"), role: .destructive) { confirmDelete?(); confirmDelete = nil }
        } message: { Text(L("ลบแล้วกู้คืนไม่ได้", "It can't be undone")) }
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
        (L("เดิน / เลื่อนเมนู", "Walk / move in menus"), "\(k("up")) \(k("down")) \(k("left")) \(k("right"))", L("D-pad / Stick ซ้าย", "D-pad / Left stick")),
        (L("ตกลง (○)", "OK (○)"), k("ok"), "B / ○"),
        (L("ยกเลิก (×)", "Cancel (×)"), k("cancel"), "A / ×"),
        (L("เปิดเมนู (△)", "Open the menu (△)"), k("menu"), "Y / △"),
        ("□", k("square"), "X / □"),
        ("L1 / R1", "\(k("l1")) / \(k("r1"))", "LB / RB"),
        ("L2 / R2", "\(k("l2")) / \(k("r2"))", "LT / RT"),
        ("Select", k("select"), "View / Share"),
        (L("Start (หยุดเกม)", "Start (pause)"), k("start"), "Menu / Options"),
        ("L3 / R3", "\(k("l3")) / \(k("r3"))", L("กดสติ๊กซ้าย / ขวา", "Press the left / right stick")),
        (L("โหมด shortcut ของ FFNx", "FFNx shortcut mode"), "\(k("l3")) แล้วตามด้วยปุ่ม", L("L3 แล้วตามด้วยปุ่ม", "L3, then a button")),
        (L("  → ความเร็ว + / −", "  → Speed + / −"), "\(k("r1")) / \(k("l1"))", "R1 / L1"),
        (L("  → เปิด/ปิดเร่งความเร็ว", "  → Speed-up on/off"), "\(k("l2")) หรือ \(k("r2"))", L("L2 หรือ R2", "L2 or R2")),
        (L("  → เปิด/ปิดการเจอศัตรู", "  → Random battles on/off"), k("ok"), "○"),
        ("  → Battle enhancement", k("cancel"), "×"),
        (L("  → ข้ามภาพยนตร์", "  → Skip movie"), k("square"), "□"),
        (L("บันทึก / โหลด save state", "Save / load a save state"), "\(k("select"))+\(k("l1")) / \(k("select"))+\(k("r1"))", "Select+L1 / Select+R1"),
        (L("เปลี่ยนช่อง save state", "Change the save state slot"), "\(k("select"))+← / \(k("select"))+→", "Select+← / Select+→"),
        (L("กลับไปที่ launcher", "Back to the launcher"), "Cmd+L", L("Select+Start ค้าง 2 วินาที", "Hold Select+Start for 2 seconds")),
        (L("ดู achievement (แผงทับเกม)", "Achievements (panel over the game)"), "F1", "Select+△"),
        (L("ดู achievement (หน้าต่างแยก)", "Achievements (separate window)"), "Cmd+Shift+A", "-"),
        (L("เต็มจอ", "Full screen"), "Cmd+F", ""),
        (L("ออกจากเกม", "Quit the game"), "Cmd+Q", ""),
        ]
    }
    var body: some View {
        Form {
            KeymapEditor(map: $map)
            Section(L("ปุ่มที่ใช้ในเกม", "Buttons in the game")) {
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow { Text(L("หน้าที่", "Action")).bold(); Text(L("คีย์บอร์ด", "Keyboard")).bold(); Text(L("จอย", "Controller")).bold() }
                    Divider()
                    ForEach(rows, id: \.0) { r in GridRow { Text(r.0); Text(r.1).monospaced(); Text(r.2) } }
                }
            }
            Section {
                Text(L("จอย Xbox, PlayStation และ MFi ที่เชื่อมต่อกับ Mac ใช้ได้ทันที การเปลี่ยนปุ่มจอยทำได้ในเกมที่ Config > Controller", "Xbox, PlayStation and MFi controllers connected to the Mac work right away. Change the controller's buttons in the game, under Config > Controller."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(L("ปุ่มควบคุม", "Controls"))
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
        w.title = "GJ Materia"
        w.appearance = NSAppearance(named: .darkAqua)   // the launcher is dark, as the game and its icon
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
