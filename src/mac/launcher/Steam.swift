// Steam.swift - Steam achievements for FINAL FANTASY VII (the launcher's side; the Swift port of
// src/android SteamLink.java, which uses JavaSteam).
//
// The player signs in once by scanning a QR code with the Steam mobile app (no password here);
// Steam's refresh token is kept in the Keychain. FFNx's FF7 achievement code decides when an
// achievement is earned and talks to src/ffnx_port/steam_android.cpp, which reads steam/state.txt
// (written here: every FF7 achievement and whether this account has it) and appends unlocks to
// steam/pending.txt. sync() sends those to Steam (ClientStoreUserStats2, as the Steam client
// does), reads the stats back to confirm and rewrites state.txt.
//
// The connection is Steam's own client protocol over WebSocket (a CM server from
// ISteamDirectory): each message is EMsg | 0x80000000, the header length, a CMsgProtoBufHeader,
// then the body. Protobuf is encoded by hand below (only the fields used here).
// Foundation, CoreImage and Security only, so it runs on iPad too.
import Foundation
import Security
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: protobuf

struct PBWriter {
    var data = Data()
    mutating func varint(_ v: UInt64) { var v = v; while v >= 0x80 { data.append(UInt8(v & 0x7F) | 0x80); v >>= 7 }; data.append(UInt8(v)) }
    mutating func key(_ f: Int, _ wire: Int) { varint(UInt64(f << 3 | wire)) }
    mutating func uint(_ f: Int, _ v: UInt64) { key(f, 0); varint(v) }
    mutating func int(_ f: Int, _ v: Int64) { key(f, 0); varint(UInt64(bitPattern: v)) }
    mutating func bool(_ f: Int, _ v: Bool) { uint(f, v ? 1 : 0) }
    mutating func fixed64(_ f: Int, _ v: UInt64) { key(f, 1); withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    mutating func fixed32(_ f: Int, _ v: UInt32) { key(f, 5); withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    mutating func bytes(_ f: Int, _ b: Data) { key(f, 2); varint(UInt64(b.count)); data.append(b) }
    mutating func string(_ f: Int, _ s: String) { bytes(f, Data(s.utf8)) }
    mutating func message(_ f: Int, _ m: PBWriter) { bytes(f, m.data) }
}

/// A decoded protobuf message: field number -> values (varints and fixed as UInt64, bytes as Data).
struct PBMessage {
    enum Value { case int(UInt64), bytes(Data) }
    var fields: [Int: [Value]] = [:]

    init(_ d: Data) {
        let b = [UInt8](d)
        var i = 0
        func varint() -> UInt64? {
            var r: UInt64 = 0, s: UInt64 = 0
            while i < b.count { let c = b[i]; i += 1; r |= UInt64(c & 0x7F) << s; if c & 0x80 == 0 { return r }; s += 7; if s > 63 { return nil } }
            return nil
        }
        while i < b.count {
            guard let k = varint() else { return }
            let f = Int(k >> 3)
            switch k & 7 {
            case 0: guard let v = varint() else { return }; fields[f, default: []].append(.int(v))
            case 1: guard i + 8 <= b.count else { return }
                var v: UInt64 = 0; for n in 0..<8 { v |= UInt64(b[i + n]) << (8 * UInt64(n)) }; i += 8
                fields[f, default: []].append(.int(v))
            case 5: guard i + 4 <= b.count else { return }
                var v: UInt64 = 0; for n in 0..<4 { v |= UInt64(b[i + n]) << (8 * UInt64(n)) }; i += 4
                fields[f, default: []].append(.int(v))
            case 2: guard let n = varint(), i + Int(n) <= b.count else { return }
                fields[f, default: []].append(.bytes(Data(b[i..<(i + Int(n))]))); i += Int(n)
            default: return
            }
        }
    }
    func int(_ f: Int) -> UInt64? { if case .int(let v)? = fields[f]?.first { return v }; return nil }
    func int32(_ f: Int) -> Int32? { int(f).map { Int32(truncatingIfNeeded: $0) } }
    func bytes(_ f: Int) -> Data? { if case .bytes(let v)? = fields[f]?.first { return v }; return nil }
    func string(_ f: Int) -> String? { bytes(f).map { String(decoding: $0, as: UTF8.self) } }
    func messages(_ f: Int) -> [PBMessage] { (fields[f] ?? []).compactMap { if case .bytes(let d) = $0 { return PBMessage(d) }; return nil } }
    func float(_ f: Int) -> Float? { int(f).map { Float(bitPattern: UInt32(truncatingIfNeeded: $0)) } }
}

// MARK: binary KeyValues (the stats schema)

final class KeyValue {
    let name: String
    var value: String?
    var children: [KeyValue] = []
    init(_ n: String) { name = n }
    func child(_ n: String) -> KeyValue? { children.first { $0.name.caseInsensitiveCompare(n) == .orderedSame } }
    func find(_ n: String, depth: Int) -> KeyValue? {
        if name.caseInsensitiveCompare(n) == .orderedSame { return self }
        if depth == 0 { return nil }
        for c in children { if let f = c.find(n, depth: depth - 1) { return f } }
        return nil
    }

    static func parseBinary(_ d: Data) -> KeyValue {
        let b = [UInt8](d)
        var i = 0
        func cstr() -> String {
            let s = i
            while i < b.count && b[i] != 0 { i += 1 }
            let r = String(decoding: b[s..<i], as: UTF8.self); i += 1; return r
        }
        func u32() -> UInt32 { guard i + 4 <= b.count else { i = b.count; return 0 }
            let v = UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24; i += 4; return v }
        func read(into parent: KeyValue) {
            while i < b.count {
                let t = b[i]; i += 1
                if t == 8 || t == 11 { return }             // end of this block
                let kv = KeyValue(cstr())
                switch t {
                case 0: read(into: kv)
                case 1: kv.value = cstr()
                case 2, 4, 6: kv.value = String(Int32(bitPattern: u32()))
                case 3: kv.value = String(Float(bitPattern: u32()))
                case 7, 10: let lo = u32(), hi = u32(); kv.value = String(UInt64(hi) << 32 | UInt64(lo))
                case 5: while i + 1 < b.count && !(b[i] == 0 && b[i + 1] == 0) { i += 2 }; i += 2
                default: return
                }
                parent.children.append(kv)
            }
        }
        let root = KeyValue("")
        read(into: root)
        return root.children.count == 1 ? root.children[0] : root
    }
}

// MARK: the CM connection

struct SteamError: Error, LocalizedError {
    let message: String
    var signInAgain = false
    var errorDescription: String? { message }
}

enum EMsg {
    static let multi: UInt32 = 1, serviceMethodResponse: UInt32 = 147, serviceMethodCallFromClient: UInt32 = 151
    static let heartBeat: UInt32 = 703, logOff: UInt32 = 706, logOnResponse: UInt32 = 751, loggedOff: UInt32 = 757
    static let getUserStats: UInt32 = 818, getUserStatsResponse: UInt32 = 819
    static let getAppOwnershipTicket: UInt32 = 857, getAppOwnershipTicketResponse: UInt32 = 858
    static let gamesPlayedWithDataBlob: UInt32 = 5410, storeUserStats2: UInt32 = 5466, logon: UInt32 = 5514
    static let serviceMethodCallFromClientNonAuthed: UInt32 = 9804, hello: UInt32 = 9805
}

struct SteamPacket { let emsg: UInt32; let header: PBMessage; let body: Data }

final class SteamConnection: NSObject, @unchecked Sendable {
    static let protocolVersion: UInt64 = 65580
    private var ws: URLSessionWebSocketTask?
    private lazy var session = URLSession(configuration: .default)
    private let lock = NSLock()
    private var nextJob: UInt64 = 1
    /// A request waiting for its reply, found by its job id or (replies without one) by the reply's EMsg.
    private final class Pending {
        let c: CheckedContinuation<SteamPacket, Error>; let job: UInt64; let reply: UInt32
        init(_ c: CheckedContinuation<SteamPacket, Error>, _ job: UInt64, _ reply: UInt32) { self.c = c; self.job = job; self.reply = reply }
    }
    private var jobWaiters: [UInt64: Pending] = [:]
    private var emsgWaiters: [UInt32: Pending] = [:]

    /// Remove a pending request from both indexes (under the lock); nil if it was already answered.
    private func take(job: UInt64? = nil, emsg: UInt32? = nil) -> Pending? {
        var p: Pending?
        if let job { p = jobWaiters[job] }
        if p == nil, let emsg { p = emsgWaiters[emsg] }
        guard let p else { return nil }
        jobWaiters[p.job] = nil
        if emsgWaiters[p.reply] === p { emsgWaiters[p.reply] = nil }
        return p
    }
    private func failAll(_ e: Error) {
        lock.lock(); closed = true; let all = Array(jobWaiters.values); jobWaiters = [:]; emsgWaiters = [:]; lock.unlock()
        for p in all { p.c.resume(throwing: e) }
    }
    private var heartbeat: Task<Void, Never>?
    private(set) var steamID: UInt64 = 0x0110_0001_0000_0000   // public universe, individual, desktop instance
    private(set) var sessionID: Int32 = 0
    private var closed = false

    func connect() async throws {
        let url = URL(string: "https://api.steampowered.com/ISteamDirectory/GetCMListForConnect/v1/?cellid=0&cmtype=websockets")!
        let (d, _) = try await session.data(from: url)
        let j = try JSONSerialization.jsonObject(with: d) as? [String: Any]
        let list = ((j?["response"] as? [String: Any])?["serverlist"] as? [[String: Any]]) ?? []
        guard let ep = list.compactMap({ $0["endpoint"] as? String }).first else { throw SteamError(message: "ไม่พบเซิร์ฟเวอร์ Steam") }
        let t = session.webSocketTask(with: URL(string: "wss://\(ep)/cmsocket/")!)
        t.maximumMessageSize = 64 << 20
        ws = t
        t.resume()
        receive()
        try await send(EMsg.hello, body: { var p = PBWriter(); p.uint(1, Self.protocolVersion); return p }())
    }

    func close() {
        heartbeat?.cancel()
        failAll(SteamError(message: "การเชื่อมต่อ Steam ถูกปิด"))
        ws?.cancel(with: .normalClosure, reason: nil)
    }

    private func receive() {
        ws?.receive { [weak self] r in
            guard let self else { return }
            switch r {
            case .success(.data(let d)): self.handle(d); self.receive()
            case .success: self.receive()
            case .failure(let e):
                self.failAll(SteamError(message: "ขาดการเชื่อมต่อกับ Steam: \(e.localizedDescription)"))
            }
        }
    }

    private func handle(_ d: Data) {
        let b = [UInt8](d)
        guard b.count >= 8 else { return }
        func u32(_ o: Int) -> UInt32 { UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24 }
        let raw = u32(0)
        guard raw & 0x8000_0000 != 0 else { return }            // only protobuf messages are expected here
        let emsg = raw & 0x7FFF_FFFF
        let hl = Int(u32(4))
        guard 8 + hl <= b.count else { return }
        let header = PBMessage(Data(b[8..<(8 + hl)]))
        let body = Data(b[(8 + hl)...])
        if emsg == EMsg.multi {
            let m = PBMessage(body)
            guard var payload = m.bytes(2) else { return }
            if (m.int(1) ?? 0) > 0, let un = Gzip.inflate(payload) { payload = Data(un) }
            let p = [UInt8](payload)
            var i = 0
            while i + 4 <= p.count {
                let n = Int(UInt32(p[i]) | UInt32(p[i + 1]) << 8 | UInt32(p[i + 2]) << 16 | UInt32(p[i + 3]) << 24)
                i += 4
                guard i + n <= p.count else { break }
                handle(Data(p[i..<(i + n)])); i += n
            }
            return
        }
        let pkt = SteamPacket(emsg: emsg, header: header, body: body)
        lock.lock()
        let jt = header.int(11)
        let waiter = take(job: jt != UInt64.max ? jt : nil, emsg: emsg)
        lock.unlock()
        waiter?.c.resume(returning: pkt)
    }

    func send(_ emsg: UInt32, body: PBWriter, job: UInt64? = nil, targetJobName: String? = nil) async throws {
        var h = PBWriter()
        h.fixed64(1, steamID)
        h.int(2, Int64(sessionID))
        if let job { h.fixed64(10, job) }
        if let targetJobName { h.string(12, targetJobName) }
        var out = Data()
        withUnsafeBytes(of: (emsg | 0x8000_0000).littleEndian) { out.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(h.data.count).littleEndian) { out.append(contentsOf: $0) }
        out.append(h.data); out.append(body.data)
        guard let ws else { throw SteamError(message: "ยังไม่ได้เชื่อมต่อ Steam") }
        try await ws.send(.data(out))
    }

    private func newJob() -> UInt64 { lock.lock(); defer { lock.unlock() }; nextJob += 1; return nextJob }

    /// Send and wait for the reply to this job (or, for replies without job ids, the given EMsg).
    func request(_ emsg: UInt32, body: PBWriter, reply: UInt32, targetJobName: String? = nil, timeout: Double = 30) async throws -> SteamPacket {
        let job = newJob()
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<SteamPacket, Error>) in
            lock.lock()
            if closed { lock.unlock(); c.resume(throwing: SteamError(message: "การเชื่อมต่อ Steam ถูกปิด")); return }
            let p = Pending(c, job, reply)
            jobWaiters[job] = p
            emsgWaiters[reply] = p
            lock.unlock()
            Task {
                do { try await self.send(emsg, body: body, job: job, targetJobName: targetJobName) }
                catch { self.fail(job, reply, error) }
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1e9))
                self.fail(job, reply, SteamError(message: "Steam ไม่ตอบกลับ"))
            }
        }
    }

    private func fail(_ job: UInt64, _ reply: UInt32, _ e: Error) {
        lock.lock(); let p = take(job: job); lock.unlock()
        p?.c.resume(throwing: e)
    }

    /// A unified service method ("Authentication.BeginAuthSessionViaQR#1").
    func call(_ method: String, _ body: PBWriter, authed: Bool) async throws -> (eresult: Int32, body: PBMessage) {
        let p = try await request(authed ? EMsg.serviceMethodCallFromClient : EMsg.serviceMethodCallFromClientNonAuthed,
                                  body: body, reply: EMsg.serviceMethodResponse, targetJobName: method)
        return (p.header.int32(13) ?? 2, PBMessage(p.body))
    }

    /// ClientLogon with an account name and a refresh token (the new auth's "access_token" field).
    func logOn(account: String, token: String) async throws {
        var b = PBWriter()
        b.uint(1, Self.protocolVersion)
        b.uint(3, 0)
        b.uint(5, 1771)
        b.string(6, "english")
        b.uint(7, 16)                                              // EOSType Windows 10: the game's own platform
        b.bool(8, true)
        var ip = PBWriter(); ip.fixed32(1, 0x0F7F ^ 0xBAAD_F00D)   // our own login id: other Steam sessions stay signed in
        b.message(11, ip)
        b.string(50, account)
        b.string(96, "FF7Recomp")
        b.string(108, token)
        let p = try await request(EMsg.logon, body: b, reply: EMsg.logOnResponse)
        let r = PBMessage(p.body)
        let eresult = r.int32(1) ?? 2
        guard eresult == 1 else {
            let again = [5, 15, 26, 27, 84].contains(Int(eresult)) && eresult != 84
            throw SteamError(message: "Steam ไม่ยอมให้ลงชื่อเข้าใช้ (EResult \(eresult))", signInAgain: again)
        }
        if let s = p.header.int(1) { steamID = s }
        if let s = p.header.int32(2) { sessionID = s }
        let every = max(5, Int(r.int32(3) ?? r.int32(2) ?? 9))
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(every) * 1_000_000_000)
                try? await self?.send(EMsg.heartBeat, body: PBWriter())
            }
        }
    }

    func logOff() async { try? await send(EMsg.logOff, body: PBWriter()) }
}

