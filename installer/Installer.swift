// GJ Materia Installer - builds GJ Materia on the player's own Mac from their own copy of FINAL
// FANTASY VII (Steam). It holds no game code and downloads none: it installs Apple's Command Line
// Tools and Rosetta when missing, fetches cmake, ninja and Python's capstone into its own folder
// (no Homebrew), finds the game, clones github.com/goodjoeth/gj-materia and runs tools/build_mac.sh,
// then puts GJ Materia.app in Applications.
//
//   tools/make_installer.sh builds it.  Test without the window:
//   "GJ Materia Installer" --headless --workdir <dir> [--game <FF7 folder>] [--no-install]
import SwiftUI
import AppKit
import CryptoKit

// MARK: languages (Thai when the Mac's first language is Thai, else English)

let thai = (Locale.preferredLanguages.first ?? "").hasPrefix("th")
func L(_ th: String, _ en: String) -> String { thai ? th : en }

// MARK: the work

struct Step: Identifiable {
    enum State { case waiting, running, done, failed, skipped }
    let id: Int
    let title: String
    var state: State = .waiting
    var detail = ""
}

final class Installer: ObservableObject {
    static var repo = "https://github.com/goodjoeth/gj-materia.git"   // tests: --repo <url or path>
    // pinned tools (Kitware's and the Ninja project's official macOS builds)
    static let cmakeURL = "https://github.com/Kitware/CMake/releases/download/v3.31.6/cmake-3.31.6-macos-universal.tar.gz"
    static let cmakeSHA = "330b9514f5112e5ed4fb08b8b05803b776fd9b539a6ae12927d14dcc0ee2ba8d"
    static let ninjaURL = "https://github.com/ninja-build/ninja/releases/download/v1.12.1/ninja-mac.zip"
    static let ninjaSHA = "89a287444b5b3e98f88a945afa50ce937b8ffd1dcc59c555ad9b1baf855298c9"
    static let needGB = 15.0

    @Published var steps: [Step] = [
        Step(id: 0, title: L("เครื่องมือของ Apple (Command Line Tools)", "Apple's Command Line Tools")),
        Step(id: 1, title: "Rosetta 2"),
        Step(id: 2, title: L("เครื่องมือ build (cmake, ninja, Python)", "Build tools (cmake, ninja, Python)")),
        Step(id: 3, title: L("ไฟล์เกม FINAL FANTASY VII ของคุณ", "Your FINAL FANTASY VII files")),
        Step(id: 4, title: L("ซอร์สโค้ด GJ Materia", "GJ Materia's source code")),
        Step(id: 5, title: L("แปลงโค้ดเกมและ build แอป (20–40 นาที)", "Translate the game's code and build the app (20–40 min)")),
        Step(id: 6, title: L("ติดตั้งลงในโฟลเดอร์ Applications", "Install into Applications")),
    ]
    @Published var log: [String] = []
    @Published var running = false
    @Published var finished = false
    @Published var failure: String?
    @Published var needGame = false
    @Published var workDir: URL
    @Published var gameDir: URL?
    @Published var installedApp: URL?
    @Published var buildPart = 0.0          // 0...1 inside the build step
    var headless = false
    var installToApplications = true

    let fm = FileManager.default
    var support: URL { fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("GJ Materia Installer") }
    var tools: URL { support.appendingPathComponent("tools") }
    var venv: URL { tools.appendingPathComponent("venv") }

    init() {
        workDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("GJ Materia")
        gameDir = Self.findGame()
    }

    // MARK: running commands

    var env: [String: String] {
        var e = ProcessInfo.processInfo.environment
        // our tools first, then the system's; Homebrew left out so every Mac builds the same way
        e["PATH"] = [venv.appendingPathComponent("bin").path, tools.appendingPathComponent("bin").path,
                     tools.appendingPathComponent("CMake.app/Contents/bin").path,
                     "/usr/bin", "/bin", "/usr/sbin", "/sbin"].joined(separator: ":")
        e["PYTHONNOUSERSITE"] = "1"
        e.removeValue(forKey: "PYTHONPATH")
        return e
    }

