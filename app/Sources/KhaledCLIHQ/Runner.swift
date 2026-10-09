import AppKit
import Foundation
@preconcurrency import UserNotifications

// يشغّل tiktok-hq.sh على المقاطع واحد ورا الثاني، ويقرا مخرجاته عشان يعرض المراحل.
// الأداة نفسها ما تتغير: التطبيق واجهة فوقها بس.

enum Stage: Int { case prep, patch, check }
enum Phase { case idle, working, finished }

struct JobResult: Identifiable {
    let id = UUID()
    let input: URL
    var output: URL?
    var ok: Bool
    var message: String
    var checks: [String]
    var info: String
}

struct RecentItem: Codable, Identifiable {
    var id = UUID()
    var name: String
    var label: String
    var date: Date
    var path: String
    var ok: Bool
}

@MainActor
final class Runner: ObservableObject {
    @Published var res: Int { didSet { UserDefaults.standard.set(res, forKey: "res") } }
    @Published var phase: Phase = .idle
    @Published var current: URL?
    @Published var stage: Stage = .prep
    @Published var progress: Double = 0
    @Published var info = ""
    @Published var started = Date()
    @Published var queueIndex = 0
    @Published var queueCount = 0
    @Published var results: [JobResult] = []
    @Published var recent: [RecentItem] = []
    @Published var notice = ""
    @Published var targeted = false   // مقطع مسحوب فوق النافذة (بدل @State: ماكرو SwiftUI يحتاج Xcode)

    let toolDir: URL
    private var queue: [URL] = []
    private var process: Process?
    private var cancelled = false
    private var expectedFrames = 0.0
    private var checks: [String] = []
    private var output: URL?
    private var failure = ""
    private var log: [String] = []

    static let videoTypes: Set<String> = ["mov", "mp4", "m4v"]
    static let outputMarkers = ["_khaled_cli", "_TikTokHQ", "_CHECK-FAILED"]

    private var recentFile: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("khaled_cli HQ", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("recent.json")
    }

    init() {
        let saved = UserDefaults.standard.integer(forKey: "res")
        res = saved == 1080 ? 1080 : 2160
        // مسار الأداة ينكتب في Info.plist وقت التركيب (install.sh)، وإذا ما لقيناه نستخدم المكان الافتراضي
        if let path = Bundle.main.object(forInfoDictionaryKey: "HQToolDir") as? String, !path.isEmpty {
            toolDir = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            toolDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("khaled_cli HQ/tool", isDirectory: true)
        }
        if let data = try? Data(contentsOf: recentFile),
           let items = try? JSONDecoder().decode([RecentItem].self, from: data) {
            recent = items
        }
    }

    // MARK: - الطابور

    func add(_ urls: [URL]) {
        var accepted: [URL] = []
        var skipped: [String] = []
        for url in urls {
            let name = url.lastPathComponent
            if !Self.videoTypes.contains(url.pathExtension.lowercased()) {
                skipped.append("\(name) مو فيديو")
            } else if Self.outputMarkers.contains(where: { name.contains($0) }) {
                skipped.append("\(name) جاهز من قبل")
            } else {
                accepted.append(url)
            }
        }
        notice = skipped.joined(separator: " · ")
        guard !accepted.isEmpty else { return }
        if phase != .working {
            results = []
            queueIndex = 0
            queueCount = 0
            phase = .working
            queue = accepted
            queueCount = accepted.count
            startNext()
        } else {
            queue += accepted
            queueCount += accepted.count
        }
    }

    func cancel() {
        cancelled = true
        queue = []
        if let pid = process?.processIdentifier { Self.killTree(pid) }
    }

    func reset() {
        phase = .idle
        results = []
        notice = ""
    }