// MARK: the account and the sync

@MainActor
final class SteamLink: ObservableObject {
    static let appRerelease: UInt32 = 3837340, app2013: UInt32 = 39140
    struct Info: Codable { var account = ""; var appid: UInt32 = 0 }
    struct Ach { let name: String; let stat: UInt32; let bit: Int; let display: String }

    @Published var info = Info()
    @Published var qrURL: String?
    @Published var status: String?
    @Published var busy = false
    @Published var achievements: [(name: String, display: String, got: Bool)] = []
    private var signInTask: Task<Void, Never>?

    static var dir: URL { Paths.base.appendingPathComponent("steam") }
    static var state: URL { dir.appendingPathComponent("state.txt") }
    static var pending: URL { dir.appendingPathComponent("pending.txt") }
    static var sending: URL { dir.appendingPathComponent("pending.sending") }
    static var infoURL: URL { dir.appendingPathComponent("account.json") }

    init() {
        if let d = try? Data(contentsOf: Self.infoURL), let i = try? JSONDecoder().decode(Info.self, from: d) { info = i }
        loadState()
    }

    var signedIn: Bool { !info.account.isEmpty && Keychain.get(info.account) != nil }
    /// FFNx's Steam achievements on: signed in and the account's FF7 achievements known.
    var active: Bool { signedIn && Paths.fm.fileExists(atPath: Self.state.path) }
    var waiting: Int { Self.lines(Self.pending).count + Self.lines(Self.sending).count }

