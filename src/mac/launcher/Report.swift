// Report.swift - "Report a problem": one file with what a bug report needs (src/android
// Reports.java): the logs of the last two runs, FFNx's log and settings, the mod profile and
// list, the launcher's settings, and this Mac and build. Home-folder paths are shortened to ~ and
// nothing of the Steam sign-in goes in. No game files.
import Foundation

enum Report {
    static func build() throws -> URL {
        let fm = Paths.fm
        let dir = fm.temporaryDirectory.appendingPathComponent("FF7Recomp-report-\(Int(Date().timeIntervalSince1970))")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let home = NSHomeDirectory()
        func put(_ src: URL, _ name: String) {
            guard var s = try? String(contentsOf: src, encoding: .utf8) ?? String(contentsOf: src, encoding: .isoLatin1) else { return }
            s = s.replacingOccurrences(of: home, with: "~")
            if s.count > 4_000_000 { s = "(first part cut)\n" + String(s.suffix(4_000_000)) }
            try? s.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        put(Paths.log, "ff7.log")
        put(Paths.base.appendingPathComponent("ff7.prev.log"), "ff7.prev.log")
        put(Paths.game.appendingPathComponent("FFNx.log"), "FFNx.log")
        put(Paths.game.appendingPathComponent("FFNx.toml"), "FFNx.toml")
        put(Paths.profile, "profile.xml")
        put(Paths.settings, "launcher.json")
        put(Paths.boosters, "boosters.txt")

        var info = "FF7Recomp for macOS report, \(ISO8601DateFormatter().string(from: Date()))\n"
        let p = ProcessInfo.processInfo
        info += "macOS \(p.operatingSystemVersionString), \(p.processorCount) cores, \(p.physicalMemory >> 30) GB\n"
        var size = 0; sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var cpu = [CChar](repeating: 0, count: max(size, 1)); sysctlbyname("machdep.cpu.brand_string", &cpu, &size, nil, 0)
        info += "CPU: \(String(cString: cpu))\n"
        if let b = Bundle.main.resourceURL, let s = try? String(contentsOf: b.appendingPathComponent("build-info.txt"), encoding: .utf8) { info += "Build: \(s)" }
        info += "Game exe matches the build: \(Bundle.main.resourceURL.flatMap { try? String(contentsOf: $0.appendingPathComponent("ff7_en.sha1"), encoding: .utf8) } != nil)\n"
        info += "Game data: " + ((try? fm.destinationOfSymbolicLink(atPath: Paths.game.appendingPathComponent("data").path)).map { "linked to " + $0.replacingOccurrences(of: home, with: "~") } ?? "copied") + "\n\nMods (priority order):\n"
        if let d = try? Data(contentsOf: Paths.profile), let root = XMLReader.parse(d) {
            for m in root.all("Mod") {
                let path = m.attr("Path") ?? "?"
                let mi = ModInfo.read(path.hasPrefix("/") ? URL(fileURLWithPath: path) : Paths.mods.appendingPathComponent(path))
                info += "  [\((m.attr("Enabled") ?? "true") == "false" ? " " : "x")] \(mi?.name.isEmpty == false ? mi!.name : path) \(mi?.version ?? "")\n"
            }
        }
        info += "\nSaves: \(FF7Save.list().count) file(s); save states: \(SaveStates.all().filter { $0.exists }.count)\n"
        try info.replacingOccurrences(of: home, with: "~").write(to: dir.appendingPathComponent("about.txt"), atomically: true, encoding: .utf8)

        let zip = fm.temporaryDirectory.appendingPathComponent(dir.lastPathComponent + ".zip")
        try? fm.removeItem(at: zip)
        #if os(macOS)
        let pr = Process()
        pr.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        pr.arguments = ["-c", "-k", "--keepParent", dir.path, zip.path]
        try pr.run(); pr.waitUntilExit()
        try? fm.removeItem(at: dir)
        return zip
        #else
        return dir
        #endif
    }
}