    /// Runs a command, its output going to the log line by line; returns the exit status.
    @discardableResult
    func run(_ path: String, _ args: [String], cwd: URL? = nil, onLine: ((String) -> Void)? = nil) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.environment = env
        if let cwd { p.currentDirectoryURL = cwd }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        var pending = Data()
        pipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { return }
            pending.append(d)
            while let nl = pending.firstIndex(of: 10) {
                let line = String(decoding: pending[..<nl], as: UTF8.self).replacingOccurrences(of: "\u{1B}[1m", with: "")
                    .replacingOccurrences(of: "\u{1B}[0m", with: "").replacingOccurrences(of: "\u{1B}[31m", with: "")
                pending.removeSubrange(...nl)
                self.say(line)
                onLine?(line)
            }
        }
        do { try p.run() } catch { say("! \(error.localizedDescription)"); return -1 }
        p.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil
        if !pending.isEmpty { say(String(decoding: pending, as: UTF8.self)) }
        return p.terminationStatus
    }

    func ok(_ path: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.environment = env
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    func say(_ s: String) {
        if headless { print(s); fflush(stdout); return }
        DispatchQueue.main.async { self.log.append(s); if self.log.count > 4000 { self.log.removeFirst(1000) } }
    }

    func set(_ i: Int, _ st: Step.State, _ detail: String = "") {
        if headless { print("[\(i + 1)/7] \(steps[i].title): \(st) \(detail)"); fflush(stdout) }
        DispatchQueue.main.async { self.steps[i].state = st; self.steps[i].detail = detail }
    }

    struct Failed: Error { let message: String }

    // MARK: the steps

    func start() {
        guard !running else { return }
        running = true; failure = nil; finished = false
        for i in steps.indices { steps[i].state = .waiting; steps[i].detail = "" }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.commandLineTools()
                try self.rosetta()
                try self.buildTools()
                try self.game()
                try self.source()
                try self.build()
                try self.install()
                DispatchQueue.main.async { self.finished = true; self.running = false }
                if self.headless { print("DONE"); exit(0) }
            } catch let f as Failed {
                DispatchQueue.main.async { self.failure = f.message; self.running = false }
                if self.headless { print("FAILED: \(f.message)"); exit(1) }
            } catch {
                DispatchQueue.main.async { self.failure = error.localizedDescription; self.running = false }
                if self.headless { print("FAILED: \(error)"); exit(1) }
            }
        }
    }

    func commandLineTools() throws {
        set(0, .running)
        if ok("/usr/bin/xcode-select", ["-p"]) && ok("/usr/bin/xcrun", ["--find", "clang"]) { set(0, .done); return }
        if headless { throw Failed(message: "the Command Line Tools are missing (xcode-select --install)") }
        _ = ok("/usr/bin/xcode-select", ["--install"])
        set(0, .running, L("กด “ติดตั้ง” ในหน้าต่างที่ macOS เปิดขึ้นมา แล้วรอให้เสร็จ (ไม่กี่นาทีถึงครึ่งชั่วโมง)",
                            "Click “Install” in the window macOS opened and wait for it to finish (a few minutes to half an hour)"))
        let until = Date().addingTimeInterval(90 * 60)
        while Date() < until {
            Thread.sleep(forTimeInterval: 5)
            if ok("/usr/bin/xcode-select", ["-p"]) && ok("/usr/bin/xcrun", ["--find", "clang"]) { set(0, .done); return }
        }
        set(0, .failed)
        throw Failed(message: L("ยังไม่ได้ติดตั้ง Command Line Tools", "The Command Line Tools were not installed"))
    }

    func rosetta() throws {
        var info = utsname(); uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        // under Rosetta the installer itself reports x86_64; sysctl tells the real chip
        var arm: Int32 = 0; var sz = MemoryLayout<Int32>.size
        let isArm = machine == "arm64" || (sysctlbyname("hw.optional.arm64", &arm, &sz, nil, 0) == 0 && arm == 1)
        guard isArm else { set(1, .skipped, L("Mac รุ่น Intel ไม่ต้องใช้", "Not needed on an Intel Mac")); return }
        set(1, .running)
        if ok("/usr/bin/arch", ["-x86_64", "/usr/bin/true"]) { set(1, .done); return }
        if headless { throw Failed(message: "Rosetta 2 is missing") }
        set(1, .running, L("macOS จะถามรหัสผ่านเพื่อติดตั้ง Rosetta 2", "macOS asks for your password to install Rosetta 2"))
        let script = "do shell script \"/usr/sbin/softwareupdate --install-rosetta --agree-to-license\" with administrator privileges"
        run("/usr/bin/osascript", ["-e", script])
        guard ok("/usr/bin/arch", ["-x86_64", "/usr/bin/true"]) else {
            set(1, .failed); throw Failed(message: L("ติดตั้ง Rosetta 2 ไม่สำเร็จ", "Rosetta 2 could not be installed"))
        }
        set(1, .done)
    }

    func fetch(_ url: String, sha: String, to dest: URL) throws {
        say("downloading \(url)")
        guard run("/usr/bin/curl", ["-fL", "--retry", "3", "-s", "-o", dest.path, url]) == 0, let d = try? Data(contentsOf: dest) else {
            throw Failed(message: L("ดาวน์โหลดไม่สำเร็จ: ", "Download failed: ") + url)
        }
        let h = SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
        guard h == sha else { throw Failed(message: L("ไฟล์ที่ดาวน์โหลดไม่ตรงกับที่ควรเป็น: ", "The download does not match its checksum: ") + url) }
    }

    func buildTools() throws {
        set(2, .running)
        try fm.createDirectory(at: tools.appendingPathComponent("bin"), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: tools.appendingPathComponent("CMake.app/Contents/bin/cmake").path) {
            set(2, .running, "cmake")
            let tgz = tools.appendingPathComponent("cmake.tgz")
            try fetch(Self.cmakeURL, sha: Self.cmakeSHA, to: tgz)
            guard run("/usr/bin/tar", ["-xzf", tgz.path, "-C", tools.path, "--strip-components", "1"]) == 0 else {
                throw Failed(message: "cmake could not be unpacked")
            }
            try? fm.removeItem(at: tgz)
        }
        if !fm.fileExists(atPath: tools.appendingPathComponent("bin/ninja").path) {
            set(2, .running, "ninja")
            let zip = tools.appendingPathComponent("ninja.zip")
            try fetch(Self.ninjaURL, sha: Self.ninjaSHA, to: zip)
            guard run("/usr/bin/unzip", ["-o", "-q", zip.path, "-d", tools.appendingPathComponent("bin").path]) == 0 else {
                throw Failed(message: "ninja could not be unpacked")
            }
            try? fm.removeItem(at: zip)
        }
        if !ok(venv.appendingPathComponent("bin/python3").path, ["-c", "import capstone"]) {
            set(2, .running, "Python + capstone")
            guard run("/usr/bin/python3", ["-m", "venv", "--clear", venv.path]) == 0,
                  run(venv.appendingPathComponent("bin/python3").path, ["-m", "pip", "install", "-q", "--disable-pip-version-check", "capstone"]) == 0 else {
                throw Failed(message: L("ติดตั้ง Python capstone ไม่สำเร็จ", "Python's capstone could not be installed"))
            }
        }
        set(2, .done)
    }

    static func isGame(_ u: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: u.appendingPathComponent("ff7/resources/ff7_1.02/ff7_en").path)
            && fm.fileExists(atPath: u.appendingPathComponent("ff7/workingdir/data").path)
    }

    /// Where FF7's Steam folder usually is (as the app's own search).
    static func findGame() -> URL? {
        let home = NSHomeDirectory(), fm = FileManager.default
        var dirs = ["\(home)/Library/Application Support/Steam/steamapps/common", "\(home)", "\(home)/Downloads", "\(home)/Desktop",
                    "\(home)/Documents", "\(home)/Games"]
        for b in ["\(home)/Library/Application Support/CrossOver/Bottles", "\(home)/Library/Containers/com.isaacmarovitz.Whisky/Bottles"] {
            for bottle in (try? fm.contentsOfDirectory(atPath: b)) ?? [] {
                for pf in ["Program Files (x86)", "Program Files"] { dirs.append("\(b)/\(bottle)/drive_c/\(pf)/Steam/steamapps/common") }
            }
        }
        for v in (try? fm.contentsOfDirectory(atPath: "/Volumes")) ?? [] {
            dirs.append("/Volumes/\(v)")
            for sub in (try? fm.contentsOfDirectory(atPath: "/Volumes/\(v)")) ?? [] { dirs.append("/Volumes/\(v)/\(sub)") }
        }
        if fm.fileExists(atPath: "\(home)/FF7"), isGame(URL(fileURLWithPath: "\(home)/FF7")) { return URL(fileURLWithPath: "\(home)/FF7") }
        for d in dirs {
            for name in (try? fm.contentsOfDirectory(atPath: d)) ?? [] where name.hasPrefix("FINAL FANTASY VII") {
                let u = URL(fileURLWithPath: d).appendingPathComponent(name)
                if isGame(u) { return u }
            }
        }
        return nil
    }

    func game() throws {
        set(3, .running)
        if gameDir == nil || !Self.isGame(gameDir!) { gameDir = Self.findGame() }
        if gameDir == nil {
            if headless { throw Failed(message: "FINAL FANTASY VII was not found; pass --game") }
            set(3, .running, L("ไม่พบในเครื่อง กด “เลือกโฟลเดอร์เกม…” ด้านบน", "Not found on this Mac: press “Choose the game folder…” above"))
            DispatchQueue.main.async { self.needGame = true }
            while gameDir == nil || !Self.isGame(gameDir!) { Thread.sleep(forTimeInterval: 0.5) }
            DispatchQueue.main.async { self.needGame = false }
        }
        set(3, .done, gameDir!.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
    }

    func freeGB(_ u: URL) -> Double {
        var probe = u
        while !fm.fileExists(atPath: probe.path) { probe.deleteLastPathComponent() }
        let v = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        // "for important usage" is 0 on some external drives: the larger of the two
        let important = v?.volumeAvailableCapacityForImportantUsage.map { Double($0) } ?? 0
        let plain = v?.volumeAvailableCapacity.map { Double($0) } ?? 0
        return max(important, plain) / 1e9
    }

    func source() throws {
        set(4, .running)
        let git = "/usr/bin/git"
        if fm.fileExists(atPath: workDir.appendingPathComponent(".git").path) {
            set(4, .running, L("อัปเดต", "Updating"))
            if run(git, ["-C", workDir.path, "pull", "--ff-only", "-q"]) != 0 { say("(could not update; building what is there)") }
        } else {
            let free = freeGB(workDir)
            if free < Self.needGB {
                set(4, .failed)
                throw Failed(message: String(format: L("พื้นที่ว่างไม่พอ: ต้องการ %.0f GB แต่มี %.0f GB (เลือกที่เก็บอื่นได้ เช่นไดรฟ์ภายนอก)",
                                                         "Not enough space: %.0f GB needed, %.0f GB free (choose another place, such as an external drive)"),
                                                  Self.needGB, free))
            }
            if fm.fileExists(atPath: workDir.path), ((try? fm.contentsOfDirectory(atPath: workDir.path)) ?? []).contains(where: { !$0.hasPrefix(".") }) {
                set(4, .failed)
                throw Failed(message: L("โฟลเดอร์ที่เลือกมีไฟล์อื่นอยู่แล้ว เลือกโฟลเดอร์ว่าง", "The chosen folder is not empty: choose an empty one"))
            }
            set(4, .running, L("ดาวน์โหลด", "Downloading"))
            guard run(git, ["clone", "--depth", "1", "-q", Self.repo, workDir.path]) == 0 else {
                set(4, .failed); throw Failed(message: L("ดาวน์โหลดซอร์สไม่สำเร็จ (เช็คอินเทอร์เน็ต)", "Could not download the source (check the internet connection)"))
            }
        }
        set(4, .done, workDir.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
    }

    func build() throws {
        set(5, .running)
        let names = [L("ตรวจเครื่องมือ", "checking the tools"), L("ดาวน์โหลดไลบรารี", "libraries"), L("ไฟล์เกม", "your game files"),
                     L("แปลงโค้ดเกม", "translating the game's code"), "FFmpeg", "shaders", L("compile แอป", "compiling the app"), L("เสร็จ", "done")]
        let status = run("/bin/bash", ["tools/build_mac.sh", gameDir!.path], cwd: workDir) { line in
            // "== 4/8 translating..." from build_mac.sh
            if line.hasPrefix("== "), let slash = line.firstIndex(of: "/"),
               let n = Int(line[line.index(line.startIndex, offsetBy: 3)..<slash]), n >= 1, n <= 8 {
                self.set(5, .running, "\(n)/8 · \(names[n - 1])")
                DispatchQueue.main.async { self.buildPart = Double(n - 1) / 8 }
            }
        }
        let app = workDir.appendingPathComponent("build/macos/GJ Materia.app")
        guard status == 0, fm.fileExists(atPath: app.appendingPathComponent("Contents/MacOS/GJ Materia").path) else {
            set(5, .failed)
            throw Failed(message: L("build ไม่สำเร็จ ดูรายละเอียดใน log ด้านล่าง (ปุ่ม “ส่ง log”)", "The build failed: see the log below (“Save the log”)"))
        }
        DispatchQueue.main.async { self.buildPart = 1 }
        set(5, .done)
    }

    func install() throws {
        let app = workDir.appendingPathComponent("build/macos/GJ Materia.app")
        guard installToApplications else { set(6, .skipped); installedApp = app; return }
        set(6, .running)
        var dest = URL(fileURLWithPath: "/Applications/GJ Materia.app")
        if !fm.isWritableFile(atPath: "/Applications") {
            dest = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications/GJ Materia.app")
            try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        try? fm.removeItem(at: dest)
        guard run("/usr/bin/ditto", [app.path, dest.path]) == 0 else { set(6, .failed); throw Failed(message: "could not copy the app") }
        DispatchQueue.main.async { self.installedApp = dest }
        set(6, .done, dest.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
    }
}

// MARK: the window

let gold = Color(red: 0.93, green: 0.72, blue: 0.32)
let goldLight = Color(red: 1.0, green: 0.9, blue: 0.6)
let crimson = Color(red: 0.72, green: 0.06, blue: 0.1)

struct InstallerView: View {
    @ObservedObject var inst: Installer
    @State private var showLog = false

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 4) {
                    Text("GJ Materia").font(.system(size: 30, weight: .bold, design: .serif))
                        .foregroundStyle(LinearGradient(colors: [goldLight, gold], startPoint: .top, endPoint: .bottom))
                    Text(L("ตัวติดตั้ง · FINAL FANTASY VII บน Mac แบบ native · by Good JOE", "Installer · FINAL FANTASY VII, native on the Mac · by Good JOE"))
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text(L("ตัวติดตั้งนี้ไม่มีไฟล์หรือโค้ดของเกม มันจะแปลงเกม FINAL FANTASY VII (Steam) ของคุณเองบน Mac เครื่องนี้ ต้องซื้อเกมบน Steam และมีไฟล์เกมในเครื่องก่อน · ไม่เกี่ยวข้องกับ Square Enix",
                   "This installer has no game files or code. It translates your own FINAL FANTASY VII (Steam) on this Mac: you need to have bought the game on Steam and have its files here. · Not affiliated with Square Enix."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    row(L("เกม", "Game"), inst.gameDir.map { $0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") } ?? L("ยังไม่พบ", "not found yet"),
                        button: L("เลือกโฟลเดอร์เกม…", "Choose the game folder…"), highlight: inst.needGame) { pickGame() }
                    row(L("ที่เก็บซอร์สและไฟล์ build (~15 GB)", "Source and build files (~15 GB)"), inst.workDir.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"),
                        button: L("เปลี่ยน…", "Change…"), highlight: false) { pickWork() }
                        .disabled(inst.running)
                    if inst.gameDir == nil {
                        Link(L("วิธีได้ไฟล์เกม (ต้องทำก่อน)", "How to get the game files (do this first)"),
                             destination: URL(string: "https://github.com/goodjoeth/gj-materia#first-your-game-files")!)
                            .font(.caption)
                    }
                }
                .padding(4)
            }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(inst.steps) { s in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Group {
                            switch s.state {
                            case .waiting: Image(systemName: "circle").foregroundStyle(.secondary)
                            case .running: ProgressView().controlSize(.small)
                            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                            case .skipped: Image(systemName: "minus.circle").foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.title).fontWeight(s.state == .running ? .semibold : .regular)
                            if !s.detail.isEmpty { Text(s.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                            if s.id == 5 && s.state == .running { ProgressView(value: inst.buildPart).frame(maxWidth: 360) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let f = inst.failure { Text(f).foregroundStyle(.red).font(.callout).fixedSize(horizontal: false, vertical: true) }

            HStack {
                Button(showLog ? L("ซ่อน log", "Hide the log") : L("แสดง log", "Show the log")) { showLog.toggle() }
                if !inst.log.isEmpty { Button(L("ส่ง log…", "Save the log…")) { saveLog() } }
                Spacer()
                if inst.finished, let app = inst.installedApp {
                    Button { NSWorkspace.shared.open(app); NSApp.terminate(nil) } label: {
                        Label(L("เปิด GJ Materia", "Open GJ Materia"), systemImage: "play.fill").padding(.horizontal, 18).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent).tint(crimson).keyboardShortcut(.defaultAction)
                } else {
                    Button { inst.start() } label: {
                        Text(inst.running ? L("กำลังติดตั้ง…", "Installing…") : (inst.failure == nil ? L("ติดตั้ง", "Install") : L("ลองอีกครั้ง", "Try again")))
                            .padding(.horizontal, 22).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent).tint(crimson).disabled(inst.running).keyboardShortcut(.defaultAction)
                }
            }
            if showLog {
                ScrollViewReader { sv in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(inst.log.enumerated()), id: \.offset) { i, l in
                                Text(l).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).id(i)
                            }
                        }
                    }
                    .frame(height: 180)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.35)))
                    .onChange(of: inst.log.count) { n in sv.scrollTo(n - 1) }
                }
            }
            if inst.running {
                Text(L("ปล่อยให้ทำงานไปได้เลย Mac ควรต่อสายชาร์จไว้ ครั้งแรกใช้เวลา 20–40 นาที", "Leave it running, with the Mac plugged in. The first time takes 20–40 minutes."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .frame(width: 640)
        .tint(gold)
        .preferredColorScheme(.dark)
    }

    func row(_ title: String, _ value: String, button: String, highlight: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.callout).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button(button, action: action).buttonStyle(.bordered).tint(highlight ? crimson : nil)
        }
    }

    func pickGame() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false
        p.message = L("เลือกโฟลเดอร์ “FINAL FANTASY VII Steam Edition” (ที่มีโฟลเดอร์ ff7 อยู่ข้างใน)",
                      "Choose the “FINAL FANTASY VII Steam Edition” folder (the one with the ff7 folder inside)")
        guard p.runModal() == .OK, let u = p.url else { return }
        if Installer.isGame(u) { inst.gameDir = u }
        else {
            let a = NSAlert(); a.messageText = L("ไม่พบไฟล์เกมในโฟลเดอร์นี้", "No game files in this folder")
            a.informativeText = L("ต้องมี ff7/resources/ff7_1.02/ff7_en และ ff7/workingdir/data", "It needs ff7/resources/ff7_1.02/ff7_en and ff7/workingdir/data")
            a.runModal()
        }
    }

    func pickWork() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.message = L("เลือกที่เก็บซอร์สและไฟล์ build (ต้องการพื้นที่ ~15 GB และเก็บไว้ใช้ตอนทำให้ม็อดเร็วขึ้น)",
                      "Where to keep the source and build files (~15 GB; kept for “Make mods faster”)")
        guard p.runModal() == .OK, let u = p.url else { return }
        inst.workDir = u.lastPathComponent == "GJ Materia" ? u : u.appendingPathComponent("GJ Materia")
    }

    func saveLog() {
        let p = NSSavePanel()
        p.nameFieldStringValue = "GJMateria-install-log.txt"
        guard p.runModal() == .OK, let u = p.url else { return }
        try? inst.log.joined(separator: "\n").write(to: u, atomically: true, encoding: .utf8)
    }
}