    private func startNext() {
        guard !queue.isEmpty else { return finish() }
        let url = queue.removeFirst()
        queueIndex += 1
        current = url
        stage = .prep
        progress = 0
        info = ""
        checks = []
        output = nil
        failure = ""
        log = []
        expectedFrames = 0
        started = Date()

        let script = toolDir.appendingPathComponent("tiktok-hq.sh").path
        guard FileManager.default.isExecutableFile(atPath: script) else {
            failure = "ما لقيت الأداة في \(toolDir.path). أعد أمر التركيب."
            return ended(url, status: 1)
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script, "--res", String(res), url.path]
        var env = ProcessInfo.processInfo.environment
        env["HQ_NO_NOTIFY"] = "1"
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        process = p
        do {
            try p.run()
        } catch {
            failure = "ما قدرت أشغّل الأداة: \(error.localizedDescription)"
            return ended(url, status: 1)
        }
        let handle = pipe.fileHandleForReading
        // نقرا بخيط جانبي، ونقسم على \n و \r (ffmpeg يكتب التقدم بـ \r) قبل فك UTF-8
        DispatchQueue.global(qos: .userInitiated).async {
            var buffer = Data()
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let cut = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                    let line = String(decoding: buffer[buffer.startIndex..<cut], as: UTF8.self)
                    buffer.removeSubrange(buffer.startIndex...cut)
                    if !line.isEmpty { DispatchQueue.main.async { self.consume(line) } }
                }
            }
            if !buffer.isEmpty {
                let line = String(decoding: buffer, as: UTF8.self)
                DispatchQueue.main.async { self.consume(line) }
            }
            p.waitUntilExit()
            let status = p.terminationStatus
            DispatchQueue.main.async { self.ended(url, status: status) }
        }
    }

    private func consume(_ line: String) {
        log.append(line)
        let text = line.trimmingCharacters(in: .whitespaces)
        if let m = text.firstMatch(of: #/frame=\s*(\d+)/#) {
            if expectedFrames > 0, let n = Double(m.1) {
                progress = min(n / expectedFrames, 1)
                if n >= expectedFrames { stage = .patch }
            }
        } else if text.hasPrefix("-- "), let m = text.firstMatch(of: #/fps=(\S+) \((\d+) .*-> (\S+) fps=(\S+)/#) {
            let src = Self.rate(String(m.1)), dst = Self.rate(String(m.4))
            if let frames = Double(m.2), src > 0 { expectedFrames = (frames * dst / src).rounded(.up) }
            info = "\(m.3) · \(Int(dst.rounded()))P"
        } else if text.hasPrefix("[+]") {
            stage = .patch
            progress = 1
        } else if text.hasPrefix("-- فحص") {
            stage = .check
        } else if text.hasPrefix("✓") || text.hasPrefix("✗") || text.hasPrefix("!!") && stage == .check {
            checks.append(text)
        }
        if text.hasPrefix("++ جاهز: ") {
            output = URL(fileURLWithPath: String(text.dropFirst("++ جاهز: ".count)))
        } else if text.hasPrefix("!! ") {
            failure = String(text.dropFirst(3))
        }
    }

    private func ended(_ url: URL, status: Int32) {
        process = nil
        if cancelled {
            cancelled = false
            phase = .idle
            notice = "انلغى"
            return
        }
        let ok = status == 0 && output != nil
        if !ok && failure.isEmpty {
            failure = log.last(where: { !$0.hasPrefix("frame=") }) ?? "الأداة وقفت بدون سبب واضح"
        }
        let result = JobResult(input: url, output: output, ok: ok, message: failure,
                               checks: checks.filter { !$0.hasPrefix("!!") || !ok }, info: info)
        results.append(result)
        let label = info.components(separatedBy: " · ").first ?? ""
        recent.insert(RecentItem(name: url.deletingPathExtension().lastPathComponent, label: label,
                                 date: Date(), path: (output ?? url).path, ok: ok), at: 0)
        recent = Array(recent.prefix(5))
        if let data = try? JSONEncoder().encode(recent) { try? data.write(to: recentFile) }
        startNext()
    }

    private func finish() {
        phase = .finished
        let good = results.filter(\.ok).count, bad = results.count - good
        let title = bad == 0 ? "جاهز للرفع" : "فيه مشكلة"
        let body = bad == 0
            ? (good == 1 ? (results[0].output?.lastPathComponent ?? "") : "\(good) مقاطع جاهزة")
            : "نجح \(good) · فشل \(bad) — لا ترفع اللي فشل"
        Self.notify(title: title, body: body)
        NSSound(named: bad == 0 ? "Glass" : "Basso")?.play()
        NSApp.requestUserAttention(.informationalRequest)
    }

    // MARK: - أدوات صغيرة

    static func rate(_ s: String) -> Double {
        let parts = s.split(separator: "/").compactMap { Double($0) }
        if parts.count == 2, parts[1] != 0 { return parts[0] / parts[1] }
        return parts.first ?? 0
    }

    /// يوقف السكربت وكل اللي تحته (ffmpeg والفحص)، مو bash بس
    static func killTree(_ pid: Int32) {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-P", String(pid)]
        let pipe = Pipe()
        pgrep.standardOutput = pipe
        try? pgrep.run()
        pgrep.waitUntilExit()
        let children = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .split(separator: "\n").compactMap { Int32($0) }
        children.forEach(killTree)
        kill(pid, SIGTERM)
    }

    static func notify(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    static func timecode(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let frames = Int((seconds - Double(total)) * 30)
        return String(format: "%02d:%02d:%02d:%02d", total / 3600, total / 60 % 60, total % 60, frames)
    }
}
