import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var runner: Runner

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            ColorBars()
            Group {
                switch runner.phase {
                case .idle: IdleView(targeted: runner.targeted)
                case .working: WorkingView()
                case .finished: FinishedView()
                }
            }
            .padding([.horizontal, .top], 20)
        }
        .frame(width: 440)
        .containerBackground(Theme.bg, for: .window)
        .foregroundStyle(Theme.text)
        .dropDestination(for: URL.self) { urls, _ in
            runner.add(urls)
            return true
        } isTargeted: { runner.targeted = $0 }
        .ignoresSafeArea()
    }
}

// MARK: - الشريط العلوي

struct TopBar: View {
    @EnvironmentObject var runner: Runner

    var body: some View {
        HStack {
            Spacer().frame(width: 90)   // مكان أزرار النافذة (يمين، لأن الواجهة عربية)
            Spacer()
            Text("khaled_cli HQ").font(Theme.mono(11)).foregroundStyle(Theme.dim)
            Spacer()
            HStack(spacing: 10) {
                status
                XLink()
            }
            .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
    }

    @ViewBuilder private var status: some View {
        switch runner.phase {
        case .working:
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let on = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
                HStack(spacing: 4) {
                    Circle().fill(Theme.red).frame(width: 7, height: 7).opacity(on ? 1 : 0.25)
                    Text("REC").font(Theme.mono(11)).foregroundStyle(Theme.red)
                }
                .environment(\.layoutDirection, .leftToRight)
            }
        case .finished:
            let ok = runner.results.allSatisfy(\.ok)
            Text(ok ? "OK" : "FAIL").font(Theme.mono(11)).foregroundStyle(ok ? Theme.green : Theme.red)
        case .idle:
            Text("STBY").font(Theme.mono(11)).foregroundStyle(Theme.dim)
        }
    }
}

/// زر X: يفتح حساب صاحب التطبيق
struct XLink: View {
    static let url = URL(string: "https://x.com/khaled_cli")!

    var body: some View {
        Link(destination: Self.url) {
            Text("𝕏").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted)
        }
        .buttonStyle(.plain)
        .help("@khaled_cli على X")
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

struct ColorBars: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Theme.bars.indices, id: \.self) { Theme.bars[$0] }
        }
        .frame(height: 6)
        .environment(\.layoutDirection, .leftToRight)
    }
}

// MARK: - 1. قبل

struct IdleView: View {
    @EnvironmentObject var runner: Runner
    let targeted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ResPicker()

            Button(action: pickFiles) {
                VStack(spacing: 8) {
                    Image(systemName: "film").font(.system(size: 26, weight: .light)).foregroundStyle(Theme.muted)
                    Text("اسحب المقطع هني").font(Theme.title(20))
                    HStack(spacing: 4) {
                        Text("أو").foregroundStyle(Theme.muted)
                        Text("اختار ملف").foregroundStyle(Theme.amber)
                        Text("· تقدر تحط أكثر من مقطع").foregroundStyle(Theme.muted)
                    }
                    .font(.system(size: 12))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 38)
                .background(targeted ? Theme.amber.opacity(0.08) : Theme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(targeted ? Theme.amber : Theme.dim.opacity(0.6),
                                      style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !runner.notice.isEmpty {
                Text(runner.notice).font(.system(size: 12)).foregroundStyle(Theme.amber)
            }

            if !runner.recent.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("آخر المقاطع").font(.system(size: 11)).foregroundStyle(Theme.dim).padding(.bottom, 6)
                    ForEach(runner.recent) { item in
                        Divider().overlay(Theme.line)
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.ok ? "checkmark.circle" : "xmark.circle")
                                    .foregroundStyle(item.ok ? Theme.green : Theme.red)
                                Text(item.name).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text("\(item.label) · \(item.date.formatted(.relative(presentation: .named)))")
                                    .font(.system(size: 11)).foregroundStyle(Theme.dim)
                            }
                            .font(.system(size: 13))
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("ورني الملف")
                    }
                }
            }
        }
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie]
        panel.prompt = "جهّز"
        if panel.runModal() == .OK { runner.add(panel.urls) }
    }
}

struct ResPicker: View {
    @EnvironmentObject var runner: Runner

    var body: some View {
        HStack(spacing: 3) {
            option("4K", 2160)
            option("1080p", 1080)
        }
        .padding(3)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .environment(\.layoutDirection, .leftToRight)
    }