    private func saveInfo() {
        try? Paths.fm.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(info).write(to: Self.infoURL, options: .atomic)
    }

    func loadState() {
        achievements = Self.lines(Self.state).compactMap { l in
            let f = l.split(separator: " ", maxSplits: 3).map(String.init)
            guard f.count >= 3, f[0] == "ach" else { return nil }
            return (f[1], f.count > 3 ? f[3] : f[1], f[2] == "1")
        }
    }

    static func lines(_ u: URL) -> [String] {
        ((try? String(contentsOf: u, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    func signOut() {
        if !info.account.isEmpty { Keychain.delete(info.account) }
        info = Info(); saveInfo()
        try? Paths.fm.removeItem(at: Self.state)
        achievements = []
        status = "ออกจากระบบ Steam แล้ว"
    }

    func cancelSignIn() { signInTask?.cancel(); signInTask = nil; qrURL = nil; busy = false }

    // MARK: sign in by QR

    func signIn() {
        guard signInTask == nil else { return }
        busy = true; status = "กำลังเชื่อมต่อ Steam…"
        signInTask = Task {
            let c = SteamConnection()
            defer { c.close(); signInTask = nil; busy = false; qrURL = nil }
            do {
                try await c.connect()
                var dev = PBWriter(); dev.string(1, "FF7Recomp"); dev.uint(2, 1); dev.int(3, 16)
                var req = PBWriter()
                req.string(1, "FF7Recomp"); req.uint(2, 1); req.message(3, dev); req.string(4, "Client")
                let (er, r) = try await c.call("Authentication.BeginAuthSessionViaQR#1", req, authed: false)
                guard er == 1, var clientID = r.int(1), let requestID = r.bytes(3) else {
                    throw SteamError(message: "Steam ไม่สร้าง QR ให้ (EResult \(er))")
                }
                qrURL = r.string(2)
                status = "สแกน QR ด้วยแอป Steam บนมือถือ (เมนู Steam Guard → สแกน QR)"
                let interval = Double(r.float(4) ?? 5)
                while !Task.isCancelled {
                    try await Task.sleep(nanoseconds: UInt64(max(1, interval) * 1e9))
                    var poll = PBWriter(); poll.uint(1, clientID); poll.bytes(2, requestID)
                    let (pe, p) = try await c.call("Authentication.PollAuthSessionStatus#1", poll, authed: false)
                    if pe != 1 { throw SteamError(message: "QR หมดอายุแล้ว กดลงชื่อเข้าใช้ใหม่ (EResult \(pe))") }
                    if let n = p.int(1), n != 0 { clientID = n }
                    if let u = p.string(2), !u.isEmpty { qrURL = u }
                    if let token = p.string(3), !token.isEmpty, let account = p.string(6) {
                        qrURL = nil
                        status = "กำลังลงชื่อเข้าใช้ \(account)…"
                        try await c.logOn(account: account, token: token)
                        Keychain.set(account, token)
                        info.account = account; saveInfo()
                        do { let n = try await exchange(c); status = "ลงชื่อเข้าใช้แล้ว: \(account)" + (n.isEmpty ? "" : " · ส่ง \(n.count) achievement") }
                        catch { status = "ลงชื่อเข้าใช้แล้ว แต่ยังอ่าน achievement ของ FF7 ไม่ได้: \(error.localizedDescription) (กด Sync อีกครั้ง)" }
                        await c.logOff()
                        return
                    }
                }
            } catch is CancellationError {
                status = "ยกเลิกแล้ว"
            } catch {
                status = error.localizedDescription
            }
        }
    }

    // MARK: sync

    /// Sends waiting unlocks and refreshes state.txt; returns the display names newly sent.
    @discardableResult
    func sync() async -> [String] {
        guard signedIn, !busy, let token = Keychain.get(info.account) else { return [] }
        busy = true; defer { busy = false }
        let c = SteamConnection()
        defer { c.close() }
        do {
            try await c.connect()
            do { try await c.logOn(account: info.account, token: token) }
            catch let e as SteamError where e.signInAgain { signOut(); status = "Steam ขอให้ลงชื่อเข้าใช้ใหม่"; return [] }
            let n = try await exchange(c)
            await c.logOff()
            status = n.isEmpty ? "ซิงก์กับ Steam แล้ว" : "ส่งไป Steam แล้ว: " + n.joined(separator: ", ")
            return n
        } catch {
            status = "ซิงก์ไม่สำเร็จ: \(error.localizedDescription)"
            return []
        }
    }

    private func owns(_ c: SteamConnection, _ app: UInt32) async -> Bool {
        var b = PBWriter(); b.uint(1, UInt64(app))
        guard let p = try? await c.request(EMsg.getAppOwnershipTicket, body: b, reply: EMsg.getAppOwnershipTicketResponse) else { return false }
        return PBMessage(p.body).int(1) == 1
    }

    private func stats(_ c: SteamConnection, _ app: UInt32) async throws -> PBMessage {
        var b = PBWriter()
        b.fixed64(1, UInt64(app)); b.uint(2, 0); b.int(3, -1); b.fixed64(4, c.steamID)
        let p = try await c.request(EMsg.getUserStats, body: b, reply: EMsg.getUserStatsResponse)
        return PBMessage(p.body)
    }

    private func playing(_ c: SteamConnection, _ app: UInt32?) async {
        var b = PBWriter()
        if let app { var g = PBWriter(); g.fixed64(2, UInt64(app)); b.message(1, g) }
        try? await c.send(EMsg.gamesPlayedWithDataBlob, body: b)
    }

    private func exchange(_ c: SteamConnection) async throws -> [String] {
        if info.appid == 0 {
            info.appid = await owns(c, Self.appRerelease) ? Self.appRerelease : await owns(c, Self.app2013) ? Self.app2013 : 0
            if info.appid == 0 { throw SteamError(message: "บัญชี Steam นี้ไม่มี FINAL FANTASY VII จึงไม่มี achievement ของ FF7") }
            saveInfo()
        }
        let app = info.appid
        var st = try await stats(c, app)
        var playingSent = false
        if (st.int32(2) ?? 2) != 1 {                           // Steam keeps stats ready only for a running game
            await playing(c, app); playingSent = true
            try await Task.sleep(nanoseconds: 2_000_000_000)
            st = try await stats(c, app)
        }
        defer { if playingSent { Task { await self.playing(c, nil) } } }
        guard (st.int32(2) ?? 2) == 1 else { throw SteamError(message: "Steam ไม่ส่ง achievement ของ FF7 มา (EResult \(st.int32(2) ?? 2))") }
        let schema = Self.parseSchema(KeyValue.parseBinary(st.bytes(4) ?? Data()))
        if schema.isEmpty { throw SteamError(message: "Steam ไม่ส่งรายการ achievement ของ FF7 มา") }
        var values = Self.values(st)
        let crc = UInt32(truncatingIfNeeded: st.int(3) ?? 0)

        // what the game unlocked: pending.txt, moved aside so the game can keep appending
        try? Paths.fm.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        if Paths.fm.fileExists(atPath: Self.pending.path) {
            let add = Self.lines(Self.pending)
            try? Paths.fm.removeItem(at: Self.pending)
            let all = Self.lines(Self.sending) + add
            try? (all.joined(separator: "\n") + "\n").write(to: Self.sending, atomically: true, encoding: .utf8)
        }
        var waiting: [String] = []
        for l in Self.lines(Self.sending) {
            let n = l.split(separator: "\t").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            if !n.isEmpty && !waiting.contains(n) { waiting.append(n) }
        }
        var push: [UInt32: UInt32] = [:]
        var newly: [String] = []
        for n in waiting {
            guard let a = schema[n] else { continue }
            var v = values[a.stat] ?? 0
            if v >> a.bit & 1 != 0 { continue }                  // already on Steam
            v |= 1 << a.bit
            values[a.stat] = v; push[a.stat] = v
            newly.append(a.display)
        }
        if !push.isEmpty {
            var b = PBWriter()
            b.fixed64(1, UInt64(app)); b.fixed64(2, c.steamID); b.fixed64(3, c.steamID); b.uint(4, UInt64(crc)); b.bool(5, false)
            for (k, v) in push { var s = PBWriter(); s.uint(1, UInt64(k)); s.uint(2, UInt64(v)); b.message(6, s) }
            try await c.send(EMsg.storeUserStats2, body: b)
            var confirmed = false
            for _ in 0..<5 {
                try await Task.sleep(nanoseconds: 1_500_000_000)
                let again = try await stats(c, app)
                guard (again.int32(2) ?? 2) == 1 else { continue }
                let back = Self.values(again)
                if push.allSatisfy({ (back[$0.key] ?? 0) & $0.value == $0.value }) { values = back; confirmed = true; break }
            }
            if !confirmed { throw SteamError(message: "Steam ยังไม่รับ achievement (จะส่งใหม่ครั้งหน้า)") }
        }
        var s = "appid \(app)\n"
        for a in schema.values.sorted(by: { ($0.stat, $0.bit) < ($1.stat, $1.bit) }) {
            s += "ach \(a.name) \((values[a.stat] ?? 0) >> a.bit & 1) \(a.display.replacingOccurrences(of: "\n", with: " "))\n"
        }
        try s.write(to: Self.state, atomically: true, encoding: .utf8)
        try? Paths.fm.removeItem(at: Self.sending)
        loadState()
        return newly
    }

    static func values(_ st: PBMessage) -> [UInt32: UInt32] {
        var m: [UInt32: UInt32] = [:]
        for s in st.messages(5) { if let id = s.int(1) { m[UInt32(id)] = UInt32(truncatingIfNeeded: s.int(2) ?? 0) } }
        return m
    }

    /// The achievement bits of the stats schema: API name -> (stat id, bit, display name).
    static func parseSchema(_ root: KeyValue) -> [String: Ach] {
        var out: [String: Ach] = [:]
        guard let stats = root.find("stats", depth: 3) else { return out }
        for stat in stats.children {
            guard let bits = stat.child("bits"), let statID = UInt32(stat.name) else { continue }
            for b in bits.children {
                guard let bit = Int(b.name), let name = b.child("name")?.value else { continue }
                var display = name
                if let d = b.child("display")?.child("name") {
                    if let v = d.value, !v.isEmpty { display = v }
                    if let en = d.child("english")?.value { display = en }
                }
                out[name] = Ach(name: name, stat: statID, bit: bit, display: display)
            }
        }
        return out
    }

    /// The QR picture of the sign-in link.
    static func qrImage(_ s: String) -> CGImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(s.utf8)
        f.correctionLevel = "M"
        guard let img = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        return CIContext().createCGImage(img, from: img.extent)
    }
}

// MARK: the refresh token
//
// Kept in a file only this user can read (steam/token, mode 0600), as the Android app keeps it in
// its private storage. Not the Keychain: an app built on this Mac is signed ad hoc, so every
// rebuild (a mod re-lift, an update) is a new app to the Keychain, which then stops the launcher
// with a password prompt (even reading an older version's item would).

enum Keychain {
    static let service = "com.ff7recomp.steam"
    static var dir: URL { Paths.base.appendingPathComponent("steam") }
    static var file: URL { dir.appendingPathComponent("token") }
    private static var cache: [String: String] = [:]

    static func set(_ account: String, _ token: String) {
        try? Paths.fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let line = account + "\n" + token + "\n"
        Paths.fm.createFile(atPath: file.path, contents: Data(line.utf8), attributes: [.posixPermissions: 0o600])
        try? Paths.fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        cache[account] = token
    }
    static func get(_ account: String) -> String? {
        if let t = cache[account] { return t }
        if let s = try? String(contentsOf: file, encoding: .utf8) {
            let l = s.split(separator: "\n").map(String.init)
            if l.count >= 2, l[0] == account { cache[account] = l[1]; return l[1] }
        }
        return nil
    }
    static func delete(_ account: String) {
        cache[account] = nil
        try? Paths.fm.removeItem(at: file)
    }
}