// MARK: the app

final class AppDelegate: NSObject, NSApplicationDelegate {
    let inst = Installer()
    var window: NSWindow?
    func applicationDidFinishLaunching(_ n: Notification) {
        let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        w.title = L("ตัวติดตั้ง GJ Materia", "GJ Materia Installer")
        w.appearance = NSAppearance(named: .darkAqua)
        w.contentViewController = NSHostingController(rootView: InstallerView(inst: inst))
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ s: NSApplication) -> NSApplication.TerminateReply {
        guard inst.running else { return .terminateNow }
        let a = NSAlert()
        a.messageText = L("กำลังติดตั้งอยู่ จะออกเลยไหม?", "Still installing. Quit anyway?")
        a.informativeText = L("เปิดตัวติดตั้งอีกครั้งแล้วกด ติดตั้ง จะทำต่อจากที่ค้างไว้", "Open the installer again and press Install: it carries on where it stopped.")
        a.addButton(withTitle: L("ออก", "Quit")); a.addButton(withTitle: L("ทำต่อ", "Keep going"))
        return a.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
}

let args = CommandLine.arguments
if args.contains("--headless") {
    // tests: the same steps without the window
    let inst = Installer()
    inst.headless = true
    if let i = args.firstIndex(of: "--workdir"), i + 1 < args.count { inst.workDir = URL(fileURLWithPath: args[i + 1]) }
    if let i = args.firstIndex(of: "--game"), i + 1 < args.count { inst.gameDir = URL(fileURLWithPath: args[i + 1]) }
    if args.contains("--no-install") { inst.installToApplications = false }
    if let i = args.firstIndex(of: "--repo"), i + 1 < args.count { Installer.repo = args[i + 1] }
    inst.start()
    dispatchMain()
} else {
    let app = NSApplication.shared
    let d = AppDelegate()
    app.delegate = d
    app.setActivationPolicy(.regular)
    app.run()
}