    private func option(_ label: String, _ value: Int) -> some View {
        let on = runner.res == value
        return Button { runner.res = value } label: {
            Text(label)
                .font(Theme.mono(13))
                .foregroundStyle(on ? Theme.text : Theme.dim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(on ? Theme.line : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 2. يشتغل

struct WorkingView: View {
    @EnvironmentObject var runner: Runner

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(runner.current?.deletingPathExtension().lastPathComponent ?? "")
                    .font(Theme.title(22)).lineLimit(1).truncationMode(.middle)
                Spacer()
                TimelineView(.periodic(from: runner.started, by: 1.0 / 15)) { context in
                    Text(Runner.timecode(context.date.timeIntervalSince(runner.started)))
                        .font(Theme.mono(12)).foregroundStyle(Theme.muted)
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
            HStack {
                Text(runner.info.isEmpty ? "..." : runner.info).font(Theme.mono(12)).foregroundStyle(Theme.muted)
                Spacer()
                if runner.queueCount > 1 {
                    Text("مقطع \(runner.queueIndex) من \(runner.queueCount)").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
            }
            .padding(.bottom, 12)

            StepRow(title: "تجهيز المقطع", step: .prep)
            StepRow(title: "الباتش", step: .patch)
            StepRow(title: "فحص الناتج", step: .check)

            HStack {
                Spacer()
                Button("إلغاء") { runner.cancel() }.controlSize(.large)
                Spacer()
            }
            .padding(.top, 16)
        }
    }
}

struct StepRow: View {
    @EnvironmentObject var runner: Runner
    let title: String
    let step: Stage

    var body: some View {
        let state = runner.stage.rawValue - step.rawValue   // موجب: خلص، صفر: الحين، سالب: بعدين
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(tag(state)).font(Theme.mono(11))
                    .foregroundStyle(state > 0 ? Theme.green : state == 0 ? Theme.amber : Theme.dim)
                    .frame(width: 34, alignment: .leading)
                    .environment(\.layoutDirection, .leftToRight)
                Text(title).font(.system(size: 14, weight: state == 0 ? .semibold : .regular))
                    .foregroundStyle(state < 0 ? Theme.dim : Theme.text)
            }
            if state == 0 {
                if step == .prep {
                    Bar(fraction: runner.progress)
                } else {
                    MovingBar()
                }
            }
        }
        .padding(.vertical, 7)
    }

    private func tag(_ state: Int) -> String {
        if state > 0 { return "OK" }
        if state < 0 { return "--" }
        return step == .prep ? "\(Int(runner.progress * 100))%" : "..."
    }
}

struct Bar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Theme.line
                Theme.amber.frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 5)
        .environment(\.layoutDirection, .rightToLeft)
        .animation(.linear(duration: 0.2), value: fraction)
    }
}

/// شريط يتحرك للمراحل اللي ما نعرف نسبتها
struct MovingBar: View {
    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { geo in
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                let w = geo.size.width * 0.3
                ZStack(alignment: .leading) {
                    Theme.line
                    Theme.amber.frame(width: w).offset(x: -w + (geo.size.width + w) * t)
                }
                .clipped()
            }
        }
        .frame(height: 5)
        .environment(\.layoutDirection, .leftToRight)
    }
}

// MARK: - 3. خلص

struct FinishedView: View {
    @EnvironmentObject var runner: Runner

    var body: some View {
        let ok = runner.results.allSatisfy(\.ok)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: ok ? "checkmark.circle" : "exclamationmark.triangle")
                Text(ok ? "جاهز للرفع" : runner.results.count == 1 ? "لا ترفعه" : "لا ترفع اللي فيه مشكلة").font(Theme.title(18))
            }
            .foregroundStyle(ok ? Theme.green : Theme.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background((ok ? Theme.green : Theme.red).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if runner.results.count == 1, let result = runner.results.first {
                Detail(result: result)
            } else {
                ForEach(runner.results) { result in
                    HStack(spacing: 10) {
                        Image(systemName: result.ok ? "checkmark.circle" : "xmark.circle")
                            .foregroundStyle(result.ok ? Theme.green : Theme.red)
                        Text(result.input.deletingPathExtension().lastPathComponent).lineLimit(1)
                        Spacer()
                        Text(result.ok ? result.info : "فشل").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                    }
                    .font(.system(size: 13))
                    Divider().overlay(Theme.line)
                }
            }

            HStack(spacing: 8) {
                Button {
                    let files = runner.results.compactMap { $0.output ?? $0.input }
                    NSWorkspace.shared.activateFileViewerSelecting(files)
                } label: {
                    Label("ورني الملف", systemImage: "folder").frame(maxWidth: .infinity)
                }
                if runner.results.contains(where: \.ok) {
                    Button {
                        NSWorkspace.shared.open(URL(string: "https://www.tiktok.com/tiktokstudio/upload")!)
                    } label: {
                        Label("افتح صفحة الرفع", systemImage: "arrow.up.circle").frame(maxWidth: .infinity)
                    }
                }
            }
            .controlSize(.large)
            .padding(.top, 4)

            HStack {
                Text(ok ? "ارفعه من المتصفح، مو من تطبيق الجوال" : "شوف السبب فوق، والسجل في last-run.log")
                    .font(.system(size: 11)).foregroundStyle(Theme.dim)
                Spacer()
                Button("مقطع ثاني") { runner.reset() }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.amber)
            }
        }
    }
}

struct Detail: View {
    let result: JobResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text((result.output ?? result.input).lastPathComponent)
                .font(Theme.mono(12)).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .environment(\.layoutDirection, .leftToRight)
            let meta = [result.info, size].filter { !$0.isEmpty }.joined(separator: " · ")
            if !meta.isEmpty {
                Text(meta).font(Theme.mono(11)).foregroundStyle(Theme.muted)
            }
            Spacer().frame(height: 6)
            if !result.ok && !result.message.isEmpty {
                Text(result.message).font(.system(size: 13)).foregroundStyle(Theme.red).padding(.bottom, 4)
            }
            ForEach(result.checks, id: \.self) { line in
                let passed = line.hasPrefix("✓")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: passed ? "checkmark" : "xmark")
                        .foregroundStyle(passed ? Theme.green : Theme.red).font(.system(size: 11, weight: .bold))
                    Text(line.dropFirst(1).trimmingCharacters(in: .whitespaces))
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var size: String {
        guard let url = result.output,
              let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return "" }
        return "\(bytes / 1_000_000) MB"
    }
}
